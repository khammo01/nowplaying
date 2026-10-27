#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
font_dir="$root/esphome/fonts"
mkdir -p "$font_dir"
curl -fL --retry 3 -o "$font_dir/NotoEmoji-VariableFont_wght.ttf" \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf'
curl -fL --retry 3 -o "$font_dir/materialdesignicons-webfont.ttf" \
  'https://raw.githubusercontent.com/Templarian/MaterialDesign-Webfont/master/fonts/materialdesignicons-webfont.ttf'
echo "Controller fonts installed in $font_dir"
