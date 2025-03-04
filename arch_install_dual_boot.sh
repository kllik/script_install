#!/bin/bash

# === SCRIPT DE INSTALACIÓN DE ARCH LINUX CON BTRFS, HYPRLAND Y WAYBAR ===
# Configuración para: Nvidia RTX 3080 + AMD Ryzen 9 5900HX con Dual Boot
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
EFI_DEV="${DISK}p5"  # Partición 5: EFI System (1GB) para Arch
SWAP_DEV="${DISK}p6"  # Partición 6: Linux swap (16GB)
SYSTEM_DEV="${DISK}p7"  # Partición 7: Linux filesystem (resto)

print_message "Dispositivos a utilizar (Dual Boot):"
print_message "Partición EFI para Arch: $EFI_DEV (1GB)"
print_message "Partición SWAP: $SWAP_DEV (16GB)"
print_message "Partición Sistema (BTRFS): $SYSTEM_DEV (resto de los 400GB)"
print_warning "Este script asume que ya creaste las particiones con cfdisk"
print_warning "Las particiones 1-4 son de Windows, y las 5-7 serán para Arch Linux"
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
pacstrap /mnt base base-devel linux linux-headers linux-firmware amd-ucode btrfs-progs
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

# --- 8) INSTALAR NANO ---
print_message "Instalando nano..."
pacman -Sy nano --noconfirm
print_success "Nano instalado"

# --- 9) CONFIGURAR LOCALE Y ZONA HORARIA ---
print_message "Configurando locale y zona horaria..."
sed -i 's/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=es_ES.UTF-8" > /etc/locale.conf

# Configurar teclado con múltiples layouts (US y ES)
echo "KEYMAP=us" > /etc/vconsole.conf
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us,es"
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
EOF

ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc
print_success "Locale, zona horaria y teclado configurados"

# --- 10) HOSTNAME Y HOSTS ---
print_message "Configurando hostname..."
echo "host" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   host.localdomain host
EOF
print_success "Hostname configurado"

# --- 11) CONTRASEÑA ROOT ---
print_message "A continuación deberás configurar la contraseña de root:"
passwd

# --- 12) HABILITAR MULTILIB ---
print_message "Habilitando repositorio multilib..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syy
print_success "Repositorio multilib habilitado"

# --- 13) INSTALAR PAQUETES CLAVE ---
print_message "Instalando paquetes clave (esto tomará tiempo)..."
pacman -S --noconfirm nvidia nvidia-utils nvidia-dkms nvidia-prime nvidia-settings lib32-nvidia-utils \
    hyprland xdg-desktop-portal-hyprland xorg-xwayland wlroots \
    waybar rofi-wayland kitty networkmanager sudo grub efibootmgr os-prober \
    pipewire pipewire-pulse pipewire-alsa wireplumber bluez bluez-utils \
    firefox discord steam obs-studio neovim bash egl-wayland thunar thunar-archive-plugin \
    xarchiver zip unzip p7zip unrar \
    python python-pip lua go nodejs npm typescript sqlite \
    clang cmake ninja meson gdb lldb git tmux \
    sdl2 vulkan-icd-loader vulkan-validation-layers vulkan-tools spirv-tools \
    hyprpaper hyprlock fastfetch pavucontrol ddcutil btop \
    ttf-jetbrains-mono-nerd ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd \
    yazi zathura zathura-pdf-mupdf bluetui swaync \
    noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation \
    nerd-fonts-meta \
    xdg-utils xorg-xrandr qt5-wayland qt6-wayland \
    adwaita-icon-theme gnome-themes-extra blueman \
    polkit-gnome xdg-desktop-portal-gtk brightnessctl playerctl \
    mesa vulkan-radeon amdvlk lib32-vulkan-radeon lib32-amdvlk xf86-video-amdgpu \
    grim slurp wl-clipboard \
    arandr wdisplays \
    gtk3 kvantum qt5ct qt6ct lxappearance \
    cliphist wl-clipboard xclip \
    libreoffice-fresh imv glow wget

