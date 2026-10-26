import QtQuick

// Fondo de los otros monitores: el fondo de ese monitor, un poco oscurecido.
// Misma cadena que el login: fondo-<monitor> → fondo → el de respaldo.
Item {
    id: f
    required property string screenName
    required property string dir
    readonly property var chain: [dir + "/fondo-" + screenName, dir + "/fondo",
                                  "/usr/share/sddm/themes/material-you/bg.png"]
    property int index: 0

    Rectangle { anchors.fill: parent; color: "#000000" }
    Image {
        anchors.fill: parent
        source: "file://" + f.chain[f.index]
        sourceSize.width: Math.max(f.width, 1920)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: if (status === Image.Error && f.index < f.chain.length - 1) f.index++
    }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.25 }
}
