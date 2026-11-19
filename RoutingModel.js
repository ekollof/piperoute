/**
 * PipeRoute model helpers.
 *
 * PipeWire deletes and reuses nodes at any moment. A Repeater row that holds a
 * live PwNode QObject can dangle when that happens (the built-in audio panel
 * documents the resulting shell crash), so every row built here is a plain
 * primitive: id, name, label. Live nodes are resolved only when an action is
 * taken, and never stored in a model.
 */

var MAX_ROWS = 64
var MAX_LABEL = 80

/** Escape-safe label from untrusted node text: printable, single-line, bounded. */
function safeLabel(value, maxLen) {
  var limit = maxLen > 0 ? maxLen : MAX_LABEL
  var text = String(value === undefined || value === null ? "" : value)
  var out = ""
  for (var i = 0; i < text.length && out.length < limit; i++) {
    var ch = text.charAt(i)
    var code = text.charCodeAt(i)
    var allowed = (code >= 32 && code < 127) || code > 159
    if (!allowed) { out += " "; continue }
    // Markup-shaped input must never reach a tooltip or Text sink.
    if (ch === "<" || ch === ">" || ch === "&" || ch === '"' || ch === "'") out += " "
    else out += ch
  }
  return out.replace(/\s+/g, " ").trim().slice(0, limit)
}

/** Only the characters a PipeWire node name legitimately contains. */
function safeToken(value) {
  return String(value === undefined || null ? "" : value)
    .replace(/[^A-Za-z0-9._@-]/g, "")
    .slice(0, 200)
}

function nodeKind(node) {
  if (!node) return "unknown"
  if (node.isStream) return node.isSink ? "playback" : "capture"
  return node.isSink ? "sink" : "source"
}

function row(node) {
  if (!node || node.id === undefined || node.id === null) return null
  var label = safeLabel(node.description || node.nickname || node.name, MAX_LABEL)
  return {
    id: Number(node.id),
    name: safeToken(node.name),
    label: label || "PipeWire node " + Number(node.id),
    short: label.length > 16 ? label.slice(0, 15) + "…" : label,
    kind: nodeKind(node)
  }
}

function rows(nodes, wanted, max) {
  var values = nodes && nodes.length ? nodes : []
  var limit = max > 0 ? Math.min(max, MAX_ROWS) : MAX_ROWS
  var result = []
  for (var i = 0; i < values.length && result.length < limit; i++) {
    var r = row(values[i])
    if (r && r.kind === wanted) result.push(r)
  }
  return result
}

function nodeById(nodes, id) {
  var values = nodes && nodes.length ? nodes : []
  for (var i = 0; i < values.length; i++) {
    if (values[i] && Number(values[i].id) === Number(id)) return values[i]
  }
  return null
}

/**
 * Where a stream currently routes, as a primitive row.
 * playback: the stream produces audio, the sink consumes it (group.source = stream)
 * capture:  the source produces audio, the stream consumes it (group.target = stream)
 */
function routeOf(linkGroups, streamId, direction) {
  var values = linkGroups && linkGroups.length ? linkGroups : []
  for (var i = 0; i < values.length; i++) {
    var g = values[i]
    if (!g) continue
    if (direction === "playback") {
      if (g.source && Number(g.source.id) === Number(streamId) && g.target) return row(g.target)
    } else {
      if (g.target && Number(g.target.id) === Number(streamId) && g.source) return row(g.source)
    }
  }
  return null
}

function glyph(kind) {
  if (kind === "sink" || kind === "playback") return "󰓃" // volume / speaker
  if (kind === "source" || kind === "capture") return "󰍬" // microphone
  return "󰌘" // lan-connect
}

function findRow(list, id) {
  var values = list && list.length ? list : []
  for (var i = 0; i < values.length; i++) if (values[i] && values[i].id === Number(id)) return values[i]
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    safeLabel: safeLabel, safeToken: safeToken, nodeKind: nodeKind, row: row,
    rows: rows, nodeById: nodeById, routeOf: routeOf, glyph: glyph, findRow: findRow
  }
}
