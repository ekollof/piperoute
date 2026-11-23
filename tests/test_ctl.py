#!/usr/bin/python3
"""Pure tests for the control helper: no live routing is changed."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CTL = os.path.join(HERE, "..", "bin", "piperoute-ctl")
loader = importlib.machinery.SourceFileLoader("piperoute_ctl", CTL)
spec = importlib.util.spec_from_loader(loader.name, loader)
ctl = importlib.util.module_from_spec(spec)
loader.exec_module(ctl)

# External values are validated before they can reach an argv.
assert ctl.ID_RE.match("12345")
assert not ctl.ID_RE.match("1;wpctl set-default 80")
assert not ctl.ID_RE.match("-1")
assert ctl.ENDPOINT_RE.match("alsa_output.usb-UMC-00.pro-output-0")
assert not ctl.ENDPOINT_RE.match("sink;rm -rf /")
assert ctl.MANAGED_RE.match("pr_test_a1b2")
assert not ctl.MANAGED_RE.match("alsa_output.usb-UMC")
assert len(ctl.safe_text("A" * 500)) <= 240
assert "<" not in ctl.safe_text("<script>alert(1)</script>")
assert "&" not in ctl.safe_text("a & b")
assert "'" in ctl.safe_text("Logitech's Mic")
assert ctl.safe_text('"studio"') == '"studio"'

# Structured graph building from a pw-dump-shaped object list.
dump = [
    {"id": 10, "type": "PipeWire:Interface:Node", "info": {"props": {
        "node.name": "alsa_output.usb-UMC", "node.description": "UMC 404HD",
        "media.class": "Audio/Sink"}}},
    {"id": 11, "type": "PipeWire:Interface:Node", "info": {"props": {
        "node.name": "Brave", "media.class": "Stream/Output/Audio"}}},
    {"id": 12, "type": "PipeWire:Interface:Node", "info": {"props": {
        "node.name": "Midi-Bridge", "media.class": "Midi/Bridge"}}},
    {"id": 14, "type": "PipeWire:Interface:Node", "info": {"props": {
        "node.name": "webcam", "media.class": "Video/Source"}}},
    {"id": 15, "type": "PipeWire:Interface:Node", "info": {"props": {
        "node.name": "bluez_midi.server", "node.description": "BLE MIDI 1",
        "media.class": "Midi/Bridge"}}},
    {"id": 20, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 10, "port.name": "playback_FL", "port.direction": "in"}}},
    {"id": 21, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 10, "port.name": "monitor_FL", "port.direction": "out"}}},
    {"id": 22, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 11, "port.name": "output_FL", "port.direction": "out"}}},
    {"id": 23, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 12, "port.name": "Midi Through: Port-0 (capture)",
        "object.path": "alsa:seq:default:client_14:capture_0",
        "port.direction": "out"}}},
    {"id": 26, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 12, "port.name": "UMC404HD 192k: MIDI 1 (playback)",
        "object.path": "alsa:seq:default:client_16:playback_0",
        "port.direction": "in"}}},
    {"id": 27, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 15, "port.name": "in", "port.direction": "in"}}},
    {"id": 28, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 15, "port.name": "out", "port.direction": "out"}}},
    {"id": 25, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": 14, "port.name": "capture_1", "port.direction": "out"}}},
    {"id": 30, "type": "PipeWire:Interface:Link", "info": {"props": {
        "link.output.port": 22, "link.input.port": 20}}},
]
graph = ctl.build_graph(dump)
by_name = {n["name"]: n for n in graph["nodes"]}
assert set(by_name) == {
    "alsa_output.usb-UMC", "Brave", "14:Midi Through", "16:UMC404HD 192k", "bluez_midi.server"
}, by_name.keys()
assert "webcam" not in by_name, "video nodes stay out of the patchbay"
assert "Midi-Bridge" not in by_name, "the bridge is split into per-client boxes"
assert by_name["Brave"]["kind"] == "stream"
assert by_name["14:Midi Through"]["kind"] == "midi"
assert by_name["14:Midi Through"]["outputs"][0]["name"] == "Midi-Bridge:Midi Through: Port-0 (capture)"
assert by_name["16:UMC404HD 192k"]["inputs"][0]["name"] == "Midi-Bridge:UMC404HD 192k: MIDI 1 (playback)"
assert by_name["bluez_midi.server"]["label"] == "BLE MIDI 1"
assert by_name["bluez_midi.server"]["outputs"][0]["name"] == "bluez_midi.server:out"
assert by_name["alsa_output.usb-UMC"]["label"] == "UMC 404HD"
assert by_name["Brave"]["outputs"][0]["name"] == "Brave:output_FL"
assert by_name["alsa_output.usb-UMC"]["inputs"][0]["name"] == "alsa_output.usb-UMC:playback_FL"
assert graph["links"] == [{"id": "30", "out": "22", "in": "20"}]
assert graph["managed"] == []
assert ctl.port_by_id(dump, "20")["port.direction"] == "in"
assert ctl.port_by_id(dump, "22")["port.direction"] == "out"
assert ctl.port_by_id(dump, "999") is None

# Connecting addresses the exact port ids from the canvas, never textual
# names. Two clients may expose identical names; the id still selects one.
original_dump = ctl.dump_json
original_run = ctl.run
calls = []
ctl.dump_json = lambda: (dump, "")
ctl.run = lambda argv: (calls.append(argv) or (True, "", ""))
assert ctl.cmd_connect(["22", "20"]) == 0
assert calls[-1] == [ctl.PW_LINK, "22", "20"]
with contextlib.redirect_stdout(io.StringIO()):
    assert ctl.cmd_connect(["20", "22"]) == 1, "input-to-input is refused"
    assert ctl.cmd_connect(["999", "20"]) == 1, "unknown port is refused"
    assert ctl.cmd_connect(["Brave:output_FL", "alsa_output:playback_FL"]) == 1, "names are refused"
assert len(calls) == 1, "only the valid pair reached pw-link"
ctl.dump_json = original_dump
ctl.run = original_run

# A node this plugin created is reported as managed and tagged as virtual.
dump.append({"id": 13, "type": "PipeWire:Interface:Node", "info": {"props": {
    "node.name": "pr_node_abcd", "media.class": "Audio/Sink",
    "node.description": "pr_node_abcd"}}})
dump.append({"id": 24, "type": "PipeWire:Interface:Port", "info": {"props": {
    "node.id": 13, "port.name": "playback_FL", "port.direction": "in"}}})
managed_graph = ctl.build_graph(dump)
assert managed_graph["managed"][0]["name"] == "pr_node_abcd"
assert any(n["kind"] == "virtual" for n in managed_graph["nodes"])

# Bounded parsing of a pactl dump and the object.id -> index mapping.
pactl_raw = """Sink Input #128451
\tDriver: PipeWire
\tProperties:
\t\tapplication.name = "Brave"
\t\tnode.name = "Brave"
\t\tobject.id = "111"

