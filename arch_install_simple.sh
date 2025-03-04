#!/bin/bash

# === SCRIPT DE INSTALACIÓN DE ARCH LINUX CON BTRFS, HYPRLAND Y WAYBAR ===
# Configuración para: Nvidia RTX 3080 + AMD Ryzen 9 5900HX
# Autor: Antonio
# Uso: Este script continúa la instalación DESPUÉS de usar cfdisk para crear las particiones

# Colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
print_message() {
    echo -e "${BLUE}[INSTALACIÓN]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[COMPLETADO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

# Verificar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root"
    exit 1
fi

# Definir dispositivos (asumiendo que ya se han creado las particiones)
DISK="/dev/nvme0n1"
EFI_DEV="${DISK}p1"  # Partición 1: EFI System (1GB)
SWAP_DEV="${DISK}p2"  # Partición 2: Linux swap (16GB)
SYSTEM_DEV="${DISK}p3"  # Partición 3: Linux filesystem (resto)

print_message "Dispositivos a utilizar:"
print_message "Partición EFI: $EFI_DEV (1GB)"
print_message "Partición SWAP: $SWAP_DEV (16GB)"
print_message "Partición Sistema (BTRFS): $SYSTEM_DEV (resto del disco)"
print_warning "Este script asume que ya creaste las particiones con cfdisk"
echo
read -p "¿Continuar con la instalación? [s/N]: " response
if [[ ! "$response" =~ ^([sS][iI]|[sS])$ ]]; then
    print_message "Instalación cancelada"
    exit 0
fi

# --- 2) FORMATEO Y ACTIVACIÓN SWAP ---
print_message "Formateando partición EFI (${EFI_DEV})..."
mkfs.fat -F32 $EFI_DEV
print_success "Partición EFI formateada"

print_message "Formateando y activando SWAP (${SWAP_DEV})..."
mkswap $SWAP_DEV && swapon $SWAP_DEV
print_success "SWAP configurada"

print_message "Formateando partición del sistema como BTRFS (${SYSTEM_DEV})..."
mkfs.btrfs -f $SYSTEM_DEV
print_success "Partición BTRFS formateada"

# --- 3) CREAR SUBVOLÚMENES BTRFS PARA TIMESHIFT ---
print_message "Creando subvolúmenes BTRFS..."
mount $SYSTEM_DEV /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt
print_success "Subvolúmenes BTRFS creados"

# --- 4) MONTAR SUBVOLÚMENES BTRFS ---
print_message "Montando subvolúmenes BTRFS..."
mount -o noatime,compress=zstd,space_cache=v2,subvol=@ $SYSTEM_DEV /mnt
mkdir -p /mnt/{boot/efi,home,var,.snapshots}
mount -o noatime,compress=zstd,space_cache=v2,subvol=@home $SYSTEM_DEV /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,subvol=@var $SYSTEM_DEV /mnt/var
mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots $SYSTEM_DEV /mnt/.snapshots
mount $EFI_DEV /mnt/boot/efi
print_success "Subvolúmenes BTRFS montados"

# --- 5) INSTALAR SISTEMA BASE ---
print_message "Instalando sistema base (esto puede tomar tiempo)..."
pacstrap /mnt base base-devel linux linux-headers linux-firmware amd-ucode btrfs-progs nano grub efibootmgr sudo networkmanager
print_success "Sistema base instalado"

# --- 6) GENERAR FSTAB ---
print_message "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
print_success "fstab generado"

# --- 7) PREPARAR CHROOT ---
print_message "Preparando archivos para chroot..."

# Crear script post-chroot
cat > /mnt/root/post-chroot.sh << 'EOL'
#!/bin/bash

# Colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
print_message() {
    echo -e "${BLUE}[INSTALACIÓN]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[COMPLETADO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

# --- 8) CONFIGURAR LOCALE Y ZONA HORARIA ---
print_message "Configurando locale y zona horaria..."
sed -i 's/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=es_ES.UTF-8" > /etc/locale.conf

# Configurar teclado con múltiples layouts (US y ES)
echo "KEYMAP=us" > /etc/vconsole.conf
mkdir -p /etc/X11/xorg.conf.d

ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc
print_success "Locale, zona horaria y teclado configurados"

# --- 9) HOSTNAME Y HOSTS ---
print_message "Configurando hostname..."
echo "host" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   host.localdomain host
EOF
print_success "Hostname configurado"

# --- 10) CONTRASEÑA ROOT ---
print_message "A continuación deberás configurar la contraseña de root:"
passwd

# --- 11) HABILITAR MULTILIB ---
print_message "Habilitando repositorio multilib..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syy
print_success "Repositorio multilib habilitado"

# --- 12) INSTALAR PAQUETES CLAVE (por batches) ---
print_message "Instalando drivers y paquetes base (esto tomará tiempo)..."
pacman -S --noconfirm --needed nvidia nvidia-utils nvidia-dkms lib32-nvidia-utils polkit

print_message "Instalando entorno Wayland y Hyprland..."
pacman -S --noconfirm --needed hyprland xorg-xwayland waybar

print_message "Instalando utilidades básicas..."
pacman -S --noconfirm --needed kitty rofi networkmanager bluez bluez-utils

print_message "Instalando multimedia y soporte de audio..."
pacman -S --noconfirm --needed pipewire pipewire-pulse pipewire-alsa wireplumber

print_message "Instalando fuentes y temas..."
pacman -S --noconfirm --needed ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji ttf-dejavu

print_message "Instalando herramientas y utilidades..."
pacman -S --noconfirm --needed firefox thunar grim slurp wl-clipboard xclip zip unzip p7zip

print_message "Instalando soporte para desarrollo..."
pacman -S --noconfirm --needed git python python-pip

print_message "Instalando herramientas de monitoreo..."
pacman -S --noconfirm --needed btop

print_message "Instalando controladores AMD..."
pacman -S --noconfirm --needed mesa xf86-video-amdgpu vulkan-radeon

print_message "Añadir soporte para formatos multimedia..."
pacman -S --noconfirm --needed ffmpeg

print_success "Paquetes clave instalados"

# --- 13) CONFIGURAR NVIDIA PARA WAYLAND ---
print_message "Configurando NVIDIA para Wayland..."
mkdir -p /etc/modprobe.d/
echo "options nvidia_drm modeset=1" > /etc/modprobe.d/nvidia.conf
sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm amdgpu /' /etc/mkinitcpio.conf
mkinitcpio -P
print_success "NVIDIA configurado para Wayland"

# --- 14) CONFIGURAR GRUB ---
print_message "Configurando GRUB..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"/' /etc/default/grub

print_message "Instalando GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCHLINUX
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configurado"

# --- 15) CREAR USUARIO ---
print_message "Creando usuario 'antonio'..."
useradd -m -G wheel,video,audio,storage,optical -s /bin/bash antonio
print_message "Configura la contraseña para el usuario 'antonio':"
passwd antonio

# Configurar sudo para el usuario antonio
echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
print_success "Usuario creado"

# --- 16) HABILITAR SERVICIOS ---
print_message "Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable fstrim.timer
print_success "Servicios habilitados"

# --- 17) CONFIGURAR HYPRLAND ---
print_message "Configurando Hyprland para el usuario..."
mkdir -p /home/antonio/.config/hypr
cat > /home/antonio/.config/hypr/hyprland.conf << EOF
# Configuración de Hyprland para AMD + NVIDIA

# Configuración del monitor
monitor=,preferred,auto,1

# Variables de entorno
env = XCURSOR_SIZE,24
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = MOZ_ENABLE_WAYLAND,1

# Autostart
exec-once = waybar &
exec-once = sleep 2 && waybar # Intento de inicio de waybar con retraso como respaldo

# Input
input {
    kb_layout = us,es
    kb_options = grp:alt_shift_toggle
    follow_mouse = 1
    touchpad {
        natural_scroll = true
    }
    sensitivity = 0
}

# Aspecto
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee)
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# Decoración - Versión correcta para Hyprland actual
decoration {
    rounding = 10
    
    # La sección blur tiene que estar dentro de decoration
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    
    # Estos son atributos directos de decoration, no dentro de una subsección
    drop_shadow = true
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

dwindle {
    pseudotile = true
    preserve_split = true
}

master {
    new_is_master = true
}

gestures {
    workspace_swipe = true
}

# Reglas de ventanas
windowrule = float, ^(pavucontrol)$
windowrule = float, ^(blueman-manager)$
windowrule = float, ^(nm-connection-editor)$

# Atajos de teclado - Definición del modificador principal
$mainMod = SUPER

# Aplicaciones y controles de ventana
bind = $mainMod, Q, exec, kitty
bind = $mainMod, C, killactive, 
bind = $mainMod, M, exit, 
bind = $mainMod, E, exec, thunar
bind = $mainMod SHIFT, F, togglefloating, 
bind = $mainMod, R, exec, rofi -show drun
bind = $mainMod, P, pseudo, 
bind = $mainMod, F, fullscreen, 
bind = $mainMod, J, togglesplit, 
bind = $mainMod, Z, exec, grim -g "$(slurp)" ~/Imágenes/$(date +%Y-%m-%d_%H-%M-%S).png

# Movimiento entre ventanas
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Cambio de espacios de trabajo
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Mover ventana al espacio de trabajo
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# Control de volumen y brillo
bind = , XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
bind = , XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
bind = , XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
EOF

# Configuración de Waybar
mkdir -p /home/antonio/.config/waybar
cat > /home/antonio/.config/waybar/config << EOF
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    
    "modules-left": ["hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["tray", "pulseaudio", "network", "memory"],
    
    "hyprland/workspaces": {
        "format": "{name}: {icon}",
        "format-icons": {
            "1": "1",
            "2": "2",
            "3": "3",
            "4": "4",
            "5": "5",
            "urgent": "",
            "focused": "",
            "default": ""
        }
    },
    
    "hyprland/window": {
        "format": "{}",
        "max-length": 50,
        "separate-outputs": true
    },
    
    "clock": {
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>",
        "format": "{:%H:%M:%S}",
        "format-alt": "{:%Y-%m-%d}",
        "interval": 1
    },
    
    "memory": {
        "format": "{used:0.1f}GB/{total:0.1f}GB ",
        "interval": 2,
        "tooltip": true
    },
    
    "network": {
        "format-wifi": "{essid}",
        "format-ethernet": "{ipaddr}",
        "tooltip-format": "{ifname} via {gwaddr}",
        "format-linked": "{ifname} (No IP)",
        "format-disconnected": "Disconnected",
        "format-alt": "{ifname}: {ipaddr}"
    },
    
    "pulseaudio": {
        "format": "{volume}%",
        "format-bluetooth": "{volume}%",
        "format-bluetooth-muted": "",
        "format-muted": "",
        "on-click": "pavucontrol"
    },
    
    "tray": {
        "icon-size": 21,
        "spacing": 10
    }
}
EOF

# Configuración estilo Waybar
cat > /home/antonio/.config/waybar/style.css << EOF
* {
    border: none;
    border-radius: 0;
    font-family: sans-serif;
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background-color: rgba(0, 0, 0, 0.9);
    border-bottom: 3px solid rgba(100, 114, 125, 0.5);
    color: #ffffff;
}

window#waybar.hidden {
    opacity: 0.2;
}

#workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: #ffffff;
}

