#!/bin/bash

# === SCRIPT DE POST-INSTALACIÓN PARA CONFIGURAR HYPRLAND CON AYLUR'S GTK SHELL ===
# Entorno estilo moderno con temas Catppuccin
# Optimizado para: NVIDIA RTX 3080 + AMD Ryzen 9 5900HX
# Adaptado para: Kitty terminal y Bash shell
# Versión: 1.0 (Marzo 2025)

# Colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
print_message() {
    echo -e "${BLUE}[CONFIGURACIÓN]${NC} $1"
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

# Función para verificar la existencia de paquetes
check_package() {
    if ! pacman -Q $1 &>/dev/null; then
        print_warning "El paquete $1 no está instalado. Intentando instalarlo..."
        if sudo pacman -S --noconfirm $1 2>/dev/null; then
            print_success "Paquete $1 instalado correctamente."
            return 0
        else
            print_error "No se pudo instalar $1 desde los repositorios oficiales."
            return 1
        fi
    else
        return 0
    fi
}

# Verificar si se está ejecutando como usuario normal (no root)
if [ "$EUID" -eq 0 ]; then
    print_error "Este script debe ejecutarse como usuario normal, no como root"
    exit 1
fi

# --- 1) VERIFICAR PAQUETES CRÍTICOS ---
print_message "Verificando paquetes críticos..."
CRITICAL_PACKAGES=(
    "hyprland" "kitty" "grim" "slurp" 
    "fuzzel" "git" "python" "meson" "ninja" "gcc"
)

missing_critical=false
for pkg in "${CRITICAL_PACKAGES[@]}"; do
    if ! check_package "$pkg"; then
        missing_critical=true
        print_error "No se pudo instalar el paquete crítico: $pkg"
    fi
done

if [ "$missing_critical" = true ]; then
    print_warning "Algunos paquetes críticos no pudieron ser instalados."
    read -p "¿Deseas continuar de todos modos? [s/N]: " continue_response
    if [[ ! "$continue_response" =~ ^([sS][iI]|[sS])$ ]]; then
        print_message "Instalación cancelada"
        exit 1
    fi
else
    print_success "Todos los paquetes críticos están disponibles"
fi

# --- 2) INSTALAR YAY (AUR HELPER) SI NO ESTÁ INSTALADO ---
if ! command -v yay &>/dev/null; then
    print_message "Instalando yay (AUR helper)..."
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    cd ~
    print_success "yay instalado"
else
    print_success "yay ya está instalado en el sistema"
fi

# --- 3) VERIFICAR/INSTALAR PAQUETES ADICIONALES DESDE AUR ---
print_message "Instalando paquetes adicionales desde AUR..."
yay -S --noconfirm --needed \
    catppuccin-gtk-theme-mocha adw-gtk3 \
    bibata-cursor-theme catppuccin-cursors-mocha hyprpicker-git \
    gradience swaylock-effects-git wlogout mako-git

# --- 4) INSTALAR AYLUR'S GTK SHELL (AGS) ---
# Verificar si ags está instalado
if ! command -v ags &>/dev/null; then
    print_message "Instalando Aylur's GTK Shell..."
    # Método 1: Verificar AUR
    if yay -Ss "^ags$" | grep -q "aur/ags"; then
        print_message "Instalando AGS desde AUR..."
        yay -S --noconfirm ags
    else
        # Método 2: Compilar desde GitHub
        print_message "Compilando AGS desde el repositorio oficial..."
        cd /tmp
        rm -rf ags
        git clone https://github.com/Aylur/ags.git
        cd ags
        # Instalamos las dependencias
        sudo pacman -S --noconfirm --needed gtk3 gtk-layer-shell gjs
        # Instalamos AGS
        meson setup build
        meson configure -Dbuildtype=release build
        ninja -C build
        sudo ninja -C build install
    fi
    
    if ! command -v ags &>/dev/null; then
        print_error "No se pudo instalar AGS. Intento final usando npm..."
        cd /tmp
        rm -rf ags
        git clone https://github.com/Aylur/ags.git
        cd ags
        npm install
        sudo npm install -g
    fi
else
    print_success "AGS ya está instalado en el sistema"
fi

# --- 5) CREAR DIRECTORIOS DE CONFIGURACIÓN ---
print_message "Creando directorios de configuración..."
mkdir -p ~/.config/{hypr,ags,kitty,fuzzel,fastfetch,swaylock,wlogout,mako}
mkdir -p ~/.config/ags/{widgets,services,modules}
mkdir -p ~/.config/hypr/wallpapers
mkdir -p ~/Pictures/Screenshots
print_success "Directorios creados"

# --- 6) DESCARGAR WALLPAPER NO ANIME ---
print_message "Descargando wallpaper minimalista..."
# Wallpaper estilo abstracto/minimalista
curl -s -o ~/.config/hypr/wallpapers/wallpaper.jpg "https://w.wallhaven.cc/full/85/wallhaven-85oj9o.jpg"
print_success "Wallpaper descargado"

# --- 7) CONFIGURAR KITTY TERMINAL ---
print_message "Configurando Kitty Terminal..."
cat > ~/.config/kitty/kitty.conf << 'EOF'
# Kitty Configuration - Optimizada para RTX 3080
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size 12.0

# Tema Catppuccin Mocha
include themes/mocha.conf

# Rendimiento optimizado para NVIDIA
sync_to_monitor yes
repaint_delay 10
input_delay 3
enable_audio_bell no
confirm_os_window_close 0

# Apariencia
background_opacity 0.95
window_padding_width 12
cursor_shape beam
cursor_blink_interval 0.5
dynamic_background_opacity yes
wayland_titlebar_color background

# Configuración de copiar/pegar
copy_on_select yes
strip_trailing_spaces smart
clipboard_control write-clipboard write-primary no-append

# Shell y terminal
shell /bin/bash
term xterm-kitty

# Atajos de teclado
map ctrl+shift+c copy_to_clipboard
map ctrl+shift+v paste_from_clipboard
map ctrl+shift+equal change_font_size all +1.0
map ctrl+shift+minus change_font_size all -1.0
map ctrl+shift+0 change_font_size all 0
map ctrl+shift+f5 load_config_file
map ctrl+shift+t new_tab
map ctrl+shift+q close_tab
map ctrl+shift+right next_tab
map ctrl+shift+left previous_tab
map ctrl+shift+l next_layout

# Abrir URLs
mouse_map ctrl+left press ungrabbed,grabbed mouse_click_url
EOF

# Crear tema Catppuccin Mocha para Kitty
mkdir -p ~/.config/kitty/themes
cat > ~/.config/kitty/themes/mocha.conf << 'EOF'
# Catppuccin Mocha
foreground              #CDD6F4
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #F5E0DC

# black
color0 #45475A
color8 #585B70

# red
color1 #F38BA8
color9 #F38BA8

# green
color2  #A6E3A1
color10 #A6E3A1

# yellow
color3  #F9E2AF
color11 #F9E2AF

# blue
color4  #89B4FA
color12 #89B4FA

# magenta
color5  #F5C2E7
color13 #F5C2E7

# cyan
color6  #94E2D5
color14 #94E2D5

# white
color7  #BAC2DE
color15 #A6ADC8

# Cursor colors
cursor            #F5E0DC
cursor_text_color #1E1E2E

# URL underline color when hovering
url_color #F5E0DC

# Tab bar colors
active_tab_foreground   #1E1E2E
active_tab_background   #CBA6F7
inactive_tab_foreground #CDD6F4
inactive_tab_background #181825
tab_bar_background      #1E1E2E
EOF
print_success "Kitty configurada"

# --- 8) CONFIGURAR HYPRLAND ---
print_message "Configurando Hyprland con keybindings modernos..."

# Crear archivo principal de configuración Hyprland
cat > ~/.config/hypr/hyprland.conf << 'EOF'
# Configuración personalizada de Hyprland
# Optimizada para NVIDIA RTX 3080 + AMD Ryzen 9 5900HX

# Monitor
monitor=,preferred,auto,1

# Autostart
exec-once = ags
exec-once = swww init && swww img ~/.config/hypr/wallpapers/wallpaper.jpg --transition-fps 60
exec-once = mako
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Variables de entorno para NVIDIA
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
env = __GL_GSYNC_ALLOWED,0
env = __GL_VRR_ALLOWED,0
env = WLR_DRM_NO_ATOMIC,1
env = MOZ_ENABLE_WAYLAND,1
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24

# Variables de tema
env = GTK_THEME,Catppuccin-Mocha-Standard-Blue-Dark
env = XCURSOR_THEME,Catppuccin-Mocha-Dark-Cursors

# Configuración General
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(cba6f7ff) rgba(89b4faff) 45deg
    col.inactive_border = rgba(6c7086aa)
    layout = dwindle
    allow_tearing = false
}

