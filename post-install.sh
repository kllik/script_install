#!/bin/bash

# === SCRIPT DE POST-INSTALACIÓN PARA CONFIGURAR HYPRLAND CON AYLUR'S GTK SHELL ===
# Configuración basada en: https://github.com/end-4/dots-hyprland
# Optimizado para: NVIDIA RTX 3080 + AMD Ryzen 9 5900HX
# Adaptado para: Kitty terminal y Bash shell
# Versión: 2.1 (Marzo 2025)

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
    "hyprland" "kitty" "waybar" "grim" "slurp" 
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

# Verificar AGS
if ! command -v ags &>/dev/null; then
    print_message "AGS no está instalado, instalando Aylur's GTK Shell..."
    # Verificamos si existe el paquete AUR primero
    if yay -Ss ^ags$ | grep -q "aur/ags"; then
        print_message "Instalando AGS desde AUR..."
        yay -S --noconfirm ags
    else
        print_message "Compilando AGS desde la fuente..."
        cd /tmp
        rm -rf ags
        git clone https://github.com/Aylur/ags.git
        cd ags
        npm install
        meson setup build
        meson configure -Dbuildtype=release build
        ninja -C build
        sudo ninja -C build install
    fi
else
    print_success "AGS ya está instalado"
fi

print_success "Paquetes adicionales instalados"

# --- 4) CREAR DIRECTORIO CONFIG Y CLONAR TEMPORALMENTE PARA REFERENCIAS ---
print_message "Clonando repositorio de referencia temporalmente..."
cd /tmp
if [ -d "end4-dots" ]; then
    rm -rf end4-dots
fi
git clone https://github.com/end-4/dots-hyprland.git end4-dots
if [ $? -ne 0 ]; then
    print_error "Error al clonar el repositorio de referencia. Verificando conectividad a internet..."
    if ping -c 1 github.com &>/dev/null; then
        print_error "La conexión a internet funciona, pero no se pudo clonar el repositorio."
        print_error "Esto puede deberse a un cambio en la URL o a que el repositorio ya no existe."
        read -p "¿Deseas continuar con la configuración manual? [s/N]: " continue_manual
        if [[ ! "$continue_manual" =~ ^([sS][iI]|[sS])$ ]]; then
            print_message "Instalación cancelada"
            exit 1
        fi
    else
        print_error "No hay conexión a internet. Por favor, verifica tu conexión y vuelve a intentarlo."
        exit 1
    fi
else
    print_success "Repositorio clonado para referencia"
fi

# --- 5) CREAR DIRECTORIOS DE CONFIGURACIÓN ---
print_message "Creando directorios de configuración..."
mkdir -p ~/.config/{hypr,ags,kitty,fuzzel,fastfetch,swaylock,wlogout,waybar,mako}
print_success "Directorios creados"

# --- 6) CONFIGURAR KITTY TERMINAL ---
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

# --- 7) CONFIGURAR HYPRLAND ---
print_message "Configurando Hyprland..."

