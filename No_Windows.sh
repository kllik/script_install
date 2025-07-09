#!/bin/bash

# === SCRIPT DE INSTALACIÓN DE ARCH LINUX CON BTRFS, HYPRLAND Y WAYBAR ===

# Configuración para: Nvidia RTX 3080 + AMD Ryzen 9 5900HX

# Autor: Antonio

# Uso: Este script continúa la instalación DESPUÉS de usar cfdisk para crear las particiones

# Configuración: Single boot - Solo Arch Linux (sin snapshots/puntos de recuperación)

# Colores para mensajes

GREEN=’\033[0;32m’
BLUE=’\033[0;34m’
RED=’\033[0;31m’
YELLOW=’\033[0;33m’
NC=’\033[0m’ # No Color

# Función para mostrar mensajes

print_message() {
echo -e “${BLUE}[INSTALACIÓN]${NC} $1”
}

print_success() {
echo -e “${GREEN}[COMPLETADO]${NC} $1”
}

print_error() {
echo -e “${RED}[ERROR]${NC} $1”
}

print_warning() {
echo -e “${YELLOW}[ADVERTENCIA]${NC} $1”
}

# Verificar si se está ejecutando como root

if [ “$(id -u)” -ne 0 ]; then
print_error “Este script debe ejecutarse como root”
exit 1
fi

# Definir dispositivos (asumiendo que ya se han creado las particiones)

DISK=”/dev/nvme0n1”
SYSTEM_DEV=”${DISK}p1”  # Partición 1: Linux filesystem (935GB)
SWAP_DEV=”${DISK}p2”    # Partición 2: Linux swap (16GB)
EFI_DEV=”${DISK}p3”     # Partición 3: EFI System (1GB)

print_message “Dispositivos a utilizar:”
print_message “Partición Sistema BTRFS: $SYSTEM_DEV - 935GB”
print_message “Partición SWAP: $SWAP_DEV - 16GB”
print_message “Partición EFI: $EFI_DEV - 1GB”
print_warning “Este script asume que ya creaste las particiones con cfdisk”
print_warning “Asegúrate de que las particiones existan y sean correctas”
echo
read -p “¿Continuar con la instalación? [s/N]: “ response
if [[ ! “$response” =~ ^([sS][iI]|[sS])$ ]]; then
print_message “Instalación cancelada”
exit 0
fi

# — 2) FORMATEO Y ACTIVACIÓN SWAP —

print_message “Formateando partición EFI (${EFI_DEV})…”
mkfs.fat -F32 $EFI_DEV
print_success “Partición EFI formateada”

print_message “Formateando y activando SWAP (${SWAP_DEV})…”
mkswap $SWAP_DEV && swapon $SWAP_DEV
print_success “SWAP configurada”

print_message “Formateando partición del sistema como BTRFS (${SYSTEM_DEV})…”
mkfs.btrfs -f $SYSTEM_DEV
print_success “Partición BTRFS formateada”

# — 3) MONTAR SISTEMA —

print_message “Montando sistema de archivos…”
mount -o noatime,compress=zstd,space_cache=v2 $SYSTEM_DEV /mnt
mkdir -p /mnt/boot/efi
mount $EFI_DEV /mnt/boot/efi
print_success “Sistema de archivos montado”

# — 4) INSTALAR SISTEMA BASE —

print_message “Instalando sistema base (esto puede tomar tiempo)…”
pacstrap /mnt base base-devel linux linux-headers linux-firmware amd-ucode btrfs-progs
print_success “Sistema base instalado”

# — 5) GENERAR FSTAB —

print_message “Generando fstab…”
genfstab -U /mnt >> /mnt/etc/fstab
print_success “fstab generado”

# — 6) PREPARAR CHROOT —

print_message “Preparando archivos para chroot…”

# Crear script post-chroot

cat > /mnt/root/post-chroot.sh << ‘EOL’
#!/bin/bash

# Colores para mensajes

GREEN=’\033[0;32m’
BLUE=’\033[0;34m’
RED=’\033[0;31m’
NC=’\033[0m’ # No Color

# Función para mostrar mensajes

print_message() {
echo -e “${BLUE}[INSTALACIÓN]${NC} $1”
}

print_success() {
echo -e “${GREEN}[COMPLETADO]${NC} $1”
}

print_error() {
echo -e “${RED}[ERROR]${NC} $1”
}

# — 8) INSTALAR NANO —

print_message “Instalando nano…”
pacman -Sy nano –noconfirm
print_success “Nano instalado”

# — 9) CONFIGURAR LOCALE Y ZONA HORARIA —

print_message “Configurando locale y zona horaria…”
sed -i ‘s/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/’ /etc/locale.gen
sed -i ‘s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/’ /etc/locale.gen
locale-gen
echo “LANG=es_ES.UTF-8” > /etc/locale.conf
ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime
hwclock –systohc
print_success “Locale y zona horaria configurados”

# — 10) HOSTNAME Y HOSTS —

print_message “Configurando hostname…”
echo “host” > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   host.localdomain host
EOF
print_success “Hostname configurado”

# — 11) CONTRASEÑA ROOT —

print_message “A continuación deberás configurar la contraseña de root:”
passwd

# — 12) HABILITAR MULTILIB —

print_message “Habilitando repositorio multilib…”
sed -i “/[multilib]/,/Include/”‘s/^#//’ /etc/pacman.conf
pacman -Syy
print_success “Repositorio multilib habilitado”

# — 13) INSTALAR PAQUETES ESENCIALES PRIMERO —

print_message “Instalando paquetes esenciales del sistema…”
pacman -S –noconfirm   
networkmanager sudo grub efibootmgr ntfs-3g mtools dosfstools   
nano vim git base-devel linux-headers
print_success “Paquetes esenciales instalados”

# — 14) INSTALAR DRIVERS NVIDIA —

print_message “Instalando drivers NVIDIA…”
pacman -S –noconfirm   
nvidia nvidia-utils nvidia-dkms nvidia-settings lib32-nvidia-utils   
vulkan-icd-loader lib32-vulkan-icd-loader egl-wayland
print_success “Drivers NVIDIA instalados”

# — 15) CONFIGURAR NVIDIA PARA WAYLAND —

print_message “Configurando NVIDIA para Wayland…”

# Crear directorio si no existe

mkdir -p /etc/modprobe.d

# Configuración de módulos NVIDIA

cat > /etc/modprobe.d/nvidia.conf << EOF
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

# Configurar mkinitcpio correctamente

print_message “Configurando mkinitcpio…”

# Asegurar que los módulos NVIDIA se agreguen correctamente

sed -i ‘s/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/’ /etc/mkinitcpio.conf

# Si ya hay módulos, agregar los de nvidia

sed -i ‘/^MODULES=(/s/)/ nvidia nvidia_modeset nvidia_uvm nvidia_drm)/’ /etc/mkinitcpio.conf

# Eliminar duplicados si los hay

sed -i ‘s/MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/’ /etc/mkinitcpio.conf

# Regenerar initramfs (esto se hará después de instalar todos los paquetes)

print_success “Configuración de NVIDIA preparada”

# — 16) INSTALAR HYPRLAND Y COMPONENTES DE ESCRITORIO —

print_message “Instalando Hyprland y componentes de escritorio…”
pacman -S –noconfirm   
hyprland xdg-desktop-portal-hyprland xorg-xwayland   
waybar wofi alacritty   
polkit polkit-gnome xdg-desktop-portal-gtk   
pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber   
grim slurp wl-clipboard brightnessctl playerctl   
thunar thunar-archive-plugin gvfs udisks2   
hyprpaper hyprlock hypridle swaync   
network-manager-applet blueman pavucontrol
print_success “Hyprland y componentes instalados”

# — 17) INSTALAR APLICACIONES —

print_message “Instalando aplicaciones…”
pacman -S –noconfirm   
firefox discord steam obs-studio   
neovim tmux   
btop fastfetch   
libreoffice-fresh   
imv mpv   
zathura zathura-pdf-mupdf   
unzip wget curl
print_success “Aplicaciones instaladas”

# — 18) INSTALAR FUENTES —

print_message “Instalando fuentes…”
pacman -S –noconfirm   
ttf-jetbrains-mono-nerd ttf-font-awesome   
noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation   
ttf-roboto ttf-ubuntu-font-family
print_success “Fuentes instaladas”

# — 19) INSTALAR HERRAMIENTAS DE DESARROLLO —

print_message “Instalando herramientas de desarrollo…”
pacman -S –noconfirm   
gcc clang cmake ninja meson gdb lldb   
python python-pip   
nodejs npm   
go   
rust rustup   
jdk-openjdk   
dotnet-sdk   
php sqlite   
lua   
typescript   
ruby rubygems   
kotlin
print_success “Herramientas de desarrollo instaladas”

# — 20) INSTALAR TEMAS Y CONFIGURACIÓN GTK/QT —

print_message “Instalando temas…”
pacman -S –noconfirm   
adwaita-icon-theme gnome-themes-extra   
qt5-wayland qt6-wayland qt5ct kvantum   
xdg-utils
print_success “Temas instalados”

# — 21) INSTALAR BLUETOOTH Y AUDIO —

print_message “Instalando soporte de Bluetooth y audio…”
pacman -S –noconfirm   
bluez bluez-utils   
pulseaudio-bluetooth
print_success “Bluetooth y audio instalados”

# — 22) INSTALAR HERRAMIENTAS ADICIONALES —

print_message “Instalando herramientas adicionales…”
pacman -S –noconfirm   
vulkan-tools vulkan-validation-layers   
sdl2 ddcutil
print_success “Herramientas adicionales instaladas”

# — 23) REGENERAR INITRAMFS CON TODOS LOS MÓDULOS —

print_message “Regenerando initramfs con configuración completa…”
mkinitcpio -P
print_success “Initramfs regenerado”

# — 24) CONFIGURAR GRUB —

print_message “Configurando GRUB…”

# Crear archivo de configuración si no existe

if [ ! -f /etc/default/grub ]; then
print_error “Archivo de GRUB no encontrado, creándolo…”
cat > /etc/default/grub << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=“Arch”
GRUB_CMDLINE_LINUX_DEFAULT=“loglevel=3 quiet nvidia-drm.modeset=1 amd_pstate=active”
GRUB_CMDLINE_LINUX=””
GRUB_PRELOAD_MODULES=“part_gpt part_msdos”
GRUB_TIMEOUT_STYLE=menu
GRUB_TERMINAL_INPUT=console
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_DISABLE_RECOVERY=true
EOF
else
# Modificar archivo existente
sed -i ‘s/GRUB_CMDLINE_LINUX_DEFAULT=”[^”]*”/GRUB_CMDLINE_LINUX_DEFAULT=“loglevel=3 quiet nvidia-drm.modeset=1 amd_pstate=active”/’ /etc/default/grub
fi

# Instalar GRUB

grub-install –target=x86_64-efi –efi-directory=/boot/efi –bootloader-id=GRUB

# Generar configuración de GRUB

grub-mkconfig -o /boot/grub/grub.cfg
print_success “GRUB configurado”

# — 25) CREAR GRUPOS NECESARIOS —

print_message “Creando grupos necesarios…”
groupadd -f wheel
groupadd -f video
groupadd -f audio
groupadd -f storage
groupadd -f optical
groupadd -f network
groupadd -f power
print_success “Grupos creados”

# — 26) CREAR USUARIO —

print_message “Creando usuario ‘antonio’…”

# Crear el usuario con los grupos correctos

useradd -m -G wheel,video,audio,storage,optical,network,power -s /bin/bash antonio

# Configurar contraseña

print_message “Configura la contraseña para el usuario ‘antonio’:”
passwd antonio

# Configurar sudo para el grupo wheel

print_message “Configurando privilegios sudo para el usuario ‘antonio’…”
echo “%wheel ALL=(ALL:ALL) ALL” > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
print_success “Usuario creado con privilegios sudo”

# — 27) HABILITAR SERVICIOS —

print_message “Habilitando servicios…”
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable fstrim.timer
print_success “Servicios habilitados”

# — 28) CONFIGURAR TEMA OSCURO Y VARIABLES DE ENTORNO —

print_message “Configurando tema oscuro para GTK y Qt…”

# Configuración global de GTK para modo oscuro

mkdir -p /etc/gtk-3.0 /etc/gtk-4.0
cat > /etc/gtk-3.0/settings.ini << EOF
[Settings]
gtk-application-prefer-dark-theme=true
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=JetBrains Mono Nerd Font 11
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF

# Copiar la misma configuración para GTK4

cp /etc/gtk-3.0/settings.ini /etc/gtk-4.0/settings.ini

# Configurar variables de entorno para el sistema

cat > /etc/environment << EOF

# Tema oscuro para Qt y GTK

QT_QPA_PLATFORMTHEME=qt5ct
GTK_THEME=Adwaita-dark
EOF

print_success “Tema oscuro configurado”

# — 29) CONFIGURAR HYPRLAND, WAYBAR Y ALACRITTY —

print_message “Configurando entorno Hyprland, Waybar y Alacritty…”

# Crear directorios de configuración

mkdir -p /home/antonio/.config/{hypr/scripts,waybar,alacritty,qt5ct,gtk-3.0,gtk-4.0,wofi}
mkdir -p /home/antonio/Imágenes/Capturas
mkdir -p /home/antonio/Wallpapers

# Script para cambiar el fondo de pantalla

cat > /home/antonio/.config/hypr/scripts/wallpaper-changer.sh << ‘EOF’
#!/bin/bash
WALLPAPERS_DIR=”$HOME/Wallpapers”
if [ ! -d “$WALLPAPERS_DIR” ] || [ -z “$(ls -A $WALLPAPERS_DIR)” ]; then
notify-send “Error” “No hay fondos de pantalla disponibles en $WALLPAPERS_DIR” -i dialog-error
exit 1
fi

WALLPAPERS=($WALLPAPERS_DIR/*)
RANDOM_WALLPAPER=${WALLPAPERS[$RANDOM % ${#WALLPAPERS[@]}]}
MONITOR=${1:-“eDP-1”}

# Actualiza la configuración de hyprpaper

sed -i “s|wallpaper = $MONITOR,.*|wallpaper = $MONITOR,$RANDOM_WALLPAPER|g” $HOME/.config/hypr/hyprpaper.conf

# Recarga hyprpaper

killall hyprpaper
hyprpaper &

notify-send “Fondo cambiado” “Nuevo fondo: $RANDOM_WALLPAPER” -i dialog-information
EOF

chmod +x /home/antonio/.config/hypr/scripts/wallpaper-changer.sh

# Configuración básica de hyprpaper

cat > /home/antonio/.config/hypr/hyprpaper.conf << EOF

# Para añadir fondos, coloca imágenes en ~/Wallpapers y añade las siguientes líneas:

# preload = /home/antonio/Wallpapers/tu-imagen.jpg

# wallpaper = HDMI-A-1,/home/antonio/Wallpapers/tu-imagen.jpg

# wallpaper = eDP-1,/home/antonio/Wallpapers/tu-imagen.jpg

EOF

# Configuración de Hyprland

cat > /home/antonio/.config/hypr/hyprland.conf << EOF
################

### MONITORS

################

# Configuración exacta basada en hyprctl monitors

monitor=HDMI-A-1,1920x1080@144.01300,0x0,1
monitor=eDP-1,2560x1600@165.00400,1920x0,1.6
bind = SUPER, Z, exec, grim -g “$(slurp)” ~/Imágenes/Capturas/captura-$(date +’%Y%m%d-%H%M%S’).png

###################

### MY PROGRAMS

###################
$terminal = alacritty
$fileManager = thunar
$menu = wofi –show drun

#################

### AUTOSTART

#################
exec-once = waybar
exec-once = hyprpaper
exec-once = blueman-applet
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = nm-applet
exec-once = swaync
exec-once = dbus-update-activation-environment –systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

#############################

### ENVIRONMENT VARIABLES

#############################
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GDK_BACKEND,wayland
env = GTK_THEME,Adwaita-dark

# Optimizaciones para NVIDIA RTX 3080

env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GL_GSYNC_ALLOWED,1
env = __GL_VRR_ALLOWED,1
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_DRM_NO_ATOMIC,1

#####################

### LOOK AND FEEL

#####################
general {
gaps_in = 2
gaps_out = 8
border_size = 2
col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
col.inactive_border = rgba(595959aa)
resize_on_border = false
allow_tearing = false
layout = dwindle
}

decoration {
rounding = 10
active_opacity = 1.0
inactive_opacity = 1.0

```
blur {
    enabled = true
    size = 3
    passes = 1
    vibrancy = 0.1696
}

drop_shadow = true
shadow_range = 4
shadow_render_power = 3
col.shadow = rgba(1a1a1aee)
```

}

animations {
enabled = yes
bezier = easeOutQuint,0.23,1,0.32,1
bezier = easeInOutCubic,0.65,0.05,0.36,1
bezier = linear,0,0,1,1
bezier = almostLinear,0.5,0.5,0.75,1.0
bezier = quick,0.15,0,0.1,1

```
animation = global, 1, 10, default
animation = border, 1, 5.39, easeOutQuint
animation = windows, 1, 4.79, easeOutQuint
animation = windowsIn, 1, 4.1, easeOutQuint, popin 87%
animation = windowsOut, 1, 1.49, linear, popin 87%
animation = fadeIn, 1, 1.73, almostLinear
animation = fadeOut, 1, 1.46, almostLinear
animation = fade, 1, 3.03, quick
animation = layers, 1, 3.81, easeOutQuint
animation = layersIn, 1, 4, easeOutQuint, fade
animation = layersOut, 1, 1.5, linear, fade
animation = fadeLayersIn, 1, 1.79, almostLinear
animation = fadeLayersOut, 1, 1.39, almostLinear
animation = workspaces, 1, 1.94, almostLinear, fade
animation = workspacesIn, 1, 1.21, almostLinear, fade
animation = workspacesOut, 1, 1.94, almostLinear, fade
```

}

dwindle {
pseudotile = true
preserve_split = true
}

master {
new_status = master
}

misc {
force_default_wallpaper = 0
disable_hyprland_logo = true
vfr = true
vrr = 1
}

xwayland {
force_zero_scaling = true
}

#############

### INPUT

#############
input {
kb_layout = us,es
kb_variant = ,
kb_model =
kb_options = grp:alt_shift_toggle
kb_rules =

```
follow_mouse = 1
sensitivity = 0

touchpad {
    natural_scroll = false
}
```

}

gestures {
workspace_swipe = false
}

device {
name = epic-mouse-v1
sensitivity = -0.5
}

###################

### KEYBINDINGS

###################
$mainMod = SUPER

# Aplicaciones principales

bind = $mainMod, Q, exec, $terminal
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, $menu
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,
bind = $mainMod, F, fullscreen,

# Movimiento del foco

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

# Mover ventana activa a espacio de trabajo

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

# Espacio de trabajo especial (scratchpad)

bind = $mainMod, S, togglespecialworkspace, magic
bind = $mainMod SHIFT, S, movetoworkspace, special:magic

# Scroll a través de espacios de trabajo

bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Mover/redimensionar ventanas con mouse

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Control de volumen y brillo

bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindel = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindel = ,XF86MonBrightnessUp, exec, brightnessctl s 10%+
bindel = ,XF86MonBrightnessDown, exec, brightnessctl s 10%-

# Control de medios

bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPause, exec, playerctl play-pause
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioPrev, exec, playerctl previous

# Capturas de pantalla

bind = , Print, exec, grim -g “$(slurp)” - | wl-copy

# Cambiar fondo de pantalla

bind = Ctrl+Super, T, exec, ~/.config/hypr/scripts/wallpaper-changer.sh

##############################

### WINDOWS AND WORKSPACES

##############################
windowrulev2 = float,class:^(pavucontrol)$
windowrulev2 = float,class:^(blueman-manager)$
windowrulev2 = float,class:^(nm-connection-editor)$
windowrulev2 = float,title:^(Steam - News)$

# Ignorar solicitudes de maximización

windowrulev2 = suppressevent maximize, class:.*

# Arreglos para XWayland

windowrulev2 = nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0

# Arreglos para VSCode

windowrulev2 = opacity 1.0 override,class:^(code-oss)$
windowrulev2 = opacity 1.0 override,class:^(Code)$
EOF

# Configuración de Waybar (config)

cat > /home/antonio/.config/waybar/config << EOF
{
“layer”: “top”,
“position”: “top”,
“height”: 30,
“spacing”: 0,
“modules-left”: [“wlr/taskbar”, “hyprland/workspaces”],
“modules-center”: [“clock”],
“modules-right”: [“custom/ram”, “custom/cpu”, “custom/gpu”],
“wlr/taskbar”: {
“format”: “{icon}”,
“icon-size”: 18,
“tooltip-format”: “{title}”,
“on-click”: “activate”,
“on-click-middle”: “close”,
“ignore-list”: []
},
“hyprland/workspaces”: {
“format”: “{icon}”,
“format-icons”: {
“1”: “1”,
“2”: “2”,
“3”: “3”,
“4”: “4”,
“5”: “5”,
“default”: “”
},
“on-click”: “activate”
},
“clock”: {
“format”: “{:%H:%M:%S}”,
“format-alt”: “{:%Y-%m-%d}”,
“tooltip-format”: “<tt>{calendar}</tt>”,
“interval”: 1
},
“custom/ram”: {
“format”: “<span color='#00FF00'>RAM</span> <span color='white'>{}</span>”,
“exec”: “free -m | awk ‘/^Mem/ {printf "%d MiB", $3}’”,
“interval”: 1
},
“custom/cpu”: {
“format”: “<span color='#2F79F8'>CPU</span> <span color='white'>{}</span>”,
“exec”: “sensors | grep ‘Tctl’ | awk ‘{print $2}’ | cut -c 2- | tr -d ‘+’”,
“interval”: 1
},
“custom/gpu”: {
“format”: “<span color='#4B95C7'>GPU</span> <span color='white'>{}</span>”,
“exec”: “nvidia-smi –query-gpu=temperature.gpu,utilization.gpu –format=csv,noheader,nounits | awk -F’, ’ ‘{print $1"°C "$2"%"}’”,
“interval”: 1
}
}
EOF

# Configuración de Waybar (style.css)

cat > /home/antonio/.config/waybar/style.css << EOF

- {
  font-family: “JetBrains Mono Nerd Font”, “Font Awesome 6 Free”;
  font-size: 16px;
  border: none;
  border-radius: 0;
  min-height: 0;
  margin: 0;
  padding: 0;
  }

window#waybar {
background: #000000;
color: #ffffff;
}

#workspaces button {
padding: 0 5px;
background: transparent;
color: #ffffff;
}

#workspaces button.active {
color: #ffffff;
font-weight: bold;
}

#clock {
color: #ffffff;
padding: 0 10px;
}

#custom-ram {
color: #ffffff;
padding: 0 10px;
}

#custom-cpu {
padding: 0 10px;
}

#custom-gpu {
padding: 0 10px;
}
EOF

# Configuración de Alacritty

cat > /home/antonio/.config/alacritty/alacritty.toml << EOF

# Configuración completa de Alacritty para Hyprland

[window]

# Configuración de ventana

opacity = 0.95
dynamic_padding = true
decorations = “none”

[window.padding]
x = 10
y = 10

[font]

# Fuente principal

normal = { family = “JetBrainsMono Nerd Font”, style = “Regular” }
bold = { family = “JetBrainsMono Nerd Font”, style = “Bold” }
italic = { family = “JetBrainsMono Nerd Font”, style = “Italic” }
bold_italic = { family = “JetBrainsMono Nerd Font”, style = “Bold Italic” }
size = 12.0

[colors]

# Tema oscuro elegante

[colors.primary]
background = “#2B2B2B”
foreground = “#CCCCCC”

[colors.normal]
black = “#3B3B3B”
red = “#CF6A4C”
green = “#8F9D6A”
yellow = “#F9EE98”
blue = “#7587A6”
magenta = “#9B859D”
cyan = “#AFC4DB”
white = “#A7A7A7”

[colors.bright]
black = “#555555”
red = “#CF6A4C”
green = “#8F9D6A”
yellow = “#F9EE98”
blue = “#7587A6”
magenta = “#9B859D”
cyan = “#AFC4DB”
white = “#FFFFFF”

[cursor]
style = { shape = “Block”, blinking = “On” }
vi_mode_style = { shape = “Block”, blinking = “Off” }

[shell]
program = “/bin/bash”
args = [”–login”]

[env]

# Variables de entorno importantes para Wayland

TERM = “xterm-256color”

[keyboard]

# Atajos de teclado para mantener la funcionalidad de Kitty

bindings = [
# Funciones básicas de copiado y pegado
{ key = “C”, mods = “Control”, action = “Copy” },
{ key = “V”, mods = “Control”, action = “Paste” },

```
# Control de zoom
{ key = "Plus", mods = "Control", action = "IncreaseFontSize" },
{ key = "Minus", mods = "Control", action = "DecreaseFontSize" },
{ key = "Key0", mods = "Control", action = "ResetFontSize" },

# Funciones adicionales (comportamiento original de Bash)
{ key = "C", mods = "Control|Shift", chars = "\u0003" },
{ key = "V", mods = "Control|Shift", chars = "\u0016" },
{ key = "K", mods = "Control|Shift", chars = "\u000b" },

# Clear screen con Ctrl+K (como en Kitty)
{ key = "K", mods = "Control", chars = "\u0001\u000b" },
```

]
EOF

# Configuración de Wofi

mkdir -p /home/antonio/.config/wofi
cat > /home/antonio/.config/wofi/config << EOF
width=600
height=400
location=center
show=drun
prompt=Buscar
filter_rate=100
allow_markup=true
no_actions=true
halign=fill
orientation=vertical
content_halign=fill
insensitive=true
allow_images=true
image_size=40
gtk_dark=true
dynamic_lines=true
EOF

cat > /home/antonio/.config/wofi/style.css << EOF
window {
margin: 0px;
border: 2px solid #33ccff;
background-color: #2B2B2B;
border-radius: 10px;
}

#input {
margin: 5px;
border: none;
color: #ffffff;
background-color: #3B3B3B;
border-radius: 5px;
padding: 10px;
}

#inner-box {
margin: 5px;
border: none;
background-color: #2B2B2B;
}

#outer-box {
margin: 5px;
border: none;
background-color: #2B2B2B;
}

#scroll {
margin: 0px;
border: none;
}

#text {
margin: 5px;
border: none;
color: #ffffff;
}

#entry:selected {
background-color: #3B3B3B;
border-radius: 5px;
}

#text:selected {
color: #33ccff;
}
EOF

# Configurar autostart

mkdir -p /home/antonio/.config/autostart
cat > /home/antonio/.config/autostart/hyprland.desktop << EOF
[Desktop Entry]
Type=Application
Name=Hyprland
Exec=/usr/bin/Hyprland
EOF

# Configuración de Bash

cat > /home/antonio/.bashrc << ‘EOF’

# .bashrc

# If not running interactively, don’t do anything

[[ $- != *i* ]] && return

# Configuración de alias

alias ls=‘ls –color=auto’
alias ll=‘ls -la’
alias grep=‘grep –color=auto’

# Configuración del prompt

PS1=’[\u@\h \W]$ ’

# Variables de entorno para desarrollo

export EDITOR=nvim
export VISUAL=nvim

# Configuración para lenguajes de programación

export PATH=”$PATH:$HOME/.cargo/bin”
export PATH=”$PATH:/usr/lib/jvm/default/bin”
export PATH=”$PATH:$HOME/go/bin”
export GOPATH=”$HOME/go”

# Ruby Gems

export GEM_HOME=”$HOME/.gem”
export PATH=”$PATH:$GEM_HOME/bin”

# Inicializar Rust si está instalado

[ -f “$HOME/.cargo/env” ] && source “$HOME/.cargo/env”
EOF

# Configuración de perfil

cat > /home/antonio/.profile << ‘EOF’

# Variables de entorno

export QT_QPA_PLATFORMTHEME=“qt5ct”
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export GTK_THEME=“Adwaita-dark”
export MOZ_ENABLE_WAYLAND=1

# Si ejecutamos bash

if [ -n “$BASH_VERSION” ]; then
if [ -f “$HOME/.bashrc” ]; then
. “$HOME/.bashrc”
fi
fi
EOF

# Recomendaciones para post-instalación

cat > /home/antonio/recomendaciones-post-instalacion.txt << ‘EOF’
=== RECOMENDACIONES POST-INSTALACIÓN ===

Para instalar Visual Studio Code y herramientas adicionales:

1. Instalar yay (AUR helper):
   sudo pacman -S –needed git base-devel
   git clone https://aur.archlinux.org/yay.git
   cd yay
   makepkg -si
1. Instalar Visual Studio Code:
   yay -S visual-studio-code-bin
1. Configurar Rust correctamente:
   rustup default stable
1. Para proyectos con Tauri:
   sudo npm install -g @tauri-apps/cli
1. Instalar Swift:
   
   # Swift requiere instalación desde AUR
   
   yay -S swift-bin
   
   # O si prefieres compilar desde fuente:
   
   yay -S swift
1. LIMPIEZA: Eliminar xgpsspeed y xgps (se instalan con waybar pero no son necesarios):
   sudo rm /usr/bin/xgpsspeed
   sudo rm /usr/bin/xgps
   
   # Verificar que waybar funciona correctamente:
   
   waybar –version
1. Verificar instalación de lenguajes:
- PHP: php –version
- SQLite: sqlite3 –version
- Go: go version
- Java: java –version
- Kotlin: kotlin -version
- Ruby: ruby –version && gem –version
- Lua: lua -v
- Python: python –version
- C/C++: gcc –version && g++ –version
- C#: dotnet –version
- Rust: rustc –version
- JavaScript/TypeScript: node –version && tsc –version
- Swift: swift –version (después de instalarlo desde AUR)

NOTAS IMPORTANTES:

- Alacritty está configurado con los mismos atajos que tenías en Kitty
- Ctrl+C/V funcionan para copiar/pegar
- Ctrl+K limpia la pantalla
- Ctrl+Shift+C/V/K envían las señales originales de Bash
- Para cambiar entre teclado US y ES: Alt+Shift
- Para cambiar fondo de pantalla: Ctrl+Super+T
- Para captura de pantalla: Tecla Print o Super+Z
- Wofi se abre con Super+R (reemplazo de Rofi)

DESARROLLO CON KOTLIN:

- Kotlin ya está instalado y listo para usar
- Para proyectos Android, instala Android Studio:
  yay -S android-studio
- Para proyectos Kotlin Native o Multiplatform:
  Usa IntelliJ IDEA: yay -S intellij-idea-community-edition

DESARROLLO CON RUBY:

- Ruby y RubyGems ya están instalados
- Para Ruby on Rails:
  gem install rails
- Para gestionar versiones de Ruby:
  yay -S rbenv ruby-build

DESARROLLO CON SWIFT:

- Swift debe instalarse desde AUR como se indica arriba
- Para desarrollo iOS/macOS en Linux es limitado
- Principalmente útil para desarrollo del lado servidor o CLI

SOBRE SEGURIDAD:

- Steam y Discord solo transmiten datos a sus propios servidores
- Bluetooth está instalado pero puedes deshabilitarlo si no lo usas:
  sudo systemctl disable bluetooth
- Para mayor seguridad, instala un firewall:
  sudo pacman -S ufw
  sudo ufw enable
  sudo systemctl enable ufw

EOF

# Cambiar propiedad de los archivos al usuario antonio

chown -R antonio:antonio /home/antonio/

print_message “La instalación base ha sido completada.”
print_message “Después de reiniciar:”
print_message “1. Retira el medio de instalación”
print_message “2. Inicia sesión como ‘antonio’”
print_message “3. Conecta a Internet con ‘nmtui’ si es necesario”
print_message “4. Revisa el archivo ~/recomendaciones-post-instalacion.txt para más información”
print_message “5. Para cambiar entre teclado en inglés (US) y español, usa Alt+Shift”
EOL

# Hacer ejecutable el script post-chroot

chmod +x /mnt/root/post-chroot.sh

# — 7) EJECUTAR CHROOT —

print_message “Ejecutando chroot para continuar la instalación…”
arch-chroot /mnt /root/post-chroot.sh
print_success “Instalación base completada”

# — 8) FINALIZAR —

print_message “Instalación completada exitosamente.”
print_message “El sistema se reiniciará en 10 segundos.”
print_message “Recuerda retirar el medio de instalación durante el reinicio.”

sleep 10
umount -R /mnt
reboot
