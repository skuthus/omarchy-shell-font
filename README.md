# Shell Font

Pick the font family and weight used by the Omarchy Quickshell bar and shell UI.

Omarchy’s shell always asks for `monospace`, and Qt ignores weight unless the
family contains only one face. This plugin keeps a private `OmarchyShellFont`
face for the weight you chose and re-applies it every time the shell starts, so
`omarchy update` / Quickshell upgrades cannot reset the bar to JetBrains Mono.

Terminals are not touched.

## Install

```bash
omarchy plugin add https://github.com/skuthus/omarchy-shell-font.git --enable
```

Then click **Aa** on the bar to open the overlay picker, or:

```bash
omarchy-shell shell toggle skuthus.shell-font
```

A Style menu entry is optional; add this to `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"style.shell-font": {
  "icon": "Aa",
  "label": "Shell Font",
  "aliases": ["bar-font", "quickshell-font"],
  "action": "omarchy-shell shell toggle skuthus.shell-font"
}
```

## Usage

- **Family** — any installed font
- **Weight** — Thin through Black
- **Use system monospace** — restore the stock bar font

Settings live in `~/.config/omarchy/shell-font.json` and survive plugin updates.

## Why this survives updates

The plugin never edits `/usr/share/omarchy`. A small service runs at shell start,
rebuilds the private font face, and sets `Style.fontFamily`. A `post-update`
hook can call `apply-font.sh` so `fc-cache` during package upgrades does not
drop the face.

```bash
omarchy hook install post-update ~/.config/omarchy/plugins/skuthus.shell-font/apply-font.sh
```

## Remove

```bash
omarchy plugin remove skuthus.shell-font --yes
~/.config/omarchy/plugins/skuthus.shell-font/apply-font.sh --reset   # if the folder is already gone, delete:
#   ~/.config/fontconfig/conf.d/50-omarchy-shell-font.conf
#   ~/.local/share/fonts/omarchy-shell-font
#   ~/.config/omarchy/shell-font.json
omarchy restart shell
```

## License

MIT
