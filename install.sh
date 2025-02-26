#!/bin/bash

# === SCRIPT DE INSTALACIÓN DE ARCH LINUX CON BTRFS, HYPRLAND Y AYLUR'S GTK SHELL ===
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
EFI_DEV="${DISK}p5"
SWAP_DEV="${DISK}p6"
SYSTEM_DEV="${DISK}p7"

print_message "Dispositivos a utilizar:"
print_message "Partición EFI: $EFI_DEV"
print_message "Partición SWAP: $SWAP_DEV"
print_message "Partición Sistema (BTRFS): $SYSTEM_DEV"
print_warning "Este script asume que ya creaste las particiones con cfdisk"
print_warning "Asegúrate de que las particiones existan y sean correctas"
echo
read -p "¿Continuar con la instalación? [s/N]: " response
if [! "$response" =~ ^([sS][iI]|[sS])$ ]; then
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
    rofi kitty networkmanager sudo grub efibootmgr os-prober \
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
    gtk4 libadwaita gobject-introspection gjs webkit2gtk-4.1 gtksourceview5 \
    sassc adwaita-icon-theme gnome-themes-extra blueman \
    polkit-gnome xdg-desktop-portal-gtk brightnessctl playerctl \
    mesa vulkan-radeon ffmpeg gst-plugins-good gst-plugins-bad gst-plugins-ugly \
    libreoffice-fresh imv glow wget
print_success "Paquetes clave instalados"

# --- 14) CONFIGURAR NVIDIA PARA WAYLAND ---
print_message "Configurando NVIDIA para Wayland..."
echo "options nvidia_drm modeset=1" | tee /etc/modprobe.d/nvidia.conf
sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
mkinitcpio -P
print_success "NVIDIA configurado para Wayland"

# --- 15) CONFIGURAR GRUB ---
print_message "Configurando GRUB..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"/' /etc/default/grub
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
os-prober
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configurado"

# --- 16) CREAR USUARIO ---
print_message "Creando usuario 'antonio'..."
useradd -m -G wheel,seat,video,audio,storage,optical -s /bin/bash antonio
print_message "Configura la contraseña para el usuario 'antonio':"
passwd antonio
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo
print_success "Usuario creado"

# --- 17) HABILITAR SERVICIOS ---
print_message "Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable seatd
systemctl enable fstrim.timer
print_success "Servicios habilitados"

print_message "La instalación base ha sido completada."
print_message "Después de reiniciar:"
print_message "1. Retira el medio de instalación"
print_message "2. Selecciona Arch Linux en GRUB"
print_message "3. Inicia sesión como 'antonio'"
print_message "4. Conecta a Internet con 'nmtui'"
print_message "5. Sigue con la post-instalación según el README"
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
