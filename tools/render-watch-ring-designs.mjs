#!/usr/bin/env node
/**
 * SVG review exports for the locked watch-ring baseline
 * (`docs/product/WATCH_RING_DESIGN.md`).
 *
 * Usage: node tools/render-watch-ring-designs.mjs [--check]
 */

import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { mkdir } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { FONT_FILE, emit, renderPreviews } from './design-output.mjs'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const checking = process.argv.includes('--check')

const SURFACE = '#101412'
const TRACK = '#2E3632'
const LABEL = '#F4FBF8'
const WELL = '#0B0E0C'

/** The ground under everything; ring type is punched down to it rather than inked on top. */
const BACKGROUND = '#0A0D0B'

/**
 * The lit rim of a cell the wearer has not filled. The one colour the upper-cell
 * revision added: not the track, whose contrast would make the rim read as a
 * drawn ring rather than as the edge of a dish.
 */
const CELL_RIM = '#242A27'

/**
 * The cells above the clock, in the face's own units. The readings are the
 * shipped default: the day of the week is a complication, the temperature and
 * the UV index are the face's own chrome and cost no slot.
 */
const CELL = {
  size: 42,
  fontSize: 14,
  /**
   * The occupied-cell border widens inward: a stroke of 1.5 on a path of 40.5
   * spans radius 19.5 to 21.0, preserving the well's edge and band clearance.
   * An empty cell wears none, so a ring means occupied and a recess means free.
   */
  ringDiameter: 40.5,
  ringThickness: 1.5,
  /** `0xaa` of the face's text colour, and the arcs' own ambient proportion. */
  ringAmbientAlpha: 140,
  /**
   * The shipped default: a day-of-week complication, then the face's own weather.
   *
   * The two kinds of filled cell do not share a well. A complication draws an
   * opaque occluder inside its own slot, because it has to cover whatever chrome
   * the scene put under it; a weather reading is that chrome, and takes the
   * strips' own translucent well. The face carries both colours
   * (`WATCH_RING_DESIGN.md`, Upper cells, rule 10), so the board carries them
   * too — a preview draws what the face draws.
   */
  readings: [
    { x: 152, y: 114, text: 'Tue', wellOpacity: 1 },
    { x: 204, y: 100, text: '18°C', wellOpacity: 0xeb / 255 },
    { x: 256, y: 114, text: 'UV 7', wellOpacity: 0xeb / 255 },
  ],
}

/** The WFF border's smoothstep stops, including the watermark's six-percent floor. */
const CELL_RING_FADE = [
  { position: 0, alpha: 0xaa },
  { position: 0.5, alpha: 0xaa },
  { position: 0.625, alpha: 0x91 },
  { position: 0.75, alpha: 0x5a },
  { position: 0.875, alpha: 0x23 },
  { position: 1, alpha: 0x0a },
]

/** The baseline caps the face at three bands, so the strip stack is three rows deep. */
const MAX_RINGS = 3
const STRIP_AMBIENT_ALPHA = 90

/** The one family accent worn by two entries — a plan ring and a budget ring share it. */
const ANTHROPIC = '#E8915A'
const CODEX_SPARK = '#186020'

/** SIL OFL-1.1. Bold for watch-scale labels; the file itself is `FONT_FILE`. */
const FONT = 'Noto Sans'

/** The canvas the face was measured on; every absolute number below is in its units. */
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
  /** The top row of a full stack; a shorter one starts further down. */
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
 * How far above the canvas centre the clock sits, measured off the face: `watchface.xml`
 * declares a `TimeText` box 20 up, and WFF renders the digits 21.7 up. The measured number is
 * the one that counts, here as everywhere in `WATCH_RING_DESIGN.md` — a board that centred the
 * time geometrically argued for a screen nobody ships.
 */
