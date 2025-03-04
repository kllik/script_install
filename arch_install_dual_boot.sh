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
pacstrap /mnt base base-devel linux linux-headers linux-firmware btrfs-progs nano grub efibootmgr sudo networkmanager amd-ucode
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

ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime
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

# --- 12) INSTALAR PAQUETES DE NVIDIA PRIMERO ---
print_message "Instalando drivers NVIDIA..."
pacman -S --noconfirm --needed nvidia nvidia-utils nvidia-dkms nvidia-settings lib32-nvidia-utils

print_message "Creando configuración de modulos para mkinitcpio..."
mkdir -p /etc/modprobe.d/
cat > /etc/modprobe.d/nvidia.conf << EOF
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

cat > /etc/modprobe.d/nvidia-power-management.conf << EOF
options nvidia NVreg_DynamicPowerManagement=0x02
EOF

# Configuración específica de mkinitcpio para cargar módulos NVIDIA
cat > /etc/mkinitcpio.conf << EOF
# vim:set ft=sh
# The following modules are loaded before any boot hooks are
# run.  Advanced users may wish to specify all system modules
# in this array.  For instance:
#     MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)

# BINARIES
# This setting includes any additional binaries a given user may
# wish into the CPIO image.  This is run last, so it may be used to
# override the actual binaries included by a given hook
# BINARIES are dependency parsed, so you may safely ignore libraries
BINARIES=()

# FILES
# This setting is similar to BINARIES above, however, files are added
# as-is and are not parsed in any way.  This is useful for config files.
FILES=()

# HOOKS
# This is the most important setting in this file.  The HOOKS control the
# modules and scripts added to the image, and what happens at boot time.
# Order is important, and it is recommended that you do not change the
# order in which HOOKS are added.  Run 'mkinitcpio -H <hook name>' for
# help on a given hook.
# 'base' is _required_ unless you know precisely what you are doing.
# 'udev' is _required_ in order to automatically load modules
# 'filesystems' is _required_ unless you specify your fs modules in MODULES
# Examples:
#    This setup specifies all modules in the MODULES setting above.
#    No RAID, lvm2, or encrypted root is needed.
#    HOOKS=(base)
#
#    This setup will autodetect all modules for your system and should
#    work as a sane default
#    HOOKS=(base udev autodetect modconf block filesystems fsck)
HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)

# COMPRESSION
# Use this to compress the initramfs image. By default, gzip compression
# is used. Use 'cat' to create an uncompressed image.
COMPRESSION="zstd"
#COMPRESSION="gzip"
#COMPRESSION="bzip2"
#COMPRESSION="lzma"
#COMPRESSION="xz"
#COMPRESSION="lzop"
#COMPRESSION="lz4"

# COMPRESSION_OPTIONS
# Additional options for the compressor
#COMPRESSION_OPTIONS=()

# MODULES_DECOMPRESS
# Decompress kernel modules during initramfs creation.
# Enable to speedup boot process, disable to save RAM
# during early userspace. Switch (yes/no).
MODULES_DECOMPRESS="yes"
EOF

mkinitcpio -P
print_success "Configuración NVIDIA completada"

# --- 13) INSTALACIÓN DE DEMÁS PAQUETES ---
print_message "Instalando entorno Wayland y Hyprland..."
pacman -S --noconfirm --needed hyprland xorg-xwayland waybar

print_message "Instalando utilidades básicas..."
pacman -S --noconfirm --needed kitty rofi networkmanager bluez bluez-utils polkit-gnome

print_message "Instalando multimedia y soporte de audio..."
pacman -S --noconfirm --needed pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol

print_message "Instalando fuentes y temas..."
pacman -S --noconfirm --needed ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji ttf-dejavu

print_message "Instalando herramientas y utilidades..."
pacman -S --noconfirm --needed firefox thunar grim slurp wl-clipboard xclip zip unzip p7zip

print_message "Instalando controladores AMD..."
pacman -S --noconfirm --needed mesa xf86-video-amdgpu vulkan-radeon

print_message "Añadir soporte para formatos multimedia..."
pacman -S --noconfirm --needed ffmpeg

# --- INSTALACIÓN DE HERRAMIENTAS DE DESARROLLO ---
print_message "Instalando herramientas para C/C++..."
pacman -S --noconfirm --needed gcc g++ cmake clang llvm lldb gdb make valgrind boost boost-libs

print_message "Instalando herramientas para Lua..."
pacman -S --noconfirm --needed lua luarocks lua-lgi