# Decoración
decoration {
    rounding = 10
    blur {
        enabled = true
        size = 8
        passes = 3
        new_optimizations = on
        xray = false
    }
    drop_shadow = true
    shadow_range = 15
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animaciones
animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Disposición
dwindle {
    pseudotile = true
    preserve_split = true
}

master {
    new_is_master = true
}

# Gestos
gestures {
    workspace_swipe = true
}

# Rendimiento
misc {
    force_default_wallpaper = 0
    vfr = true
    vrr = 1
    mouse_move_enables_dpms = true
    key_press_enables_dpms = true
}

# Keybindings modernos similares a los populares
$mainMod = SUPER

# Aplicaciones
bind = $mainMod, Return, exec, kitty
bind = $mainMod, E, exec, thunar
bind = $mainMod, B, exec, firefox

# Lanzadores
bind = $mainMod, space, exec, fuzzel
bind = SUPER_SHIFT, V, exec, cliphist list | fuzzel -d | cliphist decode | wl-copy

# Control de ventanas
bind = $mainMod, Q, killactive
bind = $mainMod SHIFT, E, exit
bind = $mainMod, F, fullscreen
bind = $mainMod SHIFT, Space, togglefloating
bind = $mainMod, P, pseudo
bind = $mainMod, J, togglesplit

# Movimiento de enfoque
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Cambio de espacio de trabajo
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

# Mover ventanas a espacios de trabajo
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

# Cambiar espacios de trabajo con rueda del ratón
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Mover/redimensionar ventanas con ratón
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Multimedia y brillo
bind = , XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
bind = , XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
bind = , XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
bind = , XF86AudioPlay, exec, playerctl play-pause
bind = , XF86AudioNext, exec, playerctl next
bind = , XF86AudioPrev, exec, playerctl previous
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

# Screenshots
bind = , Print, exec, grim - | wl-copy
bind = SHIFT, Print, exec, grim -g "$(slurp)" - | wl-copy
bind = CTRL, Print, exec, grim ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png
bind = CTRL SHIFT, Print, exec, grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png

# AGS - teclas específicas para AGS
bind = $mainMod, Tab, exec, ags -t overview
bind = $mainMod, slash, exec, ags -t cheatsheet 
bind = $mainMod, D, exec, ags -t applauncher
bind = $mainMod, X, exec, wlogout
EOF

# Crear configuración específica para NVIDIA
cat > ~/.config/hypr/nvidia.conf << 'EOF'
# NVIDIA RTX 3080 specific settings
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
env = __GL_GSYNC_ALLOWED,0
env = __GL_VRR_ALLOWED,0
env = WLR_DRM_NO_ATOMIC,1
env = MOZ_ENABLE_WAYLAND,1
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24

# Prevención de parpadeo y optimización de rendimiento
decoration {
    blur {
        xray = false
        new_optimizations = true
    }
}

# Mejor rendimiento
general {
    gaps_in = 5
    gaps_out = 5
    border_size = 2
    allow_tearing = false
}

# Aceleración por hardware
misc {
    vfr = true
    vrr = 1
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}
EOF

# Incluir archivo de configuración de NVIDIA
echo "source = ./nvidia.conf" >> ~/.config/hypr/hyprland.conf

print_success "Hyprland configurado"

# --- 9) CONFIGURAR AYLUR'S GTK SHELL (AGS) ---
print_message "Creando configuración AGS desde cero..."

# Crear archivo principal de configuración para AGS
cat > ~/.config/ags/config.js << 'EOF'
import App from "resource:///com/github/Aylur/ags/app.js";
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import * as Utils from "resource:///com/github/Aylur/ags/utils.js";

// Importaciones de servicios
import Hyprland from "resource:///com/github/Aylur/ags/service/hyprland.js";
import Audio from "resource:///com/github/Aylur/ags/service/audio.js";
import Battery from "resource:///com/github/Aylur/ags/service/battery.js";
import Network from "resource:///com/github/Aylur/ags/service/network.js";
import SystemTray from "resource:///com/github/Aylur/ags/service/systemtray.js";
import Mpris from "resource:///com/github/Aylur/ags/service/mpris.js";

// Widgets principales
import Bar from "./widgets/bar.js";
import Overview from "./widgets/overview.js";
import OSD from "./widgets/osd.js";
import CheatSheet from "./widgets/cheatsheet.js";
import AppLauncher from "./widgets/applauncher.js";
import PowerMenu from "./widgets/powermenu.js";
import QuickSettings from "./widgets/quicksettings.js";
import Notifications from "./widgets/notifications.js";

// Estilos
const css = `
* {
    font-family: "JetBrainsMono Nerd Font", "Rubik", sans-serif;
    font-size: 14px;
}

.bar {
    background-color: rgba(30, 30, 46, 0.9);
    color: #cdd6f4;
    padding: 8px;
    border-radius: 0 0 12px 12px;
}

.bar-widget {
    margin: 0 5px;
}

.workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: #cdd6f4;
    font-size: 16px;
    min-width: 24px;
    min-height: 24px;
    border-radius: 99px;
    margin: 0 2px;
}

.workspaces button.active {
    background-color: #89b4fa;
    color: #1e1e2e;
}

.widget-button {
    border-radius: 99px;
    min-width: 24px;
    min-height: 24px;
    padding: 0 10px;
    background-color: transparent;
}

.widget-button:hover {
    background-color: rgba(49, 50, 68, 0.7);
}

.menu-box {
    background-color: rgba(30, 30, 46, 0.95);
    padding: 12px;
    border-radius: 12px;
    border: 2px solid #89b4fa;
}

.menu-header {
    font-weight: bold;
    font-size: 16px;
    margin-bottom: 8px;
    color: #cdd6f4;
}

.overview {
    background-color: rgba(30, 30, 46, 0.8);
    border-radius: 12px;
    border: 2px solid #cba6f7;
    padding: 20px;
}

.overview-workspace {
    background-color: rgba(49, 50, 68, 0.7);
    border-radius: 10px;
    margin: 5px;
    padding: 10px;
}

.overview-window {
    background-color: #1e1e2e;
    border-radius: 8px;
    border: 1px solid #89b4fa;
    color: #cdd6f4;
    padding: 5px;
    margin: 3px;
}

.cheatsheet {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 12px;
    border: 2px solid #f9e2af;
    padding: 20px;
}

.launcher {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 12px;
    border: 2px solid #89b4fa;
    padding: 15px;
}

.launcher-entry {
    border-radius: 8px;
    padding: 8px;
}

.launcher-entry:hover {
    background-color: rgba(49, 50, 68, 0.7);
}

.launcher-icon {
    min-width: 48px;
    min-height: 48px;
    margin-right: 8px;
}

.notification {
    background-color: rgba(30, 30, 46, 0.95);
    border-radius: 10px;
    border-left: 4px solid #89b4fa;
    padding: 12px;
    margin: 5px 0;
}

.notification.critical {
    border-left: 4px solid #f38ba8;
}

.powermenu {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 20px;
    border: 2px solid #f5c2e7;
}

.powermenu-button {
    padding: 20px;
    font-size: 32px;
    border-radius: 15px;
    margin: 10px;
    min-width: 100px;
    min-height: 100px;
}

.powermenu-button:hover {
    background-color: rgba(49, 50, 68, 0.7);
}

.quicksettings {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 15px;
    border: 2px solid #94e2d5;
    padding: 15px;
}

.slider trough highlight {
    background-color: #89b4fa;
    border-radius: 10px;
}

.slider trough {
    background-color: #313244;
    border-radius: 10px;
    min-height: 6px;
    min-width: 150px;
}

.osd {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 10px;
    padding: 15px;
    border: 2px solid #cba6f7;
    color: #cdd6f4;
}
`;

// Exportar configuración
export default {
    css,
    windows: [
        Bar(),
        Overview(),
        OSD(),
        CheatSheet(),
        AppLauncher(),
        PowerMenu(),
        QuickSettings(),
        Notifications(),
    ]
};
EOF

# Crear widgets principales
mkdir -p ~/.config/ags/widgets

# Barra principal
cat > ~/.config/ags/widgets/bar.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import * as Utils from "resource:///com/github/Aylur/ags/utils.js";
import Hyprland from "resource:///com/github/Aylur/ags/service/hyprland.js";
import Audio from "resource:///com/github/Aylur/ags/service/audio.js";
import Battery from "resource:///com/github/Aylur/ags/service/battery.js";
import Network from "resource:///com/github/Aylur/ags/service/network.js";
import SystemTray from "resource:///com/github/Aylur/ags/service/systemtray.js";
import Mpris from "resource:///com/github/Aylur/ags/service/mpris.js";

// Workspaces Widget
const Workspaces = () => Widget.Box({
    className: "workspaces",
    children: Hyprland.bind("workspaces").transform(workspaces => {
        return workspaces.map(ws => Widget.Button({
            className: `workspace ${Hyprland.active.workspace.id === ws.id ? "active" : ""}`,
            child: Widget.Label({
                label: `${ws.id}`,
            }),
            onClicked: () => Utils.execAsync(`hyprctl dispatch workspace ${ws.id}`),
        }));
    }),
});

// Window title
const WindowTitle = () => Widget.Label({
    className: "window-title",
    label: Hyprland.active.bind("client").transform(c => c?.title || "Desktop"),
    truncate: "end",
    maxWidthChars: 40,
});

// Clock Widget
const Clock = () => Widget.Label({
    className: "clock",
    label: Utils.formatTime("%H:%M - %a %d %b"),
    setup: self => self.poll(1000, self => {
        self.label = Utils.formatTime("%H:%M - %a %d %b");
    }),
});

// Battery Widget
const BatteryWidget = () => Widget.Box({
    className: "battery-widget",
    visible: Battery.bind("available"),
    children: [
        Widget.Icon({
            icon: Battery.bind("percent").transform(p => {
                if (Battery.charging) return "battery-charging-symbolic";
                if (p < 10) return "battery-empty-symbolic";
                if (p < 30) return "battery-low-symbolic";
                if (p < 60) return "battery-good-symbolic";
                return "battery-full-symbolic";
            }),
        }),
        Widget.Label({
            label: Battery.bind("percent").transform(p => `${p}%`),
        }),
    ],
});

// Network Widget
const NetworkWidget = () => Widget.Box({
    className: "network-widget",
    children: [
        Widget.Icon({
            icon: Network.bind("primary").transform(p => {
                if (!p) return "network-offline-symbolic";
                if (p.type === "wired") return "network-wired-symbolic";
                if (!p.strength) return "network-wireless-disconnected-symbolic";
                if (p.strength < 30) return "network-wireless-weak-symbolic";
                if (p.strength < 60) return "network-wireless-ok-symbolic";
                return "network-wireless-good-symbolic";
            }),
        }),
        Widget.Label({
            label: Network.bind("primary").transform(p => p?.name || "Not Connected"),
        }),
    ],
});

// Volume Widget
const VolumeWidget = () => Widget.Box({
    className: "volume-widget",
    children: [
        Widget.Icon({
            icon: Audio.bind("speaker").transform(s => {
                if (!s) return "audio-volume-muted-symbolic";
                if (s.muted) return "audio-volume-muted-symbolic";
                if (s.volume < 30) return "audio-volume-low-symbolic";
                if (s.volume < 70) return "audio-volume-medium-symbolic";
                return "audio-volume-high-symbolic";
            }),
        }),
        Widget.Label({
            label: Audio.bind("speaker").transform(s => s ? `${Math.round(s.volume)}%` : ""),
        }),
    ],
});

// System Tray
const Tray = () => Widget.Box({
    className: "system-tray",
    children: [
        SystemTray.bind().transform(items => {
            return items.map(item => Widget.Button({
                className: "tray-item",
                child: Widget.Icon({
                    icon: item.bind("icon"),
                }),
                onPrimaryClick: (_, event) => item.activate(event),
                onSecondaryClick: (_, event) => item.openMenu(event),
            }));
        }),
    ],
});

// Music Widget
const MusicWidget = () => Widget.Box({
    className: "music-widget",
    visible: Mpris.bind("players").transform(p => p.length > 0),
    children: [
        Widget.Icon({
            icon: "audio-x-generic-symbolic",
        }),
        Widget.Label({
            truncate: "end",
            maxWidthChars: 40,
            label: Mpris.bind("players").transform(players => {
                if (players.length === 0) return "";
                const player = players[0];
                return `${player.trackArtists.join(", ")} - ${player.trackTitle}`;
            }),
        }),
    ],
});

// The Bar
export default () => Widget.Window({
    name: "bar",
    className: "bar",
    anchor: ["top", "left", "right"],
    exclusive: true,
    child: Widget.CenterBox({
        startWidget: Widget.Box({
            className: "bar-widget",
            children: [
                Widget.Button({
                    className: "widget-button launcher-button",
                    child: Widget.Label({
                        label: "",
                    }),
                    onClicked: () => Utils.execAsync("ags -t applauncher"),
                }),
                Workspaces(),
                WindowTitle(),
            ],
        }),
        centerWidget: Widget.Box({
            className: "bar-widget",
            children: [
                MusicWidget(),
            ],
        }),
        endWidget: Widget.Box({
            className: "bar-widget",
            hpack: "end",
            children: [
                NetworkWidget(),
                VolumeWidget(),
                BatteryWidget(),
                Clock(),
                Tray(),
                Widget.Button({
                    className: "widget-button power-button",
                    child: Widget.Label({
                        label: "󰐥",
                    }),
                    onClicked: () => Utils.execAsync("ags -t powermenu"),
                }),
            ],
        }),
    }),
});
EOF

# Widget de Overview (similar al de end-4/dots-hyprland)
cat > ~/.config/ags/widgets/overview.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import * as Utils from "resource:///com/github/Aylur/ags/utils.js";
import App from "resource:///com/github/Aylur/ags/app.js";
import Hyprland from "resource:///com/github/Aylur/ags/service/hyprland.js";

const WorkspaceBox = () => Widget.Box({
    vertical: true,
    className: "overview-workspaces",
    children: Hyprland.bind("workspaces").transform(workspaces => {
        return workspaces.map(ws => {
            const clients = Hyprland.clients.filter(c => c.workspace.id === ws.id);
            
            return Widget.Box({
                className: "overview-workspace",
                vertical: true,
                children: [
                    Widget.Label({
                        className: "overview-workspace-label",
                        label: `Workspace ${ws.id}`,
                    }),
                    Widget.Box({
                        className: "overview-workspace-clients",
                        children: clients.map(client => Widget.Button({
                            className: "overview-window",
                            child: Widget.Box({
                                children: [
                                    Widget.Icon({
                                        icon: "application-x-executable-symbolic",
                                    }),
                                    Widget.Label({
                                        label: client.title || client.class || "Unknown",
                                        truncate: "end",
                                        maxWidthChars: 20,
                                    }),
                                ],
                            }),
                            onClicked: () => {
                                Utils.execAsync(`hyprctl dispatch focuswindow address:${client.address}`);
                                App.toggleWindow("overview");
                            },
                        })),
                    }),
                ],
            });
        });
    }),
});

const SearchBox = () => Widget.Box({
    className: "overview-search",
    vertical: true,
    children: [
        Widget.Entry({
            className: "overview-search-entry",
            hexpand: true,
            placeholder: "Search...",
            onAccept: (entry) => {
                Utils.execAsync(`fuzzel -d -I ${entry.text}`);
                App.toggleWindow("overview");
                entry.text = "";
            },
        }),
    ],
});

export default () => Widget.Window({
    name: "overview",
    visible: false,
    exclusive: true,
    focusable: true,
    popup: true,
    anchor: ["center"],
    child: Widget.Box({
        className: "overview",
        vertical: true,
        children: [
            Widget.Box({
                className: "overview-header",
                children: [
                    Widget.Label({
                        className: "overview-title",
                        label: "Overview",
                    }),
                    Widget.Button({
                        className: "overview-close",
                        child: Widget.Label({
                            label: "󰅖",
                        }),
                        onClicked: () => App.toggleWindow("overview"),
                    }),
                ],
            }),
            SearchBox(),
            WorkspaceBox(),
        ],
    }),
});
EOF

# Widget de OSD (Mensajes On-Screen Display)
cat > ~/.config/ags/widgets/osd.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import Audio from "resource:///com/github/Aylur/ags/service/audio.js";
import Battery from "resource:///com/github/Aylur/ags/service/battery.js";
import App from "resource:///com/github/Aylur/ags/app.js";

// Volume OSD
const VolumeIndicator = () => Widget.Box({
    className: "osd-indicator",
    vertical: true,
    children: [
        Widget.Icon({
            icon: Audio.bind("speaker").transform(s => {
                if (!s) return "audio-volume-muted-symbolic";
                if (s.muted) return "audio-volume-muted-symbolic";
                if (s.volume < 30) return "audio-volume-low-symbolic";
                if (s.volume < 70) return "audio-volume-medium-symbolic";
                return "audio-volume-high-symbolic";
            }),
            size: 48,
        }),
        Widget.Slider({
            className: "osd-slider",
            hexpand: true,
            value: Audio.bind("speaker").transform(s => s?.volume || 0),
            onChange: value => Audio.speaker.volume = value,
        }),
        Widget.Label({
            className: "osd-label",
            label: Audio.bind("speaker").transform(s => s ? `Volume: ${Math.round(s.volume)}%` : "Volume: 0%"),
        }),
    ],
});

// Brightness OSD
const BrightnessIndicator = () => Widget.Box({
    className: "osd-indicator",
    vertical: true,
    children: [
        Widget.Icon({
            icon: "display-brightness-symbolic",
            size: 48,
        }),
        Widget.Label({
            className: "osd-label",
            label: "Brightness Adjusted",
        }),
    ],
});

// Battery OSD
const BatteryIndicator = () => Widget.Box({
    className: "osd-indicator",
    vertical: true,
    children: [
        Widget.Icon({
            icon: Battery.bind("percent").transform(p => {
                if (Battery.charging) return "battery-charging-symbolic";
                if (p < 10) return "battery-empty-symbolic";
                if (p < 30) return "battery-low-symbolic";
                if (p < 60) return "battery-good-symbolic";
                return "battery-full-symbolic";
            }),
            size: 48,
        }),
        Widget.Label({
            className: "osd-label",
            label: Battery.bind("percent").transform(p => `Battery: ${p}%`),
        }),
    ],
});

export default () => Widget.Window({
    name: "osd",
    className: "osd",
    anchor: ["right", "top"],
    exclusive: false,
    focusable: false,
    popup: true,
    visible: false,
    child: Widget.Stack({
        transition: "slide_left",
        items: [
            ["volume", VolumeIndicator()],
            ["brightness", BrightnessIndicator()],
            ["battery", BatteryIndicator()],
        ],
    }),
});
EOF

# Widget de CheatSheet (lista de atajos)
cat > ~/.config/ags/widgets/cheatsheet.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import App from "resource:///com/github/Aylur/ags/app.js";

// Definir los atajos de teclado para mostrar
const shortcuts = [
    { keys: "Super + Enter", description: "Abrir terminal" },
    { keys: "Super + Q", description: "Cerrar ventana activa" },
    { keys: "Super + E", description: "Abrir explorador de archivos" },
    { keys: "Super + B", description: "Abrir navegador" },
    { keys: "Super + Space", description: "Abrir launcher de aplicaciones" },
    { keys: "Super + F", description: "Ventana a pantalla completa" },
    { keys: "Super + Tab", description: "Abrir vista general (overview)" },
    { keys: "Super + /", description: "Mostrar esta cheatsheet" },
    { keys: "Super + D", description: "Abrir lanzador de aplicaciones" },
    { keys: "Super + X", description: "Abrir menú de apagado" },
    { keys: "Super + 1-0", description: "Cambiar al espacio de trabajo 1-10" },
    { keys: "Super + Shift + 1-0", description: "Mover ventana al espacio 1-10" },
    { keys: "Super + ↑/↓/←/→", description: "Cambiar foco de ventana" },
    { keys: "Print", description: "Captura de pantalla (clipboard)" },
    { keys: "Shift + Print", description: "Captura de área (clipboard)" },
    { keys: "Ctrl + Print", description: "Guardar captura pantalla" },
    { keys: "Ctrl + Shift + Print", description: "Guardar captura de área" },
];

// Widget de ShortcutRow
const ShortcutRow = (shortcut) => Widget.Box({
    className: "shortcut-row",
    children: [
        Widget.Label({
            className: "shortcut-keys",
            label: shortcut.keys,
            xalign: 0,
        }),
        Widget.Label({
            className: "shortcut-description",
            label: shortcut.description,
            xalign: 0,
        }),
    ],
});

export default () => Widget.Window({
    name: "cheatsheet",
    className: "cheatsheet",
    visible: false,
    anchor: ["center"],
    exclusive: true,
    focusable: true,
    popup: true,
    child: Widget.Box({
        vertical: true,
        children: [
            Widget.Box({
                className: "cheatsheet-header",
                children: [
                    Widget.Label({
                        className: "cheatsheet-title",
                        label: "Atajos de Teclado",
                    }),
                    Widget.Button({
                        className: "cheatsheet-close",
                        child: Widget.Label({
                            label: "󰅖",
                        }),
                        onClicked: () => App.toggleWindow("cheatsheet"),
                    }),
                ],
            }),
            Widget.Box({
                className: "cheatsheet-content",
                vertical: true,
                children: shortcuts.map(shortcut => ShortcutRow(shortcut)),
            }),
        ],
    }),
});
EOF

# Widget de AppLauncher
cat > ~/.config/ags/widgets/applauncher.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import App from "resource:///com/github/Aylur/ags/app.js";
import Applications from "resource:///com/github/Aylur/ags/service/applications.js";
import * as Utils from "resource:///com/github/Aylur/ags/utils.js";

// Widget de aplicación individual
const AppItem = app => Widget.Button({
    className: "launcher-entry",
    onClicked: () => {
        app.launch();
        App.toggleWindow("applauncher");
    },
    child: Widget.Box({
        children: [
            Widget.Icon({
                className: "launcher-icon",
                icon: app.icon_name || "application-x-executable-symbolic",
                size: 48,
            }),
            Widget.Box({
                vertical: true,
                children: [
                    Widget.Label({
                        className: "launcher-title",
                        label: app.name,
                        xalign: 0,
                        truncate: "end",
                        maxWidthChars: 20,
                    }),
                    Widget.Label({
                        className: "launcher-description",
                        label: app.description || "",
                        xalign: 0,
                        truncate: "end",
                        maxWidthChars: 30,
                    }),
                ],
            }),
        ],
    }),
});

export default () => Widget.Window({
    name: "applauncher",
    className: "launcher",
    visible: false,
    exclusive: true,
    focusable: true,
    popup: true,
    anchor: ["center"],
    child: Widget.Box({
        vertical: true,
        children: [
            Widget.Entry({
                className: "launcher-search",
                hexpand: true,
                placeholder: "Buscar aplicaciones...",
                onAccept: (entry) => {
                    // Buscar y lanzar la primera aplicación que coincida
                    const app = Applications.query(entry.text)[0];
                    if (app) {
                        app.launch();
                        App.toggleWindow("applauncher");
                        entry.text = "";
                    }
                },
                onChange: (entry) => {
                    // Actualizar la lista de aplicaciones al escribir
                    const query = entry.text;
                    const apps = query.length > 0 
                        ? Applications.query(query)
                        : Applications.list;
                        
                    const box = entry.parent.get_children()[1];
                    box.children = apps.map(app => AppItem(app));
                },
            }),
            Widget.ScrollBox({
                className: "launcher-apps",
                hscroll: "never",
                vscroll: "automatic",
                height: 500,
                child: Widget.Box({
                    vertical: true,
                    children: Applications.bind("list").transform(apps => 
                        apps.map(app => AppItem(app))
                    ),
                }),
            }),
        ],
    }),
});
EOF

# Widget de PowerMenu
cat > ~/.config/ags/widgets/powermenu.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import App from "resource:///com/github/Aylur/ags/app.js";
import * as Utils from "resource:///com/github/Aylur/ags/utils.js";

// Action button
const PowerButton = ({ icon, label, action, className = "" }) => Widget.Button({
    className: `powermenu-button ${className}`,
    child: Widget.Box({
        vertical: true,
        children: [
            Widget.Label({
                label: icon,
                className: "powermenu-icon",
            }),
            Widget.Label({
                label: label,
                className: "powermenu-label",
            }),
        ],
    }),
    onClicked: () => {
        App.closeWindow("powermenu");
        Utils.execAsync(action);
    },
});

export default () => Widget.Window({
    name: "powermenu",
    className: "powermenu",
    visible: false,
    anchor: ["center"],
    exclusive: true,
    focusable: true,
    popup: true,
    child: Widget.Box({
        vertical: true,
        children: [
            Widget.Box({
                className: "powermenu-header",
                children: [
                    Widget.Label({
                        className: "powermenu-title",
                        label: "Power Menu",
                    }),
                    Widget.Button({
                        className: "powermenu-close",
                        child: Widget.Label({
                            label: "󰅖",
                        }),
                        onClicked: () => App.toggleWindow("powermenu"),
                    }),
                ],
            }),
            Widget.Box({
                className: "powermenu-buttons",
                homogeneous: true,
                children: [
                    PowerButton({
                        icon: "󰤄",
                        label: "Suspend",
                        action: "systemctl suspend",
                        className: "suspend",
                    }),
                    PowerButton({
                        icon: "󰜉",
                        label: "Reboot",
                        action: "systemctl reboot",
                        className: "reboot",
                    }),
                    PowerButton({
                        icon: "󰐥",
                        label: "Shutdown",
                        action: "systemctl poweroff",
                        className: "shutdown",
                    }),
                    PowerButton({
                        icon: "󰍃",
                        label: "Logout",
                        action: "hyprctl dispatch exit",
                        className: "logout",
                    }),
                    PowerButton({
                        icon: "󰌾",
                        label: "Lock",
                        action: "swaylock",
                        className: "lock",
                    }),
                ],
            }),
        ],
    }),
});
EOF

# Widget de QuickSettings
cat > ~/.config/ags/widgets/quicksettings.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import App from "resource:///com/github/Aylur/ags/app.js";
import Audio from "resource:///com/github/Aylur/ags/service/audio.js";
import Network from "resource:///com/github/Aylur/ags/service/network.js";
import Battery from "resource:///com/github/Aylur/ags/service/battery.js";
import * as Utils from "resource:///com/github/Aylur/ags/utils.js";

// Slider with icon
const IconSlider = ({ icon, value, onChange }) => Widget.Box({
    className: "quicksettings-slider",
    children: [
        Widget.Icon({
            icon: icon,
            size: 24,
        }),
        Widget.Slider({
            className: "slider",
            hexpand: true,
            drawValue: false,
            value: value,
            onChange: onChange,
        }),
    ],
});

// Toggle button
const ToggleButton = ({ icon, active, label, onClicked }) => Widget.Button({
    className: `quicksettings-toggle ${active ? "active" : ""}`,
    child: Widget.Box({
        children: [
            Widget.Icon({
                icon: icon,
                size: 24,
            }),
            Widget.Label({
                label: label,
            }),
        ],
    }),
    onClicked: onClicked,
});

export default () => Widget.Window({
    name: "quicksettings",
    className: "quicksettings",
    visible: false,
    anchor: ["top", "right"],
    exclusive: true,
    focusable: true,
    popup: true,
    child: Widget.Box({
        vertical: true,
        children: [
            Widget.Box({
                className: "quicksettings-header",
                children: [
                    Widget.Label({
                        className: "quicksettings-title",
                        label: "Quick Settings",
                    }),
                    Widget.Button({
                        className: "quicksettings-close",
                        child: Widget.Label({
                            label: "󰅖",
                        }),
                        onClicked: () => App.toggleWindow("quicksettings"),
                    }),
                ],
            }),
            Widget.Box({
                className: "quicksettings-volume",
                vertical: true,
                children: [
                    Widget.Label({
                        xalign: 0,
                        label: "Volume",
                    }),
                    IconSlider({
                        icon: Audio.bind("speaker").transform(s => {
                            if (!s) return "audio-volume-muted-symbolic";
                            if (s.muted) return "audio-volume-muted-symbolic";
                            if (s.volume < 30) return "audio-volume-low-symbolic";
                            if (s.volume < 70) return "audio-volume-medium-symbolic";
                            return "audio-volume-high-symbolic";
                        }),
                        value: Audio.bind("speaker").transform(s => s?.volume || 0),
                        onChange: value => Audio.speaker.volume = value,
                    }),
                    Widget.Button({
                        className: "mute-button",
                        child: Widget.Box({
                            children: [
                                Widget.Icon({
                                    icon: Audio.bind("speaker").transform(s => 
                                        s?.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
                                    ),
                                }),
                                Widget.Label({
                                    label: Audio.bind("speaker").transform(s => 
                                        s?.muted ? "Unmute" : "Mute"
                                    ),
                                }),
                            ],
                        }),
                        onClicked: () => {
                            if (Audio.speaker) 
                                Audio.speaker.muted = !Audio.speaker.muted;
                        },
                    }),
                ],
            }),
            Widget.Box({
                className: "quicksettings-toggles",
                children: [
                    ToggleButton({
                        icon: Network.wifi?.bind("enabled").transform(e => 
                            e ? "network-wireless-symbolic" : "network-wireless-offline-symbolic"
                        ),
                        active: Network.wifi?.bind("enabled"),
                        label: "WiFi",
                        onClicked: () => {
                            if (Network.wifi) 
                                Network.wifi.enabled = !Network.wifi.enabled;
                        },
                    }),
                    ToggleButton({
                        icon: Network.bluetooth?.bind("enabled").transform(e => 
                            e ? "bluetooth-active-symbolic" : "bluetooth-disabled-symbolic"
                        ),
                        active: Network.bluetooth?.bind("enabled"),
                        label: "Bluetooth",
                        onClicked: () => {
                            if (Network.bluetooth) 
                                Network.bluetooth.enabled = !Network.bluetooth.enabled;
                        },
                    }),
                    ToggleButton({
                        icon: "display-brightness-symbolic",
                        active: false,
                        label: "Night Light",
                        onClicked: () => Utils.execAsync("wlsunset -t 4500"),
                    }),
                ],
            }),
            Widget.Box({
                className: "quicksettings-system",
                children: [
                    ToggleButton({
                        icon: "system-shutdown-symbolic",
                        label: "Power Menu",
                        onClicked: () => {
                            App.toggleWindow("powermenu");
                            App.closeWindow("quicksettings");
                        },
                    }),
                    ToggleButton({
                        icon: "system-lock-screen-symbolic",
                        label: "Lock",
                        onClicked: () => {
                            Utils.execAsync("swaylock");
                            App.closeWindow("quicksettings");
                        },
                    }),
                ],
            }),
        ],
    }),
});
EOF

# Widget de Notificaciones
cat > ~/.config/ags/widgets/notifications.js << 'EOF'
import Widget from "resource:///com/github/Aylur/ags/widget.js";
import Notifications from "resource:///com/github/Aylur/ags/service/notifications.js";

// Notification Widget
const NotificationWidget = notification => Widget.Box({
    className: `notification ${notification.urgency}`,
    vertical: true,
    children: [
        Widget.Box({
            children: [
                Widget.Icon({
                    icon: notification.app_icon || "dialog-information-symbolic",
                    size: 32,
                }),
                Widget.Box({
                    hexpand: true,
                    vertical: true,
                    children: [
                        Widget.Label({
                            xalign: 0,
                            className: "notification-title",
                            truncate: "end",
                            maxWidthChars: 40,
                            label: notification.summary,
                        }),
                        Widget.Label({
                            xalign: 0,
                            className: "notification-body",
                            truncate: "end",
                            maxWidthChars: 60,
                            label: notification.body,
                        }),
                    ],
                }),
                Widget.Button({
                    className: "notification-close",
                    child: Widget.Label({
                        label: "󰅖",
                    }),
                    onClicked: () => notification.close(),
                }),
            ],
        }),
        Widget.Box({
            className: "notification-actions",
            children: notification.actions.map(action => Widget.Button({
                className: "notification-action",
                child: Widget.Label({
                    label: action.label,
                }),
                onClicked: () => {
                    notification.invoke(action.id);
                    notification.close();
                },
            })),
        }),
    ],
});

export default () => Widget.Window({
    name: "notifications",
    anchor: ["top", "right"],
    child: Widget.Box({
        className: "notifications-container",
        vertical: true,
        children: Notifications.bind("notifications").transform(notifications => {
            return notifications.map(notification => NotificationWidget(notification));
        }),
    }),
});
EOF

# Crear archivo de estilo
cat > ~/.config/ags/style.css << 'EOF'
* {
    font-family: "JetBrainsMono Nerd Font", "Rubik", sans-serif;
    font-size: 14px;
}

.bar {
    background-color: rgba(30, 30, 46, 0.9);
    color: #cdd6f4;
    padding: 8px;
    border-radius: 0 0 12px 12px;
}

.bar-widget {
    margin: 0 5px;
}

.workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: #cdd6f4;
    font-size: 16px;
    min-width: 24px;
    min-height: 24px;
    border-radius: 99px;
    margin: 0 2px;
}