#workspaces button:hover {
    background: rgba(0, 0, 0, 0.2);
}

#workspaces button.focused {
    background-color: #64727D;
}

#workspaces button.urgent {
    background-color: #eb4d4b;
}

#window {
    margin-left: 10px;
    font-weight: bold;
}

#clock {
    font-weight: bold;
    font-size: 14px;
}

#clock,
#battery,
#network,
#pulseaudio,
#memory,
#tray {
    padding: 0 10px;
    margin: 0 4px;
    color: #ffffff;
}

#memory {
    padding-right: 16px;
}
EOF

# Script de autostart para asegurar que Waybar inicie correctamente
mkdir -p /home/antonio/.config/autostart
cat > /home/antonio/.config/autostart/waybar.desktop << EOF
[Desktop Entry]
Type=Application
Name=Waybar
Exec=waybar
Terminal=false
Categories=System;
EOF

# Crear archivo de perfil para variables de entorno para Wayland
cat > /home/antonio/.profile << EOF
# Variables de entorno para Wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export MOZ_ENABLE_WAYLAND=1
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export WLR_NO_HARDWARE_CURSORS=1
export LIBVA_DRIVER_NAME=nvidia
export EDITOR=nano

# Directorio de imágenes para capturas de pantalla
mkdir -p ~/Imágenes
EOF

