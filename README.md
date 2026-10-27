# omarchy-shurectl

Every setting of a Shure MV7+ from the Omarchy bar, through
[joelgaff/shurectl](https://github.com/joelgaff/shurectl): a fork of
[Humblemonk/shurectl](https://github.com/Humblemonk/shurectl) that adds `--state`,
`--set` and `--follow`. Upstream keeps its command line to one-shot commands, so the
plugin can't run on upstream's shurectl or the AUR package. The fork is pinned here as
the `shurectl` submodule, and `install.sh` builds it.

| Action | How |
| --- | --- |
| Open the panel | Click the mic icon |
| Mute / unmute | Middle-click the icon, the Muted/Live button, or `M` in the panel |
| How loud you hear yourself | Scroll on the icon, or the "You" slider |
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

## Updating shurectl

Work on shurectl happens in the fork (see its FORK.md for taking changes from upstream).
To move the plugin to a newer fork commit:

```bash
git -C shurectl pull origin main
./install.sh                           # build and try it
git add shurectl && git commit -m "Pin shurectl <version>"
```
