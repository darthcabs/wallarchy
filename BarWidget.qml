import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry point.
//
// Left click opens the browser overlay, middle click pulls a fresh random
// wallpaper, right click flips rotation on and off. Everything it shows is
// read from files the CLI and the service write, so it needs no direct handle
// on either of them.
BarWidget {
  id: root
  moduleName: "co.klair.omasplash"

  readonly property string cliPath: Qt.resolvedUrl("omasplash").toString().replace(/^file:\/\//, "")
  readonly property string home: Quickshell.env("HOME")

  property var photo: ({})
  property bool hasKey: false
  property int rotateMinutes: 0
  property string filterLabel: ""
  property bool working: false

  readonly property bool showCredit: setting("showCredit", false) === true
  readonly property string creditText: Model.singleLine(photo && photo.user ? photo.user : "", 24)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string tooltipText: Model.barTooltip({
    hasKey: hasKey,
    photo: photo,
    filterLabel: filterLabel,
    rotateMinutes: rotateMinutes
  })

  onTooltipTextChanged: if (interactionArea.containsMouse && bar) bar.showTooltip(root, tooltipText)

  function applyConfig(raw) {
    var config = Model.parseJson(raw, {}, 65536)
    var minutes = Number(config.rotateMinutes)
    rotateMinutes = isFinite(minutes) && minutes > 0 ? Math.round(minutes) : 0
    filterLabel = Model.singleLine(config.query || config.topic || "", 40)
  }

  function applyCurrent(raw) {
    photo = Model.parseJson(raw, {}, 262144)
  }

  function openBrowser() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "co.klair.omasplash", "{}"])
  }

  function nextWallpaper() {
    if (working) return
    working = true
    nextProcess.command = [root.cliPath, "next"]
    nextProcess.running = true
  }

  // Right click is a coarse on/off: it remembers nothing, so flipping back on
  // lands on a sane default rather than whatever obscure interval was set in
  // the overlay. The overlay is where a specific interval gets chosen.
  function toggleRotation() {
    if (configProcess.running) return
    configProcess.command = [root.cliPath, "config", "set", "rotateMinutes",
      rotateMinutes > 0 ? "0" : "60"]
    configProcess.running = true
  }

  implicitWidth: content.implicitWidth + Style.space(10)
  implicitHeight: barSize

  FileView {
    path: root.home + "/.config/omarchy/omasplash.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onFileChanged: reload()
    onLoadFailed: root.applyConfig("{}")
  }

  FileView {
    path: root.home + "/.local/state/omasplash/current.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyCurrent(text())
    onFileChanged: reload()
    onLoadFailed: root.applyCurrent("{}")
  }

  Process {
    id: keyProcess
    command: [root.cliPath, "key", "status"]
    running: true
    onExited: function(code) { root.hasKey = code === 0 }
  }

  Process {
    id: nextProcess
    command: []
    onExited: root.working = false
  }

  Process {
    id: configProcess
    command: []
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(6)

    OpticalGlyph {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.bar.iconSlot
      height: Style.bar.iconSlot
      text: root.rotateMinutes > 0 ? "󰑖" : "󰋩"
      fontFamily: root.fontFamily
      fontSize: Style.font.icon
      color: root.hasKey ? root.foreground : Qt.darker(root.foreground, 1.8)
      opacity: root.working ? 0.5 : 1

      Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showCredit && root.creditText !== "" && !root.vertical
      text: root.creditText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }
  }

  MouseArea {
    id: interactionArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) root.nextWallpaper()
      else if (mouse.button === Qt.RightButton) root.toggleRotation()
      else root.openBrowser()
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
