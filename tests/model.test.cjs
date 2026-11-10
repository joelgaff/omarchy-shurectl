const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../Model.js`, 'utf8').replace(/^\.pragma library\s*/, ''), model);

function snapshot(name = 'Shure MV7', extra = {}) {
  return { model: name, connected: true, error: false,
    features: { playback_mix: true, gain_lock: true, hpf: true, reverb: true,
      led: true, device_rename: true, factory_reset: true },
    state: { mode: 'manual', gain_db: 16.5, monitor_mix: 60, playback_mix: 40,
      mute_button_disabled: false }, ...extra };
}

test('readiness rejects defaults, absent state, disconnects and unsupported models', () => {
  for (const state of [null, {}, snapshot('Shure MV7', { connected: false }),
    snapshot('Shure MV7', { error: true }), snapshot('Shure MV7', { state: null }),
    snapshot('Shure MV6'), snapshot('Shure MV7', { state_ready: false })]) {
    assert.equal(model.ready(state), false);
    for (const key of ['mute', 'gain', 'preset_load', 'monitor_mix']) assert.equal(model.canSet(state, key), false);
  }
  assert.equal(model.ready(snapshot()), true);
  assert.equal(model.ready(snapshot('Shure MV7', { state_ready: true, error: true })), true);
  assert.equal(model.canSet(snapshot('Shure MV7', { error: true }), 'refresh'), true);
  assert.equal(model.canSet(null, 'refresh'), false);
});

test('MV7 only exposes supported settings in their applicable mode', () => {
  const state = snapshot();
  for (const key of ['mute', 'gain', 'mode', 'lock', 'monitor_mix', 'eq_preset', 'compressor', 'preset_save']) assert.equal(model.canSet(state, key), true, key);
  for (const key of ['auto_position', 'auto_tone', 'playback_mix', 'hpf', 'gain_lock', 'reverb_output', 'led_behavior', 'device_name', 'denoiser', 'limiter', 'popper_stopper', 'tone', 'mute_button_disabled', 'led_live_meter', 'led_night_mode']) assert.equal(model.canSet(state, key), false, key);
  state.state.mode = 'auto';
  for (const key of ['auto_position', 'auto_tone']) assert.equal(model.canSet(state, key), true, key);
  for (const key of ['gain', 'eq_preset', 'compressor']) assert.equal(model.canSet(state, key), false, key);
  state.features.led_live_meter = true;
  assert.equal(model.canSet(state, 'led_live_meter'), true);
  assert.equal(model.canSet(state, 'led_night_mode'), false);
});

test('MV7+ retains its supported controls and respects feature flags', () => {
  const state = snapshot('Shure MV7+');
  for (const key of ['gain', 'mute', 'mode', 'monitor_mix', 'playback_mix', 'gain_lock', 'hpf', 'compressor', 'limiter', 'denoiser', 'popper_stopper', 'tone', 'reverb_output', 'reverb_monitoring', 'reverb_type', 'reverb_intensity', 'led_behavior', 'led_brightness', 'led_live_theme', 'led_solid_rgb', 'device_name', 'factory_reset', 'mute_button_disabled']) assert.equal(model.canSet(state, key), true, key);
  for (const key of ['eq_preset', 'lock', 'led_live_meter', 'led_night_mode']) assert.equal(model.canSet(state, key), false, key);
  state.state.gain_lock = true;
  assert.equal(model.canSet(state, 'gain'), false);
  state.features.playback_mix = false;
  assert.equal(model.canSet(state, 'playback_mix'), false);
});

test('fractional gain and monitor labels match each model', () => {
  assert.equal(model.capabilities(snapshot()).gainStep, 1.5);
  assert.equal(model.capabilities(snapshot('Shure MV7+')).gainStep, 1);
  assert.equal(model.gainLabel(16.5), '16.5 dB');
  assert.equal(model.snap(16.7, 0, 36, 1.5), 16.5);
  assert.equal(model.snap(99, 0, 36, 1.5), 36);
  assert.equal(model.snap(-1, 0, 36, 1.5), 0);
  assert.match(model.tooltip(snapshot()), /Shure MV7 · live · 16.5 dB · monitor mix 60%/);
  assert.match(model.tooltip(snapshot('Shure MV7+')), /you 60%, computer 40%/);
  assert.match(model.tooltip(snapshot()), /scroll: monitor mix \(mic ↔ computer\)/);
  assert.match(model.tooltip(snapshot('Shure MV7+')), /scroll: how loud you hear yourself/);
  assert.doesNotMatch(model.tooltip(snapshot('Shure MV7', { error: true })), /live|16.5 dB/);
});

test('terminal wrapper signals completion and passes the binary path without shell interpolation', () => {
  const os = require('node:os');
  const path = require('node:path');
  const { spawnSync } = require('node:child_process');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shurectl-terminal-'));
  try {
    const qml = fs.readFileSync(`${__dirname}/../Mv7.qml`, 'utf8');
    const wrapper = JSON.parse(qml.match(/^\s*("trap .*"),$/m)[1]);
    const binary = path.join(dir, 'mic with spaces $(invalid)');
    const output = path.join(dir, 'ipc');
    fs.writeFileSync(binary, '#!/bin/sh\nexit 7\n', { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'omarchy-shell'), '#!/bin/sh\nprintf "%s\\n" "$@" > "$IPC_OUTPUT"\n', { mode: 0o755 });
    const result = spawnSync('sh', ['-c', wrapper, 'shurectl-tui', binary, path.join(dir, 'device.lock')], {
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, IPC_OUTPUT: output }
    });
    assert.equal(result.status, 7);
    assert.equal(result.stderr.toString(), '');
    assert.equal(fs.readFileSync(output, 'utf8'), 'joelgaff.shurectl\nresumeTui\n');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('terminal ownership blocks a reloaded follower and releases after a crash', { timeout: 5000 }, async () => {
  const os = require('node:os');
  const path = require('node:path');
  const { spawn, spawnSync } = require('node:child_process');
  const { once } = require('node:events');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shurectl-lock-'));
  let terminal, follow, ownerPid;
  try {
    const qml = fs.readFileSync(`${__dirname}/../Mv7.qml`, 'utf8');
    const wrapper = JSON.parse(qml.match(/^\s*("trap .*"),$/m)[1]);
    const binary = path.join(dir, 'fake-mic');
    const lockPath = path.join(dir, 'device.lock');
    fs.writeFileSync(binary, '#!/bin/sh\nprintf "%s\\n" "$$"\nread -r done\n', { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'omarchy-shell'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    const env = { ...process.env, PATH: `${dir}:${process.env.PATH}` };
    terminal = spawn('sh', ['-c', wrapper, 'shurectl-tui', binary, lockPath], { env });
    ownerPid = Number((await once(terminal.stdout, 'data'))[0].toString().trim());
    const command = vm.runInNewContext(qml.match(/command: (\["flock"[^\n]+)/)[1], {
      root: { lockPath, shurectl: binary, pollMs: 400 }
    });
    const rejected = spawnSync(command[0], command.slice(1), { env });
    assert.equal(rejected.status, 75);
    assert.equal(rejected.stdout.toString(), '');
    const terminalClosed = once(terminal, 'close');
    process.kill(ownerPid, 'SIGKILL');
    ownerPid = undefined;
    await terminalClosed;
    follow = spawn(command[0], command.slice(1), { env });
    const followPid = Number((await once(follow.stdout, 'data'))[0].toString().trim());
    assert.equal(followPid, follow.pid, '--no-fork preserves ownership when Process stops');
    const followClosed = once(follow, 'close');
    follow.kill('SIGTERM');
    await followClosed;
    assert.equal(fs.existsSync(lockPath), true);
    assert.equal(spawnSync('flock', ['--nonblock', lockPath, 'true']).status, 0,
      'an existing lock file does not retain ownership after the process exits');
  } finally {
    if (ownerPid) { try { process.kill(ownerPid, 'SIGKILL'); } catch {} }
    terminal?.kill();
    follow?.kill();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