.workspaces button.active {
    background-color: #89b4fa;
    color: #1e1e2e;
}

.window-title {
    font-weight: bold;
    margin-left: 10px;
}

.widget-button {
    border-radius: 99px;
    min-width: 24px;
    min-height: 24px;
    padding: 0 10px;
    background-color: transparent;
}

.widget-button:hover {
    background-color: rgba(49, 50, 68, 0.7);
}

.clock {
    font-weight: bold;
}

.battery-widget, .volume-widget, .network-widget {
    margin: 0 5px;
}

.music-widget {
    background-color: rgba(49, 50, 68, 0.5);
    border-radius: 8px;
    padding: 0 10px;
}

.launcher-button {
    font-size: 18px;
    padding: 0 10px;
}

.power-button {
    font-size: 18px;
    padding: 0 10px;
}

.system-tray {
    margin-left: 10px;
}

.tray-item {
    margin: 0 2px;
}

.overview {
    background-color: rgba(30, 30, 46, 0.8);
    border-radius: 12px;
    border: 2px solid #cba6f7;
    padding: 20px;
}

.overview-header {
    margin-bottom: 20px;
}

.overview-title {
    font-size: 20px;
    font-weight: bold;
}

.overview-close {
    margin-left: auto;
    padding: 8px;
    border-radius: 8px;
    background-color: #313244;
}

