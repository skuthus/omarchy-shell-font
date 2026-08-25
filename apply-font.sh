#!/bin/bash
# Apply or reset the Omarchy shell UI font.
# Used by the plugin service, and safe to run from post-update hooks.
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell-font.json"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d"
CONF="$CONF_DIR/50-omarchy-shell-font.conf"
OLD_CONF="$CONF_DIR/50-omarchy-bar-inter.conf"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/omarchy-shell-font"
PRIVATE_FAMILY="OmarchyShellFont"

usage() {
  echo "Usage: apply-font.sh [--reset] [family] [weight]"
}

fc_weight() {
  case "${1:-regular}" in
    thin) echo thin ;;
    extralight|extra-light) echo extralight ;;
    light) echo light ;;
    regular|normal) echo regular ;;
    medium) echo medium ;;
    semibold|semi-bold|demibold|demi-bold) echo demibold ;;
    bold) echo bold ;;
    extrabold|extra-bold) echo extrabold ;;
    black) echo black ;;
    *) echo regular ;;
  esac
}

reset_font() {
  rm -f "$CONF" "$OLD_CONF"
  rm -rf "$FONT_DIR"
  fc-cache -f >/dev/null 2>&1 || true
  echo "RESET"
}

read_config() {
  [[ -f $CONFIG ]] || return 1
  python3 - "$CONFIG" <<'PY'
import json, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text()
data = json.loads(raw) if raw.strip() else {}
if data.get("enabled") is False:
    raise SystemExit(2)
family = str(data.get("family") or "").strip()
weight = str(data.get("weight") or "regular").strip().lower()
if not family:
    raise SystemExit(1)
print(family)
print(weight)
PY
}

apply_font() {
  local family="$1"
  local weight="$2"
  local fcw file ext dest

  fcw=$(fc_weight "$weight")
  file=$(fc-match -f '%{file}' "${family}:weight=${fcw}:slant=roman")
  if [[ -z $file || ! -e $file ]]; then
    echo "ERROR no font file for $family $weight" >&2
    exit 1
  fi

  mkdir -p "$FONT_DIR" "$CONF_DIR"
  rm -f "$FONT_DIR"/*
  ext="${file##*.}"
  dest="$FONT_DIR/ui-font.${ext}"
  ln -sfn "$file" "$dest"

  cat >"$CONF" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Private single-face family so Qt cannot ignore the chosen weight. -->
  <match target="scan">
    <test name="family">
      <string>${family}</string>
    </test>
    <test name="weight" compare="eq">
      <const>${fcw}</const>
    </test>
    <test name="slant" compare="eq">
      <const>roman</const>
    </test>
    <edit name="family" mode="prepend" binding="strong">
      <string>${PRIVATE_FAMILY}</string>
    </edit>
  </match>

  <match target="pattern">
    <test name="prgname">
      <string>quickshell</string>
    </test>
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="assign_replace" binding="strong">
      <string>${PRIVATE_FAMILY}</string>
    </edit>
  </match>

  <match target="pattern">
    <test name="prgname">
      <string>omarchy-shell</string>
    </test>
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="assign_replace" binding="strong">
      <string>${PRIVATE_FAMILY}</string>
    </edit>
  </match>
</fontconfig>
XML

  rm -f "$OLD_CONF"
  fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true

  local resolved
  resolved=$(fc-match -f '%{family} %{style} %{weight}' ":family=${PRIVATE_FAMILY}")
  if [[ $resolved != ${PRIVATE_FAMILY}* ]]; then
    echo "ERROR private family missing: $resolved" >&2
    exit 1
  fi
  echo "OK ${PRIVATE_FAMILY} ${family} ${weight} ${resolved}"
}

RESET=0
FAMILY=""
WEIGHT=""

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --reset) RESET=1 ;;
    -*) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
    *)
      if [[ -z $FAMILY ]]; then FAMILY="$arg"
      elif [[ -z $WEIGHT ]]; then WEIGHT="$arg"
      fi
      ;;
  esac
done

if [[ $RESET -eq 1 ]]; then
  reset_font
  exit 0
fi

if [[ -z $FAMILY ]]; then
  if ! cfg=$(read_config); then
    if [[ $? -eq 2 ]]; then
      reset_font
      exit 0
    fi
    echo "ERROR no family (pass args or write $CONFIG)" >&2
    exit 1
  fi
  FAMILY=$(printf '%s\n' "$cfg" | sed -n '1p')
  WEIGHT=$(printf '%s\n' "$cfg" | sed -n '2p')
fi

WEIGHT="${WEIGHT:-regular}"
apply_font "$FAMILY" "$WEIGHT"
