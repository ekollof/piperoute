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

  // Read the live PipeWire graph directly. No helper daemon, config file or
  // manual setup: Quickshell is already a PipeWire client like any other app.
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var pwLinks: Pipewire.linkGroups ? Pipewire.linkGroups.values : []
  readonly property var defaultSinkNode: Pipewire.defaultAudioSink
  readonly property var defaultSourceNode: Pipewire.defaultAudioSource

  // Plain primitives only. PipeWire deletes and reuses nodes while it runs,
  // so live PwNode QObjects are never kept in a Repeater model.
  property var sinks: []
  property var sources: []
  property var playbackStreams: []
  property var captureStreams: []
  property var defaultSink: null
  property var defaultSource: null

  property bool popupOpen: false
  property var selectedStream: null
  property string errorText: ""

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

  function glyph() { return "󰌘" } // md-lan-connect

  function statusLine() {
    if (!Pipewire.ready) return strings.t("status.connecting")
    var out = defaultSink ? defaultSink.label : strings.t("status.none")
    var input = defaultSource ? defaultSource.label : strings.t("status.none")
    var streams = playbackStreams.length + captureStreams.length
    return strings.t("status.output").arg(out) + " · " +
      strings.t("status.input").arg(input) + " · " +
      strings.t("status.streams").arg(streams)
  }

  function runCtl(args) {
    if (action.running) return
    action.command = [helperPath].concat(args)
    errorText = ""
    action.start()
  }

  function setDefaultSink(row) {
    if (!row) return
    var node = Model.nodeById(root.pwNodes, row.id)
    if (node) Pipewire.preferredDefaultAudioSink = node
    runCtl(["default", String(row.id)])
  }

  function setDefaultSource(row) {
    if (!row) return
    var node = Model.nodeById(root.pwNodes, row.id)
    if (node) Pipewire.preferredDefaultAudioSource = node
    runCtl(["default", String(row.id)])
  }

  function chooseStream(row) {
    selectedStream = (selectedStream && selectedStream.id === row.id) ? null : row
  }

  function moveStream(target) {
    if (!selectedStream || !target) return
    var verb = selectedStream.kind === "playback" ? "move-output" : "move-input"
    runCtl([verb, String(selectedStream.id), target.name])
    selectedStream = null
  }

  function close() { popupOpen = false }

  Run {
    id: action
    command: []
    deadlineMs: 10000
    onFinished: result => {
      if (result.state === "ok") { errorText = ""; return }
      var detail = String(result.reason || result.stdout || "").slice(0, 200)
      errorText = result.state + (detail ? ": " + detail : "")
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.glyph() : (root.glyph() + " " + (root.defaultSink ? root.defaultSink.short : "…"))
    tooltipText: root.statusLine()
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        root.selectedStream = null
        root.errorText = ""
        root.popupOpen = !root.popupOpen
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(360)
    contentHeight: popup.fittedContentHeight(Math.min(560, column.implicitHeight))

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
        spacing: Style.space(4)

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
          text: root.statusLine()
          color: Qt.darker(Commons.Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.errorText !== ""
          textFormat: Text.PlainText
          text: root.errorText
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
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
          text: root.selectedStream
            ? strings.t("section.routeTo").arg(root.selectedStream.label) : ""
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

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("hint")
          color: Qt.darker(Commons.Color.popups.text, 1.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          topPadding: Style.space(4)
        }
      }
    }
  }
}
