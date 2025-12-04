#!/bin/bash

# === SCRIPT DE INSTALACIÓN DE ARCH LINUX CON BTRFS, HYPRLAND Y WAYBAR ===
# Configuración para: Nvidia RTX 3080 + AMD Ryzen 9 5900HX
# Uso: Este script continúa la instalación DESPUÉS de usar cfdisk para crear las particiones
# Configuración: Single boot - Solo Arch Linux (sin snapshots/puntos de recuperación)

# --- Colores para mensajes ---
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m" # No Color

# --- Funciones para mostrar mensajes ---
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

# --- 1) VERIFICACIONES INICIALES ---

# Verificar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root"
    exit 1
fi

# Definir dispositivos (asumiendo que ya se han creado las particiones)
DISK="/dev/nvme0n1"
SYSTEM_DEV="${DISK}p1" # Partición 1: Linux filesystem (935GB)
SWAP_DEV="${DISK}p2"   # Partición 2: Linux swap (16GB)
EFI_DEV="${DISK}p3"    # Partición 3: EFI System (1GB)

print_message "Dispositivos a utilizar:"
print_message "Partición Sistema BTRFS: $SYSTEM_DEV - 935GB"
print_message "Partición SWAP: $SWAP_DEV - 16GB"
print_message "Partición EFI: $EFI_DEV - 1GB"
print_warning "Este script asume que ya creaste las particiones con cfdisk."
print_warning "Asegúrate de que las particiones existan y sean correctas."
echo
read -p "¿Continuar con la instalación? [s/N]: " response
if [[ ! "$response" =~ ^([sS][iI]|[sS])$ ]]; then
    print_message "Instalación cancelada."
    exit 0
fi

# --- 2) FORMATEO Y ACTIVACIÓN SWAP ---

print_message "Formateando partición EFI (${EFI_DEV})..."
mkfs.fat -F32 "$EFI_DEV"
print_success "Partición EFI formateada."

print_message "Formateando y activando SWAP (${SWAP_DEV})..."
mkswap "$SWAP_DEV" && swapon "$SWAP_DEV"
print_success "SWAP configurada."

print_message "Formateando partición del sistema como BTRFS (${SYSTEM_DEV})..."
mkfs.btrfs -f "$SYSTEM_DEV"
print_success "Partición BTRFS formateada."

# --- 3) MONTAR SISTEMA ---

print_message "Montando sistema de archivos..."
mount -o noatime,compress=zstd,space_cache=v2 "$SYSTEM_DEV" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_DEV" /mnt/boot/efi
print_success "Sistema de archivos montado."

# --- 4) INSTALAR SISTEMA BASE ---

print_message "Instalando sistema base (esto puede tomar tiempo)..."
pacstrap /mnt base base-devel linux linux-headers linux-firmware amd-ucode btrfs-progs
print_success "Sistema base instalado."

# --- 5) GENERAR FSTAB ---

print_message "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
print_success "fstab generado."

# --- 6) PREPARAR CHROOT ---

print_message "Preparando archivos para chroot..."

# Crear script post-chroot
cat > /mnt/root/post-chroot.sh << 'EOL'
#!/bin/bash

# --- Colores y funciones de mensaje (dentro de chroot) ---
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

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
pacman -Syu --noconfirm nano
print_success "Nano instalado."

# --- 9) CONFIGURAR LOCALE Y ZONA HORARIA ---
print_message "Configurando locale y zona horaria..."
sed -i 's/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=es_ES.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime
hwclock --systohc
print_success "Locale y zona horaria configurados."

# --- 10) CONFIGURAR CONSOLE FONT ---
print_message "Configurando fuente de consola..."
pacman -S --noconfirm terminus-font
cat > /etc/vconsole.conf << EOF
KEYMAP=us
FONT=ter-v18n
FONT_MAP=8859-1
EOF
print_success "Fuente de consola configurada (Terminus 18pt)."

