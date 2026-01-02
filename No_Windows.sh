#!/bin/bash

# === ARCH LINUX INSTALLATION SCRIPT WITH BTRFS, HYPRLAND AND QUICKSHELL ===
# Configuration for: Nvidia RTX 3080 + AMD Ryzen 9 5900HX
# Usage: This script continues installation AFTER using cfdisk to create partitions
# Configuration: Single boot - Arch Linux only
# Updated: January 1, 2026

set -e

# --- Colors for messages ---
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

# --- Message display functions ---
print_message() {
    echo -e "${BLUE}[INSTALLATION]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[COMPLETED]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# --- 1) INITIAL CHECKS ---

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# --- VERIFY INTERNET CONNECTION ---
print_message "Verifying internet connection..."
if ! ping -c 1 archlinux.org &> /dev/null; then
    print_error "No internet connection. Please connect to the internet first."
    exit 1
fi
print_success "Internet connection verified."

# --- AUTOMATIC DISK DETECTION ---
print_message "Detecting available disks..."
echo

mapfile -t AVAILABLE_DISKS < <(lsblk -dpno NAME,SIZE,TYPE | grep 'disk' | awk '{print $1 " (" $2 ")"}')

if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
    print_error "No disks detected on system"
    exit 1
fi

echo "Available disks:"
for i in "${!AVAILABLE_DISKS[@]}"; do
    echo "  $((i+1))) ${AVAILABLE_DISKS[$i]}"
done
echo

read -p "Select disk number for installation: " disk_choice

if ! [[ "$disk_choice" =~ ^[0-9]+$ ]] || [ "$disk_choice" -lt 1 ] || [ "$disk_choice" -gt ${#AVAILABLE_DISKS[@]} ]; then
    print_error "Invalid selection"
    exit 1
fi

DISK=$(echo "${AVAILABLE_DISKS[$((disk_choice-1))]}" | awk '{print $1}')

# Determine partition naming convention (nvme uses p1, sda uses 1)
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="${DISK}"
fi

# --- PARTITION DETECTION ---
print_message "Detecting partitions on $DISK..."
echo

# Use lsblk in list mode (-l) to avoid tree indentation issues
mapfile -t PARTITIONS < <(lsblk -lnpo NAME,SIZE,FSTYPE "$DISK" | grep -E "^${PART_PREFIX}[0-9]")

if [ ${#PARTITIONS[@]} -lt 3 ]; then
    print_error "Expected at least 3 partitions (System, Swap, EFI)"
    print_message "Create partitions first with: cfdisk $DISK"
    print_message "Debug: PART_PREFIX=$PART_PREFIX"
    print_message "Debug: Partitions found:"
    lsblk -lnpo NAME,SIZE,FSTYPE "$DISK"
    exit 1
fi

echo "Detected partitions:"
for i in "${!PARTITIONS[@]}"; do
    echo "  $((i+1))) ${PARTITIONS[$i]}"
done
echo

read -p "Enter partition number for BTRFS SYSTEM: " sys_choice
read -p "Enter partition number for SWAP: " swap_choice
read -p "Enter partition number for EFI: " efi_choice

# Validate input is numeric and within range
for choice in "$sys_choice" "$swap_choice" "$efi_choice"; do
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#PARTITIONS[@]} ]; then
        print_error "Invalid partition selection: $choice"
        exit 1
    fi
done

SYSTEM_DEV=$(echo "${PARTITIONS[$((sys_choice-1))]}" | awk '{print $1}')
SWAP_DEV=$(echo "${PARTITIONS[$((swap_choice-1))]}" | awk '{print $1}')
EFI_DEV=$(echo "${PARTITIONS[$((efi_choice-1))]}" | awk '{print $1}')

# --- 2) FORMAT AND ACTIVATE SWAP ---

print_message "Formatting EFI partition (${EFI_DEV})..."
mkfs.fat -F32 "$EFI_DEV"
print_success "EFI partition formatted."

print_message "Formatting and activating SWAP (${SWAP_DEV})..."
mkswap "$SWAP_DEV" && swapon "$SWAP_DEV"
print_success "SWAP configured."

print_message "Formatting system partition as BTRFS (${SYSTEM_DEV})..."
mkfs.btrfs -f "$SYSTEM_DEV"
print_success "BTRFS partition formatted."

# --- 3) MOUNT SYSTEM ---

print_message "Mounting file system..."
mount -o noatime,compress=zstd,space_cache=v2 "$SYSTEM_DEV" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_DEV" /mnt/boot/efi
print_success "File system mounted."

# --- 4) UPDATE KEYRING AND INSTALL BASE SYSTEM ---

print_message "Synchronizing package databases..."
pacman -Sy
print_success "Package databases synchronized."

print_message "Updating pacman keyring (this fixes PGP signature errors)..."
pacman -S --noconfirm archlinux-keyring
pacman-key --init
pacman-key --populate archlinux
print_success "Keyring updated."

print_message "Installing base system (this may take time)..."
if ! pacstrap -K /mnt base base-devel linux linux-headers linux-firmware amd-ucode btrfs-progs; then
    print_error "pacstrap failed. Aborting installation."
    print_message "Try running: pacman-key --refresh-keys"
    umount -R /mnt 2>/dev/null || true
    exit 1
fi
print_success "Base system installed."

# --- 5) GENERATE FSTAB ---

print_message "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
print_success "fstab generated."

# Verify /mnt/root exists before creating chroot script
if [ ! -d "/mnt/root" ]; then
    print_error "Directory /mnt/root does not exist. Base system installation may have failed."
    exit 1
fi

# --- 6) PREPARE CHROOT ---

print_message "Preparing files for chroot..."

cat > /mnt/root/post-chroot.sh << 'EOL'
#!/bin/bash

set -e

GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

print_message() {
    echo -e "${BLUE}[INSTALLATION]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[COMPLETED]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# --- 8) UPDATE KEYRING INSIDE CHROOT ---
print_message "Initializing pacman keyring inside chroot..."
pacman-key --init
pacman-key --populate archlinux
print_success "Keyring initialized."

# --- 9) INSTALL NANO ---
print_message "Installing nano..."
pacman -Syu --noconfirm nano
print_success "Nano installed."

# --- 10) CONFIGURE LOCALE AND TIMEZONE ---
print_message "Configuring locale and timezone..."
sed -i 's/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=es_ES.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime
hwclock --systohc
print_success "Locale and timezone configured."

# --- 11) HOSTNAME AND HOSTS ---
print_message "Configuring hostname..."
echo "host" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   host.localdomain host
EOF
print_success "Hostname configured."

# --- 12) ROOT PASSWORD ---
print_message "Configure root password:"
passwd

# --- 13) ENABLE MULTILIB ---
print_message "Enabling multilib repository..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syy
print_success "Multilib repository enabled."

# --- 14) INSTALL ESSENTIAL PACKAGES ---
print_message "Installing essential system packages..."
pacman -S --noconfirm networkmanager sudo grub efibootmgr ntfs-3g mtools dosfstools nano vim git linux-headers
print_success "Essential packages installed."

# --- 15) INSTALL NVIDIA DRIVERS ---
print_message "Installing NVIDIA drivers..."
pacman -S --noconfirm nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils vulkan-icd-loader lib32-vulkan-icd-loader egl-wayland libva-nvidia-driver
print_success "NVIDIA drivers installed."

# --- 16) CONFIGURE NVIDIA FOR WAYLAND ---
print_message "Configuring NVIDIA for Wayland..."
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/nvidia.conf << EOF
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
print_success "NVIDIA configuration prepared."

# --- 17) INSTALL HYPRLAND AND DESKTOP COMPONENTS ---
print_message "Installing Hyprland and desktop components..."
pacman -S --noconfirm \
    hyprland \
    xdg-desktop-portal-hyprland \
    xorg-xwayland \
    quickshell \
    hyprpicker \
    swww \
    wlr-randr \
    zenity \
    wofi \
    alacritty \
    polkit \
    polkit-gnome \
    xdg-desktop-portal-gtk \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    pipewire-jack \
    wireplumber \
    grim \
    slurp \
    wl-clipboard \
    brightnessctl \
    playerctl \
    thunar \
    thunar-archive-plugin \
    gvfs \
    udisks2 \
    hyprpaper \
    hyprlock \
    hypridle \
    swaync \
    network-manager-applet \
    blueman \
    pavucontrol \
    lm_sensors
print_success "Hyprland and components installed."

# --- 18) INSTALL APPLICATIONS ---
print_message "Installing applications..."
pacman -S --noconfirm \
    chromium \
    zathura \
    zathura-pdf-mupdf \
    obs-studio \
    neovim \
    btop \
    unzip \
    wget \
    curl \
    jq \
    socat
print_success "Applications installed."

# --- 19) INSTALL FONTS ---
print_message "Installing fonts..."
pacman -S --noconfirm \
    ttf-jetbrains-mono-nerd \
    ttf-font-awesome \
    noto-fonts \
    noto-fonts-emoji \
    ttf-dejavu \
    ttf-liberation \
    ttf-roboto \
    ttf-ubuntu-font-family
print_success "Fonts installed."

# --- 20) INSTALL DEVELOPMENT TOOLS ---
print_message "Installing development tools..."
pacman -S --noconfirm \
    gcc \
    clang \
    gdb \
    lldb \
    make \
    python \
    python-pip \
    lua
print_success "Development tools installed."

# --- 21) INSTALL THEMES AND GTK/QT CONFIGURATION ---
print_message "Installing themes..."
pacman -S --noconfirm \
    adwaita-icon-theme \
    gnome-themes-extra \
    qt5-wayland \
    qt6-wayland \
    qt5ct \
    xdg-utils
print_success "Themes installed."

# --- 22) INSTALL BLUETOOTH AND AUDIO ---
print_message "Installing Bluetooth and audio support..."
pacman -S --noconfirm bluez bluez-utils
print_success "Bluetooth and audio installed."

# --- 23) INSTALL ADDITIONAL TOOLS ---
print_message "Installing additional tools..."
pacman -S --noconfirm vulkan-tools ddcutil libnotify
print_success "Additional tools installed."

# --- 24) INSTALL VIRTUALIZATION TOOLS ---
print_message "Installing virtualization tools..."
pacman -S --noconfirm virtualbox virtualbox-host-modules-arch
print_success "VirtualBox installed."

# --- 25) REGENERATE INITRAMFS ---
print_message "Regenerating initramfs with complete configuration..."
mkinitcpio -P
print_success "Initramfs regenerated."

# --- 26) CONFIGURE GRUB ---
print_message "Configuring GRUB..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia-drm.modeset=1 amd_pstate=active"/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configured."

# --- 27) CREATE NECESSARY GROUPS ---
print_message "Creating necessary groups..."
groupadd -f wheel
groupadd -f video
groupadd -f audio
groupadd -f storage
groupadd -f optical
groupadd -f network
groupadd -f power
print_success "Groups created."

# --- 28) CREATE USER ---
print_message "Creating user 'antonio'..."
useradd -m -G wheel,video,audio,storage,optical,network,power -s /bin/bash antonio
print_message "Configure password for user 'antonio':"
passwd antonio

print_message "Configuring sudo privileges for user 'antonio'..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Add user to vboxusers group
usermod -aG vboxusers antonio

print_success "User created with sudo privileges."

# --- 29) ENABLE SERVICES ---
print_message "Enabling services..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable fstrim.timer
print_success "Services enabled."

# --- 30) CONFIGURE DARK THEME AND ENVIRONMENT VARIABLES ---
print_message "Configuring dark theme for GTK and Qt..."
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
QT_QPA_PLATFORMTHEME=qt5ct
GTK_THEME=Adwaita-dark
EOF
print_success "Dark theme configured."

# --- 31) CONFIGURE DESKTOP ENVIRONMENT ---
print_message "Configuring Hyprland, Quickshell and Alacritty..."

mkdir -p /home/antonio/.config/{hypr/scripts,quickshell/widgets,quickshell/scripts,alacritty,qt5ct,gtk-3.0,gtk-4.0,wofi}
mkdir -p /home/antonio/Imágenes/Capturas
mkdir -p /home/antonio/Wallpapers

# --- HYPRLAND CONFIGURATION ---
cat > /home/antonio/.config/hypr/hyprland.conf << 'EOHYPR'
# Hyprland configuration file
# Complete configuration for Nvidia RTX 3080 + AMD Ryzen 9 5900HX

# --- MONITORS ---
monitor=HDMI-A-1,2560x1440@144,-2048x0,1.25
monitor=eDP-1,2560x1600@165,0x0,1.6

# --- PROGRAMS ---
$terminal = alacritty
$fileManager = thunar
$menu = wofi --show drun

# --- AUTOSTART ---
exec-once = swww-daemon
exec-once = quickshell
exec-once = blueman-applet
exec-once = gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 12'
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = nm-applet
exec-once = swaync
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

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

# --- KEYBINDINGS ---
$mainMod = SUPER

bind = $mainMod, Q, exec, $terminal
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, $menu
bind = $mainMod, P, pseudo,
bind = $mainMod, T, togglesplit,
bind = $mainMod, F, fullscreen,

bind = $mainMod, h, movefocus, l
bind = $mainMod, l, movefocus, r
bind = $mainMod, k, movefocus, u
bind = $mainMod, j, movefocus, d

bind = $mainMod SHIFT, h, movewindow, l
bind = $mainMod SHIFT, l, movewindow, r
bind = $mainMod SHIFT, k, movewindow, u
bind = $mainMod SHIFT, j, movewindow, d

bind = $mainMod CTRL, h, resizeactive, -40 0
bind = $mainMod CTRL, l, resizeactive, 40 0
bind = $mainMod CTRL, k, resizeactive, 0 -40
bind = $mainMod CTRL, j, resizeactive, 0 40

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

bind = $mainMod, S, togglespecialworkspace, magic
bind = $mainMod SHIFT, S, movetoworkspace, special:magic

bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

binde = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
binde = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

binde = , XF86MonBrightnessUp, exec, brightnessctl s 10%+
binde = , XF86MonBrightnessDown, exec, brightnessctl s 10%-

bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPrev, exec, playerctl previous
bindl = , XF86AudioPlay, exec, playerctl play-pause

bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
bind = SUPER, Z, exec, grim -g "$(slurp)" ~/Imágenes/Capturas/captura-$(date +'%Y-%m-%d-%H%M%S').png

windowrulev2 = float,class:^(pavucontrol)$
windowrulev2 = float,class:^(blueman-manager)$
windowrulev2 = float,class:^(nm-connection-editor)$
windowrulev2 = suppressevent maximize, class:.*
windowrulev2 = opacity 1.0 override,class:^(code-oss|Code)$
EOHYPR

# --- QUICKSHELL MAIN CONFIGURATION ---
cat > /home/antonio/.config/quickshell/shell.qml << 'EOSHELL'
// shell.qml
// Main entry point for the Quickshell bar configuration

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "widgets"

ShellRoot {
    id: root

    property int globalVolume: 50

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            property int monitorIndex: {
                let screens = Quickshell.screens;
                for (let i = 0; i < screens.length; i++) {
                    if (screens[i].name === modelData.name) return i + 1;
                }
                return 1;
            }

            screen: modelData
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32
            color: "#1e1e23"

            WlrLayershell.namespace: "quickshell:bar"
            WlrLayershell.layer: WlrLayer.Top

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 12

                RowLayout {
                    Layout.alignment: Qt.AlignLeft
                    spacing: 8

                    ToolButton {
                        label: "CLR"
                        tooltip: "Color Picker (copies hex to clipboard)"
                        onClicked: colorPickerScript.running = true
                    }

                    ToolButton {
                        label: "WP"
                        tooltip: "Change Wallpaper"
                        onClicked: wallpaperScript.running = true
                    }

                    ToolButton {
                        label: "MON"
                        tooltip: "Monitor Settings"
                        onClicked: monitorScript.running = true
                    }

                    Rectangle {
                        width: 1
                        height: 20
                        color: "#404040"
                    }

                    WorkspaceIndicator {
                        monitorNumber: barWindow.monitorIndex
                    }
                }

                Item { Layout.fillWidth: true }

                ClockWidget {
                    Layout.alignment: Qt.AlignHCenter
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 12

                    CpuIndicator {}
                    GpuIndicator {}
                    RamIndicator {}
                    NetworkIndicator {}
                    BluetoothIndicator {}
                    AudioIndicator {
                        onVolumeAdjusted: function(vol) {
                            root.globalVolume = vol;
                            volumeOsd.showVolume(vol);
                        }
                    }
                    BatteryIndicator {}
                }
            }
        }
    }

    VolumeOSD { id: volumeOsd }

    Process {
        id: colorPickerScript
        command: ["hyprpicker", "-a", "-f", "hex"]
        running: false
    }

    Process {
        id: wallpaperScript
        command: ["sh", "-c", "~/.config/quickshell/scripts/wallpaper-picker.sh"]
        running: false
    }

    Process {
        id: monitorScript
        command: ["wlr-randr"]
        running: false
    }
}
EOSHELL

# --- QUICKSHELL WIDGETS ---

# ToolButton widget
cat > /home/antonio/.config/quickshell/widgets/ToolButton.qml << 'EOWIDGET'
// widgets/ToolButton.qml
// Reusable clickable button with label and tooltip

import QtQuick
import QtQuick.Controls

Rectangle {
    id: toolButton
    property string icon: ""
    property string label: ""
    property string tooltip: ""
    signal clicked()

    width: labelText.visible ? labelText.width + 16 : 28
    height: 28
    radius: 4
    color: mouseArea.containsMouse ? "#3a3a45" : "transparent"

    Text {
        id: labelText
        anchors.centerIn: parent
        text: toolButton.label
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
        font.bold: true
        color: mouseArea.containsMouse ? "#ffffff" : "#b0b0b0"
        visible: toolButton.label !== ""
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: toolButton.clicked()
    }

    ToolTip {
        visible: mouseArea.containsMouse && toolButton.tooltip !== ""
        text: toolButton.tooltip
        delay: 500
    }
}
EOWIDGET

# WorkspaceIndicator widget
cat > /home/antonio/.config/quickshell/widgets/WorkspaceIndicator.qml << 'EOWIDGET'
// widgets/WorkspaceIndicator.qml
// Displays current workspace number for the associated monitor

import QtQuick
import Quickshell.Hyprland

Rectangle {
    id: workspaceIndicator
    property int monitorNumber: 1

    width: 32
    height: 24
    radius: 4
    color: "#2a2a35"
    border.color: "#33ccff"
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: workspaceIndicator.monitorNumber.toString()
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
        font.bold: true
        color: "#33ccff"
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onWheel: function(event) {
            if (event.angleDelta.y > 0) {
                Hyprland.dispatch("workspace e-1");
            } else {
                Hyprland.dispatch("workspace e+1");
            }
        }
    }
}
EOWIDGET

# ClockWidget with calendar
cat > /home/antonio/.config/quickshell/widgets/ClockWidget.qml << 'EOWIDGET'
// widgets/ClockWidget.qml
// Displays current time with calendar popup on click

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: clockWidget
    width: timeText.width
    height: timeText.height

    property string currentTime: Qt.formatDateTime(new Date(), "HH:mm")
    property date currentDate: new Date()

    Text {
        id: timeText
        text: clockWidget.currentTime
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
        font.bold: true
        color: "#ffffff"
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            clockWidget.currentTime = Qt.formatDateTime(new Date(), "HH:mm");
            clockWidget.currentDate = new Date();
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: calendarPopup.visible = !calendarPopup.visible
    }

    Rectangle {
        id: calendarPopup
        visible: false
        width: 220
        height: 260
        color: "#2a2a35"
        radius: 8
        border.color: "#404040"
        border.width: 1

        y: timeText.height + 8
        x: timeText.width / 2 - width / 2

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clockWidget.currentDate, "MMMM yyyy")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                font.bold: true
                color: "#33ccff"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#404040"
            }

            Grid {
                columns: 7
                spacing: 2
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: ["Lu", "Ma", "Mi", "Ju", "Vi", "Sa", "Do"]
                    Text {
                        width: 26
                        height: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.bold: true
                        color: "#888888"
                    }
                }
            }

            Grid {
                columns: 7
                spacing: 2
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: clockWidget.generateCalendarDays()

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: modelData.isToday ? "#33ccff" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.day
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            color: {
                                if (modelData.isToday) return "#1e1e23";
                                if (modelData.isCurrentMonth) return "#ffffff";
                                return "#555555";
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#404040"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clockWidget.currentDate, "dddd, d 'de' MMMM")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                color: "#b0b0b0"
            }
        }
    }

    function generateCalendarDays() {
        let days = [];
        let date = new Date(currentDate.getFullYear(), currentDate.getMonth(), 1);
        let firstDay = date.getDay();
        firstDay = firstDay === 0 ? 6 : firstDay - 1;

        let prevMonth = new Date(date.getFullYear(), date.getMonth(), 0);
        for (let i = firstDay - 1; i >= 0; i--) {
            days.push({
                day: prevMonth.getDate() - i,
                isCurrentMonth: false,
                isToday: false
            });
        }

        let daysInMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
        let today = new Date();
        for (let i = 1; i <= daysInMonth; i++) {
            days.push({
                day: i,
                isCurrentMonth: true,
                isToday: i === today.getDate() &&
                         date.getMonth() === today.getMonth() &&
                         date.getFullYear() === today.getFullYear()
            });
        }

        let remaining = 42 - days.length;
        for (let i = 1; i <= remaining; i++) {
            days.push({
                day: i,
                isCurrentMonth: false,
                isToday: false
            });
        }

        return days;
    }
}
EOWIDGET

