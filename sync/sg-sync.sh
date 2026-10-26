#!/usr/bin/env bash
# sg-sync: copia al login el fondo del escritorio y SOLO la temperatura del clima.
# Corre como tu usuario (servicio de usuario). El login (usuario greetd) solo lee lo que deja aquí.
#   fondo                 captura del fondo principal (sirve también para fondos de video)
#   fondo-<monitor>       captura del fondo de cada monitor (eDP-1, HDMI-A-1...)
#   clima.json            current_temp_formatted, current_icon y fetched_at (sin coordenadas)
set -euo pipefail

DEST="${SG_DEST:-/var/lib/serpantinum-greeter}"
WP_DIR="$HOME/.cache/serpantinum/wallpaper"
WEATHER="$HOME/.cache/serpantinum/weather/weather.json"
MAX_BYTES=$((40 * 1024 * 1024))

# Una sola copia a la vez (el servicio puede dispararse varias veces seguidas)
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/sg-sync.lock"
flock 9

if [ ! -d "$DEST" ] || [ ! -w "$DEST" ]; then
    echo "sg-sync: $DEST no existe o no se puede escribir" >&2
    exit 1
fi

# Copia atómica: primero a un temporal en el mismo directorio y luego mv (nunca se lee a medias)
copiar() {
    local src=$1 dst=$2 tmp
    [ -f "$src" ] && [ -r "$src" ] || return 0
    [ "$(stat -c %s -- "$src")" -le "$MAX_BYTES" ] || { echo "sg-sync: $src es demasiado grande" >&2; return 0; }
    case "$(file -b --mime-type -- "$src")" in
        image/jpeg|image/png|image/webp) ;;
        *) echo "sg-sync: $src no es una imagen" >&2; return 0 ;;
    esac
    tmp=$(mktemp "$DEST/.tmp.XXXXXX")
    cp -- "$src" "$tmp"
    chmod 644 -- "$tmp"
    mv -f -- "$tmp" "$DEST/$dst"
}

# 1) Fondos
copiar "$WP_DIR/current_wallpaper.png" fondo
for snap in "$WP_DIR"/current_wallpaper_*.png; do
    [ -e "$snap" ] || continue
    mon=${snap##*/current_wallpaper_}
    mon=${mon%.png}
    [[ $mon =~ ^[A-Za-z0-9-]{1,32}$ ]] || continue
    copiar "$snap" "fondo-$mon"
done

# 2) Clima: solo 3 campos; las coordenadas nunca salen de ~/.cache
if [ -r "$WEATHER" ]; then
    tmp=$(mktemp "$DEST/.tmp.XXXXXX")
    if jq -c '{current_temp_formatted, current_icon, fetched_at}' "$WEATHER" > "$tmp"; then
        chmod 644 -- "$tmp"
        mv -f -- "$tmp" "$DEST/clima.json"
    else
        rm -f -- "$tmp"
    fi
fi