# --- 11) HOSTNAME Y HOSTS ---
print_message "Configurando hostname..."
echo "host" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   host.localdomain host
EOF
print_success "Hostname configurado."

# --- 12) CONTRASEÑA ROOT ---
print_message "A continuación deberás configurar la contraseña de root:"
passwd

# --- 13) HABILITAR MULTILIB ---
print_message "Habilitando repositorio multilib..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syy
print_success "Repositorio multilib habilitado."

# --- 14) INSTALAR PAQUETES ESENCIALES ---
print_message "Instalando paquetes esenciales del sistema..."
pacman -S --noconfirm networkmanager sudo grub efibootmgr ntfs-3g mtools dosfstools nano vim git base-devel linux-headers
print_success "Paquetes esenciales instalados."

# --- 15) INSTALAR DRIVERS NVIDIA ---
print_message "Instalando drivers NVIDIA..."
pacman -S --noconfirm nvidia nvidia-utils nvidia-settings lib32-nvidia-utils vulkan-icd-loader lib32-vulkan-icd-loader egl-wayland
print_success "Drivers NVIDIA instalados."

# --- 16) CONFIGURAR NVIDIA PARA WAYLAND ---
print_message "Configurando NVIDIA para Wayland..."
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/nvidia.conf << EOF
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

print_message "Configurando mkinitcpio..."
# Reemplaza la línea de módulos para asegurar que los de NVIDIA estén presentes
sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
print_success "Configuración de NVIDIA preparada."

# --- 17) INSTALAR HYPRLAND Y COMPONENTES DE ESCRITORIO ---
print_message "Instalando Hyprland y componentes de escritorio..."
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland xorg-xwayland waybar wofi alacritty polkit polkit-gnome xdg-desktop-portal-gtk pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber grim slurp wl-clipboard brightnessctl playerctl thunar thunar-archive-plugin gvfs udisks2 hyprpaper hyprlock hypridle swaync network-manager-applet blueman pavucontrol lm_sensors pamixer hyprpicker zenity jq wdisplays
print_success "Hyprland y componentes instalados."

# --- 18) INSTALAR APLICACIONES ---
print_message "Instalando aplicaciones..."
pacman -S --noconfirm chromium zathura zathura-pdf-mupdf steam neovim btop unzip wget curl libnotify
print_success "Aplicaciones instaladas."

# --- 19) INSTALAR FUENTES ---
print_message "Instalando fuentes..."
pacman -S --noconfirm ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation ttf-roboto ttf-ubuntu-font-family
print_success "Fuentes instaladas."

# --- 20) INSTALAR HERRAMIENTAS DE DESARROLLO ---
print_message "Instalando herramientas de desarrollo..."
pacman -S --noconfirm gcc clang cmake ninja meson gdb lldb python python-pip nodejs npm jdk-openjdk sqlite lua typescript
print_success "Herramientas de desarrollo instaladas."

# --- 21) INSTALAR TEMAS Y CONFIGURACIÓN GTK/QT ---
print_message "Instalando temas..."
pacman -S --noconfirm adwaita-icon-theme gnome-themes-extra qt5-wayland qt6-wayland qt5ct xdg-utils
print_success "Temas instalados."

# --- 22) INSTALAR BLUETOOTH Y AUDIO ---
print_message "Instalando soporte de Bluetooth y audio..."
pacman -S --noconfirm bluez bluez-utils pulseaudio-bluetooth
print_success "Bluetooth y audio instalados."

# --- 23) INSTALAR HERRAMIENTAS ADICIONALES ---
print_message "Instalando herramientas adicionales..."
pacman -S --noconfirm vulkan-tools vulkan-validation-layers sdl2 ddcutil
print_success "Herramientas adicionales instaladas."

# --- 24) REGENERAR INITRAMFS ---
print_message "Regenerando initramfs con configuración completa..."
mkinitcpio -P
print_success "Initramfs regenerado."

