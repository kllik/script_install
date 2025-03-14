#!/bin/bash

# === SCRIPT DE INSTALACIÓN DE ARCH LINUX CON BTRFS, HYPRLAND Y WAYBAR ===
# Configuración para: Nvidia RTX 3080 + AMD Ryzen 9 5900HX
# Autor: Antonio
# Uso: Este script continúa la instalación DESPUÉS de usar cfdisk para crear las particiones
# Modificado para: Dual boot con Windows (utilizando particiones 5, 6 y 7)

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
EFI_DEV="${DISK}p5"  # Partición 5: EFI System (1GB)
SWAP_DEV="${DISK}p6"  # Partición 6: Linux swap (8GB)
SYSTEM_DEV="${DISK}p7"  # Partición 7: Linux filesystem (resto)

print_message "Dispositivos a utilizar para dual boot:"
print_message "Partición EFI: $EFI_DEV (1GB)"
print_message "Partición SWAP: $SWAP_DEV (8GB)"
print_message "Partición Sistema (BTRFS): $SYSTEM_DEV (resto del disco)"
print_warning "Este script asume que ya creaste las particiones con cfdisk"
print_warning "Asegúrate de que las particiones existan y sean correctas"
print_warning "Este script está configurado para dual boot con Windows"
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
ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime
hwclock --systohc
print_success "Locale y zona horaria configurados"

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
pacman -S --noconfirm nvidia nvidia-utils nvidia-dkms lib32-nvidia-utils \
    hyprland xdg-desktop-portal-hyprland xorg-xwayland wlroots \
    waybar rofi kitty networkmanager sudo grub efibootmgr \
    pipewire pipewire-pulse pipewire-alsa wireplumber bluez bluez-utils \
    firefox discord steam obs-studio neovim bash egl-wayland thunar \
    python python-pip lua go nodejs npm typescript sqlite \
    clang cmake ninja meson gdb lldb git tmux \
    sdl2 vulkan-icd-loader vulkan-validation-layers vulkan-tools spirv-tools \
    hyprpaper hyprlock fastfetch pavucontrol ddcutil btop \
    ttf-jetbrains-mono-nerd \
    yazi zathura zathura-pdf-mupdf bluetui swaync \
    noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation \
    xdg-utils xorg-xrandr qt5-wayland qt6-wayland \
    adwaita-icon-theme gnome-themes-extra blueman \
    polkit-gnome xdg-desktop-portal-gtk brightnessctl playerctl \
    grim slurp wl-clipboard network-manager-applet \
    libreoffice-fresh imv glow wget \
    timeshift unzip gvfs udisks2 thunar-archive-plugin \
    os-prober ntfs-3g
print_success "Paquetes clave instalados"

# --- 14) CONFIGURAR NVIDIA PARA WAYLAND ---
print_message "Configurando NVIDIA para Wayland..."
echo "options nvidia_drm modeset=1" > /etc/modprobe.d/nvidia.conf
echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" >> /etc/modprobe.d/nvidia.conf
echo "options nvidia NVreg_RegistryDwords=\"PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerLevel=0x3; PowerMizerDefault=0x3; PowerMizerDefaultAC=0x1\"" >> /etc/modprobe.d/nvidia.conf
sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
mkinitcpio -P
print_success "NVIDIA configurado para Wayland"

# --- 15) CONFIGURAR GRUB PARA DUAL BOOT ---
print_message "Configurando GRUB para dual boot..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1 amd_pstate=active"/' /etc/default/grub
# Habilitar os-prober para detectar Windows
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
# Actualizar os-prober para encontrar Windows
os-prober
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configurado para dual boot"

# --- 16) CREAR USUARIO ---
print_message "Creando usuario 'antonio'..."
# Primero aseguramos que exista el grupo wheel
groupadd -f wheel
# Crear el usuario
useradd -m -G wheel,seat,video,audio,storage,optical -s /bin/bash antonio
# Configurar contraseña
print_message "Configura la contraseña para el usuario 'antonio':"
passwd antonio