.overview-search {
    margin-bottom: 20px;
}

.overview-search-entry {
    padding: 10px;
    border-radius: 8px;
    background-color: #313244;
    color: #cdd6f4;
}

.overview-workspace {
    background-color: rgba(49, 50, 68, 0.7);
    border-radius: 10px;
    margin: 5px;
    padding: 10px;
}

.overview-workspace-label {
    font-weight: bold;
    margin-bottom: 5px;
}

.overview-window {
    background-color: #1e1e2e;
    border-radius: 8px;
    border: 1px solid #89b4fa;
    color: #cdd6f4;
    padding: 5px;
    margin: 3px;
}

.cheatsheet {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 12px;
    border: 2px solid #f9e2af;
    padding: 20px;
}

.cheatsheet-header {
    margin-bottom: 20px;
}

.cheatsheet-title {
    font-size: 20px;
    font-weight: bold;
}

.cheatsheet-close {
    margin-left: auto;
    padding: 8px;
    border-radius: 8px;
    background-color: #313244;
}

.shortcut-row {
    padding: 8px;
    margin: 2px;
}

.shortcut-keys {
    font-weight: bold;
    min-width: 150px;
}

.launcher {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 12px;
    border: 2px solid #89b4fa;
    padding: 15px;
}

.launcher-search {
    margin-bottom: 10px;
    padding: 10px;
    border-radius: 8px;
    background-color: #313244;
}

