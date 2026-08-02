#!/usr/bin/env node
/**
 * SVG review exports for the phone home-screen widget
 * (`docs/product/PHONE_WIDGET_DESIGN.md`).
 *
 * Rows, not arcs: family accent bar, `% left`, a two-line label carrying the
 * provider family over the pool name, and end-aligned credits. Colours mirror
 * `res/values{,-night}/colors_widget.xml` so the art cannot drift from the app
 * without the resource changing too.
 *
 * Usage: node tools/render-phone-widget-designs.mjs
 */

import { readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const designDir = join(root, 'apps/phone_flutter/design')
const resDir = join(root, 'apps/phone_flutter/android/app/src/main/res')

const FONT = 'Noto Sans, sans-serif'
const STALE = '#C46A3A'

/** Family accents, matching `RingFamily` on the phone. */
const FAMILY = {
  codex: '#65D78A',
  claude: '#E8915A',
  cursor: '#67E8D4',
}

/** `#AARRGGBB` from Android resources → SVG colour plus separate opacity. */
function argb(value) {
  if (value.length === 9) {
    return {
      color: `#${value.slice(3)}`,
      opacity: Number((parseInt(value.slice(1, 3), 16) / 255).toFixed(2)),
    }
  }
  return { color: value, opacity: 1 }
}

async function loadTheme(variant) {
  const file = join(resDir, variant, 'colors_widget.xml')
  const xml = await readFile(file, 'utf8')
  const read = (name) => {
    const match = xml.match(
      new RegExp(`<color name="ward_pulse_widget_${name}">(#[0-9A-Fa-f]+)</color>`),
    )
    if (!match) {
      throw new Error(`missing ward_pulse_widget_${name} in ${file}`)
    }
    return match[1]
  }
  const outline = argb(read('outline'))
  return {
    surface: read('surface'),
    onSurface: read('on_surface'),
    muted: read('muted'),
    outlineColor: outline.color,
    outlineOpacity: outline.opacity,
  }
}

function esc(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
}

/** Quiet face watermark, top-end beside the first row. */
function watermark({ x, y, color, opacity }) {
  return `  <g transform="translate(${x}, ${y})" opacity="${opacity}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linecap="round">
    <text x="18" y="0" font-family="${FONT}" font-size="5" font-weight="700" letter-spacing="0.5" fill="${color}" stroke="none" text-anchor="middle">WARDPULSE</text>
    <path d="M2 10 L8 10 L12 4 L18 14 L24 8 L30 8"/>
  </g>`
}

/**
 * One metric row. `family` is null when the pool name already carries it
 * (`Cursor Models`), which keeps the second line empty instead of repeating.
 */
function row({ theme, geometry, y, entry }) {
  const { padX, percentX, labelX, creditsX, fontSize, lineGap } = geometry
  // Baseline centred in the two-line block, so single-line rows line up with it.
  const centerY = y + (fontSize + lineGap) / 2
  const parts = [
    `  <rect x="${padX}" y="${y - fontSize + 3}" width="3" height="${
      fontSize * 2 + lineGap - 4
    }" rx="1" fill="${entry.color}"/>`,
    `  <text x="${percentX}" y="${centerY}" font-family="${FONT}" font-size="${fontSize}" fill="${
      theme.onSurface
    }">${esc(entry.percent)}</text>`,
  ]
  if (entry.family) {
    parts.push(
      `  <text x="${labelX}" y="${y}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.onSurface
      }" text-anchor="middle">${esc(entry.family)}</text>`,
      `  <text x="${labelX}" y="${y + fontSize + lineGap}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.onSurface
      }" text-anchor="middle">${esc(entry.pool)}</text>`,
    )
  } else {
    parts.push(
      `  <text x="${labelX}" y="${centerY}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.onSurface
      }" text-anchor="middle">${esc(entry.pool)}</text>`,
    )
  }
  if (entry.credits) {
    parts.push(
      `  <text x="${creditsX}" y="${centerY}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.muted
      }" text-anchor="end">${esc(entry.credits)}</text>`,
    )
  }
  return parts.join('\n')
}

function board({ theme, label, width, height, body }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(
    label,
  )}">
  <rect width="${width}" height="${height}" rx="20" fill="${theme.surface}" stroke="${
    theme.outlineColor
  }" stroke-opacity="${theme.outlineOpacity}"/>
