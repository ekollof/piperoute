# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.3.x | yes |
| earlier | no |

Security fixes are released on the latest `main` and tagged version.

## Report a vulnerability

Use GitHub's private vulnerability reporting for this repository:

https://github.com/ekollof/piperoute/security/advisories/new

Do not open a public issue, pull request, or discussion for a suspected
vulnerability.

Please include:

- the affected version or commit;
- the file or behaviour involved;
- reproduction steps or a minimal proof of concept;
- the impact you believe it has.

Do not include credentials, tokens, personal data, or third-party secrets.
We aim to acknowledge a report within 7 days and to agree a disclosure
timeline with you. Please allow a reasonable window for a fix and release
before public disclosure.

## Scope

In scope:

- the QML in this repository: the bar widget, the graph canvas and the
  compact menu;
- `bin/piperoute-ctl` and its argument handling;
- the vendored omakit `Run` block;
- process execution, environment construction and output bounds;
- handling of PipeWire-provided node, port and error text;
- resource exhaustion or denial of service caused by the plugin.

Out of scope:

- another process running as the same local user changing that user's own
  PipeWire graph. Such a process can invoke `pw-link`, `pw-cli`, `wpctl` or
  `pactl` directly and gains no authority from this plugin.
- a compromised user account, session, shell or plugin checkout;
- vulnerabilities in PipeWire, WirePlumber, Quickshell or Omarchy itself;
- the marketplace's automated baseline results, which are limited static
  checks and not a security review.

## Security model

The plugin runs as unsandboxed QML inside `omarchy-shell` and executes one
helper. It:

- never requests elevated privileges and never invokes privilege-escalation
  tools;
- starts only `bin/piperoute-ctl`, through the omakit `Run` block, with argv,
  a closed environment, a hard deadline and byte/line caps;
- invokes only the installed PipeWire tools `pw-dump`, `pw-link`, `pw-cli`,
  `wpctl` and `pactl`, also with argv;
- creates links from the exact PipeWire port ids selected on the canvas, never
  by textual port name, so two clients exposing identical names cannot be
  confused;
- never uses a shell, downloads or executes remote code, opens a socket, or
  makes a network request;
- keeps no settings, cache or credential files;
- treats PipeWire-provided text as untrusted: bounded, sanitised and rendered
  with `Text.PlainText`.

The helper is a user-level script. Any process running as the same user can
execute it, exactly as it can execute the underlying PipeWire tools. The
plugin adds no privilege boundary and does not claim one.

## Dependencies

The plugin ships no binaries and installs no packages. It relies on:

- the PipeWire and WirePlumber command-line tools already present on Omarchy;
- `/usr/bin/python3` for the small control helper;
- Quickshell and the Omarchy shell components.

## Removal

`omarchy plugin remove io.github.ekollof.piperoute` deletes the plugin
directory. Nothing else is installed. Virtual PipeWire nodes created from the
canvas are ordinary PipeWire objects; remove any that remain with the canvas
toolbar or `pw-cli destroy`.

## Disclosure

Confirmed issues are fixed in a new commit, noted in the release notes where
appropriate, and disclosed through the private advisory once a fix is
available. This policy is not a security audit, certification, warranty or
endorsement.