# Ajustar permisos
chown -R antonio:antonio /home/antonio/
chmod +x /home/antonio/.profile

# Crear directorio para capturas de pantalla
mkdir -p /home/antonio/Imágenes
chown -R antonio:antonio /home/antonio/Imágenes

print_message "La instalación base ha sido completada."
print_message "Después de reiniciar:"
print_message "1. Retira el medio de instalación"
print_message "2. Selecciona Arch Linux en GRUB"
print_message "3. Inicia sesión como 'antonio'"
print_message "4. Ejecuta 'EDITOR=nano sudo visudo' y asegúrate que la línea %wheel ALL=(ALL) ALL esté descomentada"
print_message "5. Conecta a Internet con 'nmtui'"
print_message "6. Para instalar paquetes adicionales, ejecuta: sudo pacman -Syu"
print_message "7. Alt+Shift para cambiar entre teclado US y ES"
print_message "8. Super+Z para capturar pantalla (seleccionando zona)"
print_message "9. Super+R para abrir el lanzador de aplicaciones rofi"

# Esto ayudará a mantener organizado el script
sleep 2
EOL

# Hacer ejecutable el script post-chroot
chmod +x /mnt/root/post-chroot.sh

# --- 7) EJECUTAR CHROOT ---
print_message "Ejecutando chroot para continuar la instalación..."
arch-chroot /mnt /root/post-chroot.sh
print_success "Instalación base completada"

# --- 19) FINALIZAR ---
print_message "Instalación completada exitosamente."
print_message "El sistema se reiniciará en 10 segundos."
print_message "Recuerda retirar el medio de instalación durante el reinicio."

sleep 10
umount -R /mnt
reboot