# CpuIndicator widget
cat > /home/antonio/.config/quickshell/widgets/CpuIndicator.qml << 'EOWIDGET'
// widgets/CpuIndicator.qml
// Displays CPU usage percentage in real time

import QtQuick
import Quickshell.Io

Item {
    id: cpuIndicator
    width: cpuRow.width
    height: cpuRow.height

    property int cpuUsage: 0

    Row {
        id: cpuRow
        spacing: 4

        Text {
            text: "CPU:"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.bold: true
            color: cpuIndicator.cpuUsage > 80 ? "#ff6666" : "#33ccff"
        }

        Text {
            text: cpuIndicator.cpuUsage + "%"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: "#b0b0b0"
        }
    }

    Process {
        id: cpuCheck
        command: ["sh", "-c", "grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf \"%.0f\", usage}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cpuIndicator.cpuUsage = parseInt(this.text.trim()) || 0;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: cpuCheck.running = true
    }
}
EOWIDGET

# GpuIndicator widget
cat > /home/antonio/.config/quickshell/widgets/GpuIndicator.qml << 'EOWIDGET'
// widgets/GpuIndicator.qml
// Displays GPU usage percentage in real time (NVIDIA)

import QtQuick
import Quickshell.Io

Item {
    id: gpuIndicator
    width: gpuRow.width
    height: gpuRow.height

    property int gpuUsage: 0

    Row {
        id: gpuRow
        spacing: 4

        Text {
            text: "GPU:"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.bold: true
            color: gpuIndicator.gpuUsage > 80 ? "#ff6666" : "#00ff99"
        }

        Text {
            text: gpuIndicator.gpuUsage + "%"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: "#b0b0b0"
        }
    }

    Process {
        id: gpuCheck
        command: ["sh", "-c", "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                gpuIndicator.gpuUsage = parseInt(this.text.trim()) || 0;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: gpuCheck.running = true
    }
}
EOWIDGET

# RamIndicator widget
cat > /home/antonio/.config/quickshell/widgets/RamIndicator.qml << 'EOWIDGET'
// widgets/RamIndicator.qml
// Displays RAM usage in real time

import QtQuick
import Quickshell.Io

Item {
    id: ramIndicator
    width: ramRow.width
    height: ramRow.height

    property string ramUsage: "0G"

    Row {
        id: ramRow
        spacing: 4

        Text {
            text: "RAM:"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.bold: true
            color: "#ffaa00"
        }

        Text {
            text: ramIndicator.ramUsage
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: "#b0b0b0"
        }
    }

    Process {
        id: ramCheck
        command: ["sh", "-c", "free -h | awk '/^Mem:/ {print $3}' | sed 's/Gi/G/' | sed 's/Mi/M/'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                ramIndicator.ramUsage = this.text.trim() || "0G";
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: ramCheck.running = true
    }
}
EOWIDGET

# NetworkIndicator widget
cat > /home/antonio/.config/quickshell/widgets/NetworkIndicator.qml << 'EOWIDGET'
// widgets/NetworkIndicator.qml
// Displays network connection status

import QtQuick
import Quickshell.Io

Item {
    id: networkIndicator
    width: netRow.width
    height: netRow.height

    property string networkStatus: "NET"
    property bool connected: false

    Row {
        id: netRow
        spacing: 4

        Text {
            text: networkIndicator.networkStatus
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.bold: true
            color: networkIndicator.connected ? "#00ff99" : "#ff6666"
        }
    }

    Process {
        id: networkCheck
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE dev | grep -q 'wifi:connected' && echo 'WIFI' || (nmcli -t -f TYPE,STATE dev | grep -q 'ethernet:connected' && echo 'ETH' || echo 'OFF')"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let result = this.text.trim();
                networkIndicator.networkStatus = result;
                networkIndicator.connected = (result !== "OFF");
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: networkCheck.running = true
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: nmEditor.running = true
    }

    Process {
        id: nmEditor
        command: ["nm-connection-editor"]
        running: false
    }
}
EOWIDGET

# BluetoothIndicator widget
cat > /home/antonio/.config/quickshell/widgets/BluetoothIndicator.qml << 'EOWIDGET'
// widgets/BluetoothIndicator.qml
// Displays Bluetooth status

import QtQuick
import Quickshell.Io

Item {
    id: btIndicator
    width: btText.width
    height: btText.height

    property string btStatus: "BT"
    property bool enabled: false

    Text {
        id: btText
        text: btIndicator.btStatus
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
        font.bold: true
        color: btIndicator.enabled ? "#33ccff" : "#666666"
    }

    Process {
        id: btCheck
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo 'BT:ON' || echo 'BT:OFF'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let result = this.text.trim();
                btIndicator.enabled = result === "BT:ON";
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: btCheck.running = true
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: btManager.running = true
    }

    Process {
        id: btManager
        command: ["blueman-manager"]
        running: false
    }
}
EOWIDGET

# AudioIndicator widget
cat > /home/antonio/.config/quickshell/widgets/AudioIndicator.qml << 'EOWIDGET'
// widgets/AudioIndicator.qml
// Displays audio volume with scroll-to-adjust and OSD trigger

import QtQuick
import Quickshell.Io

Item {
    id: audioIndicator
    width: audioRow.width
    height: audioRow.height

    property int volume: 50
    property bool muted: false
    property string icon: "VOL"

    signal volumeAdjusted(int vol)

    Row {
        id: audioRow
        spacing: 4

        Text {
            text: audioIndicator.icon
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.bold: true
            color: audioIndicator.muted ? "#ff6666" : "#33ccff"
        }

        Text {
            text: audioIndicator.volume + "%"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: "#b0b0b0"
        }
    }

    Process {
        id: volumeCheck
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim();
                audioIndicator.muted = output.includes("[MUTED]");
                let match = output.match(/Volume: ([0-9.]+)/);
                if (match) {
                    audioIndicator.volume = Math.round(parseFloat(match[1]) * 100);
                }
                audioIndicator.icon = audioIndicator.muted ? "MUT" : "VOL";
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: volumeCheck.running = true
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: pavucontrol.running = true

        onWheel: function(event) {
            if (event.angleDelta.y > 0) {
                volumeUp.running = true;
            } else {
                volumeDown.running = true;
            }
        }
    }

    Process {
        id: volumeUp
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"]
        running: false
        onRunningChanged: {
            if (!running) {
                volumeCheck.running = true;
                Qt.callLater(function() {
                    audioIndicator.volumeAdjusted(audioIndicator.volume);
                });
            }
        }
    }

    Process {
        id: volumeDown
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]
        running: false
        onRunningChanged: {
            if (!running) {
                volumeCheck.running = true;
                Qt.callLater(function() {
                    audioIndicator.volumeAdjusted(audioIndicator.volume);
                });
            }
        }
    }

    Process {
        id: pavucontrol
        command: ["pavucontrol"]
        running: false
    }
}
EOWIDGET

# BatteryIndicator widget
cat > /home/antonio/.config/quickshell/widgets/BatteryIndicator.qml << 'EOWIDGET'
// widgets/BatteryIndicator.qml
// Displays battery percentage and charging status

import QtQuick
import Quickshell.Io

Item {
    id: batteryIndicator
    width: batRow.width
    height: batRow.height

    property int percentage: 100
    property bool charging: false

    Row {
        id: batRow
        spacing: 4

        Text {
            text: batteryIndicator.charging ? "CHG" : "BAT"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.bold: true
            color: {
                if (batteryIndicator.charging) return "#00ff99";
                if (batteryIndicator.percentage <= 20) return "#ff6666";
                if (batteryIndicator.percentage <= 40) return "#ffaa00";
                return "#ffffff";
            }
        }

        Text {
            text: batteryIndicator.percentage + "%"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: "#b0b0b0"
        }
    }

    Process {
        id: batteryCheck
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 100"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                batteryIndicator.percentage = parseInt(this.text.trim()) || 100;
            }
        }
    }

    Process {
        id: chargingCheck
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo 'Full'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                batteryIndicator.charging = (this.text.trim() === "Charging");
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            batteryCheck.running = true;
            chargingCheck.running = true;
        }
    }
}
EOWIDGET

