// serpantinum-greeter: login para greetd con el diseño del bloqueo de Serpantinum.
// Si greetd no está disponible (por ejemplo, al abrirlo en una ventana para probarlo),
// funciona en MODO PRUEBA: no inicia sesión, no apaga ni reinicia.
import QtQuick
import Quickshell
import Quickshell.Services.Greetd

ShellRoot {
    id: shell

    // Configuración por variables de entorno (con valores por defecto)
    // El lanzador detecta el usuario (greetd/serpantinum-greeter-user) y lo pasa en SG_USER
    readonly property string userName: Quickshell.env("SG_USER") || ""
    readonly property string wallpaperDir: Quickshell.env("SG_FONDOS") || "/var/lib/serpantinum-greeter"
    readonly property string avatar: Quickshell.env("SG_AVATAR") || ("/var/lib/AccountsService/icons/" + userName)
    readonly property string kbLabel: Quickshell.env("SG_KB") || "LATAM"
    // Solo la temperatura y el ícono (sin coordenadas). El login nunca sale a internet.
    readonly property string climaPath: Quickshell.env("SG_CLIMA") || "/var/lib/serpantinum-greeter/clima.json"
    readonly property string transition: Quickshell.env("SG_TRANSICION") || "video"
    readonly property bool demo: !Greetd.available

    // Varios monitores (cage -m extend): una sola ventana cubre todos. El login va en el monitor
    // principal (el primero de SG_PANTALLA que esté conectado: la laptop, eDP-1) y los demás su fondo.
    // En modo prueba (una ventana normal) se dibuja todo en la ventana, salvo con SG_MULTI=1.
    readonly property bool multi: !demo || Quickshell.env("SG_MULTI") === "1"
    readonly property var screens: Quickshell.screens
    readonly property var mainScreen: {
        const prefs = (Quickshell.env("SG_PANTALLA") || "eDP-1,HDMI-A-1").split(",");
        for (const name of prefs)
            for (const sc of screens)
                if (sc.name === name.trim()) return sc;
        return screens.length > 0 ? screens[0] : null;
    }
    readonly property real originX: screens.length > 0 ? Math.min(...screens.map(sc => sc.x)) : 0
    readonly property real originY: screens.length > 0 ? Math.min(...screens.map(sc => sc.y)) : 0

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1280
        implicitHeight: 720
        title: shell.demo ? "serpantinum-greeter (modo prueba)" : "serpantinum-greeter"
        color: "#11111b"

        Repeater {
            model: shell.multi ? shell.screens : []
            Fondo {
                required property var modelData
                visible: modelData !== shell.mainScreen
                x: modelData.x - shell.originX
                y: modelData.y - shell.originY
                width: modelData.width
                height: modelData.height
                screenName: modelData.name
                dir: shell.wallpaperDir
            }
        }

        Greeter {
            readonly property bool placed: shell.multi && shell.mainScreen !== null
            clip: placed   // el círculo es más grande que la pantalla: que no invada el otro monitor
            x: placed ? shell.mainScreen.x - shell.originX : 0
            y: placed ? shell.mainScreen.y - shell.originY : 0
            width: placed ? shell.mainScreen.width : parent.width
            height: placed ? shell.mainScreen.height : parent.height
            userName: shell.userName
            wallpaper: Quickshell.env("SG_WALLPAPER")
                       || (shell.wallpaperDir + "/fondo-" + (shell.mainScreen ? shell.mainScreen.name : ""))
            wallpaperAlt: shell.wallpaperDir + "/fondo"
            avatar: shell.avatar
            kbLabel: shell.kbLabel
            climaPath: shell.climaPath
            transition: shell.transition
            demo: shell.demo
        }
    }
}