.launcher-entry {
    border-radius: 8px;
    padding: 8px;
}

.launcher-entry:hover {
    background-color: rgba(49, 50, 68, 0.7);
}

.launcher-icon {
    min-width: 48px;
    min-height: 48px;
    margin-right: 8px;
}

.launcher-title {
    font-weight: bold;
}

.launcher-description {
    opacity: 0.8;
    font-size: 12px;
}

.notification {
    background-color: rgba(30, 30, 46, 0.95);
    border-radius: 10px;
    border-left: 4px solid #89b4fa;
    padding: 12px;
    margin: 5px 0;
}

.notification.critical {
    border-left: 4px solid #f38ba8;
}

.notification-title {
    font-weight: bold;
    font-size: 15px;
}

.notification-close {
    padding: 4px;
    border-radius: 99px;
    margin-left: 10px;
    min-width: 24px;
    min-height: 24px;
}

.notification-actions {
    margin-top: 10px;
}

.notification-action {
    margin-right: 5px;
    padding: 5px 10px;
    border-radius: 8px;
    background-color: #313244;
}

.powermenu {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 20px;
    border: 2px solid #f5c2e7;
    padding: 20px;
}

.powermenu-header {
    margin-bottom: 20px;
}

.powermenu-title {
    font-size: 20px;
    font-weight: bold;
}