print_message "Instalando herramientas para JavaScript/TypeScript..."
pacman -S --noconfirm --needed nodejs npm typescript yarn deno

print_message "Instalando herramientas para SQLite..."
pacman -S --noconfirm --needed sqlite sqlitebrowser sqlite-doc

print_message "Instalando herramientas para Python..."
pacman -S --noconfirm --needed python python-pip python-setuptools python-virtualenv

print_message "Instalando herramientas para Git..."
pacman -S --noconfirm --needed git git-lfs

print_message "Instalando herramientas de documentación y desarrollo..."
pacman -S --noconfirm --needed doxygen graphviz ctags

print_message "Instalando IDEs y editores adicionales..."
pacman -S --noconfirm --needed neovim code geany

print_message "Instalando bibliotecas para desarrollo GUI..."
pacman -S --noconfirm --needed qt5-base qt6-base gtk3 gtk4 wxgtk3 sdl2 glfw-wayland

print_success "Herramientas de desarrollo instaladas"

# --- 14) CONFIGURAR GRUB PARA DUAL BOOT ---
print_message "Configurando GRUB para dual boot..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"/' /etc/default/grub
# Habilitar detección de otros sistemas operativos (Windows)
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

print_message "Instalando GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCHLINUX
os-prober
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configurado para dual boot"

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
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

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

# Atajos de teclado - usando SUPER directamente
bind = SUPER, Q, exec, kitty
bind = SUPER, C, killactive, 
bind = SUPER, M, exit, 
bind = SUPER, E, exec, thunar
bind = SUPER SHIFT, F, togglefloating, 
bind = SUPER, R, exec, rofi -show drun
bind = SUPER, P, pseudo, 
bind = SUPER, F, fullscreen, 
bind = SUPER, J, togglesplit, 
bind = SUPER, Z, exec, grim -g "$(slurp)" ~/Imágenes/$(date +%Y-%m-%d_%H-%M-%S).png
bind = SUPER, V, exec, code    # Abrir Visual Studio Code
bind = SUPER, N, exec, neovim  # Abrir Neovim

# Movimiento entre ventanas
bind = SUPER, left, movefocus, l
bind = SUPER, right, movefocus, r
bind = SUPER, up, movefocus, u
bind = SUPER, down, movefocus, d

# Cambio de espacios de trabajo
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5
bind = SUPER, 6, workspace, 6
bind = SUPER, 7, workspace, 7
bind = SUPER, 8, workspace, 8
bind = SUPER, 9, workspace, 9
bind = SUPER, 0, workspace, 10

# Mover ventana al espacio de trabajo
bind = SUPER SHIFT, 1, movetoworkspace, 1
bind = SUPER SHIFT, 2, movetoworkspace, 2
bind = SUPER SHIFT, 3, movetoworkspace, 3
bind = SUPER SHIFT, 4, movetoworkspace, 4
bind = SUPER SHIFT, 5, movetoworkspace, 5
bind = SUPER SHIFT, 6, movetoworkspace, 6
bind = SUPER SHIFT, 7, movetoworkspace, 7
bind = SUPER SHIFT, 8, movetoworkspace, 8
bind = SUPER SHIFT, 9, movetoworkspace, 9
bind = SUPER SHIFT, 0, movetoworkspace, 10

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
    "modules-right": ["custom/gpu", "temperature#gpu", "custom/cpu", "temperature#cpu", "memory", "pulseaudio", "tray"],
    
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
#network,
#pulseaudio,
#memory,
#tray,
#custom-cpu,
#custom-gpu {
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

# Variables para desarrollo
export PATH="$HOME/.local/bin:$PATH"
export CC=gcc
export CXX=g++
export CMAKE_GENERATOR=Ninja
export NODE_PATH="$HOME/.npm-packages/lib/node_modules"

# Carga de módulos NVIDIA
if ! lsmod | grep -q nvidia; then
    sudo modprobe nvidia
    sudo modprobe nvidia_modeset
    sudo modprobe nvidia_uvm
    sudo modprobe nvidia_drm
fi

# Directorio de imágenes para capturas de pantalla
mkdir -p ~/Imágenes
EOF

# Añadir script de post-boot para asegurar que los módulos NVIDIA estén cargados
cat > /etc/systemd/system/nvidia-modules.service << EOF
[Unit]
Description=Load NVIDIA modules at boot time
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/modprobe nvidia
ExecStart=/usr/bin/modprobe nvidia_modeset
ExecStart=/usr/bin/modprobe nvidia_uvm
ExecStart=/usr/bin/modprobe nvidia_drm
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable nvidia-modules.service

