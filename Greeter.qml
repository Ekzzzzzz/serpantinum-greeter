import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import Quickshell.Services.UPower

Item {
    id: g

    required property string userName
    required property string wallpaper      // el fondo de este monitor (fondo-<nombre>)
    property string wallpaperAlt: ""         // el fondo general (fondo), si falta el del monitor
    required property string avatar
    required property string kbLabel
    required property string climaPath
    required property string transition   // "video" (por defecto) o "cortina"
    required property bool demo

    // Paleta Catppuccin Mocha (la misma de Serpantinum) y fuentes del sistema
    readonly property color cText: "#cdd6f4"
    readonly property color cSub: "#a6adc8"
    readonly property color cDim: "#6c7086"
    readonly property color cSurface: "#313244"
    readonly property color cBlue: "#89b4fa"
    readonly property color cRed: "#f38ba8"
    readonly property color cGreen: "#a6e3a1"
    readonly property color cPeach: "#fab387"
    readonly property string mono: "JetBrains Mono"
    readonly property string iconFont: "Iosevka Nerd Font"

    // Sesiones del engranaje. La primera es la de por defecto.
    readonly property var sessions: [
        // systemd-cat: los mensajes de la sesión van al journal y no se ven como texto en la pantalla
        // durante el cambio del login al escritorio (journalctl -t hyprland-session)
        { name: "Hyprland", cmd: ["/usr/bin/systemd-cat", "-t", "hyprland-session", "/usr/bin/start-hyprland"],
          env: ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland"] },
        { name: "GNOME", cmd: ["/usr/bin/systemd-cat", "-t", "gnome-session", "/usr/bin/gnome-session"],
          env: ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=GNOME", "XDG_SESSION_DESKTOP=gnome"] }
    ]
    property int sessionIndex: 0
    readonly property var session: sessions[sessionIndex]

    // Fases: intro → idle (fondo nítido + reloj) → form (candado → contraseña) → launch
    property string phase: "intro"
    readonly property bool revealed: phase === "form"
    property bool busy: false
    property bool failed: false
    property string status: ""
    property string pending: ""     // la contraseña espera a que greetd la pida
    property string openMenu: ""    // "", "session" o "power"

    // Valores que animan las transiciones
    property real bgOpacity: 0
    property real bgBlur: 0
    property real bgBright: 0
    property real circleScale: 1.15
    property real circleOpacity: 0
    property real pulseScale: 0.3
    property real pulseOpacity: 0
    property real lockScale: 0.5
    property real lockOpacity: 0
    property real clockOpacity: 0
    property real clockScale: 0.96
    property real clockShift: 0
    property real formOpacity: 0
    property real formShift: 18
    property real formScale: 0.94
    property real barOpacity: 0

    readonly property bool cortina: transition === "cortina"
    readonly property real clockOut: cortina ? -g.height * 0.32 : -14
    readonly property real formIn: cortina ? g.height * 0.14 : 18

    focus: true

    // ---------- Lógica ----------
    function reveal(firstText) {
        if (g.phase === "intro") { introAnim.complete(); }
        if (g.phase === "idle") {
            g.phase = "form";
            hideAnim.stop();
            revealAnim.restart();
        }
        if (g.phase !== "form") return;
        pw.forceActiveFocus();
        if (firstText) pw.insert(pw.cursorPosition, firstText);
    }

    function hide() {
        if (g.busy || g.phase !== "form") return;
        pw.text = "";
        g.status = "";
        g.failed = false;
        g.openMenu = "";
        g.phase = "idle";
        revealAnim.stop();
        hideAnim.restart();
        g.forceActiveFocus();
    }

    function startLaunch() {
        g.phase = "launch";
        g.openMenu = "";
        revealAnim.stop();
        hideAnim.stop();
        outroAnim.restart();
    }

    function cycleSession() {
        if (g.busy) return;
        g.sessionIndex = (g.sessionIndex + 1) % g.sessions.length;
    }

    function fail(msg) {
        g.pending = "";
        pw.text = "";
        g.failed = true;
        g.status = msg;
        shake.restart();
        cooldown.restart();     // 1 s sin poder escribir: frena los intentos rápidos
    }

    function submit() {
        if (g.busy || g.phase !== "form" || pw.text.length === 0) return;
        if (g.userName === "") { g.fail("No hay usuario configurado (SG_USER)"); return; }
        g.failed = false;
        g.busy = true;
        g.status = "Autenticando…";
        if (g.demo) {
            pw.text = "";
            demoTimer.restart();
            return;
        }
        g.pending = pw.text;
        pw.text = "";
        Greetd.createSession(g.userName);
    }

    function power(action) {
        g.openMenu = "";
        if (g.demo) {
            g.status = "Modo prueba: aquí se ejecutaría «systemctl " + action + "»";
            return;
        }
        if (action === "reboot" || action === "poweroff") Quickshell.execDetached(["systemctl", action]);
    }

    // Lee solo la temperatura y el ícono. Nunca muestra otra cosa del archivo.
    property string climaTemp: ""
    property string climaIcon: ""
    function parseClima(raw) {
        g.climaTemp = "";
        g.climaIcon = "";
        try {
            const d = JSON.parse(raw);
            const t = String(d.current_temp_formatted || "").slice(0, 10);
            const age = Date.now() / 1000 - Number(d.fetched_at || 0);
            if (!/^-?\d{1,2}(\.\d)?°[CF]$/.test(t) || age > 12 * 3600) return;
            g.climaTemp = t;
            g.climaIcon = String(d.current_icon || "").slice(0, 2);
        } catch (e) { }
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_F2) { g.cycleSession(); event.accepted = true; return; }
        if (event.key === Qt.Key_Escape) { g.openMenu = ""; g.hide(); event.accepted = true; return; }
        if (g.phase !== "form") {
            const printable = event.text && event.text.length === 1 && event.text >= " ";
            g.reveal(printable ? event.text : "");
            event.accepted = true;
        }
    }

    Timer {
        id: demoTimer
        interval: 900
        onTriggered: {
            g.status = "";
            g.startLaunch();
        }
    }

    Timer {
        id: demoReset
        interval: 1800
        onTriggered: {
            g.busy = false;
            g.phase = "intro";
            g.clockShift = 0;
            g.clockScale = 0.96;
            g.circleScale = 1.15;
            introAnim.restart();
        }
    }

    Timer {
        id: cooldown
        interval: 1000
        onTriggered: { g.busy = false; pw.forceActiveFocus(); }
    }

    Connections {
        target: Greetd
        enabled: !g.demo

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(g.pending);
                g.pending = "";
            } else if (error) {
                g.status = String(message).slice(0, 80);
            }
        }
        function onAuthFailure(message) { g.fail("Contraseña incorrecta"); }
        function onReadyToLaunch() {
            g.status = "Abriendo " + g.session.name + "…";
            g.startLaunch();
        }
        function onError(error) { g.fail("Error de greetd"); }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    FileView {
        id: climaFile
        path: g.climaPath
        // Sin watchChanges: SELinux (xdm_t) no deja vigilar archivos con inotify (AVC "watch", 22-oct).
        // Leer sí está permitido, así que se relee cada 10 minutos.
        printErrors: false
        onLoaded: g.parseClima(text())
        onLoadFailed: { g.climaTemp = ""; g.climaIcon = ""; }
    }

    Timer {
        interval: 10 * 60 * 1000
        repeat: true
        running: true
        onTriggered: climaFile.reload()
    }

    // ---------- Animaciones (el candado del video, segundos 18 a 19.4, al presionar una tecla) ----------
    Component.onCompleted: introAnim.start()

    // Al encender: el fondo nítido aparece y entra el reloj
    SequentialAnimation {
        id: introAnim
        NumberAnimation { target: g; property: "bgOpacity"; to: 1; duration: 500; easing.type: Easing.OutQuad }
        ParallelAnimation {
            NumberAnimation { target: g; property: "clockOpacity"; to: 1; duration: 400 }
            NumberAnimation { target: g; property: "clockScale"; to: 1; duration: 450; easing.type: Easing.OutCubic }
            NumberAnimation { target: g; property: "barOpacity"; to: 1; duration: 450 }
        }
        ScriptAction { script: if (g.phase === "intro") g.phase = "idle" }
    }

    // Tecla o clic: el reloj sube y se va, el fondo se desenfoca dentro del círculo,
    // el anillo se expande, aparece el candado, crece y se desvanece, y entra el formulario
    ParallelAnimation {
        id: revealAnim
        NumberAnimation { target: g; property: "clockOpacity"; to: 0; duration: g.cortina ? 380 : 220 }
        NumberAnimation { target: g; property: "clockShift"; to: g.clockOut; duration: g.cortina ? 450 : 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: g; property: "bgBlur"; to: 0.95; duration: 450; easing.type: Easing.OutCubic }
        NumberAnimation { target: g; property: "bgBright"; to: -0.02; duration: 450 }
        NumberAnimation { target: g; property: "circleOpacity"; to: 1; duration: 350 }
        NumberAnimation { target: g; property: "circleScale"; to: 1.0; duration: 450; easing.type: Easing.OutCubic }
        SequentialAnimation {
            ScriptAction { script: { g.formShift = g.formIn; g.formScale = 0.94; g.lockScale = 0.5; g.pulseScale = 0.3; } }
            PauseAnimation { duration: 120 }
            ParallelAnimation {
                NumberAnimation { target: g; property: "pulseOpacity"; from: 0.6; to: 0; duration: 650; easing.type: Easing.OutQuad }
                NumberAnimation { target: g; property: "pulseScale"; from: 0.3; to: 2.4; duration: 650; easing.type: Easing.OutCubic }
                NumberAnimation { target: g; property: "lockOpacity"; to: 1; duration: 200 }
                NumberAnimation { target: g; property: "lockScale"; to: 1; duration: 260; easing.type: Easing.OutBack }
            }
            PauseAnimation { duration: 300 }
            ParallelAnimation {
                NumberAnimation { target: g; property: "lockScale"; to: 1.35; duration: 200; easing.type: Easing.InQuad }
                NumberAnimation { target: g; property: "lockOpacity"; to: 0; duration: 200 }
                SequentialAnimation {
                    PauseAnimation { duration: 80 }
                    ParallelAnimation {
                        NumberAnimation { target: g; property: "formOpacity"; to: 1; duration: 300 }
                        NumberAnimation { target: g; property: "formShift"; to: 0; duration: g.cortina ? 460 : 380; easing.type: Easing.OutCubic }
                        NumberAnimation { target: g; property: "formScale"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    // Esc: todo vuelve al fondo nítido con el reloj (y la próxima tecla repite la transición)
    ParallelAnimation {
        id: hideAnim
        NumberAnimation { target: g; property: "formOpacity"; to: 0; duration: 200 }
        NumberAnimation { target: g; property: "formShift"; to: g.formIn; duration: 260 }
        NumberAnimation { target: g; property: "lockOpacity"; to: 0; duration: 100 }
        NumberAnimation { target: g; property: "circleOpacity"; to: 0; duration: 450 }
        NumberAnimation { target: g; property: "circleScale"; to: 1.15; duration: 450; easing.type: Easing.InOutCubic }
        NumberAnimation { target: g; property: "bgBlur"; to: 0; duration: 450; easing.type: Easing.InOutCubic }
        NumberAnimation { target: g; property: "bgBright"; to: 0; duration: 450 }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            ParallelAnimation {
                NumberAnimation { target: g; property: "clockOpacity"; to: 1; duration: 350 }
                NumberAnimation { target: g; property: "clockShift"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            }
        }
    }

    // Contraseña correcta: el círculo se abre y el fondo vuelve a verse nítido,
    // como el escritorio. Sin fundido a negro: la sesión aparece sobre el mismo fondo.
    SequentialAnimation {
        id: outroAnim
        ParallelAnimation {
            NumberAnimation { target: g; property: "formOpacity"; to: 0; duration: 260 }
            NumberAnimation { target: g; property: "formScale"; to: 1.04; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: g; property: "lockOpacity"; to: 0; duration: 150 }
            NumberAnimation { target: g; property: "pulseOpacity"; to: 0; duration: 150 }
            NumberAnimation { target: g; property: "barOpacity"; to: 0; duration: 300 }
            NumberAnimation { target: g; property: "circleScale"; to: 1.6; duration: 650; easing.type: Easing.InOutCubic }
            NumberAnimation { target: g; property: "circleOpacity"; to: 0; duration: 600 }
            NumberAnimation { target: g; property: "bgBlur"; to: 0; duration: 650; easing.type: Easing.InOutCubic }
            NumberAnimation { target: g; property: "bgBright"; to: 0; duration: 650 }
        }
        PauseAnimation { duration: 120 }
        ScriptAction {
            script: {
                if (g.demo) { demoReset.start(); return; }
                // Solo se lanza si greetd confirmó la contraseña
                if (Greetd.state === GreetdState.ReadyToLaunch)
                    Greetd.launch(g.session.cmd, g.session.env);
            }
        }
    }

    // ---------- Fondo ----------
    Rectangle { anchors.fill: parent; color: "#000000" }

    // El fondo del escritorio (lo copia sg-sync). Si falta o está dañado, el de respaldo.
    readonly property string fallbackWallpaper: "/usr/share/sddm/themes/material-you/bg.png"
    readonly property var wallpaperChain: [g.wallpaper, g.wallpaperAlt, g.fallbackWallpaper].filter(p => p !== "")
    property int wallpaperIndex: 0
    Image {
        id: bgImg
        anchors.fill: parent
        source: "file://" + g.wallpaperChain[Math.min(g.wallpaperIndex, g.wallpaperChain.length - 1)]
        sourceSize.width: Math.max(g.width, 1920)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
        onStatusChanged: if (status === Image.Error && g.wallpaperIndex < g.wallpaperChain.length - 1) g.wallpaperIndex++
    }

    MultiEffect {
        anchors.fill: parent
        source: bgImg
        visible: bgImg.status === Image.Ready
        opacity: g.bgOpacity
        blurEnabled: true
        blurMax: 48
        blur: g.bgBlur
        brightness: g.bgBright
        saturation: -0.3 * g.circleOpacity
    }

    // Afuera del círculo, más oscuro (como en el video)
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.38 * g.circleOpacity
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: circleMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
    Item {
        id: circleMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(g.width, g.height) * 1.02
            height: width
            radius: width / 2
            scale: g.circleScale
        }
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(g.width, g.height) * 1.02
        height: width
        radius: width / 2
        scale: g.circleScale
        opacity: g.circleOpacity
        color: Qt.rgba(0.85, 0.9, 1, 0.09)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
    }

    // Segundo anillo, más grande y tenue (como en el video)
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(g.width, g.height) * 1.38
        height: width
        radius: width / 2
        scale: g.circleScale
        opacity: g.circleOpacity
        color: Qt.rgba(0.85, 0.9, 1, 0.035)
        border.color: Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
    }

    // Clic en cualquier lugar: muestra el formulario y cierra los menús
    MouseArea {
        anchors.fill: parent
        onClicked: {
            g.openMenu = "";
            g.reveal("");
        }
    }

    // ---------- Intro: anillo y candado ----------
    Rectangle {
        anchors.centerIn: parent
        width: 64; height: 64; radius: 32
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.7)
        border.width: 1.5
        scale: g.pulseScale
        opacity: g.pulseOpacity
    }
    Rectangle {
        anchors.centerIn: parent
        width: 64; height: 64; radius: 32
        color: Qt.rgba(0.09, 0.09, 0.12, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        scale: g.lockScale
        opacity: g.lockOpacity
        Text {
            anchors.centerIn: parent
            text: ""
            textFormat: Text.PlainText
            font.family: g.iconFont
            font.pixelSize: 22
            color: g.cText
        }
    }

    // ---------- Vista 1: reloj ----------
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: g.clockShift
        spacing: 2
        opacity: g.clockOpacity
        visible: opacity > 0
        scale: g.clockScale
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.55
            shadowBlur: 0.8
            shadowVerticalOffset: 2
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            Text { text: Qt.formatDateTime(clock.date, "HH"); textFormat: Text.PlainText; font.family: g.mono; font.pixelSize: 120; font.weight: Font.Bold; color: g.cText }
            Text { text: ":"; textFormat: Text.PlainText; font.family: g.mono; font.pixelSize: 120; font.weight: Font.Bold; color: Qt.rgba(1, 1, 1, 0.35) }
            Text { text: Qt.formatDateTime(clock.date, "mm"); textFormat: Text.PlainText; font.family: g.mono; font.pixelSize: 120; font.weight: Font.Bold; color: g.cText }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale("es_PE").toString(clock.date, "dddd, d 'de' MMMM")
            textFormat: Text.PlainText
            font.family: g.mono
            font.pixelSize: 17
            font.capitalization: Font.Capitalize
            color: g.cSub
        }
    }

    // ---------- Vista 2: avatar, nombre y contraseña ----------
    Row {
        id: form
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: shakeOffset
        anchors.verticalCenterOffset: g.formShift
        property real shakeOffset: 0
        spacing: 24
        opacity: g.formOpacity
        visible: opacity > 0 || g.phase === "form"
        scale: g.formScale

        SequentialAnimation {
            id: shake
            loops: 2
            NumberAnimation { target: form; property: "shakeOffset"; to: -12; duration: 50 }
            NumberAnimation { target: form; property: "shakeOffset"; to: 12; duration: 100 }
            NumberAnimation { target: form; property: "shakeOffset"; to: 0; duration: 50 }
        }

        // Avatar circular
        Item {
            width: 132
            height: 132
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: avatarImg
                anchors.fill: parent
                source: g.avatar !== "" ? "file://" + g.avatar : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(264, 264)
                smooth: true
                visible: false
            }
            Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: avatarImg
                visible: avatarImg.status === Image.Ready
                maskEnabled: true
                maskSource: avatarMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: avatarImg.status === Image.Ready ? "transparent" : g.cSurface
                border.color: g.failed ? g.cRed : Qt.rgba(1, 1, 1, 0.35)
                border.width: 2
                Text {
                    anchors.centerIn: parent
                    visible: avatarImg.status !== Image.Ready
                    text: ""
                    textFormat: Text.PlainText
                    font.family: g.iconFont
                    font.pixelSize: 54
                    color: g.cSub
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                text: g.userName
                textFormat: Text.PlainText
                font.family: g.mono
                font.pixelSize: 30
                font.weight: Font.DemiBold
                color: g.cText
            }

            Text {
                text: (g.failed ? "  " : "  ") + (g.status !== "" ? g.status : "INGRESA TU CONTRASEÑA")
                textFormat: Text.PlainText
                font.family: g.iconFont
                font.pixelSize: 13
                font.letterSpacing: 1.2
                color: g.failed ? g.cRed : (g.busy ? g.cBlue : Qt.rgba(1, 1, 1, 0.8))
            }

            Rectangle {
                width: 300
                height: 46
                radius: height / 2
                color: Qt.rgba(0.07, 0.07, 0.11, 0.55)
                border.width: 2
                border.color: g.failed ? g.cRed : (pw.activeFocus ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.3))
                Behavior on border.color { ColorAnimation { duration: 200 } }

                TextInput {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    passwordMaskDelay: 0
                    maximumLength: 256
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
                    persistentSelection: false
                    selectByMouse: false
                    font.family: g.mono
                    font.pixelSize: 20
                    font.letterSpacing: 4
                    color: g.cText
                    enabled: !g.busy
                    clip: true
                    onAccepted: g.submit()
                    onTextChanged: if (text.length > 0 && g.failed) { g.failed = false; g.status = ""; }
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_F2) { g.cycleSession(); event.accepted = true; }
                        else if (event.key === Qt.Key_Escape) { g.openMenu = ""; g.hide(); event.accepted = true; }
                    }
                }
            }

            Text {
                text: "Sesión: " + g.session.name + "   ·   F2 cambia la sesión"
                textFormat: Text.PlainText
                font.family: g.mono
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.6)
            }
        }
    }

    // ---------- Aviso de modo prueba ----------
    Rectangle {
        visible: g.demo
        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: demoText.implicitWidth + 32
        height: 32
        radius: 16
        color: Qt.rgba(0.98, 0.70, 0.53, 0.18)
        border.color: g.cPeach
        Text {
            id: demoText
            anchors.centerIn: parent
            text: g.phase === "launch" ? "MODO PRUEBA: aquí se abriría " + g.session.name
                                       : "MODO PRUEBA: greetd no está disponible, no se inicia sesión"
            textFormat: Text.PlainText
            font.family: g.mono
            font.pixelSize: 12
            color: g.cPeach
        }
    }

    // ---------- Abajo al centro: información (no son botones) ----------
    component Info: Row {
        id: info
        property string icon: ""
        property string label: ""
        property color tint: g.cSub
        spacing: 7
        Text { text: info.icon; textFormat: Text.PlainText; font.family: g.iconFont; font.pixelSize: 14; color: info.tint; anchors.verticalCenter: parent.verticalCenter }
        Text { text: info.label; textFormat: Text.PlainText; font.family: g.mono; font.pixelSize: 12; color: info.tint; anchors.verticalCenter: parent.verticalCenter }
    }

    readonly property bool hasBattery: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery
    readonly property int batCap: hasBattery ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool charging: hasBattery && (UPower.displayDevice.state === UPowerDeviceState.Charging
                                                    || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)

    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 26
        opacity: g.barOpacity
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.6; shadowBlur: 0.6 }

        Info { icon: ""; label: g.kbLabel }
        Info {
            visible: g.hasBattery
            icon: g.charging ? "" : (g.batCap > 60 ? "" : (g.batCap > 25 ? "" : ""))
            label: g.batCap + "%"
            tint: (!g.charging && g.batCap <= 15) ? g.cRed : (g.charging ? g.cGreen : g.cSub)
        }
        Info {
            visible: g.climaTemp !== ""
            icon: g.climaIcon !== "" ? g.climaIcon : ""
            label: g.climaTemp
        }
    }

    // ---------- Abajo a la derecha: engranaje (sesión) y apagado ----------
    component RoundButton: Rectangle {
        id: rb
        property string icon: ""
        property bool active: false
        signal clicked()
        width: 40
        height: 40
        radius: 20
        color: active ? Qt.rgba(0.54, 0.71, 0.98, 0.22) : (rbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            anchors.centerIn: parent
            text: rb.icon
            textFormat: Text.PlainText
            font.family: g.iconFont
            font.pixelSize: 17
            color: rbMouse.containsMouse || rb.active ? g.cText : g.cSub
        }
        MouseArea {
            id: rbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }

    Row {
        id: corner
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 22
        anchors.bottomMargin: 20
        spacing: 6
        opacity: g.barOpacity
        enabled: !g.busy && g.phase !== "launch"

        RoundButton {
            icon: ""
            active: g.openMenu === "session"
            onClicked: g.openMenu = (g.openMenu === "session" ? "" : "session")
        }
        RoundButton {
            icon: ""
            active: g.openMenu === "power"
            onClicked: g.openMenu = (g.openMenu === "power" ? "" : "power")
        }
    }

    component MenuItem: Rectangle {
        id: mi
        property string icon: ""
        property string label: ""
        property bool checked: false
        signal clicked()
        width: 210
        height: 38
        radius: 10
        color: miMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            spacing: 10
            Text { width: 18; text: mi.icon; textFormat: Text.PlainText; font.family: g.iconFont; font.pixelSize: 14; color: mi.checked ? g.cBlue : g.cText }
            Text { text: mi.label; textFormat: Text.PlainText; font.family: g.mono; font.pixelSize: 13; color: mi.checked ? g.cBlue : g.cText }
        }
        Text {
            visible: mi.checked
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            textFormat: Text.PlainText
            font.family: g.iconFont
            font.pixelSize: 13
            color: g.cBlue
        }
        MouseArea {
            id: miMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mi.clicked()
        }
    }

    component Menu: Rectangle {
        default property alias items: menuCol.data
        width: 226
        height: menuCol.implicitHeight + 16
        radius: 14
        color: Qt.rgba(0.07, 0.07, 0.11, 0.92)
        border.color: Qt.rgba(1, 1, 1, 0.1)
        Column {
            id: menuCol
            anchors.centerIn: parent
            spacing: 2
        }
    }

    Menu {
        visible: g.openMenu === "session"
        anchors.right: corner.right
        anchors.bottom: corner.top
        anchors.bottomMargin: 10

        Text { leftPadding: 12; topPadding: 4; bottomPadding: 4; text: "SESIÓN"; textFormat: Text.PlainText; font.family: g.mono; font.pixelSize: 11; font.letterSpacing: 1.5; color: g.cSub }
        Repeater {
            model: g.sessions
            MenuItem {
                required property var modelData
                required property int index
                icon: index === 0 ? "" : ""
                label: modelData.name + (index === 0 ? "" : " (rescate)")
                checked: index === g.sessionIndex
                onClicked: { g.sessionIndex = index; g.openMenu = ""; g.reveal(""); }
            }
        }
    }

    Menu {
        visible: g.openMenu === "power"
        anchors.right: corner.right
        anchors.bottom: corner.top
        anchors.bottomMargin: 10

        MenuItem { icon: ""; label: "Reiniciar"; onClicked: g.power("reboot") }
        MenuItem { icon: ""; label: "Apagar"; onClicked: g.power("poweroff") }
    }
}
