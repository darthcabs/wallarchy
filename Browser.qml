import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Fullscreen browser overlay: search, category chips, a thumbnail grid, and
// the rotation controls.
//
// Thumbnails are loaded straight from Unsplash's CDN by QML's Image loader
// rather than downloaded first. That is both faster and what the API terms
// ask for — only a photo the user actually applies gets downloaded, and only
// then does the CLI ping the download endpoint.
Item {
  id: root

  // Injected by omarchy-shell when the overlay is summoned.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool loading: false
  property bool applying: false
  property bool hasKey: false
  property string errorText: ""
  property string keyDraft: ""

  property string filterText: ""
  property string topic: ""
  property string query: ""
  property string orientation: "landscape"
  property int rotateMinutes: 0
  property int page: 1
  property int selectedIndex: 0

  readonly property string cliPath: Qt.resolvedUrl("omasplash").toString().replace(/^file:\/\//, "")
  readonly property string pluginId: (manifest && manifest.id) || "co.klair.omasplash"

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent

  readonly property int cardWidth: Math.min(hasKey ? Style.space(1100) : Style.space(620),
    panel.width - Style.gapsOut * 4)
  // The key form is a two-line prompt; giving it the full browsing card makes
  // an empty box the first thing a new user sees.
  readonly property int cardHeight: hasKey
    ? Math.min(Style.space(760), panel.height - Style.gapsOut * 4)
    : Math.min(Style.space(210), panel.height - Style.gapsOut * 4)

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    opened = true
    errorText = ""
    keyDraft = ""
    selectedIndex = 0
    checkKey()
    Qt.callLater(function() {
      if (root.hasKey) searchField.forceActiveFocus()
      else keyField.forceActiveFocus()
    })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  // ------------------------------------------------------------- config io

  function applyConfig(raw) {
    var config = Model.parseJson(raw, {}, 65536)
    topic = typeof config.topic === "string" ? config.topic : ""
    query = typeof config.query === "string" ? config.query : ""
    orientation = typeof config.orientation === "string" ? config.orientation : "landscape"
    var minutes = Number(config.rotateMinutes)
    rotateMinutes = isFinite(minutes) && minutes > 0 ? Math.round(minutes) : 0
    // Don't yank the field out from under someone mid-type; the config file
    // is only authoritative for the search box while it is unfocused.
    if (!searchField.activeFocus) {
      filterText = query
      searchField.text = query
    }
  }

  // Config changes are written through the CLI rather than edited in place, so
  // the file has exactly one writer and the service's watcher sees a complete
  // document instead of a half-written one.
  function setConfig(key, value, thenReload) {
    configQueue.push({ key: key, value: String(value), reload: thenReload === true })
    drainConfigQueue()
  }

  property var configQueue: []

  function drainConfigQueue() {
    if (configProcess.running || configQueue.length === 0) return
    var job = configQueue.shift()
    configProcess.pendingReload = job.reload
    configProcess.command = [root.cliPath, "config", "set", job.key, job.value]
    configProcess.running = true
  }

  // --------------------------------------------------------------- loading

  function checkKey() {
    if (keyProcess.running) return
    keyProcess.command = [root.cliPath, "key", "status"]
    keyProcess.running = true
  }

  function saveKey() {
    var value = root.keyDraft.trim()
    if (value === "" || keySaveProcess.running) return
    keySaveProcess.command = [root.cliPath, "key", "set", value]
    keySaveProcess.running = true
  }

  function loadTopics() {
    if (topicProcess.running || topicModel.count > 0) return
    topicProcess.command = [root.cliPath, "topics"]
    topicProcess.running = true
  }

  function reload() {
    page = 1
    photoModel.clear()
    selectedIndex = 0
    loadPage()
  }

  function loadPage() {
    if (photoProcess.running || !hasKey) return
    loading = true
    errorText = ""
    photoProcess.command = [root.cliPath, "photos", String(page)]
    photoProcess.running = true
  }

  function loadMore() {
    if (loading || photoModel.count === 0 || page >= 20) return
    page += 1
    loadPage()
  }

  function applyPhotos(raw) {
    var rows = Model.photoRows(Model.parseJson(raw, [], 4194304))
    if (rows.length === 0 && photoModel.count === 0) {
      errorText = "No photos came back. Check the filter, or your API rate limit."
      return
    }
    for (var i = 0; i < rows.length; i++) photoModel.append(rows[i])
  }

  // ---------------------------------------------------------------- acting

  function search(value) {
    var next = Model.singleLine(value, 120)
    root.query = next
    // A free-text search and a topic are mutually exclusive on the API side,
    // so committing one clears the other rather than silently winning.
    setConfig("query", next)
    if (next !== "") setConfig("topic", "")
    reload()
  }

  function selectTopic(slug) {
    root.topic = slug
    root.query = ""
    root.filterText = ""
    setConfig("topic", slug)
    setConfig("query", "")
    reload()
  }

  function cycleOrientation() {
    var index = Model.ORIENTATIONS.indexOf(root.orientation)
    var next = Model.ORIENTATIONS[(index + 1) % Model.ORIENTATIONS.length]
    root.orientation = next
    setConfig("orientation", next)
    reload()
  }

  function cycleInterval() {
    var index = 0
    for (var i = 0; i < Model.INTERVALS.length; i++)
      if (Model.INTERVALS[i].minutes === root.rotateMinutes) index = i
    var next = Model.INTERVALS[(index + 1) % Model.INTERVALS.length].minutes
    root.rotateMinutes = next
    setConfig("rotateMinutes", next)
  }

  function applySelected() {
    if (applying || selectedIndex < 0 || selectedIndex >= photoModel.count) return
    applyPhoto(photoModel.get(selectedIndex).json)
  }

  function applyPhoto(photoJson) {
    if (applying || !photoJson) return
    applying = true
    applyProcess.command = [root.cliPath, "apply", photoJson]
    applyProcess.running = true
  }

  function randomNow() {
    if (applying) return
    applying = true
    applyProcess.command = [root.cliPath, "next"]
    applyProcess.running = true
  }

  // ------------------------------------------------------------ data + ipc

  ListModel { id: photoModel }
  ListModel { id: topicModel }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/omasplash.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onFileChanged: reload()
    onLoadFailed: root.applyConfig("{}")
  }

  Process {
    id: keyProcess
    command: []
    onExited: function(code) {
      root.hasKey = code === 0
      if (root.hasKey) {
        root.loadTopics()
        if (photoModel.count === 0) root.loadPage()
      }
    }
  }

  Process {
    id: keySaveProcess
    command: []
    onExited: function(code) {
      root.keyDraft = ""
      keyField.text = ""
      if (code === 0) {
        root.checkKey()
        Qt.callLater(function() { searchField.forceActiveFocus() })
      } else {
        root.errorText = "Could not save the key."
      }
    }
  }

  Process {
    id: topicProcess
    command: []
    stdout: StdioCollector { id: topicOutput; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) return
      var rows = Model.topicRows(Model.parseJson(topicOutput.text, [], 262144))
      topicModel.clear()
      for (var i = 0; i < rows.length; i++) topicModel.append(rows[i])
    }
  }

  Process {
    id: photoProcess
    command: []
    stdout: StdioCollector { id: photoOutput; waitForEnd: true }
    stderr: StdioCollector { id: photoError; waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      if (code !== 0) {
        root.errorText = Model.singleLine(photoError.text, 160) || "Unsplash request failed."
        return
      }
      root.applyPhotos(photoOutput.text)
    }
  }

  Process {
    id: applyProcess
    command: []
    stderr: StdioCollector { id: applyError; waitForEnd: true }
    onExited: function(code) {
      root.applying = false
      if (code !== 0) root.errorText = Model.singleLine(applyError.text, 160) || "Could not set the wallpaper."
    }
  }

  Process {
    id: configProcess
    property bool pendingReload: false
    command: []
    onExited: {
      if (pendingReload) root.reload()
      root.drainConfigQueue()
    }
  }

  IpcHandler {
    target: "omasplash"
    function next(): string { root.randomNow(); return "ok" }
    function browse(): string { root.open("{}"); return "ok" }
  }

  // ------------------------------------------------------------------ view

  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omasplash"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      color: root.background
      border.color: root.borderColor
      border.width: 1

      // Swallow clicks so they don't reach the dismiss layer behind the card.
      MouseArea { anchors.fill: parent }

      Keys.onEscapePressed: root.dismiss()

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(20)
        spacing: Style.space(14)

        // ------------------------------------------------------- key setup

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: !root.hasKey

          Text {
            text: "Add an Unsplash Access Key"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Create a free app at unsplash.com/oauth/applications and paste its Access Key. "
              + "It is stored with 0600 permissions in ~/.config/omarchy/omasplash.key, never in shell.json."
            color: Qt.darker(root.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            TextField {
              id: keyField
              width: parent.width - saveKeyButton.width - Style.space(10)
              password: true
              placeholderText: "Access Key"
              onTextChanged: root.keyDraft = text
              onAccepted: root.saveKey()
              Keys.onEscapePressed: root.dismiss()
            }

            Button {
              id: saveKeyButton
              text: "Save"
              bordered: true
              onClicked: root.saveKey()
            }
          }
        }

        // ---------------------------------------------------------- search

        Row {
          width: parent.width
          spacing: Style.space(10)
          visible: root.hasKey

          TextField {
            id: searchField
            width: parent.width - controls.width - Style.space(10)
            placeholderText: "Search Unsplash — or pick a category below"
            onTextChanged: root.filterText = text
            onAccepted: root.search(text)
            Keys.onDownPressed: grid.forceActiveFocus()
            Keys.onEscapePressed: root.dismiss()
          }

          Row {
            id: controls
            spacing: Style.space(8)

            Button {
              text: root.orientation
              tooltipText: "Orientation filter"
              bordered: true
              onClicked: root.cycleOrientation()
            }

            Button {
              text: root.rotateMinutes > 0 ? "Every " + Model.intervalLabel(root.rotateMinutes) : "Rotation off"
              tooltipText: "How often the wallpaper changes on its own"
              bordered: true
              selected: root.rotateMinutes > 0
              onClicked: root.cycleInterval()
            }

            Button {
              iconText: "󰒲"
              text: "Surprise me"
              tooltipText: "Apply a random photo matching the current filter"
              bordered: true
              enabled: !root.applying
              onClicked: root.randomNow()
            }
          }
        }

        // ------------------------------------------------------ topic chips

        Flickable {
          width: parent.width
          height: topicRow.height
          visible: root.hasKey && topicModel.count > 0
          contentWidth: topicRow.width
          flickableDirection: Flickable.HorizontalFlick
          clip: true

          Row {
            id: topicRow
            spacing: Style.space(8)

            Button {
              text: "All"
              bordered: true
              selected: root.topic === "" && root.query === ""
              onClicked: root.selectTopic("")
            }

            Repeater {
              model: topicModel

              Button {
                required property string slug
                required property string title
                text: title
                bordered: true
                selected: root.topic === slug && root.query === ""
                onClicked: root.selectTopic(slug)
              }
            }
          }
        }

        // ------------------------------------------------------------ grid

        Item {
          width: parent.width
          // The Column hands out `y`; clamping keeps the grid from taking a
          // negative height on the short key-setup card.
          height: Math.max(0, parent.height - y)

          GridView {
            id: grid
            anchors.fill: parent
            visible: root.hasKey
            clip: true
            focus: root.opened && root.hasKey
            model: photoModel
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / Style.space(260))))
            cellHeight: Math.round(cellWidth * 0.66)
            currentIndex: root.selectedIndex
            onCurrentIndexChanged: root.selectedIndex = currentIndex
            onAtYEndChanged: if (atYEnd) root.loadMore()

            Keys.onReturnPressed: root.applySelected()
            Keys.onEnterPressed: root.applySelected()
            Keys.onEscapePressed: root.dismiss()

            delegate: Item {
              id: cell
              required property int index
              required property string thumb
              required property string color
              required property string alt
              required property string user
              required property string json

              width: grid.cellWidth
              height: grid.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                radius: Style.cornerRadius
                // The API hands back a dominant colour per photo; using it as
                // the placeholder means the grid never flashes empty boxes.
                color: cell.color
                border.width: grid.currentIndex === cell.index ? 2 : 0
                border.color: root.accent
                clip: true

                Image {
                  anchors.fill: parent
                  source: cell.thumb
                  asynchronous: true
                  cache: true
                  fillMode: Image.PreserveAspectCrop
                  sourceSize.width: Math.round(parent.width * 2)
                  opacity: status === Image.Ready ? 1 : 0

                  Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                Rectangle {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                  height: creditLabel.implicitHeight + Style.space(10)
                  visible: cellArea.containsMouse || grid.currentIndex === cell.index
                  color: Qt.rgba(0, 0, 0, 0.6)

                  Text {
                    id: creditLabel
                    anchors.fill: parent
                    anchors.margins: Style.space(5)
                    text: cell.user ? "Photo by " + cell.user : cell.alt
                    color: "#ffffff"
                    elide: Text.ElideRight
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  id: cellArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: grid.currentIndex = cell.index
                  onClicked: {
                    grid.currentIndex = cell.index
                    root.applyPhoto(cell.json)
                  }
                }
              }
            }
          }

          BusyIndicator {
            anchors.centerIn: parent
            running: root.loading && photoModel.count === 0
            visible: running
          }
        }

        // ---------------------------------------------------------- footer

        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.errorText
          color: Color.urgent
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