# Configuración básica para algunos entornos de desarrollo
mkdir -p /home/antonio/.config/nvim
cat > /home/antonio/.config/nvim/init.vim << EOF
" Configuración básica para neovim
syntax on
set number
set tabstop=4
set shiftwidth=4
set expandtab
set smartindent
set autoindent
set ruler
set showcmd
set incsearch
set hlsearch
set ignorecase
set smartcase
set termguicolors

" Detección de tipo de archivo
filetype plugin on
filetype indent on
EOF

# Añadir configuración básica de C++
mkdir -p /home/antonio/dev/cpp
cat > /home/antonio/dev/cpp/CMakeLists.txt.template << EOF
cmake_minimum_required(VERSION 3.15)
project(MiProyecto CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Añadir opciones de compilación
add_compile_options(
    -Wall
    -Wextra
    -Wpedantic
    -Werror
)

# Añadir ejecutable
add_executable(app main.cpp)

# Opcional: Enlazar con bibliotecas
# target_link_libraries(app PRIVATE biblioteca)
EOF

cat > /home/antonio/dev/cpp/main.cpp.template << EOF
#include <iostream>
#include <vector>
#include <string>

int main() {
    std::cout << "¡Hola mundo desde C++17!" << std::endl;
    return 0;
}
EOF

# Configuración básica SQLite
mkdir -p /home/antonio/dev/db
cat > /home/antonio/dev/db/ejemplo.sql << EOF
-- Ejemplo básico de SQLite
CREATE TABLE usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    email TEXT UNIQUE,
    fecha_registro DATE DEFAULT CURRENT_DATE
);

-- Insertar algunos datos de prueba
INSERT INTO usuarios (nombre, email) VALUES 
    ('Usuario1', 'usuario1@ejemplo.com'),
    ('Usuario2', 'usuario2@ejemplo.com');

-- Consulta simple
SELECT * FROM usuarios;
EOF

# Configuración básica JavaScript/TypeScript
mkdir -p /home/antonio/dev/js
cat > /home/antonio/dev/js/tsconfig.json << EOF
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
EOF

mkdir -p /home/antonio/dev/js/src
cat > /home/antonio/dev/js/src/app.ts << EOF
// Ejemplo básico de TypeScript
interface Usuario {
    id: number;
    nombre: string;
    email: string;
}

class GestorUsuarios {
    private usuarios: Usuario[] = [];

    agregarUsuario(usuario: Usuario): void {
        this.usuarios.push(usuario);
        console.log(`Usuario ${usuario.nombre} agregado con éxito.`);
    }

    listarUsuarios(): void {
        console.log('Lista de usuarios:');
        this.usuarios.forEach(usuario => {
            console.log(`- ${usuario.nombre} (${usuario.email})`);
        });
    }
}

// Uso de ejemplo
const gestor = new GestorUsuarios();
gestor.agregarUsuario({ id: 1, nombre: 'Usuario1', email: 'usuario1@ejemplo.com' });
gestor.agregarUsuario({ id: 2, nombre: 'Usuario2', email: 'usuario2@ejemplo.com' });
gestor.listarUsuarios();

export { Usuario, GestorUsuarios };
EOF

# Configuración básica Lua
mkdir -p /home/antonio/dev/lua
cat > /home/antonio/dev/lua/ejemplo.lua << EOF
-- Ejemplo básico de Lua
local function saludar(nombre)
    return "Hola, " .. nombre .. "!"
end

local function main()
    local mensaje = saludar("Mundo")
    print(mensaje)
    
    -- Tabla (similar a objetos/diccionarios)
    local persona = {
        nombre = "Antonio",
        edad = 30,
        hobbies = {"programación", "lectura", "música"}
    }
    
    print("Nombre:", persona.nombre)
    print("Hobbies:")
    for i, hobby in ipairs(persona.hobbies) do
        print(i, hobby)
    end
end

main()
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
print_message "8. SUPER+Z para capturar pantalla (seleccionando zona)"
print_message "9. SUPER+R para abrir el lanzador de aplicaciones rofi"
print_message "10. SUPER+V para abrir Visual Studio Code"
print_message "11. Encontrarás plantillas para desarrollo en ~/dev/"
print_message "12. Si persisten problemas con NVIDIA, ejecuta 'dkms autoinstall' como root"

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