if [ -d "/tmp/end4-dots/.config/hypr" ]; then
    # Copiar archivo principal de Hyprland
    cp -r /tmp/end4-dots/.config/hypr/* ~/.config/hypr/
    
    # Modificar configuración de Hyprland para usar Kitty en vez de Foot
    if [ -f ~/.config/hypr/hyprland.conf ]; then
        sed -i 's/foot/kitty/g' ~/.config/hypr/hyprland.conf
        sed -i 's/fish/bash/g' ~/.config/hypr/hyprland.conf
    else
        print_error "No se encontró el archivo hyprland.conf. Creando uno básico..."
        # Si no existe, crear una configuración básica
        cat > ~/.config/hypr/hyprland.conf << 'EOF'
# Configuración Hyprland - Optimizada para NVIDIA RTX 3080
monitor=,preferred,auto,1

# Autostart
exec-once = waybar
exec-once = mako
exec-once = ags

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

# Reglas de ventana
windowrulev2 = nomaximizerequest, class:.*
windowrulev2 = float, class:^(pavucontrol)$
windowrulev2 = float, class:^(org.kde.polkit-kde-authentication-agent-1)$
windowrulev2 = float, class:^(org.gnome.Calculator)$
windowrulev2 = float, class:^(org.gnome.Calendar)$
windowrulev2 = float, class:^(thunar)$,title:^(File Operation)$
windowrulev2 = float, class:^(firefox)$,title:^(Library)$
windowrulev2 = float, class:^(nwg-look)$
windowrulev2 = float, class:^(com.github.Aylur.ags)$

# Atajos de teclado
$mainMod = SUPER

# Aplicaciones
bind = $mainMod, return, exec, kitty
bind = $mainMod, E, exec, thunar
bind = $mainMod, B, exec, firefox
bind = $mainMod, R, exec, fuzzel
bind = $mainMod, S, exec, rofi -show window
bind = $mainMod, X, exec, wlogout

# Control de ventanas
bind = $mainMod, Q, killactive
bind = $mainMod SHIFT, Q, exit
bind = $mainMod, V, togglefloating
bind = $mainMod, P, pseudo
bind = $mainMod, J, togglesplit
bind = $mainMod, F, fullscreen

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

# Navegación de espacios de trabajo
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Mover/redimensionar ventanas con ratón
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Control de medios
bind = , XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
bind = , XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
bind = , XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
bind = , XF86AudioPlay, exec, playerctl play-pause
bind = , XF86AudioNext, exec, playerctl next
bind = , XF86AudioPrev, exec, playerctl previous

# Brillo
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

# Capturas de pantalla
bind = $mainMod, PRINT, exec, grim -g "$(slurp)" - | wl-copy
bind = , PRINT, exec, grim ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png
bind = SHIFT, PRINT, exec, grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png
EOF
    fi
else
    print_warning "No se encontró la configuración de Hyprland en el repositorio de referencia. Creando configuración básica..."
    # Crear configuración básica de Hyprland
    cat > ~/.config/hypr/hyprland.conf << 'EOF'
# Configuración Hyprland - Optimizada para NVIDIA RTX 3080
monitor=,preferred,auto,1

# Autostart
exec-once = waybar
exec-once = mako
exec-once = ags
exec-once = swww init && swww img ~/.config/hypr/wallpapers/wallpaper.jpg --transition-fps 60

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

# Reglas de ventana
windowrulev2 = nomaximizerequest, class:.*
windowrulev2 = float, class:^(pavucontrol)$
windowrulev2 = float, class:^(org.kde.polkit-kde-authentication-agent-1)$
windowrulev2 = float, class:^(org.gnome.Calculator)$
windowrulev2 = float, class:^(org.gnome.Calendar)$
windowrulev2 = float, class:^(thunar)$,title:^(File Operation)$
windowrulev2 = float, class:^(firefox)$,title:^(Library)$
windowrulev2 = float, class:^(nwg-look)$
windowrulev2 = float, class:^(com.github.Aylur.ags)$

# Atajos de teclado
$mainMod = SUPER

# Aplicaciones
bind = $mainMod, return, exec, kitty
bind = $mainMod, E, exec, thunar
bind = $mainMod, B, exec, firefox
bind = $mainMod, R, exec, fuzzel
bind = $mainMod, S, exec, rofi -show window
bind = $mainMod, X, exec, wlogout

# Control de ventanas
bind = $mainMod, Q, killactive
bind = $mainMod SHIFT, Q, exit
bind = $mainMod, V, togglefloating
bind = $mainMod, P, pseudo
bind = $mainMod, J, togglesplit
bind = $mainMod, F, fullscreen

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

# Navegación de espacios de trabajo
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Mover/redimensionar ventanas con ratón
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Control de medios
bind = , XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
bind = , XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
bind = , XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
bind = , XF86AudioPlay, exec, playerctl play-pause
bind = , XF86AudioNext, exec, playerctl next
bind = , XF86AudioPrev, exec, playerctl previous

# Brillo
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

# Capturas de pantalla
bind = $mainMod, PRINT, exec, grim -g "$(slurp)" - | wl-copy
bind = , PRINT, exec, grim ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png
bind = SHIFT, PRINT, exec, grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png
EOF
fi

# Añadir lanzamiento de Waybar y AGS si no existe
if ! grep -q "exec-once = waybar" ~/.config/hypr/hyprland.conf; then
    print_message "Añadiendo inicio automático de Waybar..."
    sed -i '/^exec-once = /a exec-once = waybar' ~/.config/hypr/hyprland.conf
fi

if ! grep -q "exec-once = ags" ~/.config/hypr/hyprland.conf; then
    print_message "Añadiendo inicio automático de AGS..."
    sed -i '/^exec-once = /a exec-once = ags' ~/.config/hypr/hyprland.conf
fi

# Asegurar configuración NVIDIA en el archivo hyprland.conf
print_message "Configurando Hyprland específicamente para NVIDIA RTX 3080..."
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

# Asegurarse de que el archivo nvidia.conf se incluya en hyprland.conf
if ! grep -q "source = ./nvidia.conf" ~/.config/hypr/hyprland.conf; then
    echo "source = ./nvidia.conf" >> ~/.config/hypr/hyprland.conf
fi

# Descargar o copiar un wallpaper no anime
print_message "Configurando wallpaper..."
mkdir -p ~/.config/hypr/wallpapers
curl -s -o ~/.config/hypr/wallpapers/wallpaper.jpg "https://w.wallhaven.cc/full/85/wallhaven-85oj9o.jpg"

# Configurar swww para iniciar con el wallpaper
if ! grep -q "swww init" ~/.config/hypr/hyprland.conf; then
    print_message "Añadiendo configuración de wallpaper con swww..."
    sed -i '/^exec-once = /a exec-once = swww init && swww img ~/.config/hypr/wallpapers/wallpaper.jpg --transition-fps 60' ~/.config/hypr/hyprland.conf
fi

print_success "Hyprland configurado"

# --- 8) CONFIGURAR AYLUR'S GTK SHELL (AGS) ---
print_message "Configurando Aylur's GTK Shell (AGS)..."

# Verificar si ags está instalado
if ! command -v ags &>/dev/null; then
    print_error "AGS no está instalado. Instalándolo..."
    cd /tmp
    git clone https://github.com/Aylur/ags.git
    cd ags
    meson setup build
    meson configure -Dbuildtype=release build
    ninja -C build
    sudo ninja -C build install
    cd ~
fi

# Crear estructura de directorios para AGS
mkdir -p ~/.config/ags/{widgets,styles,services,modules}

# Verificar si podemos copiar de los dots originales
if [ -d "/tmp/end4-dots/.config/ags" ]; then
    # Copiar la configuración de AGS
    cp -r /tmp/end4-dots/.config/ags/* ~/.config/ags/
    
    # Modificar user_options.js para quitar anime y ajustar terminal
    if [ -f ~/.config/ags/modules/.configuration/user_options.js ]; then
        print_message "Modificando opciones de usuario de AGS para quitar contenido anime..."
        # Quitar módulos de anime (waifu y booru)
        sed -i 's/\(apis: { order: \[\)"gemini", "gpt", "waifu", "booru"/\1"gemini", "gpt"/g' ~/.config/ags/modules/.configuration/user_options.js
        
        # Cambiar terminal a kitty y shell a bash
        sed -i 's/foot/kitty/g' ~/.config/ags/modules/.configuration/user_options.js
        sed -i 's/fish/bash/g' ~/.config/ags/modules/.configuration/user_options.js
    fi
    
    # Buscar y eliminar archivos o carpetas específicas relacionadas con anime
    print_message "Eliminando cualquier contenido anime residual..."
    find ~/.config/ags -name "*waifu*" -type d -exec rm -rf {} \; 2>/dev/null || true
    find ~/.config/ags -name "*booru*" -type d -exec rm -rf {} \; 2>/dev/null || true
    find ~/.config/ags -name "*anime*" -type d -exec rm -rf {} \; 2>/dev/null || true
else
    print_warning "No se encontró la configuración de AGS en el repositorio de referencia."
    print_message "Creando configuración básica de AGS..."
    
    # Crear archivos básicos de AGS
    cat > ~/.config/ags/config.js << 'EOF'
import App from 'resource:///com/github/Aylur/ags/app.js';
import Widget from 'resource:///com/github/Aylur/ags/widget.js';
import { exec, execAsync } from 'resource:///com/github/Aylur/ags/utils.js';

// Simple bar
const SimpleBar = () => Widget.Window({
    name: 'bar',
    anchor: ['top', 'left', 'right'],
    exclusivity: 'exclusive',
    child: Widget.CenterBox({
        start_widget: Widget.Box({
            children: [
                Widget.Button({
                    child: Widget.Label('🚀'),
                    on_clicked: () => execAsync('fuzzel'),
                }),
                Widget.Workspaces(),
            ],
        }),
        center_widget: Widget.Box({
            children: [
                Widget.Clock({
                    format: '%H:%M - %A %e %B %Y',
                }),
            ],
        }),
        end_widget: Widget.Box({
            children: [
                Widget.Network(),
                Widget.Volume(),
                Widget.Battery(),
                Widget.SystemTray(),
            ],
        }),
    }),
});

// Exporting the config
export default {
    windows: [
        SimpleBar(),
    ],
};
EOF
    
    print_message "Configuración básica de AGS creada. Para una configuración más completa, consulta la documentación oficial."
fi

print_success "Aylur's GTK Shell configurado"

# --- 9) CONFIGURAR WAYBAR ---
print_message "Configurando Waybar..."
if ! command -v waybar &>/dev/null; then
    print_error "Waybar no está instalada. Intentando instalarla..."
    sudo pacman -S --noconfirm waybar
    if [ $? -ne 0 ]; then
        print_error "No se pudo instalar waybar. Intentando con waybar-hyprland desde AUR..."
        yay -S --noconfirm waybar-hyprland
    fi
fi

mkdir -p ~/.config/waybar
cat > ~/.config/waybar/config << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    "margin-top": 0,
    "margin-bottom": 0,
    "margin-left": 0,
    "margin-right": 0,
    "modules-left": ["custom/launcher", "hyprland/workspaces", "hyprland/window"],
    "modules-center": ["mpris"],
    "modules-right": ["network", "pulseaudio", "cpu", "memory", "temperature", "battery", "tray", "clock"],
    
    "custom/launcher": {
        "format": "󰣇",
        "on-click": "fuzzel",
        "tooltip": false
    },
    
    "hyprland/workspaces": {
        "format": "{name}",
        "format-active": "<span foreground='#cba6f7'>{name}</span>",
        "on-click": "activate"
    },
    
    "hyprland/window": {
        "max-length": 50,
        "separate-outputs": true
    },
    
    "mpris": {
        "format": "{player_icon} <i>{status}</i> {dynamic}",
        "format-paused": "{player_icon} <i>{status}</i> {dynamic}",
        "player-icons": {
            "default": "▶",
            "mpd": "🎵",
            "firefox": "",
            "chromium": "",
            "brave": "",
            "vlc": "󰕼"
        },
        "status-icons": {
            "paused": "⏸",
            "playing": "▶",
            "stopped": "⏹"
        },
        "dynamic-order": ["artist", "album", "title"]
    },
    
    "tray": {
        "icon-size": 18,
        "spacing": 8
    },
    
    "clock": {
        "format": "{:%H:%M}",
        "format-alt": "{:%a, %b %d %Y}",
        "tooltip-format": "<tt>{calendar}</tt>",
        "calendar": {
            "mode": "month",
            "mode-mon-col": 3,
            "weeks-pos": "right",
            "on-scroll": 1,
            "format": {
                "months": "<span color='#cba6f7'><b>{}</b></span>",
                "days": "<span color='#cdd6f4'>{}</span>",
                "weeks": "<span color='#89b4fa'><b>W{}</b></span>",
                "weekdays": "<span color='#f5c2e7'><b>{}</b></span>",
                "today": "<span color='#f38ba8'><b>{}</b></span>"
            }
        },
        "actions": {
            "on-click": "mode",
            "on-click-right": "mode"
        }
    },
    
    "cpu": {
        "format": "{usage}% ",
        "tooltip": true,
        "interval": 2
    },
    
    "memory": {
        "format": "{}% ",
        "interval": 2
    },
    
    "temperature": {
        "thermal-zone": 2,
        "critical-threshold": 80,
        "format-critical": "{temperatureC}°C ",
        "format": "{temperatureC}°C "
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
        "format": "{volume}% {icon} {format_source}",
        "format-bluetooth": "{volume}% {icon} {format_source}",
        "format-bluetooth-muted": " {icon} {format_source}",
        "format-muted": " {format_source}",
        "format-source": "{volume}% ",
        "format-source-muted": "",
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
    }
}
EOF

cat > ~/.config/waybar/style.css << 'EOF'
* {
    /* `otf-font-awesome` is required to be installed for icons */
    font-family: "JetBrainsMono Nerd Font", "Rubik", sans-serif;
    font-size: 14px;
}