# VolumeOSD widget
cat > /home/antonio/.config/quickshell/widgets/VolumeOSD.qml << 'EOWIDGET'
// widgets/VolumeOSD.qml
// On-screen display for volume changes

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: osdWindow
    visible: false

    anchors {
        bottom: true
        left: true
        right: true
    }
    margins.bottom: 100

    implicitWidth: 200
    implicitHeight: 60
    color: "transparent"

    WlrLayershell.namespace: "quickshell:osd"
    WlrLayershell.layer: WlrLayer.Overlay

    property int currentVolume: 0

    function showVolume(vol) {
        currentVolume = vol;
        visible = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osdWindow.visible = false
    }

    Item {
        anchors.fill: parent

        Rectangle {
            width: 200
            height: 60
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            radius: 12
            color: "#e01e1e23"
            border.color: "#404040"
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "VOL"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#ffffff"
                }

                Rectangle {
                    width: 160
                    height: 6
                    radius: 3
                    color: "#404040"

                    Rectangle {
                        width: parent.width * (osdWindow.currentVolume / 100)
                        height: parent.height
                        radius: 3
                        color: "#33ccff"

                        Behavior on width {
                            NumberAnimation { duration: 100 }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: osdWindow.currentVolume + "%"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    color: "#b0b0b0"
                }
            }
        }
    }
}
EOWIDGET

