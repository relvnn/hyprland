#!/bin/bash
set -e

IMAGE="$1"

if [ -z "$IMAGE" ]; then
    echo "Uso: $0 /caminho/para/imagem"
    exit 1
fi

if [ ! -f "$IMAGE" ]; then
    echo "Arquivo não encontrado: $IMAGE"
    exit 1
fi

# ===============================
# Pacotes necessários (Arch)
# ===============================
REQUIRED_PKGS=(python-pywal jq waybar hyprpaper sddm)

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S --noconfirm "$pkg"
    fi
done

# ===============================
# Paths
# ===============================
HOME_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
HOME_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

WAL_DIR="$HOME_CACHE/wal"
WAL_JSON="$WAL_DIR/colors.json"
WAL_QML="$WAL_DIR/Colors.qml"

HYPR_COLORS="$WAL_DIR/colors-hyprland.conf"
WAYBAR_CSS="$(find "$HOME_CONFIG/waybar" -name style.css | head -n1)"

HYPRPAPER_CONF="$HOME_CONFIG/hypr/hyprpaper.conf"

SDDM_THEME_DIR="$(find /usr/share/sddm/themes -maxdepth 1 -type d | grep -i sugar | head -n1)"
SDDM_BG="$SDDM_THEME_DIR/Background.jpg"
SDDM_QML="$SDDM_THEME_DIR/Colors.qml"
SDDM_MAIN="$SDDM_THEME_DIR/Main.qml"

# ===============================
# Pywal
# ===============================
wal -i "$IMAGE"

# ===============================
# Hyprland colors
# ===============================
> "$HYPR_COLORS"

jq -r '.colors | to_entries[] | "\(.key) \(.value)"' "$WAL_JSON" |
while read -r name hex; do
    hex=${hex#\#}
    echo "\$$name = rgba(${hex}ff)" >> "$HYPR_COLORS"
done

# ===============================
# QML Colors (SDDM)
# ===============================
cat > "$WAL_QML" <<EOF
import QtQuick 2.15

QtObject {
EOF

jq -r '
  .special + .colors
  | to_entries[]
  | "    property color \(.key): \"\(.value)\""
' "$WAL_JSON" >> "$WAL_QML"

echo "}" >> "$WAL_QML"
chmod 644 "$WAL_QML"

# ===============================
# Waybar background
# ===============================
if [ -n "$WAYBAR_CSS" ]; then
    COLOR1_HEX=$(jq -r '.colors.color1' "$WAL_JSON")
    R=$((16#${COLOR1_HEX:1:2}))
    G=$((16#${COLOR1_HEX:3:2}))
    B=$((16#${COLOR1_HEX:5:2}))
    sed -i -E \
        "s|background-color:.*;|background-color: rgba($R,$G,$B,0.2);|" \
        "$WAYBAR_CSS"
fi

# ===============================
# SDDM - copiar background e cores
# ===============================
sudo cp "$IMAGE" "$SDDM_BG"
sudo cp "$WAL_QML" "$SDDM_QML"
sudo chown root:root "$SDDM_BG" "$SDDM_QML"
sudo chmod 644 "$SDDM_BG" "$SDDM_QML"

# ===============================
# Cores claras garantidas (SDDM)
# ===============================
COLOR_TEXT=$(jq -r '.special.foreground' "$WAL_JSON")
COLOR_HIGHLIGHT=$(jq -r '.colors.color7' "$WAL_JSON")

sudo sed -i \
    -e "s|palette.text:.*|palette.text: \"$COLOR_TEXT\"|" \
    -e "s|palette.buttonText:.*|palette.buttonText: \"$COLOR_TEXT\"|" \
    -e "s|palette.highlight:.*|palette.highlight: \"$COLOR_HIGHLIGHT\"|" \
    "$SDDM_MAIN"

# ===============================
# Retângulo preto com opacidade 0.8
# ===============================
sudo sed -i '
/Rectangle {/{
:loop
n
/}/b
s/color: .*/color: "#000000"/
s/opacity: .*/opacity: 0.5/
b loop
}
' "$SDDM_MAIN"

# ===============================
# Hyprpaper (todos os monitores)
# ===============================
MONITORS=$(hyprctl monitors -j | jq -r '.[].name')

cat > "$HYPRPAPER_CONF" <<EOF
splash = false
EOF

for MON in $MONITORS; do
cat >> "$HYPRPAPER_CONF" <<EOF

wallpaper {
    monitor = $MON
    path = $IMAGE
    fit_mode = cover
}
EOF
done

pkill hyprpaper || true
hyprpaper &

# ===============================
# Restart Waybar
# ===============================
pkill waybar || true
waybar &
