#!/usr/bin/env node
/**
 * SVG review exports for the locked watch-ring baseline
 * (`docs/product/WATCH_RING_DESIGN.md`).
 *
 * Usage: node tools/render-watch-ring-designs.mjs
 */

import { execFileSync } from 'node:child_process'
import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

const SURFACE = '#101412'
const TRACK = '#2E3632'
const LABEL = '#F4FBF8'
const WELL = '#0B0E0C'

/** SIL OFL-1.1. Bold for watch-scale labels. */
const FONT = 'Noto Sans'
const FONT_FILE = '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf'

const CATALOG = {
  codex: {
    id: 'codex',
    used: 0.92,
    color: '#65D78A',
  },
  claude: {
    id: 'claude',
    used: 0.61,
    color: '#E8915A',
  },
  cursor: {
    id: 'cursor',
    // Matches fixtures/providers/cursor/usage_summary.json autoPercentUsed.
    used: 0.47,
    color: '#67E8D4',
  },
}

/** Aggregate remaining purchased credits on the center (first) strip (not LLM tokens). */
const CREDITS_GLANCE = '500'

/** One Python round-trip: widths[text] + ascent/descent for baseline math. */
function loadFontMetrics(fontSize, texts) {
  const fallback = {
    widths: Object.fromEntries(texts.map((t) => [t, fontSize * 0.62 * t.length])),
    ascent: fontSize,
    descent: fontSize * 0.25,
  }
  try {
    const out = execFileSync(
      'python3',
      [
        '-c',
        [
          'import json',
          'from PIL import ImageFont',
          `font = ImageFont.truetype(${JSON.stringify(FONT_FILE)}, ${fontSize})`,
          `texts = ${JSON.stringify(texts)}`,
          'asc, desc = font.getmetrics()',
          'widths = {t: font.getbbox(t)[2] - font.getbbox(t)[0] for t in texts}',
          'print(json.dumps({"widths": widths, "ascent": asc, "descent": desc}))',
        ].join('\n'),
      ],
      { encoding: 'utf8' },
    )
    return JSON.parse(out)
  } catch {
    return fallback
  }
}

function esc(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
}

function ringArc({ cx, cy, r, thickness, remaining, color, ambient }) {
  const circ = 2 * Math.PI * r
  const left = Math.max(0.02, Math.min(remaining, 0.999))
  const paint = circ * left
  const weight = ambient ? thickness * 0.75 : thickness
  const valueColor = ambient ? '#8A968F' : color
  const used = circ * (1 - left)
  return `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${TRACK}"
      stroke-width="${weight}" />
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${valueColor}"
      stroke-width="${weight}" stroke-linecap="round"
      stroke-dasharray="${paint.toFixed(2)} ${circ.toFixed(2)}"
      stroke-dashoffset="${(-used).toFixed(2)}"
      transform="rotate(-90 ${cx} ${cy})" />`
}

function barLabel(layer, { showPlan, showCredits }) {
  const parts = []
  if (showPlan && layer.used < 1) {
    parts.push(`${Math.round((1 - layer.used) * 100)}%`)
  }
  // Credits glue onto the matching provider strip only (review art uses Codex credits).
  if (showCredits && layer.id === 'codex') {
    parts.push(CREDITS_GLANCE)
  }
  return parts.join(' · ')
}

function sortByRemaining(layers) {
  return [...layers].sort((a, b) => b.used - a.used)
}

function providerBars({ cx, cy, innerR, layers, showPlan, showCredits, size }) {
  const ordered = showPlan ? sortByRemaining(layers) : layers.slice(0, 1)
  const rows = ordered
    .map((layer, index) => ({
      layer,
      text: barLabel(layer, {
        showPlan,
        showCredits,
      }),
    }))
    .filter((row) => row.text.length > 0)
  if (rows.length === 0) {
    return ''
  }

  const fontSize = Math.round(size * 0.032)
  const barH = Math.max(fontSize + 8, size * 0.044)
  const gap = Math.max(3, size * 0.007)
  const rx = Math.min(6, barH * 0.28)
  const padX = 12
  const accentW = Math.max(2.5, size * 0.007)
  const metrics = loadFontMetrics(fontSize, [
    '100% · 10.0M',
    ...rows.map((row) => row.text),
  ])
  // Floor width for worst-case center label from compactCreditCount (`100% · 10.0M`).
  const worstCase = metrics.widths['100% · 10.0M'] ?? fontSize * 0.62 * 12
  const textW = Math.max(
    worstCase,
    ...rows.map((row) => metrics.widths[row.text] ?? 0),
  )
  // Cap so a 3-up stack stays inside the clear aperture (matches WFF strip width 96).
  const barW = Math.min(size * 0.213, textW + padX * 2 + accentW)
  const textBaseline =
    barH / 2 + (metrics.ascent - metrics.descent) / 2
  const stackH = rows.length * barH + (rows.length - 1) * gap
  const maxBottom = cy + Math.min(innerR * 0.95, size * 0.43)
  const preferredTop = cy + size * 0.147
  let y = Math.min(preferredTop, maxBottom - stackH)
  y = Math.max(y, cy + size * 0.14)
  const x = cx - barW / 2
  // Center labels in the well to the right of the accent.
  const textX = cx + accentW / 2

  let out = ''
  for (const row of rows) {
    const { layer, text } = row
    out += `
    <rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${barW.toFixed(1)}"
      height="${barH.toFixed(1)}" rx="${rx.toFixed(1)}" fill="${WELL}"
      fill-opacity="0.92" />
    <rect x="${x.toFixed(1)}" y="${(y + 2).toFixed(1)}" width="${accentW.toFixed(1)}"
      height="${(barH - 4).toFixed(1)}" rx="${Math.min(2, accentW).toFixed(1)}"
      fill="${layer.color}" />
    <text x="${textX.toFixed(1)}" y="${(y + textBaseline).toFixed(1)}"
      text-anchor="middle" font-family="${FONT}, sans-serif"
      font-size="${fontSize}" font-weight="700" fill="${LABEL}">${esc(text)}</text>`
    y += barH + gap
  }
  return out
}

