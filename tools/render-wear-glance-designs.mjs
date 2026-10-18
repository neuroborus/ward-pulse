#!/usr/bin/env node
/**
 * SVG review exports for the Wear OS app Glance (legend) screen
 * (`docs/product/WEAR_GLANCE_DESIGN.md`).
 *
 * This is not the watch face — text rows + small remaining arcs, provider labels
 * as a color legend for the face rings.
 *
 * Usage: node tools/render-wear-glance-designs.mjs
 */

import { execFile } from 'node:child_process'
import { mkdir } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

import { FONT_FILE, emit, renderPreviews } from './design-output.mjs'

const runFile = promisify(execFile)

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

const SURFACE = '#101412'
const TRACK = '#2E3632'
const LABEL = '#F4FBF8'
const MUTED = '#8A968F'
const OK_GREEN = '#65D78A'
const WARN = '#E6C349'
const DISABLED = '#5A635C'
/** Quieter than MUTED — problem detail under the refresh plate. */
const DETAIL = '#5C655E'
const FONT = 'Noto Sans'
const SIZE = 450

/** The density that takes a 450-unit board to the 675 the previews are read at. */
const PREVIEW_DENSITY = 144

// A budget row belongs to one connection and takes that connection's family
// color, so `cursorPlatform` repeats the Cursor teal on purpose. A Cursor plan's
// own models carry a color of their own (`WATCH_RING_DESIGN.md`, palette).
const FAMILY = {
  codex: { name: 'Codex', color: '#65D78A' },
  codexSpark: { name: 'Codex', color: '#186020' },
  claude: { name: 'Claude', color: '#E8915A' },
  cursor: { name: 'Cursor', color: '#67E8D4' },
  cursorOwn: { name: 'Cursor', color: '#7E93B8' },
  cursorPlatform: { name: 'Cursor platform', color: '#67E8D4' },
}

/** Match Wear's recognized plan windows and preserve composed or already-named labels. */
function rowTitle(row) {
  if (row.split) return `${row.family.name} plan`
  const family = row.family.name
  // Wear compares the first word, not a prefix, so `Cursorish` would still be named.
  if (row.metric.includes(' · ') || row.metric.split(' ')[0] === family) return row.metric
  if (family === 'Codex' && row.metric === 'Weekly plan') return `${family} plan · Weekly`
  if (
    (family === 'Claude' && ['5h', 'Weekly', 'Opus weekly', 'Sonnet weekly'].includes(row.metric)) ||
    (family === 'Codex' && ['5h', 'Weekly', 'Spark 5h', 'Spark Weekly'].includes(row.metric))
  ) return `${family} plan · ${row.metric}`
  return `${family} · ${row.metric}`
}

/**
 * Real metrics or nothing. These place every baseline and size the alerts plate, so a guessed
 * width moves the art: the fallback this replaces returned character-count estimates without
 * a word, which made committed SVGs depend on whether the rendering machine had Pillow.
 */
