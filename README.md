# Shell Font

Pick the font family and weight used by the Omarchy Quickshell bar and shell UI.

Omarchy’s shell asks for `monospace`, and Qt ignores weight unless a family has
one face. This plugin extracts the face you chose, writes a real
`OmarchyShellFont` font file, and reapplies it when the shell starts so updates
cannot reset the bar to JetBrains Mono.

Terminals are not changed. No extra packages. No sudo or pkexec is required.

## Install

```bash
omarchy plugin add https://github.com/skuthus/omarchy-shell-font.git --enable
```

Click **Aa** on the bar, or:

```bash
omarchy-shell shell toggle skuthus.shell-font
```

## Usage

- Type to filter fonts, `j`/`k` or arrows to move, Enter or click to select
- Choose Regular, Medium, SemiBold, Bold, or ExtraBold
- **Apply** writes the face and restarts the shell
- **Use system monospace** restores the stock bar font

Settings are stored in `~/.config/omarchy/shell-font.json` (created only after
you apply a choice).

## Remove

```bash
omarchy plugin remove skuthus.shell-font --yes
rm -f ~/.config/fontconfig/conf.d/50-omarchy-shell-font.conf
rm -rf ~/.local/share/fonts/omarchy-shell-font
rm -f ~/.config/omarchy/shell-font.json
omarchy restart shell
```

## License

MIT