.powermenu-close {
    margin-left: auto;
    padding: 8px;
    border-radius: 8px;
    background-color: #313244;
}

.powermenu-buttons {
    padding: 10px;
}

.powermenu-button {
    padding: 20px;
    font-size: 32px;
    border-radius: 15px;
    margin: 10px;
    min-width: 100px;
    min-height: 100px;
    background-color: #313244;
}

.powermenu-button:hover {
    background-color: rgba(49, 50, 68, 0.7);
}

.powermenu-icon {
    font-size: 32px;
}

.powermenu-label {
    font-size: 14px;
    margin-top: 10px;
}

.quicksettings {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 15px;
    border: 2px solid #94e2d5;
    padding: 15px;
}

.quicksettings-header {
    margin-bottom: 20px;
}

.quicksettings-title {
    font-size: 20px;
    font-weight: bold;
}

.quicksettings-close {
    margin-left: auto;
    padding: 8px;
    border-radius: 8px;
    background-color: #313244;
}

.quicksettings-volume, .quicksettings-toggles, .quicksettings-system {
    margin-bottom: 15px;
    background-color: #313244;
    border-radius: 10px;
    padding: 10px;
}

.quicksettings-slider {
    margin: 10px 0;
}

.slider trough highlight {
    background-color: #89b4fa;
    border-radius: 10px;
}