# Añadir soporte para formatos multimedia
pacman -S --noconfirm ffmpeg gst-plugins-good gst-plugins-bad gst-plugins-ugly

# Instalar herramientas de monitoreo
pacman -S --noconfirm nvtop btop

# Configurar AUR
print_message "Configurando acceso a AUR..."
cd /tmp
git clone https://aur.archlinux.org/paru.git
chown -R antonio:antonio /tmp/paru
cd paru
sudo -u antonio makepkg -si --noconfirm
print_success "Gestor AUR (paru) instalado"

# Instalar paquetes desde AUR
print_message "Instalando paquetes adicionales desde AUR..."
sudo -u antonio paru -S --noconfirm visual-studio-code-bin nerd-fonts-jetbrains-mono
print_success "Paquetes clave instalados"

# --- 14) CONFIGURAR NVIDIA PARA WAYLAND ---
print_message "Configurando NVIDIA para Wayland..."
echo "options nvidia_drm modeset=1" > /etc/modprobe.d/nvidia.conf
sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm amdgpu /' /etc/mkinitcpio.conf
mkinitcpio -P
print_success "NVIDIA configurado para Wayland"

# --- 15) CONFIGURAR GRUB PARA DUAL BOOT ---
print_message "Configurando GRUB para dual boot..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"/' /etc/default/grub
# Habilitar detección de otros sistemas operativos (Windows)
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCHLINUX
os-prober
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configurado para dual boot"

# --- 16) CREAR USUARIO ---
print_message "Creando usuario 'antonio'..."
useradd -m -G wheel,seat,video,audio,storage,optical -s /bin/bash antonio
print_message "Configura la contraseña para el usuario 'antonio':"
passwd antonio
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
print_success "Usuario creado"

# --- 17) HABILITAR SERVICIOS ---
print_message "Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable seatd
systemctl enable fstrim.timer
print_success "Servicios habilitados"

# --- 18) CONFIGURAR HYPRLAND ---
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
exec-once = hyprpaper & waybar & swaync & /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = wl-paste --type text --watch cliphist store # Guardar texto copiado
exec-once = wl-paste --type image --watch cliphist store # Guardar imágenes copiadas

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

decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
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

# Atajos de teclado
$mainMod = SUPER

bind = $mainMod, Q, exec, kitty
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, thunar
bind = $mainMod SHIFT, F, togglefloating,
bind = $mainMod, R, exec, rofi -show drun
bind = $mainMod, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy
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