# --- 25) CONFIGURAR GRUB ---
print_message "Configurando GRUB..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia-drm.modeset=1 amd_pstate=active"/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configurado."

# --- 26) CREAR GRUPOS NECESARIOS ---
print_message "Creando grupos necesarios..."
groupadd -f wheel
groupadd -f video
groupadd -f audio
groupadd -f storage
groupadd -f optical
groupadd -f network
groupadd -f power
print_success "Grupos creados."

# --- 27) CREAR USUARIO ---
print_message "Creando usuario 'antonio'..."
useradd -m -G wheel,video,audio,storage,optical,network,power -s /bin/bash antonio
print_message "Configura la contraseña para el usuario 'antonio':"
passwd antonio

print_message "Configurando privilegios sudo para el usuario 'antonio'..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
print_success "Usuario creado con privilegios sudo."

# --- 28) HABILITAR SERVICIOS ---
print_message "Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable fstrim.timer
print_success "Servicios habilitados."

# --- 29) CONFIGURAR TEMA OSCURO Y VARIABLES DE ENTORNO ---
print_message "Configurando tema oscuro para GTK y Qt..."
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
cp /etc/gtk-3.0/settings.ini /etc/gtk-4.0/settings.ini

cat > /etc/environment << EOF
# Tema oscuro para Qt y GTK
QT_QPA_PLATFORMTHEME=qt5ct
GTK_THEME=Adwaita-dark
EOF
print_success "Tema oscuro configurado."

# --- 30) CONFIGURAR ENTORNO DE ESCRITORIO ---
print_message "Configurando entorno Hyprland, Waybar y Alacritty..."

# Crear directorios de configuración
mkdir -p /home/antonio/.config/{hypr/scripts,waybar/scripts,alacritty,qt5ct,gtk-3.0,gtk-4.0,wofi,swayosd}
mkdir -p /home/antonio/Imágenes/Capturas
mkdir -p /home/antonio/Wallpapers

# Configuración de SwayOSD
cat > /home/antonio/.config/swayosd/style.css << 'EOSWAYOSD'
window#osd {
    background: rgba(0, 0, 0, 0.85);
    border-radius: 8px;
    border: 1px solid #333333;
    padding: 6px 12px;
}

#container {
    margin: 2px;
}

image {
    color: #ffffff;
    margin-right: 6px;
    -gtk-icon-size: 16px;
}

progressbar {
    min-height: 4px;
    min-width: 100px;
    border-radius: 2px;
    background: #333333;
}

progressbar progress {
    min-height: 4px;
    border-radius: 2px;
    background: #ffffff;
}

label {
    color: #ffffff;
    font-family: "JetBrainsMono Nerd Font";
    font-size: 11px;
    margin-left: 4px;
}
EOSWAYOSD

# Script para cambiar el fondo de pantalla (Waybar)
cat > /home/antonio/.config/waybar/scripts/wallpaper.sh << 'EOWALLPAPER'
#!/bin/bash
selected=$(zenity --file-selection --title="Select Wallpaper" --file-filter="Images | *.png *.jpg *.jpeg *.webp" 2>/dev/null)
if [ -n "$selected" ] && [ -f "$selected" ]; then
    echo "preload = $selected" > ~/.config/hypr/hyprpaper.conf
    echo "wallpaper = ,$selected" >> ~/.config/hypr/hyprpaper.conf
    killall hyprpaper 2>/dev/null
    hyprpaper &
    notify-send "Wallpaper changed" "$selected"
fi
EOWALLPAPER
chmod +x /home/antonio/.config/waybar/scripts/wallpaper.sh

# Configuración de hyprpaper
cat > /home/antonio/.config/hypr/hyprpaper.conf << EOF
# Para añadir fondos, coloca imágenes en ~/Wallpapers y añade líneas como las siguientes:
# preload = /home/antonio/Wallpapers/tu-imagen.jpg
# wallpaper = HDMI-A-1,/home/antonio/Wallpapers/tu-imagen.jpg
# wallpaper = eDP-1,/home/antonio/Wallpapers/tu-imagen.jpg
EOF