const TIME_LIFT = 21.7

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
  codexPair: {
    id: 'codex',
    used: 0.18,
    color: '#65D78A',
    split: { id: 'codex-spark', used: 0.59, color: CODEX_SPARK },
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
   * which now retains the pair with a grey zero half. This positive value is
   * chosen far enough from 47 to read as a second pool rather than its rounding;
   * the exhausted-half boards below cover the fixture's zero state separately.
   */
  cursorPair: {
    id: 'cursor',
    used: 0.47,
    color: '#7E93B8',
    split: { id: 'cursor-other', used: 0.38, color: '#67E8D4' },
  },
  // The live case that raised the full-ring question: an own pool nobody has
  // touched yet beside an external one already spending.
  cursorPairUntouched: {
    id: 'cursor',
    used: 0,
    color: '#7E93B8',
    split: { id: 'cursor-other', used: 0.25, color: '#67E8D4' },
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

function twoCapCutoff(r, thickness) {
  const capLength = thickness / 2
  return (2 * capLength) / (2 * Math.PI * r)
}

function ringArcBranchGeometry(r, thickness, remaining, nearEmpty) {
  const circ = 2 * Math.PI * r
  const left = Math.min(Math.max(remaining, 0), 0.999)
  return {
    circ,
    left,
    nearEmpty,
    strokeCap: nearEmpty ? 'butt' : 'round',
    paint: circ * left - (nearEmpty ? 0 : thickness),
    used: circ * (1 - left) + (nearEmpty ? 0 : thickness / 2),
  }
}

function ringArcGeometry(r, thickness, remaining) {
  const left = Math.min(Math.max(remaining, 0), 0.999)
  return ringArcBranchGeometry(r, thickness, left, left <= twoCapCutoff(r, thickness))
}

function visibleRingArcLength(geometry, thickness) {
  return geometry.paint + (geometry.strokeCap === 'round' ? thickness : 0)
}

function assertNearExhaustedArcs() {
  const epsilon = 0.000001
  const tolerance = 0.000000001
  for (const diameter of [404, 356, 308]) {
    const r = diameter / 2
    const thickness = 40
    const cutoff = twoCapCutoff(r, thickness)
    const belowRemaining = cutoff - epsilon
    const below = ringArcGeometry(r, thickness, belowRemaining)
    if (
      !below.nearEmpty ||
      below.strokeCap !== 'butt' ||
      below.paint <= 0 ||
      Math.abs(visibleRingArcLength(below, thickness) - below.circ * belowRemaining) > tolerance
    ) {
      throw new Error(
        `ring ${diameter}: a remainder below the two-cap cutoff must stay visible and proportional`,
      )
    }

    const aboveRemaining = cutoff + epsilon
    const above = ringArcGeometry(r, thickness, aboveRemaining)
    const expectedPaint = above.circ * aboveRemaining - thickness
    const expectedUsed = above.circ * (1 - aboveRemaining) + thickness / 2
    if (
      above.nearEmpty ||
      above.strokeCap !== 'round' ||
      above.paint !== expectedPaint ||
      above.used !== expectedUsed ||
      Math.abs(visibleRingArcLength(above, thickness) - above.circ * aboveRemaining) > tolerance
    ) {
      throw new Error(`ring ${diameter}: geometry above the two-cap cutoff must stay inset`)
    }

    const buttAtCutoff = ringArcBranchGeometry(r, thickness, cutoff, true)
    const roundAtCutoff = ringArcBranchGeometry(r, thickness, cutoff, false)
    const cutoffLength = buttAtCutoff.circ * cutoff
    if (
      Math.abs(visibleRingArcLength(buttAtCutoff, thickness) - cutoffLength) > tolerance ||
      Math.abs(visibleRingArcLength(roundAtCutoff, thickness) - cutoffLength) > tolerance
    ) {
      throw new Error(`ring ${diameter}: arc branches must meet at the two-cap cutoff`)
    }

    const markupArgs = { cx: 225, cy: 225, r, thickness, color: '#ffffff', ambient: false }
    if (
      !ringArc({ ...markupArgs, remaining: belowRemaining }).includes(
        'stroke-linecap="butt"',
      ) ||
      !ringArc({ ...markupArgs, remaining: aboveRemaining }).includes(
        'stroke-linecap="round"',
      )
    ) {
      throw new Error(`ring ${diameter}: generated markup must select the branch cap`)
    }
  }
}

function ringArc({ cx, cy, r, thickness, remaining, color, ambient }) {
  const valueColor = ambient ? '#8A968F' : color
  if (remaining <= 0) {
    return `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${TRACK}"
      stroke-width="${thickness}" />`
  }
  if (remaining >= 1) {
    // Nothing spent: a closed ring, because the cap inset below would leave a
    // seam at 12 on a band that has spent nothing to open one
    // (`WATCH_RING_DESIGN.md`, Ring geometry — full-ring revision 2026-08-17).
    return `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${TRACK}"
      stroke-width="${thickness}" />
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${valueColor}"
      stroke-width="${thickness}" />`
  }
  const geometry = ringArcGeometry(r, thickness, remaining)
  // Round caps reach half a thickness past each end, so the drawn span is
  // shortened by one cap on each side and started half a cap later. Below that
  // two-cap cutoff the proportional centreline stays uninset and uses straight
  // ends so its visible length remains equal to the value.
  return `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${TRACK}"
      stroke-width="${thickness}" />
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${valueColor}"
      stroke-width="${thickness}" stroke-linecap="${geometry.strokeCap}"
      stroke-dasharray="${geometry.paint.toFixed(2)} ${geometry.circ.toFixed(2)}"
      stroke-dashoffset="${(-geometry.used).toFixed(2)}"
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
    } else {
      parts.push(`${Math.round(Math.max(0, 1 - layer.used) * 100)}%`)
    }
  }
  // A split strip spends the well on its second percent, so credits never join it
  // (`WATCH_RING_DESIGN.md`, Split band, rules 4 and 5).
  if (layer.split) {
    parts.push(`${Math.round(Math.max(0, 1 - layer.split.used) * 100)}%`)
    return parts.join(' · ')
  }
  // Credits glue onto the matching provider strip only (review art uses Codex credits).
  if (showCredits && (layer.id === 'codex' || layer.providerId === 'codex')) {
    parts.push(layer.credits ?? CREDITS_GLANCE)
  }
  return parts.join(' · ')
}

function sortByRemaining(layers) {
  return [...layers].sort((a, b) =>
    Math.max(b.used, b.split?.used ?? b.used) - Math.max(a.used, a.split?.used ?? a.used),
  )
}

/** Only actual exhaustion colours a percentage; rounded positive zero stays ordinary. */
function zeroLabelMarkup(text, layer) {
  return text.split(' · ').map((part, index) => {
    const exhausted = index === 0
      ? layer.used >= 1 && !layer.budget
      : index === 1 && layer.split?.used >= 1
    return exhausted && part.startsWith('0%')
      ? `<tspan fill="#FFB4AB">0%</tspan>${esc(part.slice(2))}`
      : esc(part)
  }).join(' · ')
}

/**
 * The three cells above the clock, as a fresh install shows them: the left one
 * bound to the day of the week, the other two left empty over the face's own
 * weather chrome. The same integer origins as WFF keep both the translated
 * curved row and its radial fade directions identical to the installed face
 * (`WATCH_RING_DESIGN.md`, Upper cells, rules 1 and 11).
 *
 * Most boards show the shipped default, which is the state a wearer meets first.
 * A cell the wearer cleared shows the graded recess of rule 10 instead — the one
 * thing that tells an empty cell from a broken one — so one board carries that
 * state and `just check-designs` gates it with the rest.
 */
function upperCells({ size, ambient, clearedCells = [] }) {
  const k = size / FACE
  const r = (CELL.size / 2) * k
  // Ambient keeps the recess and dims the reading: a well is a darkening, so
  // switching it off would make the patch brighter, which is backwards. The
  // ring goes the other way — it lights — so it dims with the reading it
  // encloses rather than staying the brightest thing on an ambient face.
  const textOpacity = ambient ? 0.55 : 1
  const ringRadius = (CELL.ringDiameter / 2) * k
  const ringWidth = CELL.ringThickness * k
  // Gradient stops carry the original `0xaa`; ambient dims the whole part.
  const ringOpacity = ambient ? CELL.ringAmbientAlpha / 255 : 1
  return CELL.readings
    .map(({ x, y, text, wellOpacity }, index) => {
      const cellX = x + CELL.size / 2
      const cellY = y + CELL.size / 2
      const cx = cellX * k
      const cy = cellY * k
      const disc = (fill, opacity = 1) => `
    <circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${r.toFixed(1)}" fill="${fill}"${
        opacity === 1 ? '' : ` fill-opacity="${opacity.toFixed(2)}"`
      } />`
      if (clearedCells.includes(index)) {
        return disc('url(#cellRecess)')
      }
      const vx = cellX - FACE / 2
      const vy = cellY - FACE / 2
      const distance = Math.hypot(vx, vy)
      if ([r, ringRadius, ringWidth, distance].some((value) => !Number.isFinite(value) || value <= 0)) {
        throw new Error('Cell border geometry requires finite positive size, radius, stroke and distance from the face centre')
      }
      const dx = (ringRadius * vx) / distance
      const dy = (ringRadius * vy) / distance
      // Match the rounded circle centre, so the darkest point lies on its axis.
      const gradientX = Number(cx.toFixed(1))
      const gradientY = Number(cy.toFixed(1))
      const coordinate = (value) => {
        if (!Number.isFinite(value)) {
          throw new Error('Cell border gradient coordinates must be finite')
        }
        return Number(value.toFixed(6))
      }
      const gradient = `
    <defs>
      <linearGradient id="cellRing${index}" gradientUnits="userSpaceOnUse"
        x1="${coordinate(gradientX - dx)}" y1="${coordinate(gradientY - dy)}"
        x2="${coordinate(gradientX + dx)}" y2="${coordinate(gradientY + dy)}">
${CELL_RING_FADE.map(({ position, alpha }) => `        <stop offset="${position}" stop-color="${LABEL}" stop-opacity="${alpha / 255}" />`).join('\n')}
      </linearGradient>
    </defs>`
      return `${disc(WELL, wellOpacity)}
${gradient}
    <circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${ringRadius.toFixed(2)}" fill="none"
      stroke="url(#cellRing${index})" stroke-width="${ringWidth.toFixed(2)}"
      stroke-opacity="${ringOpacity}" />
    <text x="${cx.toFixed(1)}" y="${cy.toFixed(1)}" text-anchor="middle" dominant-baseline="central"
      font-family="${FONT}, sans-serif" font-size="${(CELL.fontSize * k).toFixed(1)}"
      font-weight="700" fill="${LABEL}" fill-opacity="${textOpacity}">${esc(text)}</text>`
    })
    .join('')
}

function providerBars({ layers, showPlan, showCredits, size, ambient }) {
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

  // The stack anchors to its bottom row, as the face's does since each strip
  // moved into its own ring's slot: the rows a face draws are always contiguous
  // and always end on the lowest one, so a short stack sits low rather than
  // leaving a gap under it (`WATCH_RING_DESIGN.md`, Upper cells, rule 3).
  const topRow = STRIP.y + (MAX_RINGS - rows.length) * STRIP.pitch

  let out = ''
  rows.forEach((row, index) => {
    const { layer, text } = row
    const y = (topRow + index * STRIP.pitch) * k
    // Match the face's enclosing strip Group so the whole row dims together.
    if (ambient) {
      out += `
    <g opacity="${STRIP_AMBIENT_ALPHA / 255}">`
    }
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
      font-weight="700" fill="${LABEL}">${zeroLabelMarkup(text, layer)}</text>`
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
    if (ambient) {
      out += `
    </g>`
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
  clearedCells = [],
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
  const hasPercent = (value) => Number.isFinite(value) && value >= 0
  const knownLayers = layers.flatMap((layer) => {
    if (!hasPercent(layer.used)) {
      return hasPercent(layer.split?.used)
        ? [{ ...layer.split, providerId: layer.providerId ?? layer.id, credits: layer.credits, split: null }]
        : []
    }
    return [{ ...layer, split: hasPercent(layer.split?.used) ? layer.split : null }]
  })
  const planLayers = sortByRemaining(knownLayers)
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
  const timeY = cy - TIME_LIFT * (size / FACE) + timeSize * 0.36
  let content = upperCells({ size, ambient, clearedCells })
  content += `
    <text x="${cx}" y="${timeY.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${timeSize.toFixed(1)}"
      font-weight="700" fill="${LABEL}">10:08</text>`
  content += providerBars({
    layers: stripLayers,
    showPlan,
    showCredits,
    size,
    ambient,
  })

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="${esc(name)}">
  <defs>
    <radialGradient id="lift" cx="50%" cy="48%" r="62%">
      <stop offset="0%" stop-color="#18201C"/>
      <stop offset="55%" stop-color="${SURFACE}"/>
      <stop offset="100%" stop-color="${BACKGROUND}"/>
    </radialGradient>
    <radialGradient id="cellRecess" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="${WELL}"/>
      <stop offset="55%" stop-color="${WELL}"/>
      <stop offset="100%" stop-color="${CELL_RIM}"/>
    </radialGradient>
  </defs>
  <rect width="${size}" height="${size}" fill="url(#lift)"/>
  ${ringMarkup}
  ${content}
</svg>
`.replace(/^[ \t]+$/gm, '')
}

const wearDir = join(root, 'apps/wear_android/design')
const wffDir = join(root, 'apps/watchface_wff/design')
if (!checking) {
  await mkdir(wearDir, { recursive: true })
  await mkdir(wffDir, { recursive: true })
}

const three = [CATALOG.codex, CATALOG.claude, CATALOG.cursor]
const two = [CATALOG.codex, CATALOG.claude]
const one = [CATALOG.codex]
const exhaustedClaude = { ...CATALOG.claude, used: 1 }
const liveCodex = { ...CATALOG.codex, used: 0.04, credits: '62.5K' }
const liveCursor = { ...CATALOG.cursorPairUntouched, split: { id: 'cursor-other', used: 0.32, color: '#67E8D4' } }
const cursorInnerZero = { ...liveCursor, used: 1 }
const cursorOuterZero = { ...liveCursor, split: { ...liveCursor.split, used: 1 } }
const cursorBothZero = { ...cursorInnerZero, split: { ...liveCursor.split, used: 1 } }
const nearExhausted = [
  { ...CATALOG.codex, used: 0.98 },
  { ...CATALOG.claude, used: 0.31 },
  { ...CATALOG.cursor, used: 0.06 },
]
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
    file: 'round-3-plan-two-pairs.svg',
    name: 'Round · 3 bands · Cursor and Codex plan pairs',
    layers: [CATALOG.claude, CATALOG.codexPair, CATALOG.cursorPair],
    showPlan: true,
    showCredits: false,
  },
  {
    // A band at 100% remaining closes: no melt to inset, so no seam at 12. The
    // rest of the board is the everyday case, so the closed ring is the only
    // thing to compare.
    file: 'round-3-plan-untouched.svg',
    name: 'Round · 3 providers · an untouched pool closes its half',
    layers: [CATALOG.codex, CATALOG.claude, CATALOG.cursorPairUntouched],
    showPlan: true,
    showCredits: false,
  },
  {
    // Reproduces the 2026-09-26 device report: the critical 2% remainder stays
    // visible beside ordinary 69% and 94% rings.
    file: 'round-3-plan-near-exhausted.svg',
    name: 'Round · 3 providers · 2%, 69%, and 94% remaining',
    layers: nearExhausted,
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
    // The left cell has no weather under it, so clearing it is the one way to
    // meet the bare recess — the state the gradient exists for
    // (`WATCH_RING_DESIGN.md`, Upper cells, rules 10 and 11).
    file: 'round-3-plan-cell-cleared.svg',
    name: 'Round · 3 providers · cleared upper cell',
    layers: three,
    showPlan: true,
    showCredits: true,
    clearedCells: [0],
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
  ...[
    { file: 'round-1-plan-exhausted.svg', name: 'Selected Claude 5h at zero', layers: [exhaustedClaude] },
    { file: 'round-3-plan-exhausted-claude.svg', name: 'Claude zero with Cursor pair and Codex', layers: [exhaustedClaude, liveCursor, liveCodex] },
    { file: 'round-plan-pair-inner-zero.svg', name: 'Selected pair with inner pool zero', layers: [cursorInnerZero, liveCodex] },
    { file: 'round-plan-pair-outer-zero.svg', name: 'Selected pair with outer pool zero', layers: [cursorOuterZero, liveCodex] },
    { file: 'round-plan-pair-both-zero.svg', name: 'Selected pair with both pools zero', layers: [cursorBothZero, liveCodex] },
    { file: 'round-3-plan-all-zero.svg', name: 'All three selected bands at zero', layers: [exhaustedClaude, cursorBothZero, { ...liveCodex, used: 1 }] },
    { file: 'round-ambient-all-zero.svg', name: 'Ambient selected bands at zero', layers: [exhaustedClaude, cursorBothZero, { ...liveCodex, used: 1 }], ambient: true },
    { file: 'round-plan-positive-rounds-zero.svg', name: 'Positive fraction rounds to ordinary zero label', layers: [{ ...CATALOG.claude, used: 0.999 }] },
    { file: 'round-plan-zero-credits.svg', name: 'Exhausted percent with neutral zero credits', layers: [{ ...CATALOG.codex, used: 1, credits: '0' }] },
    { file: 'round-plan-unavailable-inner-zero-outer.svg', name: 'Unavailable inner pool with known exhausted outer survivor', layers: [{ ...cursorOuterZero, used: -1 }] },
    { file: 'round-3-plan-two-pairs-zero.svg', name: 'Three selected bands with two exhausted pairs', layers: [exhaustedClaude, cursorBothZero, { ...CATALOG.codexPair, used: 1, split: { ...CATALOG.codexPair.split, used: 1 } }] },
    { file: 'round-budget-exhausted.svg', name: 'Exhausted budget keeps its money label', layers: [{ ...CATALOG.anthropicBudgetMonth, used: 1, budget: '$100.00/100' }] },
  ].map((variant) => ({ ...variant, showPlan: true, showCredits: true })),
]

const wffFiles = new Set([
  'round-1-plan-exhausted.svg',
  'round-3-plan-exhausted-claude.svg',
  'round-plan-pair-inner-zero.svg',
  'round-plan-pair-outer-zero.svg',
  'round-plan-pair-both-zero.svg',
  'round-3-plan-all-zero.svg',
  'round-ambient-all-zero.svg',
  'round-plan-positive-rounds-zero.svg',
  'round-plan-zero-credits.svg',
  'round-plan-unavailable-inner-zero-outer.svg',
  'round-3-plan-two-pairs-zero.svg',
  'round-budget-exhausted.svg',
  'round-3-plan-credits.svg',
  // A split band is a face-only channel, so its board belongs beside the face too.
  'round-3-plan-split.svg',
  'round-3-plan-two-pairs.svg',
  // Ring type is a face-only channel, so its board belongs beside the face too.
  'round-3-budget-periods.svg',
  // Closing a full ring is a face drawing rule, so its board goes beside it.
  'round-3-plan-untouched.svg',
  'round-3-plan-near-exhausted.svg',
  'round-1-plan-credits.svg',
  'round-credits-only.svg',
  // An empty cell is a face drawing rule, so its board belongs beside the face.
  'round-3-plan-cell-cleared.svg',
  'round-ambient-3.svg',
  'round-ambient-budget.svg',
])

/**
 * Where the face puts the watermark, read out of the shipped face rather than
 * repeated here. The portrait composes the mark at this box, so the two cannot
 * drift: move it in `render-watchface.mjs` and the picture follows on the next
 * render.
 *
 * The group holds two images — the interactive mark, and a smaller one only an
 * ambient variant reveals — and the portrait is the active treatment, so this
 * takes the one that is visible with no variant. A shape this read does not
 * recognise throws rather than guessing a box.
 */
function watermarkBox() {
  const xml = readFileSync(join(root, 'apps/watchface_wff/src/main/res/raw/watchface.xml'), 'utf8')
  const group = xml.match(/<Group\b[^>]*name="wardpulse"[^>]*>([\s\S]*?)<\/Group>/)
  if (!group) throw new Error('watchface.xml has no group named "wardpulse"')
  const part = [...group[1].matchAll(/<PartImage\b([^>]*)>/g)]
    .map((match) => Object.fromEntries(
      [...match[1].matchAll(/(\w+)="([^"]*)"/g)].map(([, key, value]) => [key, value]),
    ))
    .find((attrs) => attrs.alpha !== '0')
  if (!part) throw new Error('watchface.xml draws no visible watermark PartImage')
  return {
    x: Number(part.x),
    y: Number(part.y),
    width: Number(part.width),
    height: Number(part.height),
    alpha: Number(part.alpha) / 255,
  }
}

/** The density that takes a 450-unit board to the 675 a review preview is read at. */
const PREVIEW_DENSITY = 144

/**
 * Every board has exactly one preview, named after it. Deriving the list from
 * the boards rather than keeping a second one beside them means a new variant
 * cannot ship without the picture the baseline will be read against — three of
 * the rows Review variants labels *baseline* had no preview at all until the
 * coverage revision of 2026-10-11.
 */
const previews = variants.map(({ file }) => ({
  svg: join(wearDir, file),
  png: join(wearDir, `preview-${file.replace(/^round-/, '').replace(/\.svg$/, '.png')}`),
  density: PREVIEW_DENSITY,
}))

/**
 * `watch_face_info.xml` declares this file as the face's `Preview` and the build
 * needs it, so it is rasterized at the face's own 450 rather than the 675 a
 * review board is read at.
 *
 * It is the one preview that is composed rather than only rasterized. A review
 * board is mark-free, and this file is not a board: it is the face's portrait,
 * and the face draws the quiet watermark. The box comes out of `watchface.xml`
 * at render time rather than being repeated here, so the portrait cannot
 * disagree with the face about where the mark sits (`WATCH_RING_DESIGN.md`,
 * watermark revision 2026-10-11; `docs/DESIGN_ASSETS.md` owns the mark).
 */
const pickerPreview = {
  svg: join(wffDir, 'round-3-plan-credits.svg'),
  png: join(root, 'apps/watchface_wff/src/main/res/drawable/preview.png'),
  density: 96,
  overlay: {
    image: join(root, 'apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png'),
    ...watermarkBox(),
  },
}

assertNearExhaustedArcs()

for (const variant of variants) {
  const svg = faceSvg({
    name: variant.name,
    size: 450,
    layers: variant.layers,
    ambient: variant.ambient === true,
    showPlan: variant.showPlan,
    showCredits: variant.showCredits,
    clearedCells: variant.clearedCells ?? [],
  })
  await emit(join(wearDir, variant.file), svg, 'render-designs')
  if (wffFiles.has(variant.file)) {
    await emit(join(wffDir, variant.file), svg, 'render-designs')
  }
}

await renderPreviews([...previews, pickerPreview])