function faceSvg({
  name,
  size,
  layers = [],
  ambient = false,
  showPlan = true,
  showCredits = false,
}) {
  const cx = size / 2
  const cy = size / 2
  const outer = size * 0.435
  const gap = size * 0.01
  // ~25px on a 450 face (~+10% vs the prior 23px stroke).
  const thickness = Math.max(8, size * (ambient ? 0.052 : 0.058))
  const planLayers = sortByRemaining(layers.filter((layer) => layer.used < 1))
  const stripLayers = showPlan ? planLayers : layers.slice(0, 1)

  let ringMarkup = ''
  let innerR = size * 0.3
  if (showPlan && planLayers.length > 0) {
    // planLayers are tightest-first; draw index 0 on the innermost radius (center).
    for (let i = 0; i < planLayers.length; i += 1) {
      const fromOutside = planLayers.length - 1 - i
      const r = outer - fromOutside * (thickness + gap)
      ringMarkup += ringArc({
        cx,
        cy,
        r,
        thickness,
        remaining: 1 - planLayers[i].used,
        color: planLayers[i].color,
        ambient,
      })
    }
    innerR = outer - planLayers.length * (thickness + gap) + gap * 0.5
  } else {
    ringMarkup += `
    <circle cx="${cx}" cy="${cy}" r="${(size * 0.42).toFixed(1)}" fill="none"
      stroke="${TRACK}" stroke-width="${(size * 0.018).toFixed(1)}" />`
    innerR = size * 0.36
  }

  const timeSize = ambient ? size * 0.18 : size * 0.155
  const timeY = cy + timeSize * 0.36
  let content = `
    <text x="${cx}" y="${timeY.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${timeSize.toFixed(1)}"
      font-weight="700" fill="${LABEL}">10:08</text>`
  if (!ambient) {
    content += providerBars({
      cx,
      cy,
      innerR,
      layers: stripLayers,
      showPlan,
      showCredits,
      size,
    })
  }

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="${esc(name)}">
  <defs>
    <radialGradient id="lift" cx="50%" cy="48%" r="62%">
      <stop offset="0%" stop-color="#18201C"/>
      <stop offset="55%" stop-color="${SURFACE}"/>
      <stop offset="100%" stop-color="#0A0D0B"/>
    </radialGradient>
  </defs>
  <rect width="${size}" height="${size}" fill="url(#lift)"/>
  ${ringMarkup}
  ${content}
</svg>
`
}

const wearDir = join(root, 'apps/wear_android/design')
const wffDir = join(root, 'apps/watchface_wff/design')
await mkdir(wearDir, { recursive: true })
await mkdir(wffDir, { recursive: true })

const three = [CATALOG.codex, CATALOG.claude, CATALOG.cursor]
const two = [CATALOG.codex, CATALOG.claude]
const one = [CATALOG.codex]

const variants = [
  {
    file: 'round-3-plan-credits.svg',
    name: 'Round · 3 providers · plan + credits',
    layers: three,
    showPlan: true,
    showCredits: true,
  },
  {
    file: 'round-2-plan-credits.svg',
    name: 'Round · 2 providers · plan + credits',
    layers: two,
    showPlan: true,
    showCredits: true,
  },
  {
    file: 'round-1-plan.svg',
    name: 'Round · 1 provider · plan only',
    layers: one,
    showPlan: true,
    showCredits: false,
  },
  {
    file: 'round-1-plan-credits.svg',
    name: 'Round · 1 provider · plan + credits',
    layers: one,
    showPlan: true,
    showCredits: true,
  },
  {
    file: 'round-credits-only.svg',
    name: 'Round · credits only',
    layers: one,
    showPlan: false,
    showCredits: true,
  },
  {
    file: 'round-ambient-3.svg',
    name: 'Round · ambient · 3 providers',
    layers: three,
    ambient: true,
    showPlan: true,
    showCredits: false,
  },
]

const wffFiles = new Set([
  'round-3-plan-credits.svg',
  'round-1-plan-credits.svg',
  'round-credits-only.svg',
  'round-ambient-3.svg',
])

for (const variant of variants) {
  const svg = faceSvg({
    name: variant.name,
    size: 450,
    layers: variant.layers,
    ambient: variant.ambient === true,
    showPlan: variant.showPlan,
    showCredits: variant.showCredits,
  })
  const wearPath = join(wearDir, variant.file)
  await writeFile(wearPath, svg)
  console.log(`wrote ${wearPath}`)
  if (wffFiles.has(variant.file)) {
    const wffPath = join(wffDir, variant.file)
    await writeFile(wffPath, svg)
    console.log(`wrote ${wffPath}`)
  }
}