# Configuración de Hyprland
cat > /home/antonio/.config/hypr/hyprland.conf << 'EOHYPR'
# Hyprland configuration file - Complete and production-ready configuration
# This file manages the complete Hyprland window manager configuration


# --- MONITORS ---
# Monitor ASUS 2K - Configuración óptima: 2K@144Hz con escala 1.25
monitor=HDMI-A-1,2560x1440@144,-2048x0,1.25

# Laptop eDP-1 a la derecha
monitor=eDP-1,2560x1600@165,0x0,1.6

# --- PROGRAMS ---
$terminal = alacritty
$fileManager = thunar
$menu = wofi --show drun

# --- AUTOSTART ---
exec-once = waybar
exec-once = hyprpaper
exec-once = blueman-applet
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = nm-applet
exec-once = swaync
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = swayosd-server

# --- ENVIRONMENT VARIABLES ---
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GDK_BACKEND,wayland
env = GTK_THEME,Adwaita-dark
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GL_GSYNC_ALLOWED,1
env = __GL_VRR_ALLOWED,1
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_DRM_NO_ATOMIC,1

# --- LOOK AND FEEL ---
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

    blur {
        enabled = true
        size = 3
        passes = 1
        vibrancy = 0.1696
    }

    shadow {
        enabled = true
        range = 4
        render_power = 3
        color = rgba(1a1a1aee)
    }
}

