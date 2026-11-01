#!/usr/bin/env node
/**
 * SVG review exports for the locked watch-ring baseline
 * (`docs/product/WATCH_RING_DESIGN.md`).
 *
 * Usage: node tools/render-watch-ring-designs.mjs [--check]
 *
 * One local UNAPPROVED PREVIEW ONLY active face, without canonical export writes:
 *   node tools/render-watch-ring-designs.mjs --clock-preview-up <450-unit-offset> \
 *     --clock-preview-output LOCAL_ARTIFACTS/<new-directory>
 * The offset must be positive in 0.1-unit increments; no offset is approved here.
 * The destination's parent must exist, and its resolved path must stay inside
 * LOCAL_ARTIFACTS. The destination must be new. Preview flags cannot use --check.
 * Produces one 450x450 logo-composited PNG, its intermediate SVG, and metadata
 * with the exact invocation, content, source/input hashes and output identities.
 * Host review art does not establish native WFF fit or approve runtime adoption.
 */

import assert from 'node:assert/strict'
import { execFile } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { mkdir, readFile, realpath, writeFile } from 'node:fs/promises'
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

import { FONT_FILE, emit, renderPreviews } from './design-output.mjs'

const runFile = promisify(execFile)

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const checking = process.argv.includes('--check')
const clockPreview = parseClockPreview(process.argv.slice(2))

function parseClockPreview(args) {
  if (args.length === 0 || (args.length === 1 && args[0] === '--check')) return null
  const values = new Map()
  for (let index = 0; index < args.length; index += 2) {
    const flag = args[index]
    const value = args[index + 1]
    if (!['--clock-preview-up', '--clock-preview-output'].includes(flag) ||
        values.has(flag) || !value || value.startsWith('--')) {
      throw new Error('use both clock preview flags exactly once, without --check or other flags')
    }
    values.set(flag, value)
  }
  const up = Number(values.get('--clock-preview-up'))
  if (values.size !== 2 || !Number.isFinite(up) || up <= 0 || up !== Number(up.toFixed(1))) {
    throw new Error('clock preview requires an output directory and a positive offset in 0.1-unit increments')
  }
  return { up, output: values.get('--clock-preview-output') }
}

async function clockPreviewDirectory(output, resolveParent = realpath) {
  const localRoot = join(root, 'LOCAL_ARTIFACTS')
  const requested = resolve(root, output)
  const insideLocal = (path) => {
    const fromLocal = relative(localRoot, path)
    return fromLocal !== '' && fromLocal !== '..' &&
      !fromLocal.startsWith(`..${sep}`) && !isAbsolute(fromLocal)
  }
  if (!insideLocal(requested)) {
    throw new Error('clock preview output must be a new directory inside LOCAL_ARTIFACTS')
  }
  const directory = join(await resolveParent(dirname(requested)), basename(requested))
  if (!insideLocal(directory)) {
    throw new Error('clock preview output resolves outside LOCAL_ARTIFACTS')
  }
  return directory
}

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
 * illustrative Auto state with a known Celsius source: the day of the week is
 * a complication, the temperature and UV are the face's own chrome and cost no slot.
 */
const CELL = {
  size: 52,
  fontSize: 18,
  textWidth: 46,
  /**
   * The occupied-cell border is inscribed: a stroke of 1.5 on a path of 50.5
   * spans radius 24.5 to 26.0.
   * An empty cell wears none, so a ring means occupied and a recess means free.
   */
  ringDiameter: 50.5,
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
    { x: 147, y: 109, text: 'Tue', wellOpacity: 1 },
    { x: 199, y: 95, text: '18°C', temperature: 18, wellOpacity: 0xeb / 255 },
    { x: 251, y: 109, text: 'UV 7', uv: 7, wellOpacity: 0xeb / 255 },
  ],
}

/** The WFF outward fade, also normalized for the lateral bottom masks. */
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
 * Fixed in the 450-unit language: 132x26 boxes stepping 27 from y=259,
 * with 20/18/16-unit labels inside a centred 120-unit text region. Sizing a box to
 * its content instead is what let review art drift a stack wider than the watch draws.
 *
 * The accent is what the face paints, not what its markup declares: a 3x14 arc under a
 * 3-thick stroke covers 17 units of height and 6 of width, the left half clipped away by the
 * box edge. Same path-versus-paint trap the design document flags for the ring bands.
 */