${body}
</svg>
`
}

function metricsBoard({ theme, label, geometry, rows, staleBadge = false }) {
  const { padX, top, pitch, width } = geometry
  const height = top + rows.length * pitch + 10
  const body = [
    watermark({
      x: width - 50,
      y: staleBadge ? height - 24 : 12,
      color: theme.muted,
      opacity: 0.4,
    }),
    staleBadge
      ? `  <text x="${
          width - padX
        }" y="22" font-family="${FONT}" font-size="11" font-weight="700" letter-spacing="1" fill="${STALE}" text-anchor="end">STALE</text>`
      : null,
    ...rows.map((entry, index) =>
      row({
        theme,
        geometry,
        y: top + index * pitch,
        entry,
      }),
    ),
  ]
    .filter(Boolean)
    .join('\n')
  return board({ theme, label, width, height, body })
}

/** Medium board geometry; the small board is the same table, one size down. */
function geometryFor(width, fontSize) {
  return {
    width,
    padX: 14,
    percentX: 24,
    labelX: Math.round(width * 0.5),
    creditsX: width - 28,
    top: 34,
    fontSize,
    lineGap: 3,
    pitch: fontSize * 2 + 12,
  }
}

/**
 * Two providers with the same pool name sit next to each other on purpose —
 * that collision is why the label carries its family.
 */
const MEDIUM_ROWS = [
  {
    percent: '22% left',
    family: 'Claude',
    pool: 'Weekly plan',
    credits: '80 credits',
    color: FAMILY.claude,
  },
  {
    percent: '46% left',
    family: 'Codex',
    pool: 'Weekly plan',
    credits: '320 credits',
    color: FAMILY.codex,
  },
  {
    percent: '71% left',
    family: null,
    pool: 'Cursor Models',
    credits: '2.1K credits',
    color: FAMILY.cursor,
  },
]

const light = await loadTheme('values')
const dark = await loadTheme('values-night')

const variants = [
  {
    file: 'widget-medium.svg',
    svg: () =>
      metricsBoard({
        theme: light,
        label: 'Phone widget · medium · light · tightest-first',
        geometry: geometryFor(280, 12),
        rows: MEDIUM_ROWS,
      }),
  },
  {
    file: 'widget-dark.svg',
    svg: () =>
      metricsBoard({
        theme: dark,
        label: 'Phone widget · medium · dark · tightest-first',
        geometry: geometryFor(280, 12),
        rows: MEDIUM_ROWS,
      }),
  },
  {
    file: 'widget-small.svg',
    svg: () =>
      metricsBoard({
        theme: light,
        label: 'Phone widget · small · light · tightest-first',
        geometry: geometryFor(240, 11),
        rows: MEDIUM_ROWS.slice(0, 2),
      }),
  },
  {
    file: 'widget-stale.svg',
    svg: () =>
      metricsBoard({
        theme: light,
        label: 'Phone widget · stale',
        geometry: geometryFor(240, 11),
        rows: MEDIUM_ROWS.slice(0, 2).map((entry) => ({ ...entry, credits: null })),
        staleBadge: true,
      }),
  },
  {
    file: 'widget-empty.svg',
    svg: () =>
      board({
        theme: light,
        label: 'Phone widget · empty',
        width: 220,
        height: 88,
        body: [
          watermark({ x: 150, y: 20, color: light.muted, opacity: 0.28 }),
          `  <text x="14" y="46" font-family="${FONT}" font-size="13" fill="${light.muted}">No metrics</text>`,
        ].join('\n'),
      }),
  },
]

for (const variant of variants) {
  const path = join(designDir, variant.file)
  await writeFile(path, variant.svg())
  console.log(`wrote ${path}`)
}