window#waybar {
    background-color: rgba(30, 30, 46, 0.95);
    color: #cdd6f4;
    transition-property: background-color;
    transition-duration: .5s;
    border-radius: 0px 0px 8px 8px;
}

window#waybar.hidden {
    opacity: 0.2;
}

#workspaces button {
    padding: 0 6px;
    background-color: transparent;
    color: #cdd6f4;
    box-shadow: inset 0 -3px transparent;
    border: none;
    border-radius: 0;
}

#workspaces button:hover {
    background: rgba(180, 190, 254, 0.2);
    box-shadow: inset 0 -3px #cba6f7;
}

#workspaces button.active {
    box-shadow: inset 0 -3px #cba6f7;
}

#workspaces button.urgent {
    background-color: #f38ba8;
    color: #1e1e2e;
}

#mode {
    background-color: #89b4fa;
    color: #1e1e2e;
    border-radius: 8px;
    padding: 0 10px;
    margin: 5px 5px;
}

#clock,
#battery,
#cpu,
#memory,
#disk,
#temperature,
#backlight,
#network,
#pulseaudio,
#custom-media,
#tray,
#mode,
#idle_inhibitor,
#scratchpad,
#mpris,
#custom-launcher {
    padding: 0 10px;
    margin: 5px 0;
    color: #cdd6f4;
}