Sink Input #128452
\tProperties:
\t\tnode.name = "Other"
\t\tobject.id = "222"
"""
blocks = ctl.pactl_blocks(pactl_raw, "Sink Input #")
assert [b["index"] for b in blocks] == ["128451", "128452"]
assert ctl.block_prop(blocks[0], "object.id") == "111"
assert ctl.block_prop(blocks[0], "application.name") == "Brave"

huge = "Sink Input #1\n" + ("x\n" * 10000)
assert len(ctl.pactl_blocks(huge, "Sink Input #")[0]["lines"]) <= 4000

# A pathological graph stays bounded: the canvas payload can never exceed what
# the Run block keeps, and no node carries an unbounded port list.
big = []
for node_id in range(200):
    big.append({"id": node_id, "type": "PipeWire:Interface:Node", "info": {"props": {
        "node.name": "node_%d" % node_id, "media.class": "Audio/Sink"}}})
    for port in range(60):
        big.append({"id": 1000 + node_id * 100 + port,
                    "type": "PipeWire:Interface:Port", "info": {"props": {
                        "node.id": node_id, "port.name": "p%d" % port,
                        "port.direction": "in" if port % 2 else "out"}}})
bounded = ctl.build_graph(big)
assert len(bounded["nodes"]) <= ctl.MAX_NODES
assert all(len(n["inputs"]) <= ctl.MAX_PORTS_PER_KIND for n in bounded["nodes"])
assert all(len(n["outputs"]) <= ctl.MAX_PORTS_PER_KIND for n in bounded["nodes"])
assert len(json.dumps(bounded)) < ctl.MAX_GRAPH_BYTES

print("control-helper tests passed")