# Configuración de hyprpaper
mkdir -p /home/antonio/.config/hypr
cat > /home/antonio/.config/hypr/hyprpaper.conf << EOF
preload = /usr/share/backgrounds/archlinux/archlinux-simplyblack.png
wallpaper = ,/usr/share/backgrounds/archlinux/archlinux-simplyblack.png
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
    "modules-right": ["custom/gpu", "temperature#gpu", "custom/cpu", "temperature#cpu", "memory", "pulseaudio", "tray"],
    
    "hyprland/workspaces": {
        "format": "{name}: {icon}",
        "format-icons": {
            "1": "",
            "2": "",
            "3": "",
            "4": "",
            "5": "",
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
    
    "custom/cpu": {
        "format": "CPU {}%",
        "exec": "top -bn1 | grep 'Cpu(s)' | awk '{print int($2+$4)}'",
        "interval": 2,
        "tooltip": false,
        "on-click": "kitty -e btop"
    },
    
    "temperature#cpu": {
        "critical-threshold": 80,
        "format": "{temperatureC}°C",
        "tooltip": true,
        "hwmon-path": "/sys/class/hwmon/hwmon0/temp1_input",
        "interval": 2
    },
    
    "custom/gpu": {
        "format": "GPU {}%",
        "exec": "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits",
        "interval": 2,
        "tooltip": false,
        "on-click": "kitty -e nvtop"
    },
    
    "temperature#gpu": {
        "critical-threshold": 85,
        "format": "{temperatureC}°C",
        "tooltip": true,
        "hwmon-path": "/sys/class/hwmon/hwmon1/temp1_input",
        "interval": 2
    },
    
    "memory": {
        "format": "{used:0.1f}GB/{total:0.1f}GB ",
        "interval": 2,
        "tooltip": true
    },
    
    "backlight": {
        "format": "{percent}% {icon}",
        "format-icons": ["", "", "", "", "", "", "", "", ""]
    },
    
    "battery": {
        "states": {
            "good": 95,
            "warning": 30,
            "critical": 15
        },
        "format": "{capacity}% {icon}",
        "format-charging": "{capacity}% ",
        "format-plugged": "{capacity}% ",
        "format-alt": "{time} {icon}",
        "format-icons": ["", "", "", "", ""]
    },
    
    "network": {
        "format-wifi": "{essid} ({signalStrength}%) ",
        "format-ethernet": "{ipaddr}/{cidr} ",
        "tooltip-format": "{ifname} via {gwaddr} ",
        "format-linked": "{ifname} (No IP) ",
        "format-disconnected": "Disconnected ⚠",
        "format-alt": "{ifname}: {ipaddr}/{cidr}"
    },
    
    "pulseaudio": {
        "format": "{volume}% {icon}",
        "format-bluetooth": "{volume}% {icon}",
        "format-bluetooth-muted": " {icon}",
        "format-muted": "",
        "format-icons": {
            "headphone": "",
            "hands-free": "",
            "headset": "",
            "phone": "",
            "portable": "",
            "car": "",
            "default": ["", "", ""]
        },
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
    font-family: JetBrainsMono Nerd Font;
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background-color: rgba(0, 0, 0, 0.9);
    border-bottom: 3px solid rgba(100, 114, 125, 0.5);
    color: #ffffff;
    transition-property: background-color;
    transition-duration: .5s;
}

window#waybar.hidden {
    opacity: 0.2;
}

#workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: #ffffff;
    border-bottom: 3px solid transparent;
}

#workspaces button:hover {
    background: rgba(0, 0, 0, 0.2);
    box-shadow: inherit;
    border-bottom: 3px solid #ffffff;
}

#workspaces button.focused {
    background-color: #64727D;
    border-bottom: 3px solid #ffffff;
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

#custom-cpu {
    color: #4287f5;
    font-weight: bold;
    padding: 0 8px;
}

#temperature.cpu {
    color: #4287f5;
    padding-right: 16px;
}

#custom-gpu {
    color: #43b1b1;
    font-weight: bold;
    padding: 0 8px;
}

#temperature.gpu {
    color: #43b1b1;
    padding-right: 16px;
}

#clock,
#battery,
#cpu,
#memory,
#temperature,
#backlight,
#network,
#pulseaudio,
#custom-media,
#custom-cpu,
#custom-gpu,
#tray,
#mode,
#idle_inhibitor {
    padding: 0 10px;
    margin: 0 4px;
    color: #ffffff;
}

#memory {
    padding-right: 16px;
}

#battery.charging {
    color: #26A65B;
}

#battery.warning:not(.charging) {
    background-color: #f53c3c;
    color: #ffffff;
}

#temperature.critical {
    background-color: #eb4d4b;
}

#tray {
    background-color: #2980b9;
}
EOF

# Configurar tema oscuro para GTK y QT
mkdir -p /home/antonio/.config/gtk-3.0
cat > /home/antonio/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=Sans 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=0
gtk-toolbar-style=GTK_TOOLBAR_BOTH
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
EOF

mkdir -p /home/antonio/.config/qt5ct
cat > /home/antonio/.config/qt5ct/qt5ct.conf << EOF
[Appearance]
color_scheme_path=/usr/share/qt5ct/colors/darker.conf
custom_palette=false
icon_theme=Adwaita
standard_dialogs=default
style=Fusion

[Fonts]
fixed=@Variant(\0\0\0@\0\0\0\x12\0M\0o\0n\0o\0s\0p\0\x61\0\x63\0\x65@$\0\0\0\0\0\0\xff\xff\xff\xff\x5\x1\0\x32\x10)
general=@Variant(\0\0\0@\0\0\0\x14\0S\0\x61\0n\0s\0 \0S\0\x65\0r\0i\0\x66@$\0\0\0\0\0\0\xff\xff\xff\xff\x5\x1\0\x32\x10)
EOF

