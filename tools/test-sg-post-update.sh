#!/usr/bin/env bash
# shellcheck disable=SC2016  # los $ entre comillas simples son a propósito (scripts falsos)
# Pruebas automáticas de sg-post-update. No tocan el sistema: todo pasa en una carpeta temporal,
# con un /etc falso y versiones falsas de systemctl, pamtester, journalctl, rfkill y quickshell.
#   bash tools/test-sg-post-update.sh
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$AQUI")"
SCRIPT="$AQUI/sg-post-update"
T="$(mktemp -d)" || { echo "no se pudo crear la carpeta temporal" >&2; exit 1; }
[ -d "$T" ] || exit 1
trap 'rm -rf "${T:?}"' EXIT
pasaron=0; fallaron=0

# ---------- dobles de prueba ----------
# (las comillas simples en los heredoc/printf son a propósito: el $ es para los scripts falsos)
mkdir -p "$T/bin"
# systemctl falso que imita los alias de verdad: "enable" falla si display-manager.service ya
# apunta a OTRO gestor (como systemd: "File exists"), "disable X" quita el alias solo si es de X
cat > "$T/bin/systemctl" <<'EOF'
#!/bin/sh
l="$SG_ROOT/etc/systemd/system/display-manager.service"
case "$1" in
  disable) [ "$(basename "$(readlink "$l")")" = "$2" ] && rm -f "$l"; exit 0 ;;
  enable)  if [ -L "$l" ] && [ "$(basename "$(readlink "$l")")" != "$2" ]; then echo "File exists" >&2; exit 1; fi
           ln -sfn "/usr/lib/systemd/system/$2" "$l"; exit 0 ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$T/bin/userctl-activo"