animations {
    enabled = yes
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

# --- INPUT ---
input {
    kb_layout = us,es
    kb_options = grp:alt_shift_toggle
    follow_mouse = 1
    sensitivity = 0

    touchpad {
        natural_scroll = false
    }
}

device {
    name = epic-mouse-v1
    sensitivity = -0.5
}

# --- KEYBINDINGS ---
$mainMod = SUPER

# Application launchers
bind = $mainMod, Q, exec, $terminal
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, $menu
bind = $mainMod, P, pseudo,
bind = $mainMod, T, togglesplit,
bind = $mainMod, F, fullscreen,

# Focus movement (VIM style)
bind = $mainMod, h, movefocus, l
bind = $mainMod, l, movefocus, r
bind = $mainMod, k, movefocus, u
bind = $mainMod, j, movefocus, d

# Move windows (VIM style)
bind = $mainMod SHIFT, h, movewindow, l
bind = $mainMod SHIFT, l, movewindow, r
bind = $mainMod SHIFT, k, movewindow, u
bind = $mainMod SHIFT, j, movewindow, d

# Resize windows (VIM style)
bind = $mainMod CTRL, h, resizeactive, -40 0
bind = $mainMod CTRL, l, resizeactive, 40 0
bind = $mainMod CTRL, k, resizeactive, 0 -40
bind = $mainMod CTRL, j, resizeactive, 0 40

# Workspace switching
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

# Move window to workspace
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

# Special workspace
bind = $mainMod, S, togglespecialworkspace, magic
bind = $mainMod SHIFT, S, movetoworkspace, special:magic

# Mouse workspace switching
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Mouse window manipulation
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Volume controls with SwayOSD
bindle = , XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise
bindle = , XF86AudioLowerVolume, exec, swayosd-client --output-volume lower
bindl = , XF86AudioMute, exec, swayosd-client --output-volume mute-toggle
bindl = , XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle

# Brightness controls with SwayOSD
bindle = , XF86MonBrightnessUp, exec, swayosd-client --brightness raise
bindle = , XF86MonBrightnessDown, exec, swayosd-client --brightness lower

# Media controls
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPrev, exec, playerctl previous
bindl = , XF86AudioPlay, exec, playerctl play-pause

# Screenshots
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
bind = SUPER, Z, exec, grim -g "$(slurp)" ~/Imágenes/Capturas/captura-$(date +'%Y-%m-%d-%H%M%S').png

# --- WINDOW RULES ---
windowrulev2 = float,class:^(pavucontrol)$
windowrulev2 = float,class:^(blueman-manager)$
windowrulev2 = float,class:^(nm-connection-editor)$
windowrulev2 = float,title:^(Steam - News)$
windowrulev2 = suppressevent maximize, class:.*
windowrulev2 = opacity 1.0 override,class:^(code-oss|Code)$
EOHYPR

# Configuración de Waybar (config.jsonc)
cat > /home/antonio/.config/waybar/config.jsonc << 'EOWAYBAR'
{
    "layer": "top",
    "position": "top",
    "height": 28,
    "margin": 0,
    "spacing": 0,

    "modules-left": ["custom/colorpicker", "custom/screenshot", "custom/wallpaper", "custom/display", "hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["tray", "bluetooth", "network", "pulseaudio", "backlight", "battery"],

    "custom/colorpicker": {
        "format": "󰈊",
        "tooltip-format": "Color Picker",
        "on-click": "hyprpicker -a -n"
    },

    "custom/screenshot": {
        "format": "󰹑",
        "tooltip-format": "Screenshot (right-click: region)",
        "on-click": "grim ~/Imágenes/$(date +%Y%m%d_%H%M%S).png && notify-send 'Screenshot saved'",
        "on-click-right": "grim -g \"$(slurp)\" ~/Imágenes/$(date +%Y%m%d_%H%M%S).png && notify-send 'Screenshot saved'"
    },

    "custom/wallpaper": {
        "format": "󰸉",
        "tooltip-format": "Change Wallpaper",
        "on-click": "~/.config/waybar/scripts/wallpaper.sh"
    },

    "custom/display": {
        "format": "󰍹",
        "tooltip-format": "Switch Monitor (right-click: settings)",
        "on-click": "hyprctl dispatch focusmonitor +1",
        "on-click-right": "wdisplays || nwg-displays"
    },

    "hyprland/workspaces": {
        "format": "{name}",
        "on-click": "activate",
        "sort-by-number": true
    },

    "hyprland/window": {
        "format": "{}",
        "max-length": 40,
        "separate-outputs": true
    },

    "clock": {
        "format": " {:%H:%M}",
        "format-alt": " {:%A %d %B}",
        "tooltip-format": "{calendar}"
    },

    "tray": {
        "spacing": 8,
        "icon-size": 14
    },

    "bluetooth": {
        "format": "󰂯",
        "format-connected": "󰂱",
        "format-disabled": "󰂲",
        "format-off": "󰂲",
        "on-click": "blueman-manager",
        "tooltip-format": "{status}"
    },

    "network": {
        "format-wifi": "󰤨 {signalStrength}%",
        "format-ethernet": "󰈀",
        "format-disconnected": "󰤭",
        "on-click": "nm-connection-editor",
        "tooltip-format-wifi": "{essid} ({signalStrength}%)"
    },

    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "󰝟",
        "format-icons": {
            "default": ["󰕿", "󰖀", "󰕾"]
        },
        "on-click": "pavucontrol",
        "on-scroll-up": "swayosd-client --output-volume raise",
        "on-scroll-down": "swayosd-client --output-volume lower"
    },

    "backlight": {
        "format": "{icon} {percent}%",
        "format-icons": ["󰃞", "󰃟", "󰃠"],
        "on-scroll-up": "swayosd-client --brightness raise",
        "on-scroll-down": "swayosd-client --brightness lower"
    },

    "battery": {
        "format": "{icon} {capacity}%",
        "format-charging": "󰂄 {capacity}%",
        "format-icons": ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    }
}
EOWAYBAR

# Configuración de Waybar (style.css)
cat > /home/antonio/.config/waybar/style.css << 'EOWAYBARSTYLE'
* {
    font-family: "JetBrainsMono Nerd Font";
    font-size: 12px;
    font-weight: 500;
    min-height: 0;
    padding: 0;
    margin: 0;
}

window#waybar {
    background: #000000;
    border: none;
}