mkdir -p /home/antonio/.config/qt6ct
cat > /home/antonio/.config/qt6ct/qt6ct.conf << EOF
[Appearance]
color_scheme_path=/usr/share/qt6ct/colors/darker.conf
custom_palette=false
icon_theme=Adwaita
standard_dialogs=default
style=Fusion

[Fonts]
fixed=@Variant(\0\0\0@\0\0\0\x12\0M\0o\0n\0o\0s\0p\0\x61\0\x63\0\x65@$\0\0\0\0\0\0\xff\xff\xff\xff\x5\x1\0\x32\x10)
general=@Variant(\0\0\0@\0\0\0\x14\0S\0\x61\0n\0s\0 \0S\0\x65\0r\0i\0\x66@$\0\0\0\0\0\0\xff\xff\xff\xff\x5\x1\0\x32\x10)
EOF

# Crear archivo de perfil para variables de entorno para Wayland
cat > /home/antonio/.profile << EOF
# Variables de entorno para Wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export QT_QPA_PLATFORMTHEME=qt5ct
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export MOZ_ENABLE_WAYLAND=1
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export WLR_NO_HARDWARE_CURSORS=1
export LIBVA_DRIVER_NAME=nvidia
export EDITOR=nano

# Variables para aplicaciones específicas
export _JAVA_AWT_WM_NONREPARENTING=1
export XCURSOR_SIZE=24
export XCURSOR_THEME=Adwaita

# Variables específicas para VSCode en Wayland
export ELECTRON_OZONE_PLATFORM_HINT=wayland

# Directorio de imágenes para capturas de pantalla
mkdir -p ~/Imágenes
EOF

# Añadir una nota para la configuración de los sensores
cat > /home/antonio/.config/waybar/SENSOR_CONFIG.txt << EOF
IMPORTANTE: Las rutas de los sensores de temperatura en la configuración de Waybar podrían necesitar ajustes.

Si los indicadores de temperatura no muestran datos correctos, sigue estos pasos:

1. Ejecuta el siguiente comando para listar los sensores disponibles:
   $ ls -l /sys/class/hwmon/*/temp*_input

2. Identifica qué rutas corresponden a tu CPU y GPU.

3. Modifica los valores de "hwmon-path" en ~/.config/waybar/config para que coincidan con las rutas correctas.

Ejemplo de modificación:
"hwmon-path": "/sys/class/hwmon/hwmon4/temp1_input" (para CPU)
"hwmon-path": "/sys/class/hwmon/hwmon2/temp1_input" (para GPU)

También puedes usar "thermal-zone" en lugar de "hwmon-path" si es más confiable para tu hardware:
"thermal-zone": 0 (el número puede variar según tu sistema)
EOF

# Ajustar permisos
chown -R antonio:antonio /home/antonio/.config
chown -R antonio:antonio /home/antonio/.profile
chmod +x /home/antonio/.profile

# Crear directorio para capturas de pantalla
mkdir -p /home/antonio/Imágenes
chown -R antonio:antonio /home/antonio/Imágenes

print_message "La instalación base ha sido completada."
print_message "Después de reiniciar:"
print_message "1. Retira el medio de instalación"
print_message "2. Selecciona Arch Linux en GRUB"
print_message "3. Inicia sesión como 'antonio'"
print_message "4. Conecta a Internet con 'nmtui'"
print_message "5. Para gestionar monitores, usa wdisplays o arandr"
print_message "6. Alt+Shift para cambiar entre teclado US y ES"
print_message "7. Super+Z para capturar pantalla (seleccionando zona)"
print_message "8. Super+V para acceder al historial del portapapeles"
print_message "9. Para instalar VSCode y otros programas, ya está disponible 'paru'"
print_warning "10. Es posible que necesites ajustar las rutas de los sensores (ver ~/.config/waybar/SENSOR_CONFIG.txt)"
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