# Configurar sudo para el grupo wheel
print_message "Configurando privilegios sudo para el usuario 'antonio'..."
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
print_success "Usuario creado con privilegios sudo"

# --- 17) HABILITAR SERVICIOS ---
print_message "Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable seatd
systemctl enable fstrim.timer
print_success "Servicios habilitados"

# --- 19) CONFIGURAR TEMA OSCURO Y QT5CT ---
print_message "Configurando tema oscuro para GTK y Qt..."

# Configuración global de GTK para modo oscuro
mkdir -p /etc/gtk-3.0 /etc/gtk-4.0
cat > /etc/gtk-3.0/settings.ini << EOF
[Settings]
gtk-application-prefer-dark-theme=true
gtk-theme-name=Materia-dark
gtk-icon-theme-name=Papirus-Dark
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
QT_STYLE_OVERRIDE=kvantum
GTK_THEME=Materia-dark
EOF

print_success "Tema oscuro configurado"

# --- 20) CONFIGURAR HYPRLAND, WAYBAR Y KITTY ---
print_message "Configurando entorno Hyprland, Waybar y Kitty..."

# Crear directorios de configuración
mkdir -p /home/antonio/.config/{hypr/scripts,waybar,kitty,qt5ct,gtk-3.0,gtk-4.0,Kvantum}
mkdir -p /home/antonio/Imágenes/Capturas
mkdir -p /home/antonio/Wallpapers

# Script para cambiar el fondo de pantalla
cat > /home/antonio/.config/hypr/scripts/wallpaper-changer.sh << 'EOF'
#!/bin/bash
WALLPAPERS_DIR="$HOME/Wallpapers"
if [ ! -d "$WALLPAPERS_DIR" ] || [ -z "$(ls -A $WALLPAPERS_DIR)" ]; then
    notify-send "Error" "No hay fondos de pantalla disponibles en $WALLPAPERS_DIR" -i dialog-error
    exit 1
fi

