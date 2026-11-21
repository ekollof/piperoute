# PipeRoute

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

A **graphical PipeWire patchbay** bar widget, in the spirit of qpwgraph and
Carla. It shows the live PipeWire graph as boxes and cables on a full-screen
canvas and lets you edit it by dragging. No daemon, config file or manual setup
of its own.

Kinds: `bar-widget`

## What it does

The bar button shows the routing glyph `󰌘` and the current default output.
Its tooltip summarises default output, default input and stream count.
**Left click opens the graphical patchbay; right click opens a compact menu**
for defaults, stream routing and virtual devices.

### Graphical patchbay (left click)

A full-screen canvas on the monitor you clicked, with:

- **Nodes** — one box per audio node. Playback streams are on the left, virtual
  devices in the middle, hardware devices on the right. Each box lists its
  input ports on the left edge and output ports on the right edge.
- **Cables** — bezier curves drawn between the ports that are actually linked
  in PipeWire. They follow the nodes when you move them.
- **Drag an output port onto an input port** to create a link. A dashed cable
  follows the cursor while you drag, and the bottom edge names the port under
  the cursor.
- **Drag a node by its title bar** to rearrange the canvas.
- **Click the × at a cable's midpoint** to remove that link.
- **Toolbar** — Refresh, `+ Virtual output`, `+ Virtual input`, Close. `R`
  refreshes, `Esc` closes. The canvas also refreshes automatically every few
  seconds while open.

Only audio nodes are shown; MIDI bridges and webcam video nodes stay out of
the way.

### Compact menu (right click)

- Create/remove virtual outputs and inputs.
- Set the default output and input.
- Route individual playback/capture streams to a chosen device.
- A shortcut button to open the graphical patchbay.

## How it interfaces with PipeWire

- Bar status and the compact menu use Quickshell's native
  `Quickshell.Services.Pipewire` module: `Pipewire.nodes`, `linkGroups`,
  `defaultAudioSink`/`defaultAudioSource`. Event-driven; no polling while
  closed.
- The canvas reads `pw-dump` for structured nodes, ports and links (including
  the exact port names and link ids), and writes with the installed PipeWire
  tools: `pw-link` to connect/disconnect ports, `pw-cli` to create/destroy
  virtual nodes, `wpctl` for defaults and `pactl` for moving streams.
- Every external value is validated, commands are spawned from argv (never a
  shell), and output is bounded. Node-derived text is sanitised before display
  (`Text.PlainText` everywhere). Live `PwNode` objects are never held by a
  visual delegate — only primitive snapshots — so graph teardowns cannot crash
  the shell.

All of these tools ship with a normal PipeWire/WirePlumber install.

## Requirements

- Omarchy 4 with the Quattro shell and plugin support.
- A running PipeWire session with WirePlumber, `pw-dump`, `pw-link`, `pw-cli`,
  `wpctl` and `pactl` on `PATH` (the standard Omarchy setup).

## Installation

This plugin lives in `~/.config/omarchy/plugins/io.github.ekollof.piperoute`.
To put it on the bar:

```bash
omarchy bar put io.github.ekollof.piperoute --section right
```

## Validation and tests

```bash
./tests/run
omarchy plugin validate .
omarchy agent look plugin .
```

`tests/test_model.js` covers markup-shaped node names, node classification and
routing direction; `tests/test_ctl.py` covers input validation and the
structured graph builder that feeds the canvas.

## Removal

```bash
omarchy plugin remove io.github.ekollof.piperoute
```

The plugin keeps no state of its own. Virtual devices it created remain in the
PipeWire graph until removed (with the canvas toolbar, the compact menu, or
`pw-cli destroy`).

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Commands go
through the omakit `Run` block with a hard deadline, bounded output and a
closed environment. No secrets, credentials or network access are involved.

## License

MIT © 2026 Emiel Kollof
