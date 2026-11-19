#!/usr/bin/python3
"""Pure tests for the control helper: no live routing is changed."""
import importlib.machinery
import importlib.util
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
assert ctl.PORT_RE.match("UMC 192k: capture_AUX0")
assert not ctl.PORT_RE.match("port\nwpctl set-default 1")
assert not ctl.PORT_RE.match("$(whoami)")
assert len(ctl.safe_text("A" * 500)) <= 240
assert "<" not in ctl.safe_text("<script>alert(1)</script>")
assert "&" not in ctl.safe_text("a & b")

# Port/link parsing from pw-link -l -I, including the duplicated reverse view.
ports = ctl.parse_ports("  45 node:monitor_FL\n  81 node:playback_AUX0\n")
assert [p["id"] for p in ports] == ["45", "81"]
assert ports[0]["name"] == "node:monitor_FL"

link_dump = """  81 UMC:playback_AUX0
 113   |<-  114 Brave:output_FL
 114 Brave:output_FL
 113   |->   81 UMC:playback_AUX0
  57 UMC:playback_AUX1
  96   |<-   95 Brave:output_FR
"""
links = ctl.parse_links(link_dump)
assert len(links) == 2, links
assert links[0]["id"] == "113"
assert links[0]["out"] == "Brave:output_FL"
assert links[0]["in"] == "UMC:playback_AUX0"
assert links[1]["id"] == "96"

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

print("control-helper tests passed")