WALLPAPERS=($WALLPAPERS_DIR/*)
RANDOM_WALLPAPER=${WALLPAPERS[$RANDOM % ${#WALLPAPERS[@]}]}
MONITOR=${1:-"eDP-1"}

# Actualiza la configuración de hyprpaper
sed -i "s|wallpaper = $MONITOR,.*|wallpaper = $MONITOR,$RANDOM_WALLPAPER|g" $HOME/.config/hypr/hyprpaper.conf

# Recarga hyprpaper
killall hyprpaper
hyprpaper &

notify-send "Fondo cambiado" "Nuevo fondo: $RANDOM_WALLPAPER" -i dialog-information
EOF

chmod +x /home/antonio/.config/hypr/scripts/wallpaper-changer.sh

# Configuración básica de hyprpaper
cat > /home/antonio/.config/hypr/hyprpaper.conf << EOF
# Para añadir fondos, coloca imágenes en ~/Wallpapers y añade las siguientes líneas:
# preload = /home/antonio/Wallpapers/tu-imagen.jpg
# wallpaper = HDMI-A-1,/home/antonio/Wallpapers/tu-imagen.jpg
# wallpaper = eDP-1,/home/antonio/Wallpapers/tu-imagen.jpg
EOF

# Configuración de Hyprland con configuración exacta de monitores
cat > /home/antonio/.config/hypr/hyprland.conf << EOF
################
### MONITORS ###
################
# Configuración exacta basada en hyprctl monitors
monitor=HDMI-A-1,1920x1080@144.01300,0x0,1
monitor=eDP-1,2560x1600@165.00400,1920x0,1.6
bind = SUPER, Z, exec, grim -g "$(slurp)" ~/Imágenes/Capturas/captura-$(date +'%Y%m%d-%H%M%S').png
###################
### MY PROGRAMS ###
###################
\$terminal = kitty
\$fileManager = thunar
\$menu = rofi -show drun
#################
### AUTOSTART ###
#################
exec-once = waybar
exec-once = hyprpaper
exec-once = blueman-applet
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = nm-applet
exec-once = swaync
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
#############################
### ENVIRONMENT VARIABLES ###
#############################
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GDK_BACKEND,wayland
env = NVIDIA_FORCE_LOADING_X11GLX,1
# Forzar modo oscuro
env = GTK_THEME,Materia-dark
# Optimizaciones para NVIDIA en Wayland
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GL_GSYNC_ALLOWED,1
env = __GL_VRR_ALLOWED,1
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_DRM_NO_ATOMIC,1
#####################
### LOOK AND FEEL ###
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
    rounding_power = 2
    # Change transparency of focused and unfocused windows
    active_opacity = 1.0
    inactive_opacity = 1.0
    shadow {
        enabled = true
        range = 4
        render_power = 3
        color = rgba(1a1a1aee)
    }
    blur {
        enabled = true
        size = 3
        passes = 1
        vibrancy = 0.1696
    }
}
animations {
    enabled = yes, please :)
    bezier = easeOutQuint,0.23,1,0.32,1
    bezier = easeInOutCubic,0.65,0.05,0.36,1
    bezier = linear,0,0,1,1
    bezier = almostLinear,0.5,0.5,0.75,1.0
    bezier = quick,0.15,0,0.1,1
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
}
dwindle {
    pseudotile = true # Master switch for pseudotiling. Enabling is bound to mainMod + P in t>
    preserve_split = true # You probably want this
}
master {
    new_status = master
}
misc {
    force_default_wallpaper = 0 # Set to 0 to disable the anime mascot wallpapers
    disable_hyprland_logo = true # Disable the hyprland logo background
    vfr = true # Variable framerate for better performance
    vrr = 1 # Variable refresh rate - helps prevent tearing
}
xwayland {
    force_zero_scaling = true
}
#############
### INPUT ###
#############
input {
    kb_layout = us,es
    kb_variant = ,
    kb_model =
    kb_options = grp:alt_shift_toggle
    kb_rules =
    follow_mouse = 1
   sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
    touchpad {
        natural_scroll = false
    }
}
gestures {
    workspace_swipe = false
}
device {
    name = epic-mouse-v1
    sensitivity = -0.5
}
###################
### KEYBINDINGS ###
###################
\$mainMod = SUPER # Sets "Windows" key as main modifier
# Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
bind = \$mainMod, Q, exec, \$terminal
bind = \$mainMod, C, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, \$fileManager
bind = \$mainMod, V, togglefloating,
bind = \$mainMod, R, exec, \$menu
bind = \$mainMod, P, pseudo, # dwindle
bind = \$mainMod, J, togglesplit, # dwindle
bind = \$mainMod, F, fullscreen, # Toggle fullscreen
# Move focus with mainMod + arrow keys
bind = \$mainMod, left, movefocus, l
bind = \$mainMod, right, movefocus, r
bind = \$mainMod, up, movefocus, u
bind = \$mainMod, down, movefocus, d

# Switch workspaces with mainMod + [0-9]
bind = \$mainMod, 1, workspace, 1
bind = \$mainMod, 2, workspace, 2
bind = \$mainMod, 3, workspace, 3
bind = \$mainMod, 4, workspace, 4
bind = \$mainMod, 5, workspace, 5
bind = \$mainMod, 6, workspace, 6
bind = \$mainMod, 7, workspace, 7
bind = \$mainMod, 8, workspace, 8
bind = \$mainMod, 9, workspace, 9
bind = \$mainMod, 0, workspace, 10
# Move active window to a workspace with mainMod + SHIFT + [0-9]
bind = \$mainMod SHIFT, 1, movetoworkspace, 1
bind = \$mainMod SHIFT, 2, movetoworkspace, 2
bind = \$mainMod SHIFT, 3, movetoworkspace, 3
bind = \$mainMod SHIFT, 4, movetoworkspace, 4
bind = \$mainMod SHIFT, 5, movetoworkspace, 5
bind = \$mainMod SHIFT, 6, movetoworkspace, 6
bind = \$mainMod SHIFT, 7, movetoworkspace, 7
bind = \$mainMod SHIFT, 8, movetoworkspace, 8
bind = \$mainMod SHIFT, 9, movetoworkspace, 9
bind = \$mainMod SHIFT, 0, movetoworkspace, 10
# Example special workspace (scratchpad)
bind = \$mainMod, S, togglespecialworkspace, magic
bind = \$mainMod SHIFT, S, movetoworkspace, special:magic
# Scroll through existing workspaces with mainMod + scroll
bind = \$mainMod, mouse_down, workspace, e+1
bind = \$mainMod, mouse_up, workspace, e-1
# Move/resize windows with mainMod + LMB/RMB and dragging
bindm = \$mainMod, mouse:272, movewindow
bindm = \$mainMod, mouse:273, resizewindow
# Laptop multimedia keys for volume and LCD brightness
bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-

bindel = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindel = ,XF86MonBrightnessUp, exec, brightnessctl s 10%+
bindel = ,XF86MonBrightnessDown, exec, brightnessctl s 10%-
# Media controls using playerctl
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPause, exec, playerctl play-pause
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioPrev, exec, playerctl previous
# Take screenshots
bind = , Print, exec, grim -g "\$(slurp)" - | wl-copy
##############################
### WINDOWS AND WORKSPACES ###
##############################
# See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
# See https://wiki.hyprland.org/Configuring/Workspace-Rules/ for workspace rules
# Example windowrule v1
# windowrule = float, ^(kitty)\$
# Example windowrule v2
# windowrulev2 = float,class:^(kitty)\$,title:^(kitty)\$
# Specific rules for installed applications
windowrulev2 = float,class:^(pavucontrol)\$
windowrulev2 = float,class:^(blueman-manager)\$
windowrulev2 = float,class:^(nm-connection-editor)\$
windowrulev2 = float,title:^(Steam - News)\$
# Ignore maximize requests from apps. You'll probably like this.
windowrulev2 = suppressevent maximize, class:.*
# Fix some dragging issues with XWayland
windowrulev2 = nofocus,class:^\$,title:^\$,xwayland:1,floating:1,fullscreen:0,pinned:0
# Arreglos para VSCode y aplicaciones que se ven borrosas
windowrulev2 = opacity 1.0 override,class:^(code-oss)\$
windowrulev2 = opacity 1.0 override,class:^(Code)\$
EOF

# Añadir tecla para cambiar el fondo
echo "bind = Ctrl+Super, T, exec, ~/.config/hypr/scripts/wallpaper-changer.sh" >> /home/antonio/.config/hypr/hyprland.conf

# Configuración exacta de Waybar (config)
cat > /home/antonio/.config/waybar/config << EOF
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 0,
    "modules-left": ["wlr/taskbar", "hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["custom/ram", "custom/cpu", "custom/gpu"],
    "wlr/taskbar": {
        "format": "{icon}",
        "icon-size": 18,
        "tooltip-format": "{title}",
        "on-click": "activate",
        "on-click-middle": "close",
        "ignore-list": []
    },
    "hyprland/workspaces": {
        "format": "{icon}",
        "format-icons": {
            "1": "1",
            "2": "2",
            "3": "3",
            "4": "4",
            "5": "5",
            "default": ""
        },
        "on-click": "activate"
    },
    "clock": {
        "format": "{:%H:%M:%S}",
        "format-alt": "{:%Y-%m-%d}",
        "tooltip-format": "<tt>{calendar}</tt>",
        "interval": 1
    },
    "custom/ram": {
        "format": "<span color='#00FF00'>RAM</span> <span color='white'>{}</span>",
        "exec": "free -m | awk '/^Mem/ {printf \"%d MiB\", \$3}'",
        "interval": 1
    },
    "custom/cpu": {
        "format": "<span color='#2F79F8'>CPU</span> <span color='white'>{}</span>",
        "exec": "sensors | grep 'Tctl' | awk '{print \$2}' | cut -c 2- | tr -d '+'",
        "interval": 1
    },
    "custom/gpu": {
        "format": "<span color='#4B95C7'>GPU</span> <span color='white'>{}</span>",
        "exec": "nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits | awk -F', ' '{print \$1\"°C \"\$2\"%\"}'",
        "interval": 1
    }
}
EOF

# Configuración de Waybar (style.css)
cat > /home/antonio/.config/waybar/style.css << EOF
* {
    font-family: "JetBrains Mono Nerd Font", "Font Awesome 6 Free";
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

# Configuración de Kitty
cat > /home/antonio/.config/kitty/kitty.conf << EOF
font_family JetBrainsMono Nerd Font
font_size 12.0
# Fondo gris oscuro elegante
background #2B2B2B
# Colores básicos ajustados para modo oscuro
color0  #3B3B3B
color8  #555555
# --------------------------------------
# Funciones personalizadas (Kitty)
# --------------------------------------
map ctrl+c copy_to_clipboard
map ctrl+v paste_from_clipboard
map ctrl+k send_text all \x01\x0B
# --------------------------------------
# Restaurar comportamiento original (Bash)
# --------------------------------------
map ctrl+shift+c send_text all \x03
map ctrl+shift+v send_text all \x16
map ctrl+shift+k send_text all \x0B
EOF

# Configure autostart para que se inicie automáticamente al iniciar sesión
mkdir -p /home/antonio/.config/autostart
cat > /home/antonio/.config/autostart/hyprland.desktop << EOF
[Desktop Entry]
Type=Application
Name=Hyprland
Exec=/usr/bin/Hyprland
EOF

# Recomendaciones para post-instalación (solucionar problemas con aplicaciones borrosas)
cat > /home/antonio/recomendaciones-post-instalacion.txt << 'EOF'
=== RECOMENDACIONES POST-INSTALACIÓN ===

Para instalar Visual Studio Code y que se vea correctamente en tus monitores:

1. Instalar VS Code:
   $ sudo pacman -S code

2. Si se ve borroso, crea este archivo:
   $ mkdir -p ~/.config
   $ nano ~/.config/code-flags.conf

   Y añade estas líneas:
   --enable-features=UseOzonePlatform
   --ozone-platform=wayland
   --enable-wayland-ime

3. Si los problemas persisten, instala qt5ct y kvantum:
   $ sudo pacman -S qt5ct kvantum

4. Edita tu archivo ~/.config/hypr/hyprland.conf y añade:
   windowrulev2 = opacity 1.0 override,class:^(code-oss)$
   windowrulev2 = opacity 1.0 override,class:^(Code)$

5. Para cambiar entre teclado en inglés (US) y español, usa Alt+Shift

6. Configurar timeshift para hacer copias de seguridad regulares:
   $ sudo timeshift-gtk
EOF

# Cambiar propiedad de los archivos al usuario antonio
chown -R antonio:antonio /home/antonio/

print_message "La instalación base ha sido completada."
print_message "Después de reiniciar:"
print_message "1. Retira el medio de instalación"
print_message "2. Selecciona Arch Linux o Windows en GRUB"
print_message "3. Si seleccionas Arch, inicia sesión como 'antonio'"
print_message "4. Conecta a Internet con 'nmtui' si es necesario"
print_message "5. Revisa el archivo ~/recomendaciones-post-instalacion.txt para más información"
print_message "6. Para cambiar entre teclado en inglés (US) y español, usa Alt+Shift"
print_message "7. Para hacer backups manuales, usa Timeshift"
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
print_message "Podrás elegir entre Arch Linux y Windows en el menú de GRUB."

sleep 10
umount -R /mnt
reboot
