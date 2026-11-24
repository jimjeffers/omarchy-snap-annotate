import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// Snap Annotate in the Omarchy bar: a full-height sidebar of recent
// screenshots. Typing filters by file name; clicking a shot reopens it in
// Omasnap's editor, and its clipboard button copies the file's path.
Panel {
  id: root
  moduleName: "io.github.jimjeffers.snap-annotate"
  ipcTarget: "screenshots"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color foreground: Commons.Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string directory: {
    var dir = String(setting("directory", "") || "").trim()
    if (dir === "") dir = Quickshell.env("OMASNAP_SCREENSHOT_DIR") || Quickshell.env("OMARCHY_SCREENSHOT_DIR") || ""
    if (dir === "") dir = home + "/Pictures/Screenshots"
    if (dir === "~" || dir.indexOf("~/") === 0) dir = home + dir.slice(1)
    return dir.replace(/\/+$/, "")
  }
  readonly property int limit: Math.max(1, Number(setting("limit", 400)) || 400)

  property var shots: []
  property string query: ""
  readonly property var visibleShots: Model.filter(shots, query)
  property int cursor: 0
  property bool loaded: false
  property bool unreadable: false
  property string copiedPath: ""
  property double now: Date.now()

  function refresh() {
    if (listProc.running) return
    if (directory.charAt(0) !== "/") { unreadable = true; loaded = true; return }
    now = Date.now()
    listProc.command = ["find", "-L", directory, "-maxdepth", "1", "-type", "f", "-printf", "%T@\\t%s\\t%p\\n"]
    listProc.running = true
  }

  function setQuery(text) {
    query = String(text || "")
    cursor = 0
    scrollToCursor()
  }

  function moveCursor(delta) {
    cursor = Model.clampIndex(cursor + delta, visibleShots.length)
    scrollToCursor()
  }

  function scrollToCursor() {
    var list = panel.loadedContent ? panel.loadedContent.list : null
    if (list && cursor >= 0) list.positionViewAtIndex(cursor, ListView.Contain)
  }

  function shotAt(index) {
    return index >= 0 && index < visibleShots.length ? visibleShots[index] : null
  }

  function annotate(shot) {
    if (!shot) return
    root.close()
    Util.execArgv(["omasnap", "--file", shot.path])
  }

  function copyPath(shot) {
    if (!shot) return
    Util.execArgv(["wl-copy", "--", shot.path])
    copiedPath = shot.path
    copiedTimer.restart()
  }

  function timeLabel(shot) {
    var r = Model.relativeTime(shot.mtime, now)
    if (r.unit === "now") return strings.t("justNow", "Just now")
    var fallback = r.count === 1 ? "%1 " + r.unit + " ago" : "%1 " + r.unit + "s ago"
    return strings.tn(r.unit + "sAgo", r.count, fallback).arg(Commons.I18n.formatNumber(r.count))
  }

  function statusText() {
    if (unreadable) return strings.t("missing", "Can't read %1").arg(directory)
    if (!loaded) return ""
    if (shots.length === 0) return strings.t("empty", "No screenshots in %1 yet").arg(directory)
    if (visibleShots.length === 0) return strings.t("noMatches", "No screenshots match “%1”").arg(query)
    return ""
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      setQuery("")
      if (panel.loadedContent) panel.loadedContent.filterField.text = ""
      refresh()
      Qt.callLater(function() {
        if (root.opened && panel.loadedContent) panel.loadedContent.filterField.forceActiveFocus()
      })
    }
  }
  onVisibleShotsChanged: cursor = Model.clampIndex(cursor, visibleShots.length)

  // New captures turn up while the sidebar is open.
  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: copiedTimer
    interval: 1600
    onTriggered: root.copiedPath = ""
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseListing(text, root.limit)
        // Keep the same array when nothing changed, so the list and its
        // decoded thumbnails aren't rebuilt every refresh.
        var same = next.length === root.shots.length
        for (var i = 0; same && i < next.length; i++)
          same = next[i].path === root.shots[i].path && next[i].mtime === root.shots[i].mtime
        if (!same) root.shots = next
      }
    }
    onExited: function(code) {
      root.unreadable = code !== 0 && root.shots.length === 0
      root.loaded = true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄀"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // Screenshots run edge to edge inside the card's border.
    padding: 0
    focusTarget: panel.loadedContent ? panel.loadedContent.filterField : null
    contentWidth: panel.fittedContentWidth(Style.space(Math.max(260, Number(root.setting("panelWidth", 380)) || 380)))
    // The whole length of the screen beside (or below) the bar.
    contentHeight: Math.round(panel.availableCardHeight)

    content: Item {
      id: body
      property alias filterField: filterField
      property alias list: list
      anchors.fill: parent
      clip: true

      readonly property color rule: Util.alpha(root.foreground, 0.14)
      readonly property int selectedWidth: Math.max(2, Style.space(2))

      // Sees every key before the search line; what it leaves is typed.
      Item {
        id: keys
        Keys.onPressed: function(event) {
          var ctrl = event.modifiers & Qt.ControlModifier
          if (event.key === Qt.Key_Escape) {
            if (filterField.text !== "") filterField.text = ""
            else root.close()
          } else if (event.key === Qt.Key_Down) {
            root.moveCursor(1)
          } else if (event.key === Qt.Key_Up) {
            root.moveCursor(-1)
          } else if (event.key === Qt.Key_PageDown) {
            root.moveCursor(5)
          } else if (event.key === Qt.Key_PageUp) {
            root.moveCursor(-5)
          } else if (event.key === Qt.Key_Home && ctrl) {
            root.moveCursor(-root.visibleShots.length)
          } else if (event.key === Qt.Key_End && ctrl) {
            root.moveCursor(root.visibleShots.length)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var shot = root.shotAt(root.cursor)
            if (ctrl || (event.modifiers & Qt.ShiftModifier)) root.copyPath(shot)
            else root.annotate(shot)
          } else if (ctrl && event.key === Qt.Key_C) {
            root.copyPath(root.shotAt(root.cursor))
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.switchPanel(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
          } else {
            return
          }
          event.accepted = true
        }
      }

      // ---------- The strip ----------
      ListView {
        id: list
        anchors.fill: parent
        spacing: 0
        cacheBuffer: Style.space(800)
        boundsBehavior: Flickable.StopAtBounds
        model: root.visibleShots
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Item {
          id: card
          required property var modelData
          required property int index
          readonly property bool current: index === root.cursor
          readonly property bool copied: root.copiedPath === modelData.path
          readonly property string shotTitle: Model.title(modelData.name)
          // Very tall captures (scrolling shots) show their top, at most
          // twice as tall as the strip is wide.
          readonly property real naturalHeight: thumb.implicitWidth > 0
            ? width * thumb.implicitHeight / thumb.implicitWidth
            : Math.round(width * 0.5625)
          readonly property real imageHeight: Math.round(Math.min(naturalHeight, width * 2))

          width: list.width
          height: imageHeight + labels.implicitHeight + Style.space(14) + (divider.visible ? 1 : 0)

          Image {
            id: thumb
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: card.imageHeight
            source: Util.fileUrl(card.modelData.path)
            sourceSize.width: Math.ceil(card.width * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignTop
            asynchronous: true
            clip: true
          }

          // Name and time under the screenshot.
          Column {
            id: labels
            anchors.top: thumb.bottom
            anchors.topMargin: Style.space(7)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: card.shotTitle !== "" ? card.shotTitle : strings.t("untitled", "Screenshot")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: card.copied ? strings.t("copied", "Path copied") : root.timeLabel(card.modelData)
              color: card.copied ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Rectangle {
            id: divider
            visible: card.index < list.count - 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: body.rule
          }

          MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.cursor = card.index
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) root.copyPath(card.modelData)
              else root.annotate(card.modelData)
            }
          }


          // Selected: a border around the screenshot and its labels.
          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: card.height - (divider.visible ? 1 : 0)
            color: "transparent"
            visible: card.current
            border.width: body.selectedWidth
            border.color: root.accent
          }

          // Clipboard button over the screenshot's corner.
          Rectangle {
            id: copyButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(8)
            width: copyGlyph.implicitWidth + Style.space(14)
            height: copyGlyph.implicitHeight + Style.space(8)
            radius: Style.cornerRadius
            visible: card.current
            color: copyMouse.containsMouse || card.copied ? root.accent : Commons.Color.popups.background
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.2)

            Text {
              id: copyGlyph
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: card.copied ? "󰄬" : "󰅌"
              color: copyMouse.containsMouse || card.copied ? Commons.Color.popups.background : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }

            MouseArea {
              id: copyMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyPath(card.modelData)
            }

            PanelToolTip {
              visible: copyMouse.containsMouse
              text: card.copied ? strings.t("copied", "Path copied") : strings.t("copy", "Copy path")
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        visible: text !== ""
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.statusText()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      // The search only shows once something is typed, over the top of the
      // strip. The field is always there (transparent) so it keeps focus.
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: filterField.implicitHeight + Style.space(16)
        color: Commons.Color.popups.background
        opacity: filterField.text !== "" || filterField.preeditText !== "" ? 0.94 : 0

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: body.rule
        }

        FilterInput {
          id: filterField
          keyHandler: keys
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          onTextChanged: if (text !== root.query) root.setQuery(text)
        }
      }
    }
  }
}
