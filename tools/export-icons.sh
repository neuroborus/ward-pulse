#!/usr/bin/env bash
# Regenerate WardPulse brand SVGs and runtime launcher / app / watch-face PNGs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

write_png_if_pixels_changed() {
  local output="$1"
  shift
  local candidate="${output%.png}.tmp.png"

  rm -f "$candidate"
  if ! "$@" "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  if [[ ! -f "$output" ]]; then
    mv "$candidate" "$output"
    return
  fi

  local compare_status
  if compare -metric AE "$output" "$candidate" null: >/dev/null 2>&1; then
    rm -f "$candidate"
  else
    compare_status=$?
    if (( compare_status != 1 )); then
      rm -f "$candidate"
      echo "export-icons: failed to compare $output" >&2
      return "$compare_status"
    fi
    mv "$candidate" "$output"
  fi
}

node tools/render-brand-icons.mjs
mkdir -p brand/icons/previews

write_png_if_pixels_changed brand/icons/previews/wardpulse.png \
  convert -background none -density 192 brand/icons/wardpulse.svg

# Flutter app-bar mark: 32 logical pixels with only the densities it ships.
mkdir -p \
  apps/phone_flutter/assets/brand/2.0x \
  apps/phone_flutter/assets/brand/3.0x
write_png_if_pixels_changed apps/phone_flutter/assets/brand/wardpulse.png \
  convert -background none brand/icons/wardpulse.svg -resize 32x32 -strip
write_png_if_pixels_changed apps/phone_flutter/assets/brand/2.0x/wardpulse.png \
  convert -background none brand/icons/wardpulse.svg -resize 64x64 -strip
write_png_if_pixels_changed apps/phone_flutter/assets/brand/3.0x/wardpulse.png \
  convert -background none brand/icons/wardpulse.svg -resize 96x96 -strip

# Mono watermark: rasterize, then dissolve the lower content toward the strip stack.
if command -v inkscape >/dev/null 2>&1; then
  inkscape brand/icons/wardpulse-mono.svg --export-type=png \
    --export-filename=brand/icons/previews/wardpulse-mono.png -w 1024 -h 1024
else
  convert -background none -density 192 brand/icons/wardpulse-mono.svg \
    brand/icons/previews/wardpulse-mono.png
fi
python3 tools/fade-watermark-png.py brand/icons/previews/wardpulse-mono.png 0.28 0.06
write_png_if_pixels_changed brand/icons/previews/wardpulse-mono-on-dark.png \
  convert -size 1024x1024 xc:'#101412' brand/icons/previews/wardpulse-mono.png \
  -gravity center -compose over -composite
write_png_if_pixels_changed \
  apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png \
  convert brand/icons/previews/wardpulse-mono.png -resize 192x192
# Same faded mono for the phone home-widget (quiet brand, day/night tinted in layout).
mkdir -p apps/phone_flutter/android/app/src/main/res/drawable
write_png_if_pixels_changed \
  apps/phone_flutter/android/app/src/main/res/drawable/wardpulse_mono.png \
  convert brand/icons/previews/wardpulse-mono.png -resize 192x192

for dens in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  name="${dens%:*}"
  px="${dens#*:}"
  write_png_if_pixels_changed \
    "apps/phone_flutter/android/app/src/main/res/mipmap-${name}/ic_launcher.png" \
    convert -background none brand/icons/wardpulse.svg -resize "${px}x${px}"
  write_png_if_pixels_changed \
    "apps/wear_android/app/src/main/res/mipmap-${name}/ic_launcher.png" \
    convert -background none brand/icons/wardpulse.svg -resize "${px}x${px}"
done

for dens in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  name="${dens%:*}"
  canvas="${dens#*:}"
  logo=$((canvas * 72 / 100))
  mkdir -p "apps/phone_flutter/android/app/src/main/res/drawable-${name}"
  write_png_if_pixels_changed \
    "apps/phone_flutter/android/app/src/main/res/drawable-${name}/ic_launcher_foreground.png" \
    convert -size "${canvas}x${canvas}" xc:none \
    \( brand/icons/wardpulse.svg -background none -resize "${logo}x${logo}" \) \
    -gravity center -compose over -composite
done

echo "export-icons: done"
