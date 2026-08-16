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

/** The ground under everything; ring type is punched down to it rather than inked on top. */
const BACKGROUND = '#0A0D0B'

/** The one family accent worn by two entries — a plan ring and a budget ring share it. */
const ANTHROPIC = '#E8915A'

/** SIL OFL-1.1. Bold for watch-scale labels. */
const FONT = 'Noto Sans'
const FONT_FILE = '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf'

/** The canvas the strip stack was measured on; every strip number below is in its units. */
const FACE = 450

/**
 * Measured off the face, never derived from the canvas: `watchface.xml` fixes 88x18 boxes
 * stepping 21 from y=283, with a 12pt label inside a 78-unit text region. Sizing a box to
 * its content instead is what let review art drift a stack wider than the watch draws.
 *
 * The accent is what the face paints, not what its markup declares: a 3x14 arc under a
 * 3-thick stroke covers 17 units of height and 6 of width, the left half clipped away by the
 * box edge. Same path-versus-paint trap the design document flags for the ring bands.
 */
const STRIP = {
  x: 181,
  y: 283,
  width: 88,
  height: 18,
  pitch: 21,
  radius: 6,
  accentWidth: 4.5,
  accentHeight: 17,
  textInset: 6,
  textWidth: 78,
  fontSize: 12,
}

/**
 * The ring type drawn as texture: the budget period repeated round the band and punched out in
 * the background color, so the arc underneath keeps carrying the family
 * (`WATCH_RING_DESIGN.md`). Only a budget ring names a period; a plan window draws no type.
 *
 * The type runs in four sweeps with a bare break on each diagonal, as on the face. The repeats a
 * sweep holds are copied from `TOKENS` in `tools/render-watchface.mjs`, outer ring first, never
 * recomputed here: they were fitted to an advance measured on device, and Noto's own metrics
 * would fit a different number of tokens on the same band. Within a sweep both generators place
 * tokens by rotation — the face bakes its bands as images through the same construction, so a
 * board and the watch differ only in the rasterizer that draws them.
 *
 * Three counts per token, not four: the face caps at three rings, so a fourth would be a board
 * the baseline forbids, and the generator throws rather than draw one from a guessed count.
 */
const TEXTURE = {
  /** Cap height as a share of the band, the same share the face gives it. */
  capOfBand: 0.78,
  /** Cap height of Noto Sans Bold, 1462/2048 em. */
  capRatio: 0.714,
  /** Sweeps the type is dealt over. */
  sweeps: 4,
  /** Bare band between two sweeps, in degrees. */
  sweepGap: 10,
  /** How much of the background colour a glyph carries, as on the face: a shade, not a hole. */
  opacity: 0.45,
  /** Repeats in one sweep, not round the whole band. */
  repeats: {
    D: [15, 13, 11],
    '7D': [9, 8, 6],
    M: [12, 10, 9],
  },
}

const CATALOG = {
  codex: {
    id: 'codex',
    used: 0.92,
    color: '#65D78A',
  },
  claude: {
    id: 'claude',
    used: 0.61,
    color: ANTHROPIC,
  },
  cursor: {
    id: 'cursor',
    // Matches fixtures/providers/cursor/usage_summary.json autoPercentUsed —
    // that is the plan's own models, the one pool that leaves the family color
    // (`WATCH_RING_DESIGN.md`, Split band).
    used: 0.47,
    color: '#7E93B8',
  },
  /**
   * The same plan with both pools alive: one band split lengthwise, own models
   * inside. The fixture's external pool is exhausted (`apiPercentUsed` 100),
   * which collapses the pair, so this one value is chosen — far enough from 47
   * to read as a second pool rather than a rounding of the first.
   */
  cursorPair: {
    id: 'cursor',
    used: 0.47,
    color: '#7E93B8',
    split: { used: 0.38, color: '#67E8D4' },
  },
  // One connection's three budget periods; percents and money match Wear's
  // PreviewWatchDashboardSummary, so the boards and the preview face show one story.
  anthropicBudgetWeek: {
    id: 'anthropic-budget-week',
    used: 0.285,
    // A budget ring wears its connection's family color, never one of its own.
    color: ANTHROPIC,
    // Spend of limit, not remaining percent — the one documented exception.
    budget: '$71.30/250',
    period: '7D',
  },
  anthropicBudgetMonth: {
    id: 'anthropic-budget-month',
    used: 0.265,
    color: ANTHROPIC,
    budget: '$212.10/800',
    period: 'M',
  },
  anthropicBudgetToday: {
    id: 'anthropic-budget-today',
    used: 0.248,
    color: ANTHROPIC,
    budget: '$12.40/50',
    period: 'D',
  },
}