# --- QUICKSHELL SCRIPTS ---

# Wallpaper picker script
cat > /home/antonio/.config/quickshell/scripts/wallpaper-picker.sh << 'EOSCRIPT'
#!/bin/bash
# wallpaper-picker.sh
# Opens zenity file picker to select a wallpaper and applies it with swww

WALLPAPER_DIR="$HOME/Wallpapers"
SELECTED_FILE=$(zenity --file-selection --title="Select Wallpaper" --filename="$WALLPAPER_DIR/" --file-filter="Images | *.png *.jpg *.jpeg *.webp *.gif" 2>/dev/null)

if [ -z "$SELECTED_FILE" ]; then
    exit 0
fi

pgrep -x swww-daemon > /dev/null || swww-daemon &
sleep 0.2

swww img "$SELECTED_FILE" \
    --transition-type grow \
    --transition-duration 1 \
    --transition-fps 60

notify-send "Wallpaper Changed" "$(basename "$SELECTED_FILE")" -i preferences-desktop-wallpaper
EOSCRIPT

chmod +x /home/antonio/.config/quickshell/scripts/wallpaper-picker.sh

# --- ALACRITTY CONFIGURATION ---
cat > /home/antonio/.config/alacritty/alacritty.toml << 'EOALAC'
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

[colors.primary]
background = "#2b2b2b"
foreground = "#ffffff"

