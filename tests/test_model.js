// Node regression tests for RoutingModel.js (QML shares the same helper).
const assert = require('node:assert/strict')
const M = require('../RoutingModel.js')

// Tooltip text comes from PipeWire node names, which are untrusted. Markup must
// not survive the sanitizer that feeds the bar's tooltip/share sinks.
const evil = '<img src="https://example.invalid/tracker"> & "x" \'<b>y</b>'
const clean = M.safeLabel(evil, 200)
assert.ok(!/[<>&]/.test(clean), 'markup characters removed: ' + clean)
assert.ok(clean.includes('"x"'), 'quotes retained for honest names: ' + clean)
assert.equal(M.safeLabel("Logitech's Mic", 80), "Logitech's Mic", 'apostrophes retained')
assert.ok(!clean.includes('\n'), 'newlines collapsed')
assert.equal(M.safeLabel('A'.repeat(500), 80).length, 80, 'label bounded')
assert.equal(M.safeToken('a;rm -rf /$()'), 'arm-rf', 'node name token restricted')

const nodes = [
  { id: 80, name: 'alsa_output.usb-UMC', description: 'UMC404HD', isSink: true, isStream: false },
  { id: 76, name: 'alsa_input.usb-UMC', description: 'UMC Mic', isSink: false, isStream: false, audio: {} },
  { id: 111, name: 'Brave', description: 'Brave', isSink: true, isStream: true },
  { id: 112, name: 'Recorder', description: 'Recorder', isSink: false, isStream: true }
]
assert.deepEqual(M.rows(nodes, 'sink').map(r => r.id), [80])
assert.deepEqual(M.rows(nodes, 'source').map(r => r.id), [76])
assert.deepEqual(M.rows(nodes, 'playback').map(r => r.id), [111])
assert.deepEqual(M.rows(nodes, 'capture').map(r => r.id), [112])

// MIDI and video nodes are not audio sources and must not appear as inputs.
const mixed = [
  { id: 200, name: 'midi', isSink: false, isStream: false, type: 'Midi/Sink' },
  { id: 201, name: 'v4l2', isSink: false, isStream: false, type: 'Video/Source' },
  { id: 202, name: 'virtualmic', isSink: false, isStream: false, type: 'Audio/Source/Virtual' }
]
assert.deepEqual(M.rows(mixed, 'source').map(r => r.id), [202])

const links = [
  { source: { id: 111 }, target: { id: 80 } },   // Brave -> UMC output
  { source: { id: 76 }, target: { id: 112 } }    // UMC mic -> Recorder
]
assert.equal(M.routeOf(links, 111, 'playback').id, 80)
assert.equal(M.routeOf(links, 112, 'capture').id, 76)
assert.equal(M.routeOf(links, 111, 'capture'), null, 'direction matters')
assert.equal(M.nodeById(nodes, 76).name, 'alsa_input.usb-UMC')

console.log('model tests passed')