printf '#!/bin/sh\nexit "${FAKE_PAM:-0}"\n' > "$T/bin/pamtester"
printf '#!/bin/sh\n[ -f "$FAKE_JOURNAL" ] && cat "$FAKE_JOURNAL"; exit 0\n' > "$T/bin/journalctl"
printf '#!/bin/sh\ncase "$FAKE_RF" in bloq) echo "0: hci0: Bluetooth"; echo "	Soft blocked: yes";; libre) echo "0: hci0: Bluetooth"; echo "	Soft blocked: no";; esac\n' > "$T/bin/rfkill"
printf '#!/bin/sh\necho "Quickshell 9.9 (falso)"\n# --no-detailed-logs\n' > "$T/bin/qs-bueno"
printf '#!/bin/sh\necho "Quickshell 9.9 (falso, sin la opción)"\n' > "$T/bin/qs-malo"
chmod +x "$T"/bin/*

armar() {   # $1 = sano | roto
    rm -rf "${T:?}/root" "${T:?}/home"; local r="$T/root"   # ${T:?}: si T estuviera vacío, aborta (nunca rm -rf /home)
    mkdir -p "$r/etc/systemd/system" "$r/etc/pam.d" "$r/etc/greetd" "$r/usr/local/share/serpantinum-greeter" \
             "$r/usr/local/bin" "$r/etc/systemd/user/default.target.wants" "$r/var/lib/greetd/.config/systemd/user" \
             "$T/home/.local/state/serpantinum" "$T/home/.config/hypr"
    echo 'SERPANTINUM_VERSION="9.9.9"' > "$T/home/.local/state/serpantinum/version"
    cp "$REPO"/{shell.qml,Greeter.qml,Fondo.qml} "$r/usr/local/share/serpantinum-greeter/"
    cp "$REPO"/greetd/serpantinum-greeter-{launch,layout,user} "$r/usr/local/bin/"
    cp "$REPO/greetd/config.toml" "$r/etc/greetd/"
    for u in pipewire.socket pipewire.service pipewire-pulse.socket pipewire-pulse.service wireplumber.service; do
        ln -s /dev/null "$r/var/lib/greetd/.config/systemd/user/$u"; done
    echo "INFO: Configuration Loaded" > "$T/journal"
    if [ "$1" = sano ]; then
        ln -s /usr/lib/systemd/system/greetd.service "$r/etc/systemd/system/display-manager.service"
        cp "$REPO/pam/serpantinum" "$r/etc/pam.d/serpantinum"
        FAKE_RF=libre
    else
        ln -s /usr/lib/systemd/system/sddm.service "$r/etc/systemd/system/display-manager.service"
        printf 'auth        include      system-auth\naccount     include      system-auth\n' > "$r/etc/pam.d/serpantinum"
        ln -s /usr/lib/systemd/user/pipewire.service "$r/etc/systemd/user/default.target.wants/pipewire.service"
        rm "$r/var/lib/greetd/.config/systemd/user/wireplumber.service"
        FAKE_RF=bloq
    fi
    export FAKE_RF
}
correr() {  # ejecuta sg-post-update con los dobles; deja la salida en $T/out y el código en $cod
    HOME="$T/home" SG_ROOT="$T/root" SG_REPO="$REPO" SG_SUDO="" SG_SYSTEMCTL="$T/bin/systemctl" \
    SG_USERCTL="$T/bin/userctl-activo" SG_JOURNALCTL="$T/bin/journalctl" SG_RFKILL="${RFK:-$T/bin/rfkill}" \
    SG_PAMTESTER="${PAMT:-$T/bin/pamtester}" SG_QUICKSHELL="${QS:-$T/bin/qs-bueno}" FAKE_JOURNAL="$T/journal" \
        bash "$SCRIPT" "$@" < /dev/null > "$T/out" 2>&1
    cod=$?
}
huella() { (cd "$T/root" && find . -printf '%p→%l\n' | sort; find . -type f -exec md5sum {} + | sort) | md5sum; }
dm()  { basename "$(readlink "$T/root/etc/systemd/system/display-manager.service" 2>/dev/null)"; }
caso() { printf '%-62s' "$1"; }
bien() { echo "✅"; pasaron=$((pasaron + 1)); }
mal()  { echo "❌  $*"; sed 's/^/      | /' "$T/out" | tail -15; fallaron=$((fallaron + 1)); }
esperar() {  # esperar CÓDIGO "texto que debe aparecer" ["texto que NO debe aparecer"]
    [ "$cod" = "$1" ] || { mal "código $cod, se esperaba $1"; return; }
    grep -q -- "$2" "$T/out" || { mal "falta: $2"; return; }
    if [ -n "${3:-}" ] && grep -q -- "$3" "$T/out"; then mal "no debía aparecer: $3"; return; fi
    bien
}

echo "== Revisión (sin --arreglar)"
caso "1. sistema sano → código 0, 'Todo en orden'";      armar sano; correr; esperar 0 "Todo en orden"
caso "2. sistema roto → avisos y NO cambia nada";          armar roto; h=$(huella); correr
    if [ "$(huella)" != "$h" ]; then mal "el sistema falso cambió"; else esperar 1 "sg-post-update --arreglar" "❌"; fi
caso "3. opción mal escrita → código 64 y no hace nada";   armar roto; h=$(huella); correr --arreglr
    if [ "$(huella)" != "$h" ]; then mal "cambió algo"; else esperar 64 "opción desconocida"; fi
caso "4. journal ilegible/vacío → aviso, NO un ✅ falso";   armar sano; : > "$T/journal"; correr; esperar 1 "no se pudo comprobar" "ninguna contraseña"
caso "5. respuesta SIN censurar en el journal → ❌ (código 2)"; armar sano; echo '{"response":"x","type":"post_auth_message_response"}' >> "$T/journal"; correr; esperar 2 "SIN censurar"
caso "5b. respuesta censurada (<CENSORED>) → no es filtración";  armar sano; echo 'Sending greetd request: {"response":"<CENSORED>","type":"post_auth_message_response"}' >> "$T/journal"; correr; esperar 0 "ninguna contraseña sin censurar" "SIN censurar"
caso "6. Quickshell sin --no-detailed-logs → aviso";        armar sano; QS="$T/bin/qs-malo" correr; esperar 1 "no tiene --no-detailed-logs"
caso "7. sin rfkill → lo dice, sin inventar un ✅";        armar sano; RFK=/no/existe correr; esperar 0 "rfkill no está instalado" "no está bloqueado"
caso "8. Bluetooth bloqueado → aviso";                     armar sano; FAKE_RF=bloq; correr; esperar 1 "bloqueado por rfkill"
caso "9. la salida sin terminal no trae códigos de color";  armar sano; correr
    if grep -q $'\e\[' "$T/out"; then mal "tiene códigos de escape"; else bien; fi

echo "== Arreglar"
caso "10. SDDM → vuelve a greetd y restaura el PAM";       armar roto; correr --arreglar
    if [ "$(dm)" = greetd.service ] && cmp -s "$REPO/pam/serpantinum" "$T/root/etc/pam.d/serpantinum" \
       && compgen -G "$T/root/etc/pam.d/serpantinum.instalador-*" > /dev/null; then esperar 1 "restaurado y probado" "❌"; else mal "estado: dm=$(dm)"; fi
caso "11. GDM (otro gestor) → también vuelve a greetd";    armar roto; ln -sfn /usr/lib/systemd/system/gdm.service "$T/root/etc/systemd/system/display-manager.service"; correr --arreglar
    if [ "$(dm)" = greetd.service ]; then esperar 1 "arreglado"; else mal "dm=$(dm)"; fi
caso "12. contraseña mala → devuelve el PAM anterior";      armar roto; antes=$(md5sum < "$T/root/etc/pam.d/serpantinum"); FAKE_PAM=1 correr --arreglar
    if [ "$(md5sum < "$T/root/etc/pam.d/serpantinum")" = "$antes" ]; then esperar 2 "se devolvió la versión anterior"; else mal "el PAM quedó cambiado"; fi
caso "13. sin PAM + contraseña mala → no deja un PAM sin probar"; armar roto; rm "$T/root/etc/pam.d/serpantinum"; FAKE_PAM=1 correr --arreglar
    if [ ! -e "$T/root/etc/pam.d/serpantinum" ]; then esperar 2 "se quitó el archivo"; else mal "quedó un PAM sin probar"; fi
caso "14. sin PAM + contraseña buena → lo crea";            armar roto; rm "$T/root/etc/pam.d/serpantinum"; correr --arreglar
    if cmp -s "$REPO/pam/serpantinum" "$T/root/etc/pam.d/serpantinum"; then esperar 1 "restaurado y probado"; else mal "no se creó"; fi
caso "15. sin pamtester → no cambia el PAM";               armar roto; antes=$(md5sum < "$T/root/etc/pam.d/serpantinum"); PAMT=/no/existe correr --arreglar
    if [ "$(md5sum < "$T/root/etc/pam.d/serpantinum")" = "$antes" ]; then esperar 2 "falta pamtester"; else mal "cambió el PAM sin poder probarlo"; fi
caso "16. --arreglar dos veces → la segunda no cambia nada"; armar roto; correr --arreglar; h=$(huella); correr --arreglar
    if [ "$(huella)" = "$h" ]; then esperar 1 "es la versión de referencia" "restaurado"; else mal "la segunda vez cambió algo"; fi
caso "17. sistema sano + --arreglar → no toca nada";        armar sano; h=$(huella); correr --arreglar
    if [ "$(huella)" = "$h" ]; then esperar 0 "Todo en orden"; else mal "cambió algo"; fi

echo; echo "Resultado: $pasaron pasaron, $fallaron fallaron"
[ "$fallaron" -eq 0 ]
