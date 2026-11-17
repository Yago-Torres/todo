#!/bin/bash
# Instala (o actualiza) todo para el escritorio en Omarchy. Se puede repetir: deja lo mismo.
#   curl -fsSL https://raw.githubusercontent.com/Yago-Torres/todo/main/escritorio/omarchy/instalar.sh | bash
# Qué toca: ~/.local/bin/todo-escritorio, su icono y su .desktop (sale en el lanzador) y ~/.config/hypr/todo.conf
# (arranque, Super+Alt+N para apuntar y la caja de apuntar flotando), que se engancha a hyprland.conf con un source.
# Waybar no lo toca: al final dice qué pegar.
set -euo pipefail
REPO=https://github.com/Yago-Torres/todo
BIN="$HOME/.local/bin/todo-escritorio"

echo "· Dependencias (webkit2gtk para la ventana, appindicator para la bandeja)"
sudo pacman -S --needed --noconfirm webkit2gtk-4.1 libayatana-appindicator

echo "· La app, de la release «escritorio»"
mkdir -p "$(dirname "$BIN")"
curl -fL --progress-bar "$REPO/releases/download/escritorio/todo-escritorio-linux-x86_64" -o "$BIN.nuevo"
chmod +x "$BIN.nuevo" && mv "$BIN.nuevo" "$BIN"

ICONO="$HOME/.local/share/icons/hicolor/512x512/apps/todo-escritorio.png"
mkdir -p "$(dirname "$ICONO")" "$HOME/.local/share/applications"
curl -fsSL "https://raw.githubusercontent.com/Yago-Torres/todo/main/escritorio/icono.png" -o "$ICONO"
cat > "$HOME/.local/share/applications/todo-escritorio.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=todo
Comment=Hábitos, pendientes, notas rápidas y gastos
Exec=$BIN
Icon=todo-escritorio
Categories=Utility;
Actions=apuntar;notas;

[Desktop Action apuntar]
Name=Apuntar
Exec=$BIN --apuntar

[Desktop Action notas]
Name=Notas rápidas
Exec=$BIN --notas
DESK

echo "· Hyprland"
HYPR="$HOME/.config/hypr"
mkdir -p "$HYPR"
cat > "$HYPR/todo.conf" <<CONF
# todo para el escritorio (lo escribe escritorio/omarchy/instalar.sh; se puede editar)
exec-once = $BIN --oculta
bind = SUPER ALT, N, exec, $BIN --apuntar
windowrule = float, title:^(todo · apuntar)\$
windowrule = center, title:^(todo · apuntar)\$
windowrule = pin, title:^(todo · apuntar)\$
CONF
grep -qxF "source = ~/.config/hypr/todo.conf" "$HYPR/hyprland.conf" 2>/dev/null \
  || printf '\nsource = ~/.config/hypr/todo.conf\n' >> "$HYPR/hyprland.conf"
hyprctl reload >/dev/null 2>&1 || true

pgrep -x todo-escritorio >/dev/null || (setsid "$BIN" >/dev/null 2>&1 &)
cat <<FIN

Hecho. La primera vez la ventana pide las tres claves (las mismas de Tom).
Super+Alt+N abre la caja de apuntar; cerrar la ventana la deja en la bandeja.

Para el módulo de Waybar, en ~/.config/waybar/config.jsonc añade "custom/todo" a "modules-right" y esto:

  "custom/todo": {
    "exec": "$BIN --waybar",
    "return-type": "json",
    "interval": 300,
    "on-click": "$BIN",
    "on-click-right": "$BIN --apuntar"
  }

y reinicia Waybar (omarchy-restart-waybar o pkill -SIGUSR2 waybar).
FIN