[colors.cursor]
text = "#2b2b2b"
cursor = "#f8f8f2"

[colors.selection]
text = "#ffffff"
background = "#4169e1"

[colors.normal]
black = "#2b2b2b"
red = "#e6db74"
green = "#a6e22e"
yellow = "#f4bf75"
blue = "#66d9ef"
magenta = "#ae81ff"
cyan = "#66d9ef"
white = "#ffffff"

[colors.bright]
black = "#75715e"
red = "#f4bf75"
green = "#a6e22e"
yellow = "#fcf5ae"
blue = "#66d9ef"
magenta = "#ae81ff"
cyan = "#a1efe4"
white = "#ffffff"

[cursor]
style = { shape = "Block", blinking = "On" }
unfocused_hollow = true

[terminal]
osc52 = "OnlyCopy"

[shell]
program = "/bin/bash"
args = ["--login"]

[env]
TERM = "xterm-256color"

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
chars = "\u0003"

[[keyboard.bindings]]
key = "Key0"
mods = "Control"
action = "ResetFontSize"

[[keyboard.bindings]]
key = "Equals"
mods = "Control"
action = "IncreaseFontSize"

[[keyboard.bindings]]
key = "Minus"
mods = "Control"
action = "DecreaseFontSize"

[[keyboard.bindings]]
key = "F11"
action = "ToggleFullscreen"

