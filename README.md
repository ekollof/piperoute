# PipeRoute

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

An **advanced PipeWire audio routing** bar widget. It is a patchbay and virtual
device manager, not just an output picker: it reads and edits the live PipeWire
graph with no daemon, config file or manual setup of its own.

Kinds: `bar-widget`

## What it does

The bar button shows the routing glyph `󰌘` and the current default output.
Its tooltip summarises default output, default input and stream count.
Left-click opens the routing card with three tabs:

### Patch

- **Active links** — every PipeWire link currently in the graph, with an
  `×` button to remove any link.
- **Step 1 / Step 2** — pick any *output port* (an app's playback stream, a
  device's monitor, a virtual source capture port …), then any *input port*
  (a device's playback port, a stream's capture port …) to create a link
  between exactly those two ports. This is the same operation a desktop
  patchbay such as qpwgraph or Helvum performs.

### Virtual

- **+ Virtual output** creates a `support.null-audio-sink` output that apps can
  use as a destination, which you can then patch onward in the Patch tab.
- **+ Virtual input** creates a virtual `Audio/Source` that other apps can
  record from.
- Created devices are listed under **Virtual devices** with a remove button.
  Only nodes whose names start with `pr_` (created by this plugin) can be
  removed through the UI — hardware and application nodes are protected.

### Devices

- Set the **default output** and **default input** with a click.
- Route individual **playback / capture streams** to a chosen device.

## How it interfaces with PipeWire

- Bar status and the Devices tab use Quickshell's native
  `Quickshell.Services.Pipewire` module: `Pipewire.nodes`, `linkGroups`,
  `defaultAudioSink`/`defaultAudioSource`. This is event-driven; no polling
  process runs while the card is closed.
- Patchbay and virtual devices use the installed PipeWire tools through a
  narrow, validated helper (`bin/piperoute-ctl`): `pw-link` to list/connect/
  disconnect ports, `pw-cli` to create/destroy virtual nodes, `wpctl` for
  defaults and `pactl` for moving streams. The graph is refreshed on open,
  after every action, and every few seconds while the card is open.
- Every external value is validated, commands are spawned from argv (never a
  shell), and output is bounded. Node-derived text is sanitised before it is
  shown (`Text.PlainText` everywhere).

All of these tools ship with a normal PipeWire/WirePlumber install — nothing is
installed or configured by the plugin.

## Requirements

- Omarchy 4 with the Quattro shell and plugin support.
- A running PipeWire session with WirePlumber, `pw-link`, `pw-cli`, `pw-dump`,
  `wpctl` and `pactl` on `PATH` (the standard Omarchy setup).

## Installation

This plugin lives in `~/.config/omarchy/plugins/io.github.ekollof.piperoute`.
To put it on the bar:

```bash
omarchy bar put io.github.ekollof.piperoute --section right
```

It can also be opened from a keybinding or a script:

```bash
qs ipc call io.github.ekollof.piperoute toggle
```

## Validation and tests

```bash
./tests/run
omarchy plugin validate .
omarchy agent look plugin .
```

`tests/test_model.js` covers markup-shaped node names, node classification and
routing direction; `tests/test_ctl.py` covers input validation and bounded
parsing of `pw-link`/`pactl` output.

## Removal

```bash
omarchy plugin remove io.github.ekollof.piperoute
```

The plugin keeps no state of its own. Virtual devices it created remain in the
PipeWire graph until removed (in the Virtual tab or with `pw-cli destroy`).

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Commands go
through the omakit `Run` block with a hard deadline, bounded output and a
closed environment. No secrets, credentials or network access are involved.

## License

MIT © 2026 Emiel Kollof