#window {
    margin: 0 5px;
}

.modules-left {
    margin-left: 10px;
}

.modules-right {
    margin-right: 10px;
}

#battery.charging, #battery.plugged {
    color: #a6e3a1;
}

#battery.critical:not(.charging) {
    background-color: #f38ba8;
    color: #1e1e2e;
    border-radius: 8px;
}

@keyframes blink {
    to {
        background-color: #cdd6f4;
        color: #1e1e2e;
    }
}

#battery.warning:not(.charging) {
    background-color: #fab387;
    color: #1e1e2e;
    border-radius: 8px;
}

#network.disconnected {
    background-color: #f38ba8;
    color: #1e1e2e;
    border-radius: 8px;
}

#custom-launcher {
    color: #cba6f7;
    font-size: 20px;
    margin-right: 10px;
}

#temperature.critical {
    background-color: #f38ba8;
    color: #1e1e2e;
    border-radius: 8px;
}

#tray > .passive {
    -gtk-icon-effect: dim;
}

#tray > .needs-attention {
    -gtk-icon-effect: highlight;
    background-color: #fab387;
    border-radius: 8px;
}

#mpris {
    background-color: rgba(49, 50, 68, 0.5);
    border-radius: 8px;
    margin: 5px;
    padding: 0 10px;
}
EOF
print_success "Waybar configurado"

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