const STRIP = {
  x: 159,
  /** The top row of a full stack; a shorter one starts further down. */
  y: 259,
  width: 132,
  height: 26,
  pitch: 27,
  radius: 6,
  accentWidth: 4.5,
  accentHeight: 17,
  textInset: 6,
  textWidth: 120,
  fontSize: 20,
}

/**
 * Active adopts the approved 10-unit upward translation; ambient retains its
 * measured 08:08 reference baseline. Host SVG metrics are illustrative, not native
 * fit or balanced-gap acceptance; other time strings retain their natural optics.
 */
const CLOCK = {
  active: { fontSize: 86, baseline: 240.78125, weight: 700 },
  ambient: { fontSize: 96, baseline: 254.296875, weight: 100 },
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

// New-radius fits mirror the face's ADAPTIVE_REPEATS; N3 type repeats stay unchanged.
const ADAPTIVE_REPEATS = {
  1: { D: [11], '7D': [7], M: [9] },
  2: { D: [15, 11], '7D': [9, 6], M: [12, 9] },
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

function stripFontSize(text) {
  return text.length >= 12 ? 16 : text.length === 11 ? 18 : STRIP.fontSize
}

/**
 * Widths guard the labels instead of placing them: a supported label that
 * outgrows the fixed region must fail rather than silently overhang. A missing
 * font or Pillow fails too; substituted metrics would change the review art.
 */
async function assertLabelsFit(texts, { fontSize = stripFontSize, width = STRIP.textWidth } = {}) {
  const controller = new AbortController()
  const interrupt = () => controller.abort()
  process.on('SIGINT', interrupt)
  process.on('SIGTERM', interrupt)
  const metrics = runFile(
    'python3',
    [
      '-c',
      [
        'import json',
        'from PIL import ImageFont',
        `font_file = ${JSON.stringify(FONT_FILE)}`,
        `labels = ${JSON.stringify(texts.map((text) => [text, fontSize(text)]))}`,
        'fonts = {size: ImageFont.truetype(font_file, size) for _, size in labels}',
        'print(json.dumps({t: fonts[size].getbbox(t)[2] - fonts[size].getbbox(t)[0] for t, size in labels}))',
      ].join('\n'),
    ],
    { encoding: 'utf8', signal: controller.signal },
  )
  const closed = new Promise((resolve) => metrics.child.once('close', resolve))
  let stdout
  try {
    stdout = (await metrics).stdout
    controller.signal.throwIfAborted()
  } finally {
    await closed
    process.off('SIGINT', interrupt)
    process.off('SIGTERM', interrupt)
  }
  for (const [text, measuredWidth] of Object.entries(JSON.parse(stdout))) {
    if (measuredWidth > width) {
      throw new Error(
        `label "${text}" is ${measuredWidth} units wide, past the ${width}-unit region`,
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
  const geometries = [1, 2, 3].flatMap((count) => {
    const width = [44, 32, 20][count - 1]
    return Array.from({ length: count }, (_, index) => {
      // Preserve the accepted measured N3 art, including its ambient model.
      const modes = count === 3 ? [false, true] : [false]
      return modes.flatMap((ambient) => {
        const pitchWidth = count === 3 ? 450 * (ambient ? 0.0403 : 0.0449) : width
        const band = ambient ? pitchWidth * 0.75 : pitchWidth
        const r = count === 3
          ? 450 * 0.4264 - index * (pitchWidth + 450 * 0.0084)
          : 202 - index * (width + 4) - width / 2
        return [[r, band], ...ringArcPair(r, band)]
      })
    }).flat()
  })
  for (const [r, thickness] of geometries) {
    const diameter = r * 2
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

function ringTexture({ cx, cy, r, thickness, period, fromOutside, count }) {
  const repeats = (count === 3 ? TEXTURE.repeats : ADAPTIVE_REPEATS[count])?.[period]?.[fromOutside]
  if (!repeats) {
    throw new Error(`no measured repeat count for "${period}" on ring ${fromOutside + 1}`)
  }
  const cap = count === 3 ? thickness * TEXTURE.capOfBand : 15.756 * (cx * 2 / FACE)
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

function cellFontSize({ text, temperature, uv }) {
  if (temperature !== undefined) {
    if (temperature <= -100) return 12
    return temperature < 0 || temperature >= 100 ? 14 : CELL.fontSize
  }
  if (uv !== undefined) return uv >= 10 ? 14 : CELL.fontSize
  return text.length >= 7 ? 12 : text.length >= 5 ? 14 : CELL.fontSize
}

/**
 * The three cells as a fresh install shows them when weather is available: a
 * day-of-week complication, then the face's own temperature and UV chrome.
 * Integer origins, outward fades and border-only lateral bottom masks match WFF.
 * A cleared cell shows the graded recess instead.
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
    .map(({ x, y, text, temperature, uv, wellOpacity }, index) => {
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
      // Match the rounded circle centre for both independent gradient axes.
      const gradientX = Number(cx.toFixed(1))
      const gradientY = Number(cy.toFixed(1))
      const coordinate = (value) => {
        if (!Number.isFinite(value)) {
          throw new Error('Cell border gradient coordinates must be finite')
        }
        return Number(value.toFixed(6))
      }
      const bottomMask = vx === 0 ? '' : `
      <linearGradient id="cellBottom${index}" gradientUnits="userSpaceOnUse"
        x1="${coordinate(gradientX)}" y1="${coordinate(gradientY - ringRadius)}"
        x2="${coordinate(gradientX)}" y2="${coordinate(gradientY + ringRadius)}">
${CELL_RING_FADE.map(({ position, alpha }) => `        <stop offset="${position}" stop-color="white" stop-opacity="${Math.round(alpha * 255 / 0xaa) / 255}" />`).join('\n')}
      </linearGradient>
      <mask id="cellBottomMask${index}" maskUnits="userSpaceOnUse"
        x="${coordinate(cx - r)}" y="${coordinate(cy - r)}" width="${coordinate(2 * r)}" height="${coordinate(2 * r)}">
        <rect x="${coordinate(cx - r)}" y="${coordinate(cy - r)}" width="${coordinate(2 * r)}" height="${coordinate(2 * r)}" fill="url(#cellBottom${index})" />
      </mask>`
      const gradient = `
    <defs>
      <linearGradient id="cellRing${index}" gradientUnits="userSpaceOnUse"
        x1="${coordinate(gradientX - ringRadius * vx / distance)}" y1="${coordinate(gradientY - ringRadius * vy / distance)}"
        x2="${coordinate(gradientX + ringRadius * vx / distance)}" y2="${coordinate(gradientY + ringRadius * vy / distance)}">
${CELL_RING_FADE.map(({ position, alpha }) => `        <stop offset="${position}" stop-color="${LABEL}" stop-opacity="${alpha / 255}" />`).join('\n')}
      </linearGradient>${bottomMask}
    </defs>`
      const fontSize = cellFontSize({ text, temperature, uv })
      return `${disc(WELL, wellOpacity)}
${gradient}
    <circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${ringRadius.toFixed(2)}" fill="none"
      stroke="url(#cellRing${index})" stroke-width="${ringWidth.toFixed(2)}"
      stroke-opacity="${ringOpacity}"${vx === 0 ? '' : ` mask="url(#cellBottomMask${index})"`} />
    <text x="${cx.toFixed(1)}" y="${cy.toFixed(1)}" text-anchor="middle" dominant-baseline="central"
      font-family="${FONT}, sans-serif" font-size="${(fontSize * k).toFixed(1)}"
      font-weight="700" fill="${LABEL}" fill-opacity="${textOpacity}">${esc(text)}</text>`
    })
    .join('')
}

async function providerBars({ layers, showPlan, showCredits, size, ambient }) {
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
  await assertLabelsFit(rows.map((row) => row.text))

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
      font-family="${FONT}, sans-serif" font-size="${(stripFontSize(text) * k).toFixed(1)}"
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

async function faceSvg({
  name,
  size,
  layers = [],
  ambient = false,
  showPlan = true,
  showCredits = false,
  clearedCells = [],
  clockUp = 0,
}) {
  const cx = size / 2
  const cy = size / 2
  // Measured off the device, not taken from watchface.xml: `thickness="40"`
  // renders a 20.2-unit band on a 450 face at a 24-unit pitch, and `width` sets
  // the band's outer edge, so the outermost centre line sits at 202 - 20.2/2.
  let outer = size * 0.4264
  let gap = size * 0.0084
  let thickness = Math.max(8, size * (ambient ? 0.0403 : 0.0449))
  // Ambient art paints a thinner band than it reserves; the ring pitch stays on `thickness`
  // while the stroke and the type punched into it take `band`, so a cap set for the full
  // width cannot overflow the thinned stroke.
  let band = ambient ? thickness * 0.75 : thickness
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
  if (planLayers.length > 3) throw new Error('the face supports at most three bands')
  if (planLayers.length > 0 && planLayers.length < 3) {
    const scale = size / FACE
    thickness = [44, 32, 20][planLayers.length - 1] * scale
    outer = 202 * scale - thickness / 2
    gap = 4 * scale
    band = thickness
  }
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
          count: planLayers.length,
        })
      }
    }
  } else {
    ringMarkup += `
    <circle cx="${cx}" cy="${cy}" r="${(size * 0.42).toFixed(1)}" fill="none"
      stroke="${TRACK}" stroke-width="${(size * 0.018).toFixed(1)}" />`
  }

  const clock = ambient ? CLOCK.ambient : CLOCK.active
  const timeSize = clock.fontSize * size / FACE
  const timeY = (clock.baseline - clockUp) * size / FACE
  let content = upperCells({ size, ambient, clearedCells })
  content += `
    <text x="${cx}" y="${timeY.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${timeSize.toFixed(1)}"
      font-weight="${clock.weight}" fill="${LABEL}">10:08</text>`
  content += await providerBars({
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

const adaptiveBudgets = {
  D: CATALOG.anthropicBudgetToday,
  '7D': CATALOG.anthropicBudgetWeek,
  M: CATALOG.anthropicBudgetMonth,
}
const periods = Object.keys(adaptiveBudgets)

const adaptiveVariants = [
  { file: 'round-1-plan-split.svg', name: 'One adaptive band with two pools', layers: [CATALOG.cursorPair] },
  { file: 'round-2-plan-two-pairs.svg', name: 'Two adaptive bands with two pairs', layers: [CATALOG.codexPair, CATALOG.cursorPair] },
  ...[false, true].flatMap((ambient) => periods.map((period) => ({
    file: `round-${ambient ? 'ambient-' : ''}1-budget-${period.toLowerCase()}.svg`,
    name: `One adaptive budget band · ${period}${ambient ? ' · ambient' : ''}`,
    layers: [adaptiveBudgets[period]], ambient,
  }))),
  // Rotate distinct periods across both radii. Synthetic money/usage agree,
  // and no board invents a duplicate budget for one connection and period.
  ...[false, true].flatMap((ambient) => periods.map((period, index) => ({
    file: `round-${ambient ? 'ambient-' : ''}2-budget-${period.toLowerCase()}.svg`,
    name: `Two adaptive budget bands · ${period}${ambient ? ' · ambient' : ''}`,
    layers: [
      { ...adaptiveBudgets[period], used: 0.25, budget: '$25.00/100' },
      { ...adaptiveBudgets[periods[(index + 1) % periods.length]], used: 0.5, budget: '$50.00/100' },
    ], ambient,
  }))),
].map((variant) => ({ ...variant, showPlan: true, showCredits: false }))

const variants = [
  ...adaptiveVariants,
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
  ...adaptiveVariants.map(({ file }) => file),
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

function assertClockOnlyPreview(reference, preview, up) {
  const clock = (svg) => {
    const matches = [...svg.matchAll(/<text\b[^>]*>10:08<\/text>/g)]
    assert.equal(matches.length, 1, 'preview must retain the single whole 10:08 clock')
    const markup = matches[0][0]
    const y = markup.match(/\by="([^"]+)"/)
    assert.ok(y, 'clock must have a y coordinate')
    return { markup, y: y[1] }
  }
  const before = clock(reference)
  const after = clock(preview)
  const restored = preview.replace(after.markup, after.markup.replace(/\by="[^"]+"/, `y="${before.y}"`))
  assert.equal(restored, reference, 'preview may change only the clock y coordinate')
  assert.equal(Number((Number(before.y) - Number(after.y)).toFixed(1)), up,
    'preview must move upward by the requested 450-unit offset')
  assert.ok(Number(after.y) > 0 && Number(after.y) < Number(before.y),
    'preview clock baseline must remain positive and move upward')
  return { referenceY: Number(before.y), previewY: Number(after.y) }
}

async function sha256(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex')
}

async function renderClockPreview({ up, output }) {
  const directory = await clockPreviewDirectory(output)
  const primary = variants.find(({ file }) => file === 'round-3-plan-credits.svg')
  const reference = await faceSvg({ ...primary, size: FACE })
  const svg = await faceSvg({ ...primary, size: FACE, clockUp: up })
  const clock = assertClockOnlyPreview(reference, svg, up)
  const referencePath = join(wearDir, primary.file)
  assert.equal(reference, await readFile(referencePath, 'utf8'),
    'preview reference must match the accepted Primary board')
  const inputPaths = [
    'tools/render-watch-ring-designs.mjs',
    'tools/design-output.mjs',
    'tools/render-watchface.mjs',
    'apps/watchface_wff/src/main/res/raw/watchface.xml',
    'apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png',
    relative(root, referencePath),
    relative(root, join(wffDir, primary.file)),
    FONT_FILE,
  ]
  const inputHashes = Object.fromEntries(await Promise.all(inputPaths.map(async (path) =>
    [path, await sha256(resolve(root, path))])))
  const { stdout: rendererVersion } = await runFile('convert', ['-version'], { encoding: 'utf8' })
  // Exclusive creation keeps existing candidates, links and canonical files out of the write set.
  await mkdir(directory, { mode: 0o700 })
  const stem = join(directory, 'UNAPPROVED-PREVIEW-ONLY')
  const svgPath = `${stem}.input.svg`
  const pngPath = `${stem}.png`
  await writeFile(svgPath, svg, { flag: 'wx' })
  await renderPreviews([{
    svg: svgPath,
    png: pngPath,
    density: pickerPreview.density,
    overlay: pickerPreview.overlay,
  }])
  const png = await readFile(pngPath)
  assert.ok(png.length >= 24 &&
    png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
    png.toString('ascii', 12, 16) === 'IHDR', 'preview output must be a PNG')
  const width = png.readUInt32BE(16)
  const height = png.readUInt32BE(20)
  assert.equal(width, FACE, 'preview must retain the 450-unit canvas width')
  assert.equal(height, FACE, 'preview must retain the 450-unit canvas height')
  const metadata = {
    status: 'UNAPPROVED PREVIEW ONLY',
    evidence: 'Host review art only; no native WFF fit or runtime approval.',
    invocation: { cwd: process.cwd(), argv: [process.execPath, ...process.argv.slice(1)] },
    tools: { node: process.version, imageMagick: rendererVersion.trim() },
    inputHashes,
    reference: relative(root, referencePath),
    clock: { upwardOffset450: up, ...clock },
    displayedContent: {
      time: '10:08',
      cells: CELL.readings.map(({ text }) => text),
      legend: sortByRemaining(primary.layers).map((layer) => ({
        provider: layer.id,
        text: barLabel(layer, primary),
      })),
      layers: primary.layers,
    },
    logo: pickerPreview.overlay,
    outputs: {
      intermediateSvg: { file: basename(svgPath), sha256: await sha256(svgPath) },
      fullFacePng: { file: basename(pngPath), width, height, sha256: await sha256(pngPath) },
    },
  }
  await writeFile(`${stem}.json`, `${JSON.stringify(metadata, null, 2)}\n`, { flag: 'wx' })
  console.log(`UNAPPROVED PREVIEW ONLY: ${pngPath}`)
}

async function writeDesigns(preview, {
  writePreview = renderClockPreview,
  emitSvg = emit,
  renderImages = renderPreviews,
} = {}) {
  if (preview) {
    await writePreview(preview)
    return
  }
  if (!checking) {
    await mkdir(wearDir, { recursive: true })
    await mkdir(wffDir, { recursive: true })
  }
  for (const variant of variants) {
    const svg = await faceSvg({
      name: variant.name,
      size: FACE,
      layers: variant.layers,
      ambient: variant.ambient === true,
      showPlan: variant.showPlan,
      showCredits: variant.showCredits,
      clearedCells: variant.clearedCells ?? [],
    })
    await emitSvg(join(wearDir, variant.file), svg, 'render-designs')
    if (wffFiles.has(variant.file)) {
      await emitSvg(join(wffDir, variant.file), svg, 'render-designs')
    }
  }
  await renderImages([...previews, pickerPreview])
}

async function assertClockPreviewIsolation() {
  // Synthetic guard inputs do not select or publish a design offset or candidate.
  const flags = ['--clock-preview-up', '1', '--clock-preview-output', 'LOCAL_ARTIFACTS/preview-guard']
  const preview = parseClockPreview(flags)
  assert.equal(parseClockPreview([]), null)
  assert.equal(parseClockPreview(['--check']), null)
  assert.throws(() => parseClockPreview([...flags, '--check']), /without --check/)
  assert.throws(() => parseClockPreview(flags.slice(0, 2)), /requires an output directory/)
  for (const offset of ['0', '-1', 'NaN', '0.01']) {
    assert.throws(() => parseClockPreview([flags[0], offset, ...flags.slice(2)]), /positive offset/)
  }
  const parentUnchanged = async (path) => path
  assert.equal(await clockPreviewDirectory(preview.output, parentUnchanged), resolve(root, preview.output))
  for (const output of ['LOCAL_ARTIFACTS', 'apps/watchface_wff/design', 'LOCAL_ARTIFACTS/../brand']) {
    await assert.rejects(clockPreviewDirectory(output, parentUnchanged), /inside LOCAL_ARTIFACTS/)
  }
  await assert.rejects(clockPreviewDirectory(preview.output, async () => wearDir), /resolves outside/)
  const primary = variants.find(({ file }) => file === 'round-3-plan-credits.svg')
  const reference = await faceSvg({ ...primary, size: FACE })
  const candidate = await faceSvg({ ...primary, size: FACE, clockUp: preview.up })
  assertClockOnlyPreview(reference, candidate, preview.up)
  let previewWrites = 0
  const rejectCanonicalWrite = () => assert.fail('preview must not write or render canonical exports')
  await writeDesigns(preview, {
    writePreview: async (options) => {
      assert.deepEqual(options, preview)
      previewWrites += 1
    },
    emitSvg: rejectCanonicalWrite,
    renderImages: rejectCanonicalWrite,
  })
  assert.equal(previewWrites, 1, 'preview must dispatch exactly one candidate')
}

assertNearExhaustedArcs()

// Common and compact-bound labels must remain complete at the selected size.
// Extreme signed money and arbitrary provider text retain runtime ellipsis.
await assertLabelsFit([
  '100% · 64%', '82% · 59.5K', '100% · 100%', '100% · 999.9T',
  '$999.99/999', '$999.99/999.9T', '$999.9T/999.9T', '$-12.34/100',
  '0% · 0%', '0% · 0',
])

// Weather branches use the original numeric value and device-provided scale.
const cellFitReadings = [
  { text: 'Sat' }, { text: 'Wed' },
  { text: '18°C', temperature: 18 }, { text: '48°F', temperature: 48 },
  { text: '-10°C', temperature: -10 }, { text: '100°F', temperature: 100 },
  { text: '-100°C', temperature: -100 },
  { text: 'UV 7', uv: 7 }, { text: 'UV 11', uv: 11 },
]
await assertLabelsFit(cellFitReadings.map(({ text }) => text), {
  fontSize: (text) => cellFontSize(cellFitReadings.find((reading) => reading.text === text)),
  width: CELL.textWidth,
})

await assertClockPreviewIsolation()
await writeDesigns(clockPreview)
