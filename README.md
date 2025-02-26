# Arch Linux con BTRFS, Hyprland y Aylur's GTK Shell

Este repositorio contiene un script para automatizar la instalación de Arch Linux con BTRFS, Hyprland y Aylur's GTK Shell. Configurado especialmente para hardware NVIDIA RTX 3080 y AMD Ryzen 9 5900HX.

## Características

- Instalación automatizada de Arch Linux
- Sistema de archivos BTRFS con subvolúmenes
- Soporte para snapshots con Timeshift
- Entorno gráfico Hyprland (compositor Wayland)
- Barra de estado personalizada con Aylur's GTK Shell
- Optimizado para gráficos NVIDIA y CPU AMD

## Guía de instalación

### 1. Preparación

Arranca desde el medio de instalación de Arch Linux y asegúrate de tener conexión a Internet.

### 2. Crear particiones manualmente

Primero, crea las particiones necesarias:

```bash
cfdisk /dev/nvme0n1
