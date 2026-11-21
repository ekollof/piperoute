import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

/**
 * Fullscreen PipeWire patchbay, in the spirit of qpwgraph / Carla.
 *
 * Nodes are boxes with ports down each side; cables are bezier curves drawn on
 * a Canvas underneath. Drag from an output port (right side) to an input port
 * (left side) to create a link. Drag a node by its title bar to rearrange it.
 * Click the small x at a cable's midpoint to remove that link. All pointer
 * hit-testing happens in one MouseArea over the world, against plain JS
 * geometry, so no live PipeWire object is ever held by a visual delegate.
 */
PanelWindow {
  id: win
  property bool opened: false
  property var graph: ({ nodes: [], links: [], managed: [] })
  property string statusText: ""
  property string errorText: ""

  signal closeRequested()
  signal actionRequested(string action, var args)
  signal refreshRequested()

  readonly property color onScrim: "white"
  readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.55)
  readonly property color boxFill: "#1b1c26"
  readonly property color boxBorder: "#3b3d52"
  readonly property color cable: Qt.rgba(0.35, 0.85, 0.82, 0.95)

  readonly property int nodeWidth: 248
  readonly property int headerHeight: 30
  readonly property int portTop: 38
  readonly property int portStep: 22

  property var nodes: []
  property var pendingFrom: null
  property var pendingTo: null
  property string dragMode: ""
  property var dragNode: null
  property real dragOffsetX: 0
  property real dragOffsetY: 0
  property string hoverText: ""
  property real panStartX: 0
  property real panStartY: 0
  property real panContentX: 0
  property real panContentY: 0
  property real graphWidth: 1040
  property real graphHeight: 760

  // A live drag must not be interrupted by an automatic graph refresh.
  readonly property bool dragging: dragMode !== "" || pendingFrom !== null

  visible: opened
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "piperoute-graph"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onOpenedChanged: if (opened) Qt.callLater(function() { if (win.opened) keyCatcher.forceActiveFocus() })

  function close() { win.closeRequested() }

  // Keep positions of nodes that already existed when a refresh arrives.
  function applyGraph(data) {
    if (!data || !Array.isArray(data.nodes) || !Array.isArray(data.links)) return
    var old = {}
    for (var i = 0; i < win.nodes.length; i++) old[win.nodes[i].id] = win.nodes[i]

    var streams = [], virtuals = [], devices = []
    for (var n = 0; n < data.nodes.length && n < 64; n++) {
      var source = data.nodes[n]
      if (!source || typeof source !== "object") continue
      var id = String(source.id || "").slice(0, 20)
      if (!id) continue
      var existing = old[id]
      var node = {
        id: id,
        name: String(source.name || "").slice(0, 200),
        label: plain(source.label || source.name || id, 100),
        kind: String(source.kind || "").slice(0, 20),
        inputs: boundPorts(source.inputs),
        outputs: boundPorts(source.outputs),
        x: existing ? existing.x : 0,
        y: existing ? existing.y : 0,
        positioned: existing ? true : false
      }
      if (source.kind === "stream") streams.push(node)
      else if (source.kind === "virtual") virtuals.push(node)
      else devices.push(node)
    }

    var columns = [streams, virtuals, devices]
    var columnX = [48, 372, 696]
    var placed = []
    var maxX = 1040, maxY = 760
    for (var c = 0; c < columns.length; c++) {
      var column = columns[c]
      var nextY = 56
      for (var k = 0; k < column.length; k++) {
        var item = column[k]
        if (!item.positioned) {
          item.x = columnX[c]
          item.y = nextY
          item.positioned = true
        }
        nextY = Math.max(nextY, item.y + nodeHeight(item) + 18)
        maxX = Math.max(maxX, item.x + win.nodeWidth + 40)
        maxY = Math.max(maxY, item.y + nodeHeight(item) + 40)
        placed.push(item)
      }
    }
    win.graphWidth = maxX
    win.graphHeight = maxY
    win.nodes = placed
    win.graph = {
      nodes: data.nodes.slice(0, 64),
      links: boundLinks(data.links),
      managed: Array.isArray(data.managed) ? data.managed.slice(0, 64) : []
    }
    drawWires()
  }

  // Defence in depth: the helper already sanitizes, but the canvas is a text
  // sink of its own and must not depend on that being true forever. Only
  // display fields pass through here; port *names* used for actions stay exact.
  function plain(value, limit) {
    var text = String(value === undefined || value === null ? "" : value)
    var out = ""
    for (var i = 0; i < text.length && out.length < limit; i++) {
      var ch = text.charAt(i)
      var code = text.charCodeAt(i)
      if (ch === "<" || ch === ">" || ch === "&" || code < 32 || code === 127) out += " "
      else out += ch
    }
    return out.replace(/\s+/g, " ").trim()
  }

  function boundPorts(list) {
    var values = Array.isArray(list) ? list : []
    var out = []
    for (var i = 0; i < values.length && out.length < 32; i++) {
      var p = values[i]
      if (!p || typeof p !== "object") continue
      out.push({
        id: String(p.id || "").slice(0, 20),
        name: String(p.name || "").slice(0, 200),
        label: plain(p.label || p.name || "", 80)
      })
    }
    return out
  }

  function boundLinks(list) {
    var values = Array.isArray(list) ? list : []
    var out = []
    for (var i = 0; i < values.length && out.length < 128; i++) {
      var l = values[i]
      if (!l || typeof l !== "object") continue
      out.push({
        id: String(l.id || "").slice(0, 20),
        out: String(l.out || "").slice(0, 20),
        "in": String(l["in"] || "").slice(0, 20)
      })
    }
    return out
  }

  function nodeHeight(node) {
    var rows = Math.max(node.inputs.length, node.outputs.length, 1)
    return win.portTop + rows * win.portStep + 12
  }

  function portPos(node, direction, index) {
    var ports = direction === "out" ? node.outputs : node.inputs
    if (!node || index < 0 || index >= ports.length) return null
    var x = direction === "out" ? node.x + win.nodeWidth : node.x
    return { x: x, y: node.y + win.portTop + index * win.portStep + win.portStep / 2 }
  }

  function findPort(portId, direction) {
    for (var i = 0; i < win.nodes.length; i++) {
      var n = win.nodes[i]
      var list = direction === "out" ? n.outputs : n.inputs
      for (var j = 0; j < list.length; j++)
        if (list[j].id === portId) return { node: n, port: list[j], pos: portPos(n, direction, j), index: j }
    }
    return null
  }

  function portAt(x, y, direction) {
    for (var i = 0; i < win.nodes.length; i++) {
      var n = win.nodes[i]
      var list = direction === "out" ? n.outputs : n.inputs
      for (var j = 0; j < list.length; j++) {
        var p = portPos(n, direction, j)
        if (p && Math.abs(p.x - x) <= 12 && Math.abs(p.y - y) <= 12)
          return { node: n, port: list[j], pos: p }
      }
    }
    return null
  }

  function linkMidpoint(link) {
    var a = findPort(link.out, "out")
    var b = findPort(link["in"], "in")
    if (!a || !b) return null
    var dx = Math.max(64, Math.abs(b.pos.x - a.pos.x) * 0.45)
    var c1x = a.pos.x + dx, c2x = b.pos.x - dx
    return {
      x: 0.125 * a.pos.x + 0.375 * c1x + 0.375 * c2x + 0.125 * b.pos.x,
      y: 0.125 * a.pos.y + 0.375 * a.pos.y + 0.375 * b.pos.y + 0.125 * b.pos.y
    }
  }

  function drawWires() { if (wireCanvas.available) wireCanvas.requestPaint() }
  function drawPending() { if (pendingCanvas.available) pendingCanvas.requestPaint() }

  function refreshNodes() {
    win.nodes = win.nodes.slice()
    drawWires()
    drawPending()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0.02, 0.02, 0.04, 0.96)
    MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: win.closeRequested()
    Keys.onPressed: event => {
      if (event.key === Qt.Key_R || event.key === Qt.Key_F5) { win.refreshRequested(); event.accepted = true }
    }
    // Arrow keys pan the canvas; the mouse drag pans it too.
    Keys.onLeftPressed: keyCatcher.panBy(120, 0)
    Keys.onRightPressed: keyCatcher.panBy(-120, 0)
    Keys.onUpPressed: keyCatcher.panBy(0, 120)
    Keys.onDownPressed: keyCatcher.panBy(0, -120)

    function panBy(dx, dy) {
      flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX + dx))
      flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy))
    }

    // Swallow clicks that land on the chrome so the scrim does not close.
    MouseArea {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 58
      onClicked: {}
    }

    Row {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: 14
      spacing: 12

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "PipeRoute · " + strings.t("graph.title")
        color: win.onScrim
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: win.statusText + (win.errorText ? "  ·  " + win.errorText : "")
        color: win.errorText ? "#ff8a8a" : win.onScrimDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 8

      Button { text: strings.t("action.refresh"); onClicked: win.refreshRequested() }
      Button { text: strings.t("action.createSink"); onClicked: win.actionRequested("create-node", ["sink"]) }
      Button { text: strings.t("action.createSource"); onClicked: win.actionRequested("create-node", ["source"]) }
      Button { iconText: "󰅙"; tooltipText: strings.t("action.close"); onClicked: win.closeRequested() }
    }

    Text {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: 14
      textFormat: Text.PlainText
      text: win.hoverText !== "" ? win.hoverText : strings.t("graph.hint")
      color: win.onScrimDim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.topMargin: 58
      anchors.bottomMargin: 46
      clip: true
      contentWidth: Math.max(width, win.graphWidth)
      contentHeight: Math.max(height, win.graphHeight)
      // Panning is handled inside the world MouseArea, where a drag can be
      // told apart from a port drag; a Flickable drag would fight it.
      interactive: false
      boundsBehavior: Flickable.StopAtBounds

      Item {
        id: world
        width: flick.contentWidth
        height: flick.contentHeight

        Canvas {
          id: wireCanvas
          anchors.fill: parent
          z: 1
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = 2.5
            ctx.strokeStyle = win.cable
            var links = win.graph.links || []
            for (var i = 0; i < links.length; i++) {
              var a = win.findPort(links[i].out, "out")
              var b = win.findPort(links[i]["in"], "in")
              if (!a || !b) continue
              var dx = Math.max(64, Math.abs(b.pos.x - a.pos.x) * 0.45)
              ctx.beginPath()
              ctx.moveTo(a.pos.x, a.pos.y)
              ctx.bezierCurveTo(a.pos.x + dx, a.pos.y, b.pos.x - dx, b.pos.y, b.pos.x, b.pos.y)
              ctx.stroke()
            }
          }
        }

        Repeater {
          model: win.nodes
          delegate: Rectangle {
            required property var modelData
            x: modelData.x
            y: modelData.y
            z: 2
            width: win.nodeWidth
            height: win.nodeHeight(modelData)
            radius: 10
            clip: true
            color: win.boxFill
            border.color: modelData.kind === "stream" ? "#4a6f8a"
              : modelData.kind === "virtual" ? "#6a5a8a" : win.boxBorder
            border.width: 1

            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: "transparent"
              border.color: win.boxBorder
              border.width: 1
              opacity: 0.5
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 8
              height: win.headerHeight - 10
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: (modelData.kind === "stream" ? "󱀞 " : modelData.kind === "virtual" ? "󰌘 " : "󰓃 ") + modelData.label
              color: win.onScrim
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Repeater {
              model: modelData.inputs
              delegate: Row {
                required property var modelData
                required property int index
                x: 8
                y: win.portTop + index * win.portStep
                spacing: 8
                Rectangle {
                  width: 10; height: 10; radius: 5
                  anchors.verticalCenter: parent.verticalCenter
                  color: "#8fd1c9"
                  border.color: "#1d2a2a"
                  border.width: 1
                  x: -12
                }
                Text {
                  width: win.nodeWidth - 34
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: modelData.label
                  color: win.onScrimDim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Repeater {
              model: modelData.outputs
              delegate: Text {
                required property var modelData
                required property int index
                anchors.right: parent.right
                anchors.rightMargin: 12
                width: win.nodeWidth - 28
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                y: win.portTop + index * win.portStep
                textFormat: Text.PlainText
                text: modelData.label + " 󰁧"
                color: win.onScrimDim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Repeater {
              model: modelData.outputs
              delegate: Rectangle {
                required property var modelData
                required property int index
                x: win.nodeWidth - 5
                y: win.portTop + index * win.portStep + win.portStep / 2 - 5
                width: 10; height: 10; radius: 5
                color: win.cable
                border.color: "#18302f"
                border.width: 1
              }
            }
          }
        }

        Repeater {
          model: win.graph.links || []
          delegate: Item {
            required property var modelData
            property var midpoint: win.linkMidpoint(modelData)
            visible: midpoint !== null
            x: midpoint ? midpoint.x - 9 : 0
            y: midpoint ? midpoint.y - 9 : 0
            z: 3
            Rectangle {
              width: 18; height: 18; radius: 9
              color: "#2a2b3a"
              border.color: win.cable
              border.width: 1
              Text {
                anchors.centerIn: parent
                text: "×"
                color: win.onScrim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Canvas {
          id: pendingCanvas
          anchors.fill: parent
          z: 4
          visible: win.pendingFrom !== null && win.pendingTo !== null
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (!win.pendingFrom || !win.pendingTo) return
            var a = win.findPort(win.pendingFrom, "out")
            if (!a) return
            var dx = Math.max(64, Math.abs(win.pendingTo.x - a.pos.x) * 0.45)
            ctx.lineWidth = 2.5
            ctx.setLineDash([6, 5])
            ctx.strokeStyle = win.cable
            ctx.beginPath()
            ctx.moveTo(a.pos.x, a.pos.y)
            ctx.bezierCurveTo(a.pos.x + dx, a.pos.y, win.pendingTo.x - dx, win.pendingTo.y, win.pendingTo.x, win.pendingTo.y)
            ctx.stroke()
            ctx.setLineDash([])
          }
        }

        MouseArea {
          id: worldInput
          anchors.fill: parent
          z: 5
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

          onExited: win.hoverText = ""

          onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton) return
            // 1. cable midpoint -> remove
            var links = win.graph.links || []
            for (var i = 0; i < links.length; i++) {
              var mid = win.linkMidpoint(links[i])
              if (mid && Math.abs(mid.x - mouse.x) <= 12 && Math.abs(mid.y - mouse.y) <= 12) {
                win.actionRequested("disconnect", [links[i].id])
                mouse.accepted = true
                return
              }
            }
            // 2. output port -> start a cable
            var out = win.portAt(mouse.x, mouse.y, "out")
            if (out) {
              win.pendingFrom = out.port.id
              win.pendingTo = { x: mouse.x, y: mouse.y }
              win.drawPending()
              mouse.accepted = true
              return
            }
            // 3. node header -> drag the box
            for (var n = 0; n < win.nodes.length; n++) {
              var node = win.nodes[n]
              if (mouse.x >= node.x && mouse.x <= node.x + win.nodeWidth
                  && mouse.y >= node.y && mouse.y <= node.y + win.headerHeight) {
                win.dragMode = "node"
                win.dragNode = node
                win.dragOffsetX = mouse.x - node.x
                win.dragOffsetY = mouse.y - node.y
                mouse.accepted = true
                return
              }
            }
            // 4. empty canvas -> pan
            var scene = world.mapToItem(null, mouse.x, mouse.y)
            win.dragMode = "pan"
            win.panStartX = scene.x
            win.panStartY = scene.y
            win.panContentX = flick.contentX
            win.panContentY = flick.contentY
            mouse.accepted = true
          }

          onPositionChanged: mouse => {
            if (win.pendingFrom) {
              win.pendingTo = { x: mouse.x, y: mouse.y }
              win.drawPending()
            } else if (win.dragMode === "node" && win.dragNode) {
              win.dragNode.x = Math.max(8, Math.min(win.graphWidth - win.nodeWidth - 8,
                mouse.x - win.dragOffsetX))
              win.dragNode.y = Math.max(8, Math.min(win.graphHeight - win.nodeHeight(win.dragNode) - 8,
                mouse.y - win.dragOffsetY))
              win.refreshNodes()
            } else if (win.dragMode === "pan") {
              var scene = world.mapToItem(null, mouse.x, mouse.y)
              flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width,
                win.panContentX - (scene.x - win.panStartX)))
              flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height,
                win.panContentY - (scene.y - win.panStartY)))
            } else {
              var p = win.portAt(mouse.x, mouse.y, "out") || win.portAt(mouse.x, mouse.y, "in")
              win.hoverText = p ? p.node.label + " · " + p.port.label : ""
            }
          }

          onReleased: mouse => {
            if (win.pendingFrom) {
              var input = win.portAt(mouse.x, mouse.y, "in")
              if (input) {
                var source = win.findPort(win.pendingFrom, "out")
                // Do not stack a duplicate link on an existing one.
                var exists = false
                var links = win.graph.links || []
                for (var i = 0; i < links.length; i++) {
                  if (links[i].out === win.pendingFrom && links[i]["in"] === input.port.id) {
                    exists = true
                    break
                  }
                }
                if (source && !exists) win.actionRequested("connect", [source.port.name, input.port.name])
              }
              win.pendingFrom = null
              win.pendingTo = null
              win.drawPending()
            }
            win.dragMode = ""
            win.dragNode = null
          }
        }

        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: event => {
            var dx = event.angleDelta.x
            var dy = event.angleDelta.y
            if (event.modifiers & Qt.ShiftModifier) { dx = dy; dy = 0 }
            flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - dx))
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy))
            event.accepted = true
          }
        }
      }
    }
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
}