/** Aggregate remaining purchased credits on the center (first) strip (not LLM tokens). */
const CREDITS_GLANCE = '500'

/**
 * Widths now guard the labels instead of placing them: the box is a measured constant, so a
 * label that outgrows the text region has to fail here rather than silently overhang, the way
 * the face would ellipsize it. A missing font or Pillow fails too — the old silent fallback
 * shifted baselines by 0.3 and made committed art depend on the machine that rendered it.
 */
function assertLabelsFit(texts) {
  const out = execFileSync(
    'python3',
    [
      '-c',
      [
        'import json',
        'from PIL import ImageFont',
        `font = ImageFont.truetype(${JSON.stringify(FONT_FILE)}, ${STRIP.fontSize})`,
        `texts = ${JSON.stringify(texts)}`,
        'print(json.dumps({t: font.getbbox(t)[2] - font.getbbox(t)[0] for t in texts}))',
      ].join('\n'),
    ],
    { encoding: 'utf8' },
  )
  for (const [text, width] of Object.entries(JSON.parse(out))) {
    if (width > STRIP.textWidth) {
      throw new Error(
        `strip label "${text}" is ${width} units wide, past the ${STRIP.textWidth}-unit region`,
      )
    }
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
  const valueColor = ambient ? '#8A968F' : color
  const used = circ * (1 - left)
  return `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${TRACK}"
      stroke-width="${thickness}" />
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${valueColor}"
      stroke-width="${thickness}" stroke-linecap="round"
      stroke-dasharray="${paint.toFixed(2)} ${circ.toFixed(2)}"
      stroke-dashoffset="${(-used).toFixed(2)}"
      transform="rotate(-90 ${cx} ${cy})" />`
}

/** Inner half first, then outer: the same order the payload packs a pair in. */
function ringArcPair(r, band) {
  return [
    [r - band / 4, band / 2],
    [r + band / 4, band / 2],
  ]
}

function ringTexture({ cx, cy, r, thickness, period, fromOutside }) {
  const repeats = TEXTURE.repeats[period]?.[fromOutside]
  if (!repeats) {
    throw new Error(`no measured repeat count for "${period}" on ring ${fromOutside + 1}`)
  }
  const cap = thickness * TEXTURE.capOfBand
  // Baseline half a cap height below the centre line leaves the cap centred on the band.
  const y = (cy - r + cap / 2).toFixed(1)
  const pitch = 360 / TEXTURE.sweeps
  const slot = (pitch - TEXTURE.sweepGap) / repeats
  // Half a sweep off 12, as on the face: the breaks land on the diagonals.
  const origin = pitch / 2 + TEXTURE.sweepGap / 2
  const tokens = Array.from({ length: TEXTURE.sweeps }, (_, index) =>
    Array.from({ length: repeats }, (_, repeat) => {
      const angle = (origin + index * pitch + (repeat + 0.5) * slot).toFixed(2)
      return `<text x="${cx}" y="${y}" transform="rotate(${angle} ${cx} ${cy})">${period}</text>`
    }).join(''),
  ).join('')
  return `
    <g font-family="${FONT}, sans-serif" font-size="${(cap / TEXTURE.capRatio).toFixed(1)}"
      font-weight="700" fill="${BACKGROUND}" fill-opacity="${TEXTURE.opacity}"
      text-anchor="middle">${tokens}</g>`
}

function barLabel(layer, { showPlan, showCredits }) {
  const parts = []
  if (showPlan) {
    if (layer.budget) {
      parts.push(layer.budget)
    } else if (layer.used < 1) {
      parts.push(`${Math.round((1 - layer.used) * 100)}%`)
    }
  }
  // A split strip spends the well on its second percent, so credits never join it
  // (`WATCH_RING_DESIGN.md`, Split band, rules 4 and 5).
  if (layer.split) {
    parts.push(`${Math.round((1 - layer.split.used) * 100)}%`)
    return parts.join(' · ')
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

function providerBars({ layers, showPlan, showCredits, size }) {
  const ordered = showPlan ? sortByRemaining(layers) : layers.slice(0, 1)
  const rows = ordered
    .map((layer) => ({
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
  assertLabelsFit(rows.map((row) => row.text))

  // The face lays the stack out in its own 450 units; only the canvas scale differs here.
  const k = size / FACE
  const textX = (STRIP.x + STRIP.textInset + STRIP.textWidth / 2) * k

  let out = ''
  rows.forEach((row, index) => {
    const { layer, text } = row
    const y = (STRIP.y + index * STRIP.pitch) * k
    out += `
    <rect x="${(STRIP.x * k).toFixed(1)}" y="${y.toFixed(1)}"
      width="${(STRIP.width * k).toFixed(1)}" height="${(STRIP.height * k).toFixed(1)}"
      rx="${(STRIP.radius * k).toFixed(1)}" fill="${WELL}" fill-opacity="0.92" />
    <rect x="${(STRIP.x * k).toFixed(1)}"
      y="${(y + ((STRIP.height - STRIP.accentHeight) / 2) * k).toFixed(1)}"
      width="${(STRIP.accentWidth * k).toFixed(1)}"
      height="${(STRIP.accentHeight * k).toFixed(1)}"
      rx="${((STRIP.accentWidth / 2) * k).toFixed(1)}" fill="${layer.color}" />
    <text x="${textX.toFixed(1)}" y="${(y + (STRIP.height / 2) * k).toFixed(1)}"
      text-anchor="middle" dominant-baseline="central"
      font-family="${FONT}, sans-serif" font-size="${(STRIP.fontSize * k).toFixed(1)}"
      font-weight="700" fill="${LABEL}">${esc(text)}</text>`
    if (layer.split) {
      // The far end names the second pool; its colour can only come from a slot
      // of its own on the face, which is why the fourth strip slot went here.
      out += `
    <rect x="${((STRIP.x + STRIP.width - STRIP.accentWidth) * k).toFixed(1)}"
      y="${(y + ((STRIP.height - STRIP.accentHeight) / 2) * k).toFixed(1)}"
      width="${(STRIP.accentWidth * k).toFixed(1)}"
      height="${(STRIP.accentHeight * k).toFixed(1)}"
      rx="${((STRIP.accentWidth / 2) * k).toFixed(1)}" fill="${layer.split.color}" />`
    }
  })
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
  // Measured off the device, not taken from watchface.xml: `thickness="40"`
  // renders a 20.2-unit band on a 450 face at a 24-unit pitch, and `width` sets
  // the band's outer edge, so the outermost centre line sits at 202 - 20.2/2.
  const outer = size * 0.4264
  const gap = size * 0.0084
  const thickness = Math.max(8, size * (ambient ? 0.0403 : 0.0449))
  // Ambient art paints a thinner band than it reserves; the ring pitch stays on `thickness`
  // while the stroke and the type punched into it take `band`, so a cap set for the full
  // width cannot overflow the thinned stroke.
  const band = ambient ? thickness * 0.75 : thickness
  const planLayers = sortByRemaining(layers.filter((layer) => layer.used < 1))
  const stripLayers = showPlan ? planLayers : layers.slice(0, 1)

  let ringMarkup = ''
  if (showPlan && planLayers.length > 0) {
    // planLayers are tightest-first; draw index 0 on the innermost radius (center).
    for (let i = 0; i < planLayers.length; i += 1) {
      const fromOutside = planLayers.length - 1 - i
      const r = outer - fromOutside * (thickness + gap)
      const split = planLayers[i].split
      if (split) {
        // Halves of one band: centre lines a quarter-band either side of it,
        // each half as thick, exactly as the face draws them.
        ringArcPair(r, band).forEach(([radius, halfBand], half) => {
          ringMarkup += ringArc({
            cx,
            cy,
            r: radius,
            thickness: halfBand,
            remaining: 1 - (half === 0 ? planLayers[i].used : split.used),
            color: half === 0 ? planLayers[i].color : split.color,
            ambient,
          })
        })
      } else {
        ringMarkup += ringArc({
          cx,
          cy,
          r,
          thickness: band,
          remaining: 1 - planLayers[i].used,
          color: planLayers[i].color,
          ambient,
        })
      }
      if (planLayers[i].period) {
        ringMarkup += ringTexture({
          cx,
          cy,
          r,
          thickness: band,
          period: planLayers[i].period,
          fromOutside,
        })
      }
    }
  } else {
    ringMarkup += `
    <circle cx="${cx}" cy="${cy}" r="${(size * 0.42).toFixed(1)}" fill="none"
      stroke="${TRACK}" stroke-width="${(size * 0.018).toFixed(1)}" />`
  }

  const timeSize = ambient ? size * 0.18 : size * 0.155
  const timeY = cy + timeSize * 0.36
  let content = `
    <text x="${cx}" y="${timeY.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${timeSize.toFixed(1)}"
      font-weight="700" fill="${LABEL}">10:08</text>`
  if (!ambient) {
    content += providerBars({
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
      <stop offset="100%" stop-color="${BACKGROUND}"/>
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
// One connection's three budget periods. The type baseline and its ambient counterpart draw
// the same rings, and sharing the set is what keeps the two boards from drifting apart.
const budgetPeriods = [
  CATALOG.anthropicBudgetWeek,
  CATALOG.anthropicBudgetMonth,
  CATALOG.anthropicBudgetToday,
]

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
    // The split band: one plan on one band, its two pools in their own colours,
    // two markers and two percents on the strip it shares
    // (`WATCH_RING_DESIGN.md`, Split band).
    file: 'round-3-plan-split.svg',
    name: 'Round · 3 providers · a Cursor plan sharing one band',
    layers: [CATALOG.codex, CATALOG.claude, CATALOG.cursorPair],
    showPlan: true,
    showCredits: false,
  },
  {
    // Codex and Cursor keep their own colors, so the budget ring is the only orange one:
    // pairing it with the Claude plan ring would draw the multi-profile case the document
    // still leaves open.
    file: 'round-3-plan-budget.svg',
    name: 'Round · 3 providers · plan + budget',
    layers: [CATALOG.codex, CATALOG.cursor, CATALOG.anthropicBudgetWeek],
    showPlan: true,
    showCredits: false,
  },
  {
    // The board the ring type exists for: one connection's three budget periods wear one
    // family color, so the type punched into each band is all that tells them apart.
    file: 'round-3-budget-periods.svg',
    name: 'Round · 3 budget periods · one connection',
    layers: budgetPeriods,
    showPlan: true,
    showCredits: false,
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
  {
    // Ambient dims the band the type is punched into, it does not switch the type off.
    // The board shows that the type survives; it cannot show at what level, because the
    // arc here is the muted gray of ambient art, not the family color the face dims.
    file: 'round-ambient-budget.svg',
    name: 'Round · ambient · 3 budget periods',
    layers: budgetPeriods,
    ambient: true,
    showPlan: true,
    showCredits: false,
  },
]

const wffFiles = new Set([
  'round-3-plan-credits.svg',
  // A split band is a face-only channel, so its board belongs beside the face too.
  'round-3-plan-split.svg',
  // Ring type is a face-only channel, so its board belongs beside the face too.
  'round-3-budget-periods.svg',
  'round-1-plan-credits.svg',
  'round-credits-only.svg',
  'round-ambient-3.svg',
  'round-ambient-budget.svg',
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
