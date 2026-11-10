# omarchy-shurectl

Control a Shure MV7 or MV7+ from the Omarchy bar, through
[joelgaff/shurectl](https://github.com/joelgaff/shurectl): a fork of
[Humblemonk/shurectl](https://github.com/Humblemonk/shurectl) that adds `--state`,
`--set` and `--follow`. Upstream keeps its command line to one-shot commands, so the
plugin can't run on upstream's shurectl or the AUR package. The fork is pinned here as
the `shurectl` submodule, and `install.sh` builds it.

| Action | How |
| --- | --- |
| Open the panel | Click the mic icon |
| Mute / unmute | Middle-click the icon, the Muted/Live button, or `M` in the panel |
| Headphone mix | Scroll on the icon, or use "Monitor mix" on MV7 / "You" on MV7+ |
| Load preset 1–4 | `1`–`4` in the panel, or `omarchy-shell joelgaff.shurectl preset 2` |
| The full terminal UI | Right-click the icon |

## Install

Needs `cargo`.

```bash
git clone --recurse-submodules https://github.com/joelgaff/omarchy-shurectl ~/Work/omarchy-shurectl
~/Work/omarchy-shurectl/install.sh     # builds shurectl to ~/.local/bin, adds the udev rule
ln -s ~/Work/omarchy-shurectl ~/.config/omarchy/plugins/joelgaff.shurectl
omarchy-shell shell rescanPlugins
omarchy plugin enable joelgaff.shurectl
```

After a `git pull`, run `install.sh` again: it builds whichever shurectl commit the
plugin pins.

The icon is red while the mic is muted and hollow while it's unplugged. Mv7.qml
keeps the one `shurectl --follow` process for every bar; Panel.qml is the UI;
Model.js the option lists and labels.

## Model support

The original MV7 panel shows Auto Level position and tone, manual gain in 1.5 dB
steps, configuration lock, headphone monitor mix, manual EQ presets and
compression. Its monitor slider runs from mic toward computer audio, from 0 to
100. These are mix positions, not linear loudness percentages. It does not have
the MV7+'s separate playback slider. MV7+ keeps its processing, reverb and color
LED controls. Other models are not supported.

Controls stay unavailable until shurectl reads device settings successfully.
shurectl's `state_ready` field keeps a command error visible without disabling
valid settings; a shurectl without it falls back to requiring `error: false`.
Original MV7 firmware that rejects the LED commands reads back without them from
the pinned fork's 99e156a on.
Original MV7 LED controls appear only when shurectl explicitly reports the
`led_live_meter` or `led_night_mode` feature as supported.

Run helper tests with `node --test tests/model.test.cjs`.

Opening the terminal UI pauses the bar's device connection. Both processes use
`flock` from util-linux so a shell reload cannot start a competing reader while
the terminal is open. Manually launched shurectl processes are outside this lock.
The terminal child signals the bar when shurectl exits, then polling resumes. If
the terminal is killed before it can send that signal, close any shurectl terminal first, then
run `omarchy-shell joelgaff.shurectl resumeTui` to resume polling.

## Updating shurectl

Work on shurectl happens in the fork (see its FORK.md for taking changes from upstream).
To move the plugin to a newer fork commit:

```bash
git -C shurectl pull origin main
./install.sh                           # build and try it
git add shurectl && git commit -m "Pin shurectl <version>"
```
