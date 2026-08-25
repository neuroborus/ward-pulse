#!/usr/bin/env bash
# Regenerate WardPulse brand SVGs and runtime launcher / watch-face PNGs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

node tools/render-brand-icons.mjs
mkdir -p brand/icons/previews

convert -background none -density 192 brand/icons/wardpulse.svg \
  brand/icons/previews/wardpulse.png

# Mono watermark: rasterize, then dissolve the lower content toward the strip stack.
if command -v inkscape >/dev/null 2>&1; then
  inkscape brand/icons/wardpulse-mono.svg --export-type=png \
    --export-filename=brand/icons/previews/wardpulse-mono.png -w 1024 -h 1024
else
  convert -background none -density 192 brand/icons/wardpulse-mono.svg \
    brand/icons/previews/wardpulse-mono.png
fi
python3 tools/fade-watermark-png.py brand/icons/previews/wardpulse-mono.png 0.28 0.06
convert -size 1024x1024 xc:'#101412' brand/icons/previews/wardpulse-mono.png \
  -gravity center -compose over -composite brand/icons/previews/wardpulse-mono-on-dark.png
convert brand/icons/previews/wardpulse-mono.png -resize 192x192 \
  apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png
# Same faded mono for the phone home-widget (quiet brand, day/night tinted in layout).
mkdir -p apps/phone_flutter/android/app/src/main/res/drawable
convert brand/icons/previews/wardpulse-mono.png -resize 192x192 \
  apps/phone_flutter/android/app/src/main/res/drawable/wardpulse_mono.png

for dens in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  name="${dens%:*}"
  px="${dens#*:}"
  convert -background none brand/icons/wardpulse.svg -resize "${px}x${px}" \
    "apps/phone_flutter/android/app/src/main/res/mipmap-${name}/ic_launcher.png"
  convert -background none brand/icons/wardpulse.svg -resize "${px}x${px}" \
    "apps/wear_android/app/src/main/res/mipmap-${name}/ic_launcher.png"
done

for dens in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  name="${dens%:*}"
  canvas="${dens#*:}"
  logo=$((canvas * 72 / 100))
  mkdir -p "apps/phone_flutter/android/app/src/main/res/drawable-${name}"
  convert -size "${canvas}x${canvas}" xc:none \
    \( brand/icons/wardpulse.svg -background none -resize "${logo}x${logo}" \) \
    -gravity center -compose over -composite \
    "apps/phone_flutter/android/app/src/main/res/drawable-${name}/ic_launcher_foreground.png"
done

echo "export-icons: done"