[mouse]
hide_when_typing = true

[selection]
save_to_clipboard = false
EOALAC

# --- WOFI CONFIGURATION ---
cat > /home/antonio/.config/wofi/config << EOF
width=600
height=400
location=center
show=drun
prompt=Search
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

# --- BASH CONFIGURATION ---
cat > /home/antonio/.bashrc << 'EORC'
[[ $- != *i* ]] && return
alias ls='ls --color=auto'
alias ll='ls -alF'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
export EDITOR=nvim
export VISUAL=nvim
EORC

cat > /home/antonio/.profile << 'EOPF'
export QT_QPA_PLATFORMTHEME="qt5ct"
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export GTK_THEME="Adwaita-dark"
export MOZ_ENABLE_WAYLAND=1
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
EOPF

# --- POST-INSTALLATION RECOMMENDATIONS ---
cat > /home/antonio/post-installation-notes.txt << 'EOTXT'
=== POST-INSTALLATION NOTES ===

KEYBOARD SHORTCUTS:
- Switch between US/ES keyboard: Alt+Shift
- Open terminal: Super+Q
- Open file manager: Super+E
- Open application launcher: Super+R
- Close window: Super+C
- Toggle fullscreen: Super+F
- Screenshot (select area): Print or Super+Z

BAR TOOLS:
- CLR: Color picker (copies hex to clipboard)
- WP: Wallpaper picker (opens file dialog)
- MON: Monitor configuration