#custom-colorpicker, #custom-screenshot, #custom-wallpaper, #custom-display {
    color: #888888;
    padding: 0 8px;
}

#custom-colorpicker:hover, #custom-screenshot:hover, #custom-wallpaper:hover, #custom-display:hover {
    color: #ffffff;
    background: #222222;
}

#workspaces {
    margin: 0 4px;
}

#workspaces button {
    color: #888888;
    background: transparent;
    padding: 2px 6px;
}

#workspaces button:hover { color: #ffffff; }
#workspaces button.active { color: #ffffff; background: #333333; }

#window { color: #666666; padding: 0 10px; }
#clock { color: #ffffff; padding: 0 10px; }
#tray { padding: 0 8px; }

#bluetooth { color: #6699ff; padding: 0 8px; }
#bluetooth.disabled, #bluetooth.off { color: #444444; }
#bluetooth.connected { color: #66ff99; }

#network { color: #66ccff; padding: 0 8px; }
#network.disconnected { color: #444444; }

#pulseaudio { color: #cc99ff; padding: 0 8px; }
#pulseaudio.muted { color: #444444; }

#backlight { color: #ffcc66; padding: 0 8px; }

#battery { color: #66ff99; padding: 0 10px; }
#battery.charging { color: #66ffcc; }
#battery.warning { color: #ffcc66; }
#battery.critical { color: #ff6666; }

