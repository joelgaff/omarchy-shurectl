# omarchy-shurectl

Every setting of a Shure MV7+ from the Omarchy bar, through
[shurectl](https://github.com/Humblemonk/shurectl)'s `--json` / `--set` / `--follow`
(added on the `json-cli` branch of github.com/joelgaff/shurectl; build it to
`~/.local/bin/shurectl`, the AUR package doesn't have it yet).

| Action | How |
| --- | --- |
| Open the panel | Click the mic icon |
| Mute / unmute | Middle-click the icon, the Muted/Live button, or `M` in the panel |
| How loud you hear yourself | Scroll on the icon, or the "You" slider |
| Load preset 1–4 | `1`–`4` in the panel, or `omarchy-shell joelgaff.shurectl preset 2` |
| The full terminal UI | Right-click the icon |

## Install

```bash
git clone https://github.com/joelgaff/omarchy-shurectl ~/Work/omarchy-shurectl
ln -s ~/Work/omarchy-shurectl ~/.config/omarchy/plugins/joelgaff.shurectl
omarchy-shell shell rescanPlugins
omarchy plugin enable joelgaff.shurectl
```

The icon is red while the mic is muted and hollow while it's unplugged. Mv7.qml
keeps the one `shurectl --json --follow` process for every bar; Panel.qml is the UI;
Model.js the option lists and labels.