async function loadFontMetrics(fontSize, texts) {
  const { stdout } = await runFile(
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
  return JSON.parse(stdout)
}

function esc(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
}

function miniArc({ cx, cy, r, thickness, remaining, color }) {
  const circ = 2 * Math.PI * r
  if (remaining <= 0) {
    return `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${TRACK}"
      stroke-width="${thickness}" />`
  }
  const left = Math.max(0.02, Math.min(remaining, 0.999))
  const paint = circ * left
  const used = circ * (1 - left)
  return `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${TRACK}"
      stroke-width="${thickness}" />
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${color}"
      stroke-width="${thickness}" stroke-linecap="round"
      stroke-dasharray="${Math.max(0, paint - thickness).toFixed(2)} ${circ.toFixed(2)}"
      stroke-dashoffset="${(-(used + thickness / 2)).toFixed(2)}"
      transform="rotate(-90 ${cx} ${cy})" />`
}

/** 0° = top, degrees increase clockwise. */
function polar(cx, cy, deg, rad) {
  const a = ((deg - 90) * Math.PI) / 180
  return [cx + rad * Math.cos(a), cy + rad * Math.sin(a)]
}

function clockwiseTangent(deg) {
  const a = ((deg - 90) * Math.PI) / 180 + Math.PI / 2
  return [Math.cos(a), Math.sin(a)]
}

/**
 * Butt-capped arc + explicit chevron tip. Arc stops just before the chevron so
 * the head is a distinct shape without double-painting the stroke.
 */
function refreshArrow(cx, cy, startDeg, tipDeg, arcR, sw, fill, opacity) {
  const headLen = 8
  const headHalf = sw * 1.75
  const gapDeg = 0.9
  const insetDeg = (headLen / arcR) * (180 / Math.PI)
  const baseDeg = tipDeg - insetDeg
  const arcEndDeg = baseDeg - gapDeg
  const [x0, y0] = polar(cx, cy, startDeg, arcR)
  const [ex, ey] = polar(cx, cy, arcEndDeg, arcR)
  const [bx, by] = polar(cx, cy, baseDeg, arcR)
  const [tx, ty] = polar(cx, cy, tipDeg, arcR)
  const [dx, dy] = clockwiseTangent(baseDeg)
  const px = -dy
  const py = dx
  return `
    <path d="M ${x0.toFixed(1)} ${y0.toFixed(1)} A ${arcR} ${arcR} 0 0 1 ${ex.toFixed(1)} ${ey.toFixed(1)}"
      fill="none" stroke="${fill}" stroke-width="${sw}" stroke-linecap="butt"
      opacity="${opacity}" />
    <path d="M ${tx.toFixed(1)} ${ty.toFixed(1)}
      L ${(bx + px * headHalf).toFixed(1)} ${(by + py * headHalf).toFixed(1)}
      L ${(bx - px * headHalf).toFixed(1)} ${(by - py * headHalf).toFixed(1)} Z"
      fill="${fill}" opacity="${opacity}" />`
}

/**
 * Status label in the open center of a dual-arrow refresh ring.
 * Returns { markup, plateR } so callers can place detail text below the plate.
 */
async function refreshStatusControl({
  cx,
  cy,
  r,
  ok,
  enabled,
  labelSize,
}) {
  const accent = ok ? OK_GREEN : WARN
  const glyph = enabled ? accent : DISABLED
  const text = ok ? 'OK' : '!OK'
  const textFill = enabled ? accent : DISABLED
  const plate = enabled ? '#141916' : '#121512'
  const opacity = enabled ? 1 : 0.7
  const labelMetrics = await loadFontMetrics(labelSize, [text])
  const baseline =
    cy + (labelMetrics.ascent - labelMetrics.descent) / 2
  const sw = 2.2
  const pad = 9
  // Keep flared chevron inside the plate.
  const arcR = r - pad - sw * 1.75

  const markup = `
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="${plate}"
      stroke="${TRACK}" stroke-width="1" />
    ${refreshArrow(cx, cy, 310, 76, arcR, sw, glyph, opacity)}
    ${refreshArrow(cx, cy, 130, 256, arcR, sw, glyph, opacity)}
    <text x="${cx}" y="${baseline.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${labelSize}"
      font-weight="700" fill="${textFill}">${esc(text)}</text>`

  return { markup, plateR: r }
}

/**
 * Tightest remaining first — same order rule as the watch face.
 *
 * Sort bands by their tighter half, keeping the inner pool first within a row.
 */
function sortByRemaining(rows) {
  const hasPercent = (value) => Number.isFinite(value) && value >= 0
  return [...rows]
    .flatMap((row) => {
      if (!hasPercent(row.used)) {
        return hasPercent(row.split?.used)
          ? [{ ...row.split, credits: row.credits ?? row.split.credits }]
          : []
      }
      return [{ ...row, split: hasPercent(row.split?.used) ? row.split : null }]
    })
    .sort((a, b) =>
      Math.max(b.used, b.split?.used ?? b.used) - Math.max(a.used, a.split?.used ?? a.used),
    )
}

function rowSubLine(row) {
  const pct = Math.round(Math.max(0, 1 - row.used) * 100)
  const left = row.split
    ? `${pct}% · ${Math.round(Math.max(0, 1 - row.split.used) * 100)}% left`
    : `${pct}% left`
  if (row.credits == null || row.credits === '') {
    return left
  }
  return `${left} · ${row.credits} credits`
}

/** Keep only true exhausted percentage tokens red; separators and credits stay ordinary. */
function zeroLabelMarkup(text, row) {
  return text.split(' · ').map((part, index) => {
    const exhausted = index === 0 ? row.used >= 1 : index === 1 && row.split?.used >= 1
    return exhausted && part.startsWith('0%')
      ? `<tspan fill="#FFB4AB">0%</tspan>${esc(part.slice(2))}`
      : esc(part)
  }).join(' · ')
}

async function glanceSvg({
  name,
  ok = true,
  refreshEnabled = true,
  statusDetail = null,
  rows = [],
  emptyMessage = null,
  alerts = 0,
}) {
  const cx = SIZE / 2
  const clipId = 'roundClip'
  const timeSize = 16
  const refreshLabelSize = 13
  const titleSize = 16
  const subSize = 14
  const detailSize = 11
  const alertsSize = 16
  const rowH = 54
  const miniR = 17
  const miniT = 5
  const arcColW = 44
  const textGap = 12
  const secondArcOffset = miniR * 2 + miniT + textGap
  const alertsLabel = `Alerts: ${alerts}`
  const alertsActive = alerts > 0
  const alertsFill = alertsActive ? '#2A322C' : '#171B18'
  const alertsStroke = alertsActive ? WARN : '#2A302C'
  const alertsText = alertsActive ? LABEL : DISABLED

  const ordered = sortByRemaining(rows)
  const titles = ordered.map(rowTitle)
  const subs = ordered.map((row) => rowSubLine(row))
  const titleMetrics = await loadFontMetrics(titleSize, titles)
  const subMetrics = await loadFontMetrics(subSize, [...subs, alertsLabel])
  const alertsMetrics = await loadFontMetrics(alertsSize, [alertsLabel])
  const maxTitleW = Math.max(0, ...titles.map((t) => titleMetrics.widths[t] ?? 0))
  const maxSubW = Math.max(0, ...subs.map((t) => subMetrics.widths[t] ?? 0))
  const textColW = Math.max(maxTitleW, maxSubW)
  const blockW = Math.max(
    arcColW + textGap + textColW,
    ...ordered.map((row, i) =>
      arcColW + (row.split ? secondArcOffset : 0) + textGap +
        Math.max(titleMetrics.widths[titles[i]], subMetrics.widths[subs[i]]),
    ),
  )
  const blockLeft = Math.max(42, Math.min(cx - blockW / 2, SIZE - 42 - blockW))
  const arcX = blockLeft + arcColW / 2

  const refreshCy = 96
  const refreshR = 34
  const refresh = await refreshStatusControl({
    cx,
    cy: refreshCy,
    r: refreshR,
    ok,
    enabled: refreshEnabled,
    labelSize: refreshLabelSize,
  })
  // Detail sits fully below the plate — never on the ring.
  const detailGap = 16
  const detailY = statusDetail
    ? refreshCy + refresh.plateR + detailGap
    : null
  const headerBottom = (detailY ?? refreshCy + refresh.plateR) + 12

  const alertsBtnH = 36
  const alertsBtnY = SIZE - 78
  const alertsPadX = 18
  const alertsBtnW = Math.min(
    210,
    Math.max(128, (alertsMetrics.widths[alertsLabel] ?? 90) + alertsPadX * 2),
  )
  const alertsBtnX = cx - alertsBtnW / 2
  const alertsTextY =
    alertsBtnY +
    alertsBtnH / 2 +
    (alertsMetrics.ascent - alertsMetrics.descent) / 2

  let body = `
    <text x="${cx}" y="48" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${timeSize}"
      font-weight="700" fill="${MUTED}">9:06</text>
    ${refresh.markup}`

  if (statusDetail) {
    body += `
    <text x="${cx}" y="${detailY.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${detailSize}"
      font-weight="700" fill="${DETAIL}">${esc(statusDetail)}</text>`
  }

  if (emptyMessage) {
    const lines = emptyMessage.split('\n')
    const emptyMetrics = await loadFontMetrics(titleSize, lines)
    const lineGap = 22
    const blockH =
      (lines.length - 1) * lineGap +
      (emptyMetrics.ascent + emptyMetrics.descent)
    const bandTop = headerBottom
    const bandBottom = alertsBtnY - 10
    const bandMid = (bandTop + bandBottom) / 2
    const firstBaseline =
      bandMid - blockH / 2 + emptyMetrics.ascent
    let lineY = firstBaseline
    for (const line of lines) {
      body += `
    <text x="${cx}" y="${lineY.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${titleSize}"
      font-weight="700" fill="${MUTED}">${esc(line)}</text>`
      lineY += lineGap
    }
  } else {
    const stackH = ordered.length * rowH
    const availableTop = headerBottom
    const availableBottom = alertsBtnY - 12
    const opticalLift = 6
    let y = Math.max(
      availableTop,
      availableTop + (availableBottom - availableTop - stackH) / 2 - opticalLift,
    )

    for (const row of ordered) {
      const remaining = 1 - row.used
      const title = rowTitle(row)
      const sub = rowSubLine(row)
      const rowMid = y + rowH / 2
      body += miniArc({
        cx: arcX,
        cy: rowMid,
        r: miniR,
        thickness: miniT,
        remaining,
        color: row.family.color,
      })
      if (row.split) {
        body += miniArc({
          cx: arcX + secondArcOffset,
          cy: rowMid,
          r: miniR,
          thickness: miniT,
          remaining: 1 - row.split.used,
          color: row.split.family.color,
        })
      }
      const contentLeft = blockLeft + arcColW + (row.split ? secondArcOffset : 0) + textGap
      const titleBaseline =
        rowMid - 8 + (titleMetrics.ascent - titleMetrics.descent) / 2
      const subBaseline =
        rowMid + 13 + (subMetrics.ascent - subMetrics.descent) / 2
      body += `
    <text x="${contentLeft}" y="${titleBaseline.toFixed(1)}"
      font-family="${FONT}, sans-serif" font-size="${titleSize}"
      font-weight="700" fill="${LABEL}">${esc(title)}</text>
    <text x="${contentLeft}" y="${subBaseline.toFixed(1)}"
      font-family="${FONT}, sans-serif" font-size="${subSize}"
      font-weight="700" fill="${MUTED}">${zeroLabelMarkup(sub, row)}</text>`
      y += rowH
    }
  }

  body += `
    <rect x="${alertsBtnX.toFixed(1)}" y="${alertsBtnY}" width="${alertsBtnW.toFixed(1)}"
      height="${alertsBtnH}" rx="18" fill="${alertsFill}" stroke="${alertsStroke}"
      stroke-width="${alertsActive ? 1.5 : 1}"
      fill-opacity="${alertsActive ? 1 : 0.85}" />
    <text x="${cx}" y="${alertsTextY.toFixed(1)}" text-anchor="middle"
      font-family="${FONT}, sans-serif" font-size="${alertsSize}"
      font-weight="700" fill="${alertsText}">${esc(alertsLabel)}</text>`

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}" role="img" aria-label="${esc(name)}">
  <defs>
    <radialGradient id="lift" cx="50%" cy="48%" r="62%">
      <stop offset="0%" stop-color="#18201C"/>
      <stop offset="55%" stop-color="${SURFACE}"/>
      <stop offset="100%" stop-color="#0A0D0B"/>
    </radialGradient>
    <clipPath id="${clipId}">
      <circle cx="${cx}" cy="${cx}" r="${SIZE / 2}" />
    </clipPath>
  </defs>
  <g clip-path="url(#${clipId})">
    <rect width="${SIZE}" height="${SIZE}" fill="url(#lift)"/>
    ${body}
  </g>
  <circle cx="${cx}" cy="${cx}" r="${(SIZE / 2 - 1).toFixed(1)}" fill="none"
    stroke="#1A201C" stroke-width="2" />
</svg>
`.replace(/^[ \t]+$/gm, '')
}

const wearDir = join(root, 'apps/wear_android/design')
await mkdir(wearDir, { recursive: true })

const three = [
  { family: FAMILY.codex, metric: 'Weekly plan', used: 0.92, credits: '320' },
  { family: FAMILY.claude, metric: '5h', used: 0.61, credits: '80' },
  // Matches fixtures/providers/cursor/usage_summary.json autoPercentUsed.
  { family: FAMILY.cursorOwn, metric: 'Cursor Models', used: 0.47 },
]
const exhaustedClaude = { family: FAMILY.claude, metric: '5h', used: 1 }
const liveCodex = { family: FAMILY.codex, metric: 'Weekly plan', used: 0.04, credits: '62.5K' }
const liveCursor = {
  family: FAMILY.cursorOwn, metric: 'Cursor Models', used: 0,
  split: { family: FAMILY.cursor, metric: 'Other Models', used: 0.32 },
}
const cursorInnerZero = { ...liveCursor, used: 1 }
const cursorOuterZero = { ...liveCursor, split: { ...liveCursor.split, used: 1 } }
const cursorBothZero = { ...cursorInnerZero, split: { ...liveCursor.split, used: 1 } }

const variants = [
  {
    file: 'glance-legend-3.svg',
    name: 'Glance · legend · 3 providers · OK refresh',
    ok: true,
    refreshEnabled: true,
    rows: three,
    alerts: 0,
  },
  {
    file: 'glance-legend-1.svg',
    name: 'Glance · legend · 1 provider · OK refresh',
    ok: true,
    refreshEnabled: true,
    rows: [
      { family: FAMILY.codex, metric: 'Weekly plan', used: 0.92, credits: '320' },
    ],
    alerts: 0,
  },
  {
    // One band, one row: inner pool first, even when the outer pool is tighter.
    file: 'glance-legend-pair.svg',
    name: 'Glance · legend · Cursor pair · OK refresh',
    ok: true,
    refreshEnabled: true,
    rows: [
      {
        family: FAMILY.cursorOwn,
        metric: 'Cursor Models',
        used: 0.18,
        credits: '320',
        // Synthetic active pools exercise the paired row and its credits suffix.
        split: { family: FAMILY.cursor, metric: 'Other Models', used: 0.59 },
      },
    ],
    alerts: 0,
  },
  {
    // Three rows is the ceiling: three bands, with both supported pairs active.
    file: 'glance-legend-full.svg',
    name: 'Glance · legend · three rows (three bands, two paired)',
    ok: true,
    refreshEnabled: true,
    rows: [
      { family: FAMILY.claude, metric: 'Sonnet weekly', used: 0.94, credits: '387' },
      {
        // The ceiling board carries the largest balance a row can show, in the
        // compact form the app renders it in, so the longest subtitle the rules
        // allow is on a board rather than only on a watch
        // (`WEAR_GLANCE_DESIGN.md`, revision 2026-10-11).
        family: FAMILY.cursorOwn,
        metric: 'Cursor Models',
        used: 0.0,
        credits: '62.5K',
        split: {
          family: FAMILY.cursor,
          metric: 'Other Models',
          used: 0.25,
          credits: '62.5K',
        },
      },
      {
        family: FAMILY.codex,
        metric: 'Weekly plan',
        used: 0.18,
        credits: '320',
        split: { family: FAMILY.codexSpark, metric: 'Spark 5h', used: 0.59 },
      },
    ],
    alerts: 0,
  },
  {
    file: 'glance-legend-budget.svg',
    name: 'Glance · legend · plan + budget · OK refresh',
    ok: true,
    refreshEnabled: true,
    rows: [
      {
        family: FAMILY.codex,
        metric: 'Weekly plan',
        used: 0.84,
        credits: '320',
      },
      {
        family: FAMILY.claude,
        metric: '5h',
        used: 0.4,
        credits: '80',
      },
      // Cursor platform reports billing-cycle spend only, so a monthly budget
      // is the one it can actually carry.
      { family: FAMILY.cursorPlatform, metric: 'Month', used: 0.55 },
    ],
    alerts: 0,
  },
  {
    file: 'glance-legend-stale.svg',
    name: 'Glance · legend · !OK · Stale · refresh enabled',
    ok: false,
    refreshEnabled: true,
    statusDetail: 'Stale',
    rows: three,
    alerts: 2,
  },
  {
    file: 'glance-legend-cadence.svg',
    name: 'Glance · legend · OK · cadence cooldown · refresh disabled',
    ok: true,
    refreshEnabled: false,
    rows: three,
    alerts: 0,
  },
  {
    file: 'glance-legend-rate-limit.svg',
    name: 'Glance · legend · !OK · provider rate limit · refresh disabled',
    ok: false,
    refreshEnabled: false,
    statusDetail: 'Rate limited',
    rows: three,
    alerts: 0,
  },
  {
    file: 'glance-legend-empty.svg',
    name: 'Glance · legend · empty selection · OK refresh',
    ok: true,
    refreshEnabled: true,
    rows: [],
    emptyMessage: 'Choose percent rings\nin the phone app',
    alerts: 0,
  },
  {
    file: 'glance-legend-exhausted.svg',
    name: 'Glance · all selected metrics exhausted · retained rows',
    ok: true,
    refreshEnabled: true,
    rows: [exhaustedClaude, cursorBothZero, { ...liveCodex, used: 1 }],
    emptyMessage: null,
    alerts: 0,
  },
  ...[
    { file: 'glance-legend-claude-zero.svg', name: 'Claude 5h at zero', rows: [exhaustedClaude] },
    { file: 'glance-legend-3-claude-zero.svg', name: 'Claude zero with Cursor pair and Codex', rows: [exhaustedClaude, liveCursor, liveCodex] },
    { file: 'glance-legend-pair-inner-zero.svg', name: 'Pair inner pool zero', rows: [cursorInnerZero, liveCodex] },
    { file: 'glance-legend-pair-outer-zero.svg', name: 'Pair outer pool zero', rows: [cursorOuterZero, liveCodex] },
    { file: 'glance-legend-pair-both-zero.svg', name: 'Pair both pools zero', rows: [cursorBothZero, liveCodex] },
    { file: 'glance-legend-positive-rounds-zero.svg', name: 'Positive fraction rounds to ordinary zero label', rows: [{ ...exhaustedClaude, used: 0.999 }] },
    { file: 'glance-legend-zero-credits.svg', name: 'Exhausted percent with neutral zero credits', rows: [{ ...liveCodex, used: 1, credits: '0' }] },
    { file: 'glance-legend-unavailable.svg', name: 'Selected entries have no known percentage', rows: [], emptyMessage: 'Ring data unavailable' },
    { file: 'glance-legend-unavailable-inner-zero-outer.svg', name: 'Unavailable inner pool with exhausted outer survivor', rows: [{ ...cursorOuterZero, used: -1 }] },
    { file: 'glance-legend-two-pairs-zero.svg', name: 'Three bands with two exhausted pairs', rows: [exhaustedClaude, cursorBothZero, { ...liveCodex, used: 1, split: { family: FAMILY.codexSpark, metric: 'Spark Weekly', used: 1 } }] },
  ].map((variant) => ({ ...variant, ok: true, refreshEnabled: true, alerts: 0 })),
]

for (const variant of variants) {
  const svg = await glanceSvg(variant)
  await emit(join(wearDir, variant.file), svg, 'render-designs')
}

/**
 * Every board has exactly one preview, named after it. Deriving the list from
 * the boards rather than keeping a second one beside them means a new variant
 * cannot ship without the picture the baseline will be read against.
 */
await renderPreviews(
  variants.map(({ file }) => ({
    svg: join(wearDir, file),
    png: join(wearDir, `preview-${file.replace(/\.svg$/, '.png')}`),
    density: PREVIEW_DENSITY,
  })),
)
