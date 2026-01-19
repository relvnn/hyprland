#!/bin/bash
set -e

IMAGE="$1"

[ -z "$IMAGE" ] && echo "Uso: $0 /caminho/para/imagem" && exit 1
[ ! -f "$IMAGE" ] && echo "Arquivo não encontrado: $IMAGE" && exit 1

# ===============================
# Pacotes necessários (Arch)
# ===============================
REQUIRED_PKGS=(python-pywal jq waybar hyprpaper sddm)

for pkg in "${REQUIRED_PKGS[@]}"; do
    pacman -Qi "$pkg" &>/dev/null || sudo pacman -S --noconfirm "$pkg"
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
HYPR_WALLPAPER="$HOME_CONFIG/hypr/current_wallpaper"

ROFI_DIR="$HOME_CONFIG/rofi"
ROFI_COLORS="$ROFI_DIR/colors.rasi"

SDDM_THEME_DIR="$(find /usr/share/sddm/themes -maxdepth 1 -type d | grep -i sugar | head -n1)"
SDDM_BG="$SDDM_THEME_DIR/Background.jpg"
SDDM_QML="$SDDM_THEME_DIR/Colors.qml"
SDDM_MAIN="$SDDM_THEME_DIR/Main.qml"

# ===============================
# Pywal
# ===============================
wal -i "$IMAGE"

mkdir -p "$(dirname "$HYPR_WALLPAPER")"
cp "$IMAGE" "$HYPR_WALLPAPER"
chmod 644 "$HYPR_WALLPAPER"

# ===============================
# Rofi - sobrescrever colors.rasi
# ===============================
mkdir -p "$ROFI_DIR"

declare -A COLOR_MAP=(
    [primary]=color1
    [primary-fixed]=color7
    [primary-fixed-dim]=color1
    [on-primary]=color0
    [on-primary-fixed]=color0
    [on-primary-fixed-variant]=color2
    [primary-container]=color2
    [on-primary-container]=color7
    [secondary]=color3
    [secondary-fixed]=color4
    [secondary-fixed-dim]=color3
    [on-secondary]=color0
    [on-secondary-fixed]=color0
    [on-secondary-fixed-variant]=color2
    [secondary-container]=color2
    [on-secondary-container]=color4
    [tertiary]=color5
    [tertiary-fixed]=color6
    [tertiary-fixed-dim]=color5
    [on-tertiary]=color0
    [on-tertiary-fixed]=color0
    [on-tertiary-fixed-variant]=color2
    [tertiary-container]=color2
    [on-tertiary-container]=color6
    [error]=color9
    [on-error]=color0
    [error-container]=color8
    [on-error-container]=color10
    [surface]=color0
    [on-surface]=color7
    [on-surface-variant]=color2
    [outline]=color2
    [outline-variant]=color0
    [shadow]=color0
    [scrim]=color0
    [inverse-surface]=color7
    [inverse-on-surface]=color0
    [inverse-primary]=color1
    [surface-dim]=color0
    [surface-bright]=color2
    [surface-container-lowest]=color0
    [surface-container-low]=color0
    [surface-container]=color0
    [surface-container-high]=color2
    [surface-container-highest]=color2
)

{
    echo "* {"
    for key in "${!COLOR_MAP[@]}"; do
        echo "    $key: $(jq -r ".colors.${COLOR_MAP[$key]}" "$WAL_JSON");"
    done
    echo "}"
} > "$ROFI_COLORS"

chmod 644 "$ROFI_COLORS"

# ===============================
# Hyprland colors
# ===============================
> "$HYPR_COLORS"
jq -r '.colors | to_entries[] | "\(.key) \(.value)"' "$WAL_JSON" |
while read -r name hex; do
    echo "\$$name = rgba(${hex#\#}ff)" >> "$HYPR_COLORS"
done

# ===============================
# QML Colors (SDDM)
# ===============================
cat > "$WAL_QML" <<EOF
import QtQuick 2.15
QtObject {
EOF

jq -r '.special + .colors | to_entries[] | "    property color \(.key): \"\(.value)\""' \
"$WAL_JSON" >> "$WAL_QML"

echo "}" >> "$WAL_QML"
chmod 644 "$WAL_QML"

# ===============================
# Waybar
# ===============================
if [ -n "$WAYBAR_CSS" ]; then
    HEX=$(jq -r '.colors.color1' "$WAL_JSON")
    R=$((16#${HEX:1:2}))
    G=$((16#${HEX:3:2}))
    B=$((16#${HEX:5:2}))
    sed -i -E "s|background-color:.*;|background-color: rgba($R,$G,$B,0.2);|" "$WAYBAR_CSS"
fi

# ===============================
# SDDM - CORES CLARAS (como no script antigo)
# ===============================
sudo cp "$IMAGE" "$SDDM_BG"
sudo cp "$WAL_QML" "$SDDM_QML"
sudo chown root:root "$SDDM_BG" "$SDDM_QML"
sudo chmod 644 "$SDDM_BG" "$SDDM_QML"

COLOR_TEXT=$(jq -r '.special.foreground' "$WAL_JSON")
COLOR_HIGHLIGHT=$(jq -r '.colors.color7' "$WAL_JSON")

sudo sed -i \
    -e "s|palette.text:.*|palette.text: \"$COLOR_TEXT\"|" \
    -e "s|palette.buttonText:.*|palette.buttonText: \"$COLOR_TEXT\"|" \
    -e "s|palette.highlight:.*|palette.highlight: \"$COLOR_HIGHLIGHT\"|" \
    "$SDDM_MAIN"

sudo sed -i '
/Rectangle {/{
:loop
n
/}/b
s/color:.*/color: "#000000"/
s/opacity:.*/opacity: 0.5/
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
