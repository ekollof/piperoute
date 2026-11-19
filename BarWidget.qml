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

  // Native, event-driven reads of the running PipeWire graph. No polling for
  // the bar label or the Devices tab; Quickshell is already a PipeWire client.
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

  // Patchbay data comes from the helper (pw-link/pw-dump) and is refreshed on
  // demand while the card is open, since links are not exposed by Quickshell.
  property var graph: ({ outputs: [], inputs: [], links: [], nodes: [] })
  property string tab: "patch"
  property string pendingAction: ""
  property var selectedOutputPort: null
  property var selectedStream: null
  property string errorText: ""
  property string statusText: ""

  property bool popupOpen: false

  readonly property string helperPath: decodeURIComponent(
    Qt.resolvedUrl("bin/piperoute-ctl").toString().replace(/^file:\/\//, ""))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Component.onCompleted: resnapshot()
  onPwNodesChanged: resnapshot()
  onPwLinksChanged: resnapshot()
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
    statusText = strings.t("busy")
    errorText = ""
    ctl.command = [helperPath, action].concat(args)
    ctl.start()
  }

  function refreshGraph() { runCtl("graph", []) }

  function boundRows(list, cap, withExtras) {
    var values = Array.isArray(list) ? list : []
    var out = []
    for (var i = 0; i < values.length && out.length < cap; i++) {
      var item = values[i]
      if (!item || typeof item !== "object") continue
      var row = {
        id: String(item.id === undefined || item.id === null ? "" : item.id).slice(0, 20),
        name: Model.safeLabel(item.name, 200)
      }
      if (withExtras) {
        row.out = Model.safeLabel(item.out, 200)
        row["in"] = Model.safeLabel(item["in"], 200)
        row.description = Model.safeLabel(item.description, 120)
        row.mediaClass = Model.safeLabel(item["class"], 60)
      }
      out.push(row)
    }
    return out
  }

  function takeGraph(text) {
    var data
    try { data = JSON.parse(text) }
    catch (e) { errorText = strings.t("badGraph"); return }
    if (!data || !Array.isArray(data.outputs) || !Array.isArray(data.inputs)
        || !Array.isArray(data.links) || !Array.isArray(data.nodes)) {
      errorText = strings.t("badGraph")
      return
    }
    graph = {
      outputs: boundRows(data.outputs, 200, false),
      inputs: boundRows(data.inputs, 200, false),
      links: boundRows(data.links, 200, true),
      nodes: boundRows(data.nodes, 64, true)
    }
    if (selectedOutputPort && !findPort(graph.outputs, selectedOutputPort.id))
      selectedOutputPort = null
  }

  function findPort(list, id) {
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  function finish(result) {
    if (result.state !== "ok") {
      var detail = String(result.reason || result.stdout || "").slice(0, 200)
      errorText = result.state + (detail ? ": " + detail : "")
      statusText = strings.t("ready")
      return
    }
    if (pendingAction === "graph") takeGraph(String(result.stdout || ""))
    else if (pendingAction === "create-node") {
      var parts = String(result.stdout || "").trim().split(/\s+/)
      statusText = parts.length >= 3
        ? strings.t("created").arg(parts[2]) : strings.t("createdGeneric")
    }
    statusText = statusText === strings.t("busy") ? strings.t("ready") : statusText
    if (pendingAction !== "graph") refreshGraph()
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

  function connectPort(inputPort) {
    if (!selectedOutputPort || !inputPort) return
    runCtl("connect", [selectedOutputPort.name, inputPort.name])
    selectedOutputPort = null
  }

  function open() {
    tab = "patch"
    selectedOutputPort = null
    selectedStream = null
    errorText = ""
    statusText = ""
    popupOpen = true
    refreshGraph()
  }

  function close() { popupOpen = false }

  Run {
    id: ctl
    command: []
    deadlineMs: 12000
    onFinished: result => root.finish(result)
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.popupOpen && !ctl.running
    onTriggered: root.refreshGraph()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "󰌘" : ("󰌘 " + (root.defaultSink ? root.defaultSink.short : "…"))
    tooltipText: root.statusLine() + "\n" + strings.t("tooltip")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        if (root.popupOpen) root.close()
        else root.open()
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(520)
    contentHeight: popup.fittedContentHeight(Math.min(680, body.implicitHeight))

    Flickable {
      id: scroller
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: body.implicitHeight
      focus: true

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
      }

      Column {
        id: body
        width: scroller.width
        spacing: Style.space(3)

        Row {
          width: parent.width
          spacing: Style.space(4)
          Button {
            text: strings.t("tab.patch")
            selected: root.tab === "patch"
            onClicked: { root.tab = "patch"; if (root.graph.links.length === 0) root.refreshGraph() }
          }
          Button {
            text: strings.t("tab.virtual")
            selected: root.tab === "virtual"
            onClicked: root.tab = "virtual"
          }
          Button {
            text: strings.t("tab.devices")
            selected: root.tab === "devices"
            onClicked: root.tab = "devices"
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: (root.statusText || strings.t("ready")) +
            (root.errorText ? "  ·  " + root.errorText : "")
          color: root.errorText ? Commons.Color.accent : Qt.darker(Commons.Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---------------- Patchbay ----------------
        Column {
          width: parent.width
          visible: root.tab === "patch"
          spacing: Style.space(3)

          PanelSectionHeader {
            width: parent.width
            text: strings.t("section.links").arg(root.graph.links.length)
          }
          Repeater {
            model: root.graph.links
            delegate: Item {
              width: scroller.width
              height: Math.max(linkText.implicitHeight, disconnectBtn.implicitHeight)
              Text {
                id: linkText
                anchors.left: parent.left
                anchors.right: disconnectBtn.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - disconnectBtn.width - Style.space(4)
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                wrapMode: Text.NoWrap
                text: modelData.out + "  →  " + modelData["in"]
                color: Commons.Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Button {
                id: disconnectBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅙"
                tooltipText: strings.t("action.disconnect")
                onClicked: root.runCtl("disconnect", [modelData.id])
              }
            }
          }
          Text {
            width: parent.width
            visible: root.graph.links.length === 0
            textFormat: Text.PlainText
            text: strings.t("noLinks")
            color: Qt.darker(Commons.Color.popups.text, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          PanelSectionHeader {
            width: parent.width
            text: root.selectedOutputPort
              ? strings.t("section.chooseInput").arg(root.selectedOutputPort.name)
              : strings.t("section.chooseOutput")
          }
          Repeater {
            model: root.selectedOutputPort ? root.graph.inputs : root.graph.outputs
            delegate: Button {
              width: scroller.width
              leftAlign: true
              iconText: root.selectedOutputPort ? "󰌘" : "󰁧"
              text: modelData.name
              onClicked: {
                if (root.selectedOutputPort) root.connectPort(modelData)
                else root.selectedOutputPort = modelData
              }
            }
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.selectedOutputPort ? strings.t("hint.connect") : strings.t("hint.patch")
            color: Qt.darker(Commons.Color.popups.text, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------------- Virtual devices ----------------
        Column {
          width: parent.width
          visible: root.tab === "virtual"
          spacing: Style.space(3)

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
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("hint.virtual")
            color: Qt.darker(Commons.Color.popups.text, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          PanelSectionHeader {
            width: parent.width
            text: strings.t("section.managed").arg(root.graph.nodes.length)
          }
          Repeater {
            model: root.graph.nodes
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
                wrapMode: Text.NoWrap
                text: modelData.description + "  (" + modelData.mediaClass + ")"
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
          Text {
            width: parent.width
            visible: root.graph.nodes.length === 0
            textFormat: Text.PlainText
            text: strings.t("noNodes")
            color: Qt.darker(Commons.Color.popups.text, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---------------- Devices / streams ----------------
        Column {
          width: parent.width
          visible: root.tab === "devices"
          spacing: Style.space(3)

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
}