# --- 20) CREAR DIRECTORIOS NECESARIOS ---
print_message "Creando directorios adicionales necesarios..."
mkdir -p ~/Pictures/Screenshots
print_success "Directorios adicionales creados"

# --- 21) LIMPIAR ARCHIVOS TEMPORALES ---
print_message "Limpiando archivos temporales..."
rm -rf /tmp/end4-dots
print_success "Archivos temporales eliminados"

# --- 22) MENSAJE FINAL ---
print_message "La post-instalación se ha completado exitosamente."
print_message ""
print_message "Información de sistema:"
print_message "- CPU: AMD Ryzen 9 5900HX"
print_message "- GPU: NVIDIA RTX 3080"
print_message "- WM: Hyprland (Wayland)"
print_message "- Terminal: Kitty con Bash"
print_message "- Shell Prompt: Starship"
print_message ""
print_message "Atajos de teclado importantes:"
print_message "• Super: Abrir vista general/launcher de AGS"
print_message "• Super + Enter: Abrir kitty (terminal)"
print_message "• Super + /: Mostrar ayuda con todos los atajos"
print_message "• Super + Q: Cerrar ventana activa"
print_message "• Super + SHIFT + Q: Salir de Hyprland"
print_message "• Super + F: Ventana en pantalla completa"
print_message "• Super + [1-0]: Cambiar a espacio de trabajo"
print_message "• PrintScreen: Captura de pantalla completa"
print_message ""
print_message "Nota: Si encuentras problemas de compatibilidad con NVIDIA,"
print_message "consulta la wiki de Arch o Hyprland para soluciones específicas."
print_message ""
print_message "Para que los cambios tengan efecto, cierra sesión y vuelve a iniciar, o ejecuta:"
print_message "killall -9 Hyprland && Hyprland"
print_message ""
print_message "¡Disfruta de tu nuevo sistema ArchLinux personalizado optimizado para NVIDIA!"