SYSTEM INFO (right side of bar):
- CPU/GPU/RAM usage in real time
- Network, Bluetooth, Volume, Battery status

For security, consider installing a firewall:
  sudo pacman -S ufw
  sudo ufw enable
  sudo systemctl enable ufw
EOTXT

chown -R antonio:antonio /home/antonio/
print_success "Desktop environment configuration completed."
print_message "Base installation completed."
print_warning "Type 'exit', unmount partitions with 'umount -R /mnt' and reboot."
EOL

# Verify post-chroot.sh was created successfully
if [ ! -f "/mnt/root/post-chroot.sh" ]; then
    print_error "Failed to create post-chroot.sh"
    exit 1
fi

chmod +x /mnt/root/post-chroot.sh
print_success "Chroot script created successfully."

# --- 7) EXECUTE CHROOT ---

arch-chroot /mnt /root/post-chroot.sh


# --- 8) CLEANUP ---

print_message "Cleaning up installation files..."
rm -f /mnt/root/post-chroot.sh
print_success "Cleanup completed."

# --- 9) FINISH ---

print_success "Chroot script completed."
print_message "You can unmount the system and reboot."
print_message "Suggested commands:"
print_message "  umount -R /mnt"
print_message "  reboot"
echo
print_warning "Remember to remove installation media during reboot."