.slider trough {
    background-color: #45475a;
    border-radius: 10px;
    min-height: 6px;
    min-width: 150px;
}

.mute-button, .quicksettings-toggle {
    padding: 8px;
    border-radius: 8px;
    margin: 5px;
    background-color: #45475a;
}

.quicksettings-toggle.active {
    background-color: #89b4fa;
    color: #1e1e2e;
}

.osd {
    background-color: rgba(30, 30, 46, 0.9);
    border-radius: 10px;
    padding: 15px;
    border: 2px solid #cba6f7;
    color: #cdd6f4;
}

.osd-indicator {
    padding: 10px;
}

.osd-slider {
    min-width: 300px;
    margin: 10px 0;
}

.osd-label {
    font-weight: bold;
    margin-top: 5px;
}
EOF

print_success "AGS configurado con barra de estado y widgets desde cero"

# --- 10) CONFIGURAR FUZZEL ---
print_message "Configurando Fuzzel..."
mkdir -p ~/.config/fuzzel
cat > ~/.config/fuzzel/fuzzel.ini << 'EOF'
[main]
font=Rubik:size=12
dpi-aware=auto
prompt="❯ "
icon-theme=Papirus-Dark
icons-enabled=yes
fields=name,generic,comment,categories,filename,keywords
terminal=kitty
width=35
horizontal-pad=20
vertical-pad=16
inner-pad=10
image-size-ratio=0.5
line-height=24
lines=12
letter-spacing=0
layer=overlay
exit-on-keyboard-focus-loss=yes

[colors]
background=1e1e2eee
text=cdd6f4ff
match=f38ba8ff
selection=89b4faff
selection-text=1e1e2eff
border=89b4fa88

[border]
width=2
radius=12

[dmenu]
exit-immediately-if-empty=yes

[key-bindings]
cancel=Escape Control+g Control+c
execute=Return KP_Enter Control+y
execute-or-next=Tab
cursor-left=Left Control+b
cursor-right=Right Control+f
cursor-home=Home Control+a
cursor-end=End Control+e
delete-prev=BackSpace
delete-prev-word=Control+BackSpace Control+w
delete-next=Delete
delete-next-word=Control+Delete Control+alt+d
delete-line=Control+k
prev=Up Control+p
prev-with-wrap=ISO_Left_Tab
prev-page=Page_Up KP_Page_Up Control+v
next=Down Control+n
next-with-wrap=none
next-page=Page_Down KP_Page_Down Control+V

[search-bindings]
paste=Control+v Control+y
EOF
print_success "Fuzzel configurado"

# --- 11) CONFIGURAR SWAYLOCK ---
print_message "Configurando Swaylock..."
cat > ~/.config/swaylock/config << 'EOF'
daemonize
show-failed-attempts
clock
screenshot
effect-blur=15x5
effect-vignette=0.5:0.5
color=1e1e2e
font="JetBrainsMono Nerd Font"
indicator
indicator-radius=200
indicator-thickness=20
line-color=89b4fa
ring-color=1e1e2e
inside-color=1e1e2e
key-hl-color=cba6f7
separator-color=00000000
text-color=cdd6f4
text-caps-lock-color=f38ba8
line-ver-color=a6e3a1
ring-ver-color=1e1e2e
inside-ver-color=1e1e2e
text-ver-color=a6e3a1
ring-wrong-color=f38ba8
text-wrong-color=f38ba8
inside-wrong-color=1e1e2e
inside-clear-color=1e1e2e
text-clear-color=cdd6f4
ring-clear-color=89b4fa
line-clear-color=89b4fa
line-wrong-color=f38ba8
bs-hl-color=f38ba8
grace=2
grace-no-mouse
grace-no-touch
datestr=%a, %b %d
timestr=%H:%M:%S
fade-in=0.2
ignore-empty-password
EOF
print_success "Swaylock configurado"

# --- 12) CONFIGURAR WLOGOUT ---
print_message "Configurando Wlogout..."
mkdir -p ~/.config/wlogout
cat > ~/.config/wlogout/layout << 'EOF'
{
    "label" : "lock",
    "action" : "swaylock",
    "text" : "Bloquear",
    "keybind" : "l"
}
{
    "label" : "hibernate",
    "action" : "systemctl hibernate",
    "text" : "Hibernar",
    "keybind" : "h"
}
{
    "label" : "logout",
    "action" : "hyprctl dispatch exit",
    "text" : "Cerrar sesión",
    "keybind" : "e"
}
{
    "label" : "shutdown",
    "action" : "systemctl poweroff",
    "text" : "Apagar",
    "keybind" : "s"
}
{
    "label" : "suspend",
    "action" : "systemctl suspend",
    "text" : "Suspender",
    "keybind" : "u"
}
{
    "label" : "reboot",
    "action" : "systemctl reboot",
    "text" : "Reiniciar",
    "keybind" : "r"
}
EOF

cat > ~/.config/wlogout/style.css << 'EOF'
window {
    font-family: "Rubik", "JetBrainsMono Nerd Font";
    font-size: 14pt;
    color: #cdd6f4;
    background-color: rgba(30, 30, 46, 0.7);
}

button {
    background-color: #313244;
    border-radius: 16px;
    background-repeat: no-repeat;
    background-position: center;
    background-size: 25%;
    margin: 10px;
}

button:focus, button:active, button:hover {
    background-color: #89b4fa;
    border: 2px solid #cba6f7;
    outline-style: none;
}

#lock {
    background-image: image(url("icons/lock.png"), url("/usr/share/wlogout/icons/lock.png"));
}

#logout {
    background-image: image(url("icons/logout.png"), url("/usr/share/wlogout/icons/logout.png"));
}

#suspend {
    background-image: image(url("icons/suspend.png"), url("/usr/share/wlogout/icons/suspend.png"));
}

#hibernate {
    background-image: image(url("icons/hibernate.png"), url("/usr/share/wlogout/icons/hibernate.png"));
}

#shutdown {
    background-image: image(url("icons/shutdown.png"), url("/usr/share/wlogout/icons/shutdown.png"));
}

#reboot {
    background-image: image(url("icons/reboot.png"), url("/usr/share/wlogout/icons/reboot.png"));
}
EOF
print_success "Wlogout configurado"

# --- 13) CONFIGURAR MAKO ---
print_message "Configurando Mako (notificaciones)..."

# Verificar si mako está instalado
if ! command -v mako &>/dev/null; then
    print_warning "Mako no está instalado. Instalándolo..."
    yay -S --noconfirm mako-git
fi

cat > ~/.config/mako/config << 'EOF'
sort=-time
layer=overlay
background-color=#1e1e2eee
width=300
height=110
border-size=2
border-color=#89b4faaa
border-radius=12
icons=1
max-icon-size=64
default-timeout=5000
ignore-timeout=1
font=Rubik 12
margin=10
padding=10,15

