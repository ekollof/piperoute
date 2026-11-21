import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "omakit"
import "RoutingModel.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.ekollof.piperoute"

  // Native, event-driven reads of the running PipeWire graph for the bar label
  // and the Devices tab. No polling process runs while nothing is open.
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var pwLinks: Pipewire.linkGroups ? Pipewire.linkGroups.values : []
  readonly property var defaultSinkNode: Pipewire.defaultAudioSink
  readonly property var defaultSourceNode: Pipewire.defaultAudioSource

  // Primitive snapshots only: PipeWire deletes and reuses nodes while running,
  // so live PwNode QObjects are never held in a Repeater model.
  property var sinks: []
  property var sources: []
  property var playbackStreams: []
  property var captureStreams: []
  property var defaultSink: null
  property var defaultSource: null

  // Structured graph data for the canvas, refreshed on demand.
  property var graph: ({ nodes: [], links: [], managed: [] })
  property string pendingAction: ""
  property string errorText: ""
  property string statusText: ""
  property var selectedStream: null

  property bool popupOpen: false
  property bool graphOpen: false

  readonly property string helperPath: decodeURIComponent(
    Qt.resolvedUrl("bin/piperoute-ctl").toString().replace(/^file:\/\//, ""))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Component.onCompleted: resnapshot()
  onPwNodesChanged: { resnapshot(); scheduleGraphRefresh() }
  onPwLinksChanged: { resnapshot(); scheduleGraphRefresh() }
  onDefaultSinkNodeChanged: resnapshot()
  onDefaultSourceNodeChanged: resnapshot()

  function resnapshot() {
    defaultSink = Model.row(root.defaultSinkNode)
    defaultSource = Model.row(root.defaultSourceNode)

    var pb = Model.rows(root.pwNodes, "playback")
    for (var i = 0; i < pb.length; i++)
      pb[i].route = Model.routeOf(root.pwLinks, pb[i].id, "playback") || defaultSink

    var cap = Model.rows(root.pwNodes, "capture")
    for (var j = 0; j < cap.length; j++)
      cap[j].route = Model.routeOf(root.pwLinks, cap[j].id, "capture") || defaultSource

    sinks = Model.rows(root.pwNodes, "sink")
    sources = Model.rows(root.pwNodes, "source")
    playbackStreams = pb
    captureStreams = cap

    if (selectedStream && !hasStream(selectedStream.id)) selectedStream = null
  }

  function hasStream(id) {
    var all = playbackStreams.concat(captureStreams)
    for (var i = 0; i < all.length; i++) if (all[i].id === Number(id)) return true
    return false
  }

  function statusLine() {
    if (!Pipewire.ready) return strings.t("status.connecting")
    var out = defaultSink ? defaultSink.label : strings.t("status.none")
    var input = defaultSource ? defaultSource.label : strings.t("status.none")
    var streams = playbackStreams.length + captureStreams.length
    return strings.t("status.output").arg(out) + " · " +
      strings.t("status.input").arg(input) + " · " +
      strings.t("status.streams").arg(streams)
  }

  function runCtl(action, args) {
    if (ctl.running) return
    pendingAction = action
    if (action === "graph") root.lastGraphRefreshMs = Date.now()
    statusText = strings.t("busy")
    errorText = ""
    ctl.command = [helperPath, action].concat(args)
    ctl.start()
  }

  function refreshGraph() { runCtl("graph", []) }

  readonly property bool graphBusy: graphLoader.item ? graphLoader.item.dragging : false
  property double lastGraphRefreshMs: 0

  // Topology changes arrive as native Pipewire events. Debounce them so a
  // burst of node/link changes causes one graph read, not one per signal, and
  // keep automatic reads to at most one per second. A refresh mid-drag would
  // replace the node the pointer is holding.
  function scheduleGraphRefresh() {
    if (!(root.graphOpen || root.popupOpen) || root.graphBusy) return
    var wait = Math.max(200, 1000 - (Date.now() - root.lastGraphRefreshMs))
    graphDebounce.interval = wait
    graphDebounce.restart()
  }

  function takeGraph(text) {
    var data
    try { data = JSON.parse(text) }
    catch (e) { errorText = strings.t("badGraph"); return }
    if (!data || !Array.isArray(data.nodes) || !Array.isArray(data.links)) {
      errorText = strings.t("badGraph")
      return
    }
    var managed = []
    if (Array.isArray(data.managed)) {
      for (var i = 0; i < data.managed.length && managed.length < 64; i++) {
        var m = data.managed[i]
        if (!m || typeof m !== "object") continue
        managed.push({
          id: String(m.id || "").slice(0, 20),
          description: Model.safeLabel(m.description || m.name, 100),
          "class": Model.safeLabel(m["class"], 60)
        })
      }
    }
    graph = {
      nodes: data.nodes.slice(0, 64),
      links: data.links.slice(0, 128),
      managed: managed
    }
    if (graphLoader.item) graphLoader.item.applyGraph(graph)
  }

  function finish(result) {
    var action = pendingAction
    if (result.state !== "ok") {
      var detail = String(result.reason || result.stdout || "").slice(0, 200)
      errorText = result.state + (detail ? ": " + detail : "")
      statusText = strings.t("ready")
      return
    }
    if (action === "graph") {
      root.lastGraphRefreshMs = Date.now()
      takeGraph(String(result.stdout || ""))
      // takeGraph leaves errorText set when the payload was unusable.
      if (errorText === "") statusText = strings.t("ready")
      return
    }
    if (action === "create-node") {
      var parts = String(result.stdout || "").trim().split(/\s+/)
      statusText = parts.length >= 3
        ? strings.t("created").arg(parts[2]) : strings.t("createdGeneric")
    } else {
      statusText = strings.t("ready")
    }
    errorText = ""
    // Re-read so the managed list and canvas show the new topology at once.
    if (root.popupOpen || root.graphOpen) scheduleGraphRefresh()
  }

  function setDefaultSink(row) {
    if (!row) return
    var node = Model.nodeById(root.pwNodes, row.id)
    if (node) Pipewire.preferredDefaultAudioSink = node
    runCtl("default", [String(row.id)])
  }

  function setDefaultSource(row) {
    if (!row) return
    var node = Model.nodeById(root.pwNodes, row.id)
    if (node) Pipewire.preferredDefaultAudioSource = node
    runCtl("default", [String(row.id)])
  }

  function chooseStream(row) {
    selectedStream = (selectedStream && selectedStream.id === row.id) ? null : row
  }

  function moveStream(target) {
    if (!selectedStream || !target) return
    runCtl(selectedStream.kind === "playback" ? "move-output" : "move-input",
      [String(selectedStream.id), target.name])
    selectedStream = null
  }

  function openGraph() {
    popupOpen = false
    graphOpen = true
    statusText = ""
    errorText = ""
    refreshGraph()
  }

  function closeGraph() { graphOpen = false }

  function close() { popupOpen = false }

  Run {
    id: ctl
    command: []
    deadlineMs: 12000
    // pw-dump on a busy graph is larger than the block's 64 KiB default, and
    // a truncated JSON document would make the canvas fail to parse. The
    // helper also caps what it emits (MAX_GRAPH_BYTES).
    maxBytes: 8388608
    keepBytes: 1048576
    onFinished: result => root.finish(result)
  }

  Connections {
    target: Pipewire.nodes
    function onValuesChanged() { root.resnapshot(); root.scheduleGraphRefresh() }
  }
  Connections {
    target: Pipewire.linkGroups
    function onValuesChanged() { root.scheduleGraphRefresh() }
  }

  Timer {
    id: graphDebounce
    interval: 200
    repeat: false
    onTriggered: {
      if ((root.graphOpen || root.popupOpen) && !ctl.running && !root.graphBusy)
        root.refreshGraph()
    }
  }

  // Safety net for changes the native PipeWire model does not signal (for
  // example a new null sink made by another client). The event path above is
  // what makes ordinary changes appear immediately.
  Timer {
    interval: 5000
    repeat: true
    running: root.popupOpen || root.graphOpen
    onTriggered: if (!ctl.running) root.refreshGraph()
  }

  Loader {
    id: graphLoader
    source: Qt.resolvedUrl("GraphCanvas.qml")
    onLoaded: {
      item.screen = Qt.binding(function() { return root.QsWindow.window ? root.QsWindow.window.screen : null })
      item.opened = Qt.binding(function() { return root.graphOpen })
      item.statusText = Qt.binding(function() { return root.statusText })
      item.errorText = Qt.binding(function() { return root.errorText })
      item.applyGraph(root.graph)
    }
    Connections {
      target: graphLoader.item
      function onCloseRequested() { root.closeGraph() }
      function onRefreshRequested() { root.refreshGraph() }
      function onActionRequested(action, args) { root.runCtl(action, args) }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "󰌘" : ("󰌘 " + (root.defaultSink ? root.defaultSink.short : "…"))
    tooltipText: root.statusLine() + "\n" + strings.t("tooltip")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.openGraph()
      else if (mouseButton === Qt.RightButton) {
        root.graphOpen = false
        root.errorText = ""
        root.popupOpen = !root.popupOpen
        if (root.popupOpen) root.refreshGraph()
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(420)
    contentHeight: popup.fittedContentHeight(Math.min(620, column.implicitHeight))

    Flickable {
      id: scroller
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: column.implicitHeight
      focus: true

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
      }

      Column {
        id: column
        width: scroller.width
        spacing: Style.space(3)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("title")
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.statusText + (root.errorText ? "  ·  " + root.errorText : "")
          color: root.errorText ? Commons.Color.accent : Qt.darker(Commons.Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          width: parent.width
          iconText: "󰌘"
          text: strings.t("action.openGraph")
          onClicked: root.openGraph()
        }

        PanelSectionHeader {
          width: parent.width
          text: strings.t("section.managed").arg(root.graph.managed ? root.graph.managed.length : 0)
        }
        Repeater {
          model: root.graph.managed || []
          delegate: Item {
            width: scroller.width
            height: Math.max(nodeText.implicitHeight, removeBtn.implicitHeight)
            Text {
              id: nodeText
              anchors.left: parent.left
              anchors.right: removeBtn.left
              anchors.rightMargin: Style.space(4)
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: modelData.description + "  (" + modelData["class"] + ")"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Button {
              id: removeBtn
              anchors.right: parent.right
              iconText: "󰅙"
              tooltipText: strings.t("action.destroy")
              onClicked: root.runCtl("destroy", [modelData.id])
            }
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(4)
          Button {
            text: strings.t("action.createSink")
            onClicked: root.runCtl("create-node", ["sink"])
          }
          Button {
            text: strings.t("action.createSource")
            onClicked: root.runCtl("create-node", ["source"])
          }
        }

        PanelSectionHeader { width: parent.width; text: strings.t("section.outputs") }
        Repeater {
          model: root.sinks
          delegate: Button {
            width: scroller.width
            leftAlign: true
            iconText: "󰓃"
            text: modelData.label
            selected: root.defaultSink && root.defaultSink.id === modelData.id
            onClicked: root.setDefaultSink(modelData)
          }
        }

        PanelSectionHeader { width: parent.width; text: strings.t("section.inputs") }
        Repeater {
          model: root.sources
          delegate: Button {
            width: scroller.width
            leftAlign: true
            iconText: "󰍬"
            text: modelData.label
            selected: root.defaultSource && root.defaultSource.id === modelData.id
            onClicked: root.setDefaultSource(modelData)
          }
        }

        PanelSectionHeader { width: parent.width; text: strings.t("section.playback") }
        Repeater {
          model: root.playbackStreams
          delegate: Button {
            width: scroller.width
            leftAlign: true
            iconText: "󱀞"
            text: modelData.label + "  →  " + (modelData.route ? modelData.route.label : strings.t("status.none"))
            selected: root.selectedStream && root.selectedStream.id === modelData.id
            onClicked: root.chooseStream(modelData)
          }
        }

        PanelSectionHeader { width: parent.width; text: strings.t("section.capture") }
        Repeater {
          model: root.captureStreams
          delegate: Button {
            width: scroller.width
            leftAlign: true
            iconText: "󰍬"
            text: modelData.label + "  ←  " + (modelData.route ? modelData.route.label : strings.t("status.none"))
            selected: root.selectedStream && root.selectedStream.id === modelData.id
            onClicked: root.chooseStream(modelData)
          }
        }

        PanelSectionHeader {
          width: parent.width
          visible: root.selectedStream !== null
          text: root.selectedStream ? strings.t("section.routeTo").arg(root.selectedStream.label) : ""
        }
        Repeater {
          model: root.selectedStream && root.selectedStream.kind === "playback" ? root.sinks : root.sources
          delegate: Button {
            width: scroller.width
            leftAlign: true
            iconText: root.selectedStream && root.selectedStream.kind === "playback" ? "󰓃" : "󰍬"
            text: modelData.label
            onClicked: root.moveStream(modelData)
          }
        }
      }
    }
  }
}