tooltip { background: #000000; border: 1px solid #333333; }
tooltip label { color: #ffffff; padding: 4px; }
EOWAYBARSTYLE

# Configuración de Alacritty
cat > /home/antonio/.config/alacritty/alacritty.toml << 'EOALAC'
# Alacritty Terminal Configuration - Final Version with Blue Selection
# This configuration provides a complete terminal setup with warm gray background and custom shortcuts

[window]
opacity = 0.95
dynamic_padding = true
decorations = "none"
startup_mode = "Windowed"
dynamic_title = true

[window.padding]
x = 10
y = 10

[window.dimensions]
columns = 120
lines = 30

[scrolling]
history = 10000
multiplier = 3

[font]
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
bold = { family = "JetBrainsMono Nerd Font", style = "Bold" }
italic = { family = "JetBrainsMono Nerd Font", style = "Italic" }
bold_italic = { family = "JetBrainsMono Nerd Font", style = "Bold Italic" }
size = 12.0

[font.offset]
x = 0
y = 0

[font.glyph_offset]
x = 0
y = 0

# Warm gray background with White Text and Soft Yellow for Warnings
[colors.primary]
background = "#2b2b2b"
foreground = "#ffffff"
dim_foreground = "#f8f8f2"
bright_foreground = "#ffffff"

[colors.cursor]
text = "#2b2b2b"
cursor = "#f8f8f2"

[colors.vi_mode_cursor]
text = "#2b2b2b"
cursor = "#f8f8f2"

[colors.search]
matches = { foreground = "#2b2b2b", background = "#e6db74" }
focused_match = { foreground = "#2b2b2b", background = "#a6e22e" }

[colors.hints]
start = { foreground = "#2b2b2b", background = "#e6db74" }
end = { foreground = "#2b2b2b", background = "#a6e22e" }

[colors.line_indicator]
foreground = "None"
background = "None"

[colors.footer_bar]
foreground = "#ffffff"
background = "#2b2b2b"

[colors.selection]
text = "#ffffff"
background = "#4169e1"

# Normal colors - Warm gray background palette with soft yellow for errors
[colors.normal]
black = "#2b2b2b"
red = "#e6db74"      # Soft yellow for errors/warnings instead of red
green = "#a6e22e"
yellow = "#f4bf75"   # Brighter yellow
blue = "#66d9ef"
magenta = "#ae81ff"
cyan = "#66d9ef"
white = "#ffffff"

# Bright colors
[colors.bright]
black = "#75715e"
red = "#f4bf75"      # Soft yellow for bright errors
green = "#a6e22e"
yellow = "#fcf5ae"   # Even brighter yellow
blue = "#66d9ef"
magenta = "#ae81ff"
cyan = "#a1efe4"
white = "#ffffff"

# Dim colors
[colors.dim]
black = "#2b2b2b"
red = "#d4c96e"      # Dimmed yellow
green = "#87c22f"
yellow = "#c7b55a"
blue = "#55b3cc"
magenta = "#9869d0"
cyan = "#55b3cc"
white = "#d5d5d0"

[cursor]
style = { shape = "Block", blinking = "On" }
unfocused_hollow = true
thickness = 0.15

[cursor.vi_mode_style]
shape = "Block"
blinking = "Off"

[terminal]
osc52 = "OnlyCopy"

[shell]
program = "/bin/bash"
args = ["--login"]

[env]
TERM = "xterm-256color"

# Inverted keyboard shortcuts as requested
[[keyboard.bindings]]
key = "C"
mods = "Control"
action = "Copy"

[[keyboard.bindings]]
key = "V"
mods = "Control"
action = "Paste"

[[keyboard.bindings]]
key = "C"
mods = "Control|Shift"
chars = "\u0003"  # Send interrupt signal (Ctrl+C)

[[keyboard.bindings]]
key = "V"
mods = "Control|Shift"
action = "PasteSelection"

[[keyboard.bindings]]
key = "Insert"
mods = "Shift"
action = "PasteSelection"

[[keyboard.bindings]]
key = "Key0"
mods = "Control"
action = "ResetFontSize"

[[keyboard.bindings]]
key = "Equals"
mods = "Control"
action = "IncreaseFontSize"

[[keyboard.bindings]]
key = "Plus"
mods = "Control"
action = "IncreaseFontSize"

[[keyboard.bindings]]
key = "NumpadAdd"
mods = "Control"
action = "IncreaseFontSize"

[[keyboard.bindings]]
key = "Minus"
mods = "Control"
action = "DecreaseFontSize"

[[keyboard.bindings]]
key = "NumpadSubtract"
mods = "Control"
action = "DecreaseFontSize"

[[keyboard.bindings]]
key = "L"
mods = "Control"
action = "ClearLogNotice"

[[keyboard.bindings]]
key = "L"
mods = "Control|Shift"
action = "ClearHistory"

[[keyboard.bindings]]
key = "PageUp"
mods = "Shift"
mode = "~Alt"
action = "ScrollPageUp"

[[keyboard.bindings]]
key = "PageDown"
mods = "Shift"
mode = "~Alt"
action = "ScrollPageDown"

[[keyboard.bindings]]
key = "Home"
mods = "Shift"
mode = "~Alt"
action = "ScrollToTop"

[[keyboard.bindings]]
key = "End"
mods = "Shift"
mode = "~Alt"
action = "ScrollToBottom"

[[keyboard.bindings]]
key = "N"
mods = "Control|Shift"
action = "SpawnNewInstance"

[[keyboard.bindings]]
key = "Space"
mods = "Control|Shift"
action = "ToggleViMode"

[[keyboard.bindings]]
key = "F11"
action = "ToggleFullscreen"

[mouse]
hide_when_typing = true

[selection]
semantic_escape_chars = ",│`|:\"' ()[]{}<>\t"
save_to_clipboard = false

[bell]
animation = "Linear"
duration = 0
command = "None"

[debug]
render_timer = false
persistent_logging = false
log_level = "Warn"
print_events = false
EOALAC

# Configuración de Wofi
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
insensitive=true
allow_images=true
image_size=40
gtk_dark=true
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
#inner-box, #outer-box, #scroll {
    margin: 5px;
    border: none;
    background-color: #2B2B2B;
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

# Configuración de Bash
cat > /home/antonio/.bashrc << 'EORC'
# .bashrc
[[ $- != *i* ]] && return
alias ls='ls --color=auto'
alias ll='ls -alF'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
export EDITOR=nvim
export VISUAL=nvim
export PATH="$PATH:$HOME/.cargo/bin"
export PATH="$PATH:/usr/lib/jvm/default/bin"
export PATH="$PATH:$HOME/go/bin"
export GOPATH="$HOME/go"
export GEM_HOME="$HOME/.gem"
export PATH="$PATH:$GEM_HOME/bin"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
EORC

# Configuración de perfil
cat > /home/antonio/.profile << 'EOPF'
# Variables de entorno para Wayland
export QT_QPA_PLATFORMTHEME="qt5ct"
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export GTK_THEME="Adwaita-dark"
export MOZ_ENABLE_WAYLAND=1
# Cargar bashrc
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
EOPF

# Recomendaciones post-instalación
cat > /home/antonio/recomendaciones-post-instalacion.txt << 'EOTXT'
=== RECOMENDACIONES POST-INSTALACIÓN ===

1. Instalar yay (AUR helper):
   sudo pacman -S --needed git base-devel
   git clone https://aur.archlinux.org/yay.git
   cd yay
   makepkg -si

2. IMPORTANTE - Instalar SwayOSD para el OSD de volumen/brillo:
   yay -S swayosd-git

3. Instalar aplicaciones desde AUR (ejemplo: Visual Studio Code):
   yay -S visual-studio-code-bin

4. Configurar Rust:
   rustup default stable

5. Configurar sensores de temperatura (para CPU):
   sudo sensors-detect
   # Responder YES a todas las preguntas seguras

ATAJOS DE TECLADO:
- Cambiar entre teclado US y ES: Alt+Shift
- Abrir lanzador de aplicaciones (Wofi): Super+R
- Terminal: Super+Q
- Cerrar ventana: Super+C
- Explorador de archivos: Super+E
- Screenshot a portapapeles: Print
- Screenshot guardado: Super+Z

MÓDULOS DE WAYBAR:
  IZQUIERDA (1 clic):
    󰈊 Color Picker    󰹑 Screenshot    󰸉 Wallpaper    󰍹 Display

  DERECHA (clic abre app):
    󰂯 Bluetooth    󰤨 WiFi    󰕾 Volumen    󰃠 Brillo

  Workspaces: 1 2 3 4 5 (sin iconos)
  OSD: Aparece al usar teclas de volumen/brillo (requiere swayosd-git)

Para mayor seguridad, considera instalar y configurar un firewall:
  sudo pacman -S ufw
  sudo ufw enable
  sudo systemctl enable ufw
EOTXT

# Cambiar propiedad de los archivos
chown -R antonio:antonio /home/antonio/
print_success "Configuración del entorno de escritorio finalizada."
print_message "La instalación base ha sido completada."
print_warning "Escribe 'exit', desmonta las particiones con 'umount -R /mnt' y reinicia."
EOL

# Hacer ejecutable el script post-chroot
chmod +x /mnt/root/post-chroot.sh

# --- 7) EJECUTAR CHROOT ---

print_message "Ejecutando chroot para continuar la instalación..."
arch-chroot /mnt /root/post-chroot.sh

# --- 8) FINALIZAR ---

print_success "El script dentro de chroot ha finalizado."
print_message "Puedes desmontar el sistema y reiniciar."
print_message "Comandos sugeridos:"
print_message "umount -R /mnt"
print_message "reboot"
echo
print_warning "Recuerda retirar el medio de instalación durante el reinicio."
print_warning "IMPORTANTE: Después del primer inicio, instala SwayOSD:"
print_warning "  yay -S swayosd-git"