[urgency=low]
border-color=#cba6f7aa

[urgency=normal]
border-color=#89b4faaa

[urgency=high]
border-color=#f38ba8aa
default-timeout=0

[category=mpd]
default-timeout=2000
group-by=category
EOF
print_success "Mako configurado"

# --- 14) CONFIGURAR FASTFETCH ---
print_message "Configurando Fastfetch..."
mkdir -p ~/.config/fastfetch
cat > ~/.config/fastfetch/config.jsonc << 'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "small",
        "color": {
            "1": "blue",
            "2": "magenta"
        }
    },
    "display": {
        "separator": "  "
    },
    "modules": [
        "title",
        "os",
        "kernel",
        "packages",
        "de",
        "wm",
        "shell",
        "cpu",
        "gpu",
        "memory",
        "disk",
        "uptime"
    ]
}
EOF
print_success "Fastfetch configurado"

# --- 15) CONFIGURAR BASHRC PERSONALIZADO ---
print_message "Configurando .bashrc personalizado..."
cat > ~/.bashrc << 'EOF'
# .bashrc
# Personalizado para ArchLinux + Hyprland + Aylur's GTK Shell
# Última actualización: Marzo 2025

# Si no se ejecuta interactivamente, no hacer nada
[[ $- != *i* ]] && return

# Alias útiles
alias ls='ls --color=auto'
alias ll='ls -la'
alias grep='grep --color=auto'
alias ip='ip -color=auto'
alias pacman='pacman --color=auto'
alias update='sudo pacman -Syu'
alias aur='yay -Sua'
alias clean='sudo pacman -Rns $(pacman -Qtdq)'
alias vim='nvim'
alias c='clear'
alias reboot='systemctl reboot'
alias poweroff='systemctl poweroff'
alias suspend='systemctl suspend'
alias hyprconf='nvim ~/.config/hypr/hyprland.conf'
alias kittyconf='nvim ~/.config/kitty/kitty.conf'

# Iniciar Starship
if command -v starship &>/dev/null; then
    eval "$(starship init bash)"
fi

# Historial de comandos
HISTSIZE=1000
HISTFILESIZE=2000
HISTCONTROL=ignoreboth
shopt -s histappend

# Verificar el tamaño de la ventana después de cada comando
shopt -s checkwinsize

# Completado mejorado
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Variables de entorno
export EDITOR='nvim'
export VISUAL='nvim'
export TERM=xterm-256color
export PATH="$HOME/.local/bin:$PATH"

# Variables específicas para Hyprland + NVIDIA
export WLR_NO_HARDWARE_CURSORS=1
export LIBVA_DRIVER_NAME=nvidia
export XDG_SESSION_TYPE=wayland
export MOZ_ENABLE_WAYLAND=1
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# Mostrar fastfetch al inicio
if [ -x "$(command -v fastfetch)" ]; then
    fastfetch
fi
EOF
print_success ".bashrc configurado"

# --- 16) CONFIGURAR ARCHIVO DE INICIO DE SESIÓN (.profile) ---
print_message "Configurando .profile..."
cat > ~/.profile << 'EOF'
# ~/.profile
# Variables de entorno específicas para Hyprland + NVIDIA
export WLR_NO_HARDWARE_CURSORS=1
export LIBVA_DRIVER_NAME=nvidia
export XDG_SESSION_TYPE=wayland
export MOZ_ENABLE_WAYLAND=1
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# Iniciar Hyprland automáticamente en tty1
if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
    exec Hyprland
fi
EOF
print_success ".profile configurado"

# --- 17) CONFIGURAR TEMAS GTK ---
print_message "Configurando temas GTK..."
mkdir -p ~/.config/gtk-3.0
cat > ~/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Blue-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Rubik 11
gtk-cursor-theme-name=Catppuccin-Mocha-Dark-Cursors
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
gtk-xft-rgba=rgb
EOF
print_success "Temas GTK configurados"

# --- 18) CONFIGURACIÓN DE STARSHIP PROMPT ---
print_message "Configurando Starship prompt..."
if ! command -v starship &>/dev/null; then
    print_warning "Starship no está instalado. Instalándolo..."
    curl -sS https://starship.rs/install.sh | sh
fi

mkdir -p ~/.config/starship
cat > ~/.config/starship.toml << 'EOF'
# Starship Configuration
# Optimizado para terminal Kitty + Bash

format = """
$username\
$hostname\
$directory\
$git_branch\
$git_state\
$git_status\
$cmd_duration\
$line_break\
$python\
$character"""

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
vimcmd_symbol = "[❮](green)"

[directory]
truncation_length = 3
truncation_symbol = "…/"
style = "blue"

[git_branch]
format = "[$branch]($style)"
style = "bright-black"

[git_status]
format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)"
style = "cyan"
conflicted = "​"
untracked = "​"
modified = "​"
staged = "​"
renamed = "​"
deleted = "​"
stashed = "≡"

[git_state]
format = '\([$state( $progress_current/$progress_total)]($style)\) '
style = "bright-black"

[cmd_duration]
format = "[$duration]($style) "
style = "yellow"

[python]
format = "[$virtualenv]($style) "
style = "bright-black"
EOF
print_success "Starship configurado"

# --- 19) VERIFICAR CONTROLADORES NVIDIA ---
print_message "Verificando controladores NVIDIA..."
if ! lsmod | grep -q nvidia; then
    print_warning "Los módulos NVIDIA no están cargados. Intenta reiniciar después de la instalación."
    
    print_message "Verificando instalación de drivers NVIDIA..."
    if ! pacman -Q nvidia &>/dev/null; then
        print_error "Los controladores NVIDIA no están instalados."
        print_error "Después de reiniciar, ejecuta: sudo pacman -S nvidia nvidia-utils nvidia-dkms lib32-nvidia-utils"
    fi
else
    # Verificar la versión de los controladores NVIDIA
    NVIDIA_VERSION=$(pacman -Q nvidia 2>/dev/null | awk '{print $2}' | cut -d- -f1)
    print_message "Controlador NVIDIA versión: $NVIDIA_VERSION"
    print_success "Controladores NVIDIA verificados"
fi

# --- 20) MENSAJE FINAL ---
print_message "La post-instalación se ha completado exitosamente."
print_message ""
print_message "Información de sistema:"
print_message "- CPU: AMD Ryzen 9 5900HX"
print_message "- GPU: NVIDIA RTX 3080"
print_message "- WM: Hyprland (Wayland)"
print_message "- Terminal: Kitty con Bash"
print_message "- Status Bar/Widgets: Aylur's GTK Shell (creada desde cero)"
print_message ""
print_message "Atajos de teclado principales:"
print_message "• Super + Return: Abrir kitty"
print_message "• Super + Q: Cerrar ventana activa"
print_message "• Super + F: Ventana en pantalla completa"
print_message "• Super + Space: Lanzador de aplicaciones"
print_message "• Super + Tab: Vista general/overview"
print_message "• Super + /: Mostrar cheatsheet con todos los atajos"
print_message "• Super + [1-0]: Cambiar a espacio de trabajo"
print_message "• PrintScreen: Captura de pantalla completa"
print_message ""
print_message "Para AGS (Status Bar/Widgets):"
print_message "• Super + Tab: Abre la vista general (overview)"
print_message "• Super + /: Muestra la hoja de atajos (cheatsheet)"
print_message "• Super + D: Abre el lanzador de aplicaciones"
print_message "• Super + X: Abre el menú de apagado"
print_message ""
print_message "Para que los cambios tengan efecto, cierra sesión y vuelve a iniciar, o ejecuta:"
print_message "killall -9 Hyprland && Hyprland"
print_message ""
print_message "¡Disfruta de tu nuevo sistema ArchLinux personalizado!"
