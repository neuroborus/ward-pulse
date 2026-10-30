#!/usr/bin/env node
/**
 * The watch face itself, not review art: writes
 * `apps/watchface_wff/src/main/res/raw/watchface.xml` and the ring-type drawables
 * it names (geometry and language rules: `docs/product/WATCH_RING_DESIGN.md`).
 *
 * Three rings, two shared outer-half slots and three strips spend eight slots.
 * Ring type multiplies the ring block — one branch per period, one image per branch.
 * Hand-editing means editing one and missing eight; the next such feature
 * multiplies the copies again, not the ideas.
 *
 * The textures are written by the same run because they are the same geometry:
 * splitting them would let a band and its type drift a constant apart. Baking
 * them needs ImageMagick, as `just export-icons` already does.
 *
 * Usage: node tools/render-watchface.mjs [--check]
 *   --check  compare the XML against the file on disk and exit non-zero on drift
 *   --n1-pair-diagnostics-output PATH  write only a debug build-directory XML overlay
 *
 * `--check` covers the XML only: the images are what a rasterizer made of it, and
 * comparing bytes would fail on a different ImageMagick rather than on a real
 * drift. A missing one still stops the build — the face names each by resource.
 */

import { execFile } from 'node:child_process'
import { access, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, isAbsolute, join, relative, resolve } from 'node:path'
import { pipeline } from 'node:stream/promises'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

import { emit } from './design-output.mjs'

const runFile = promisify(execFile)

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const target = join(root, 'apps/watchface_wff/src/main/res/raw/watchface.xml')
// `-nodpi`, because the images are already sized to the canvas: the density
// buckets would rescale them on load and soften what was baked to be exact.
const drawables = join(root, 'apps/watchface_wff/src/main/res/drawable-nodpi')
// The same face the review generators measure with, and named as a file for the
// same reason: the rasterizer resolves a family through fontconfig, which
// substitutes rather than fails, and would rebake every band at another metric.
const FONT_FILE = '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf'

/**
 * The canvas, which is also the design language `WATCH_RING_DESIGN.md` locks: one
 * number, no conversion, and every constant below comparable to the baseline by
 * eye. It is also the render resolution — WFF draws the scene at this size and
 * scales the result to the screen, so a larger canvas is a downscale on most
 * watches and loses antialiasing in it: edge roughness measured 0.143 px here
 * against 0.151 at 900, on a 384-pixel device. Raising it is a cost, not a knob.
 */
const FACE = { size: 450, center: 225 }

/**
 * Both ends of the melt: usage opens clockwise from 12, remaining ends at 12.
 * `359.9` retains the historical watch workaround: a literal 360 ROUND sweep
 * collapsed to a tip. Exact full uses the same sweep without either cap inset.
 */
const SWEEP = { start: 0, end: 359.9 }

const COLOR = {
  background: '#ff0a0d0b',
  track: '#ff2e3632',
  strip: '#eb0b0e0c',
  text: '#fff4fbf8',
  exhaustedPercent: '#ffffb4ab',
  /**
   * The occluder a filled cell draws inside its own slot, and the middle of an
   * empty cell's recess. Opaque where the strip well is not: it has to cover
   * whatever chrome the scene put under it, and `0xeb` leaks 7.8% of that
   * through (`WATCH_RING_DESIGN.md`, Upper cells, rule 10).
   */
  cellWell: '#ff0b0e0c',
  /**
   * The lit rim of an empty cell. Not the track: that colour means the unspent
   * part of a band, and at its contrast a rim reads as a drawn ring rather than
   * as the edge of a dish.
   */
  cellRim: '#ff242a27',
  /**
   * The border a cell draws while it is showing something. The face's own
   * text colour at `0xaa`, so the ring is the same light as the reading it
   * encloses and never a colour of its own. At 40% it does not read at a
   * glance; at full strength it competes with the text inside it and with the
   * bands behind it (`WATCH_RING_DESIGN.md`, Upper cells, rule 10).
   */
  cellRing: '#aaf4fbf8',
}

/**
 * Rings, outermost first. A `diameter` here is twice the band's **outer edge**,
 * which is what the ring textures and the split halves are laid out against.
 * They step by 48, so at a 20-unit band the neighbouring gap is 4 units.
 */
const RINGS = [
  { slotId: 101, diameter: 404, service: 'Today' },
  { slotId: 102, diameter: 356, service: 'Week' },
  { slotId: 105, diameter: 308, service: 'Ring3' },
]

/**
 * The band as painted. Until 2026-10-09 this declared 40 and a `BoundingArc` on
 * the slot cut half of it away: the clip's outer edge sat on the stroke's own
 * centre line, so only the inner half survived and the band measured about 20.
 * The clip has to go — a slot cannot draw a legend strip outside its own band
 * while one is in force — so the stroke now declares what it paints.
 *
 * The clip never trimmed a `ROUND` cap along the arc, only across it, which is
 * why the 2026-08-16 reading found a cap of half the *nominal* thickness. At a
 * true 20-unit stroke the cap is half of that, `capDegrees` is fed the real
 * number, and the two-cap cutoff moves with it (`WATCH_RING_DESIGN.md`).
 */
const BAND_THICKNESS = 20

/** MAX100 never asserts a resolved count: it always uses the legacy positions. */
const LAYOUTS = [
  { name: 'Legacy', count: 3, max: 100, thickness: 20 },
  ...[1, 2, 3].map((count) => ({
    name: `N${count}`, count, max: 100 * 2 ** count,
    thickness: (68 - 4 * (count - 1)) / count,
  })),
]

function bandGeometry(layout, index) {
  const { thickness } = layout
  const diameter = layout.count === 3
    ? RINGS[index].diameter : 404 - 2 * index * (thickness + 4)
  return {
    diameter, thickness, full: diameter - thickness,
    inner: diameter - 1.5 * thickness, outer: diameter - thickness / 2,
    half: thickness / 2,
  }
}

/** Equality and bounded comparisons also reject non-finite fields (including NaN). */
function rangeGuard(max) {
  return `[COMPLICATION.RANGED_VALUE_MIN] == 0 && [COMPLICATION.RANGED_VALUE_MAX] == ${max} && [COMPLICATION.RANGED_VALUE_VALUE] >= 0 && [COMPLICATION.RANGED_VALUE_VALUE] <= ${max}`
}

/**
 * Two outer-half slots dispatch by outside-counted band index in TITLE.
 * Moving the far marker into each strip frees slot 109 without exceeding eight.
 * Keep ordinal 0 on 106 so an installed old face retains its first outer arc.
 */
const OUTER_HALVES = [
  { slotId: 106, service: 'RingSplit', label: 'outer_half_complication' },
  { slotId: 109, service: 'StripSplit', label: 'split_marker_complication' },
]

/** The token a band's own slot sends when it draws only its inner half. */
const SPLIT_TOKEN = 'split'
const ZERO_TOKEN = 'zero'
const ZERO_STATES = ['zero-inner', 'zero-outer', 'zero-both']

/**
 * The token that lone strip sends when there is no ring at all — a credits
 * reading with no band under it. It is a `TITLE` value rather than a second
 * slot because the slot that carries it is a ring slot doing its other job.
 */
const CREDITS_TOKEN = 'credits'

/** Joins a band's own token to the outer-pool token of the strip it now carries. */
const TOKEN_SEPARATOR = ':'

/**
 * Ring type as texture: the budget period repeated around the band, drawn from a
 * baked image per ring and period rather than set as text.
 *
 * The glyphs are punched out in the background colour instead of being drawn in
 * the family colour, because `Font color` rejects
 * `[COMPLICATION.RANGED_VALUE_COLORS]` — the ramp is a colour list and the
 * attribute parses one ARGB. So the colour keeps coming from the arc
 * underneath, and as a bonus the melt boundary can never slice a glyph: it is
 * an edge in the arc, and the glyph is only ever a hole in it — a shallow one,
 * see `opacity`.
 *
 * Baked, because `TextCircular` rounds every glyph it lays out to a whole canvas
 * unit: on the 450 canvas that is 0.93 units of baseline jitter along a band,
 * repeating every 90° and plainly visible as letters that do not sit on their
 * circle. A finer canvas only trades it against the blit to the screen — 0.61
 * units at 900, 0.25 at 1800, and stepped glyph edges long before it is gone. An
 * image carries its own spacing and moves as one thing under any scale, so what
 * the ring shows is what this generator drew.
 */
const TEXTURE = {
  /**
   * The band measured off a device screenshot in `WATCH_RING_DESIGN.md`, kept
   * identical here so the texture cannot drift from the baseline. It runs a
   * little over the declared `BAND_THICKNESS` because a measured edge carries
   * its own antialiasing; the declaration is the geometry, this is the reading.
   */
  band: 20.2,
  /**
   * Cap height as a fraction of the band. The measure is how much colour
   * survives above and below the hole: at 0.94 it is 0.0 units and the ring
   * falls into disconnected chunks, at 0.78 it is 2.2, thin but continuous.
   */
  capOfBand: 0.78,
  /** Cap height of Noto Sans Bold, 1462/2048 em — the face bakes its own font. */
  capRatio: 0.714,
  /**
   * How many sweeps a band's type is dealt over. Four breaks on the diagonals,
   * aligned across every ring: a run has to end somewhere, and a declared break
   * absorbs the ends where a token gap would show them as a collision on one
   * side and a hole on the other.
   */
  sweeps: 4,
  /** Bare band between two sweeps, in degrees. */
  sweepGap: 10,
  /**
   * How much of the background colour a glyph carries. Below 1 the holes stop
   * being holes: what is left is the arc, darkened by that share, so the type
   * reads as a shade in the band rather than as a second row of marks competing
   * with the rings it labels.
   */
  opacity: 0.45,
  /** The face's own typeface now that the type is baked, not the device's. */
  font: 'Noto Sans',
  /** As the review generators set it, and as `FONT_FILE` is: Noto Sans Bold. */
  weight: 700,
}

const TEXTURE_CAP = TEXTURE.band * TEXTURE.capOfBand

/** The cap height is the design knob; a font size is what the baking takes. */
const TEXTURE_FONT_SIZE = Number((TEXTURE_CAP / TEXTURE.capRatio).toFixed(1))

/**
 * The baseline, as an inset from the ring's outer edge: an image is that ring's
 * own square, so the band runs along its rim and a baseline half a cap below the
 * band's centreline leaves the cap centred on it. This is the historical N3
 * baseline; wider bands derive their inset from the same fixed cap height.
 */
const TEXTURE_BASELINE = Number(((TEXTURE.band + TEXTURE_CAP) / 2).toFixed(2))

/** Texture alpha, dimmed for ambient by the same 140 of 255 the arcs take. */
const TEXTURE_ALPHA = Math.round(255 * TEXTURE.opacity)
const TEXTURE_ALPHA_AMBIENT = Math.round((TEXTURE_ALPHA * 140) / 255)

/**
 * Period tokens exactly as the complication writes them into TITLE, with the
 * repeats one sweep holds — outer ring first, one count per ring the face draws.
 *
 * The counts were fitted to a token advance measured on device while the type
 * was still set as text, and they are kept rather than recomputed: they are what
 * the band was designed around, and Noto's own metrics would fit a different
 * number of tokens on the same arc. `tools/render-watch-ring-designs.mjs` copies
 * this table, so the boards and the face count alike.
 */
const TOKENS = [
  { period: 'Day', title: 'D', repeats: [15, 13, 11] },
  { period: 'Week', title: '7D', repeats: [9, 8, 6] },
  { period: 'Month', title: 'M', repeats: [12, 10, 9] },
]

const ADAPTIVE_REPEATS = {
  1: { D: [13], '7D': [8], M: [10] },
  2: { D: [15, 11], '7D': [9, 6], M: [12, 9] },
}

/**
 * Rings the type can label — all of them: the baseline caps the face at three
 * bands, and the counts above are fitted per band. A shared band carries no
 * period, so it gets no texture either; that branch is chosen by TITLE.
 */
const TEXTURE_RINGS = TOKENS[0].repeats.length

// One count per token per ring, or a band bakes empty: a short row leaves the
// repeat count undefined, and nothing downstream reads that as an error.
if (TOKENS.some(({ repeats }) => repeats.length !== TEXTURE_RINGS)) {
  throw new Error('TOKENS: every period needs one repeat count per ring the type labels')
}

/**
 * Strips, one per ring, stacked below the clock. Fixed in the face's units, not
 * sized to content: 132x26 boxes stepping 27 from y=259, inside the unchanged
 * inner ring aperture. Literal WFF2 font branches fit the bounded label grammar.
 */
const STRIP = {
  x: 159,
  top: 259,
  pitch: 27,
  width: 132,
  height: 26,
  radius: 6,
  textInset: 6,
  textWidth: 120,
  fontSize: 20,
}

/**
 * The wordmark, centred below the middle cell and above the clock. Both boxes are
 * square because the asset is — WFF stretches the image to fill its box, and
 * the earlier 66x55 / 54x45 boxes flattened the mark by 17%. The PNG carries
 * its own padding: active ink spans y=156.333333-181, ambient 158.9375-179.75.
 * Native clock ink and resampling still need matched device measurements.
 */
const WORDMARK = { centerX: FACE.center, centerY: 173, size: 64, ambientSize: 54 }

/**
 * Enlarge whole digits upward from the measured 08:08 lower edges, rather than
 * retaining the old centred clock. These integer boxes are calibration starters:
 * native font metrics must establish complete glyph fit, bottom and visible gaps.
 */
const CLOCK = {
  active: { y: 176, height: 90, fontSize: 86 },
  ambient: { y: 175, height: 90, fontSize: 96 },
}

/**
 * Which row of the stack a ring's own slot paints, counted from the top.
 *
 * The stack anchors to its **bottom** row, so the outermost ring — which binds
 * the loosest payload when several are active — takes the lowest row, and the
 * innermost takes the highest. Arc slots fill from the outside, so the occupied
 * rows are always contiguous and always end at y=313, whatever the ring count
 * (`WATCH_RING_DESIGN.md`, Upper cells, rule 3). A top-anchored stack could not
 * be folded at all: the row a slot paints would move with the ring count, and
 * one slot has one height.
 */
function stripRowY(ringIndex) {
  return STRIP.top + (RINGS.length - 1 - ringIndex) * STRIP.pitch
}

/** The bottom row, and so the row a lone strip belongs on. */
const CREDITS_RING_INDEX = 0

/**
 * The three cells above the clock retain the original curved row. Since
 * 2026-10-27 the wells are 52 units. Origins are the integers
 * `WATCH_RING_DESIGN.md` rule 1 locks; the middle remains fourteen units raised.
 */
const CELL = {
  size: 52,
  /** Both the 46x24 text box and the 24-unit icon centre on the integer grid. */
  textY: 14,
  textX: 3,
  textWidth: 46,
  textHeight: 24,
  fontSize: 18,
  iconSize: 24,
  /**
   * The border that says a cell is holding something. Its 1.5-unit stroke,
   * retained from 2026-10-13, now follows a 50.5 path: radius 24.5 to 26.0,
   * inscribed in the enlarged well.
   */
  ringDiameter: 50.5,
  ringThickness: 1.5,
  /**
   * The ring dims in ambient with everything else a cell carries. Rule 12 keeps
   * the well because a well darkens, and switching a darkening off would raise
   * the luminance; a ring lights, so the same reasoning dims it rather than
   * leaving the brightest thing on an ambient face around a cell's edge. The
   * proportion is the arcs' own, 255 to 140.
   */
  ringAmbientAlpha: 140,
}

const CELLS = [
  { slotId: 201, x: 147, y: 109, label: 'cell1', provider: 'DAY_OF_WEEK', type: 'SHORT_TEXT' },
  { slotId: 202, x: 199, y: 95, label: 'cell2', provider: 'EMPTY', type: 'EMPTY' },
  { slotId: 203, x: 251, y: 109, label: 'cell3', provider: 'EMPTY', type: 'EMPTY' },
]

/** Outward-half dissolve, also normalized for the lateral bottom masks. */
const CELL_RING_FADE = [
  { position: 0, alpha: 0xaa },
  { position: 0.5, alpha: 0xaa },
  { position: 0.625, alpha: 0x91 },
  { position: 0.75, alpha: 0x5a },
  { position: 0.875, alpha: 0x23 },
  { position: 1, alpha: 0x0a },
]

/**
 * What the face draws under a cell when the wearer has not filled it. WFF reads
 * weather from a built-in source in an expression, so the default costs no
 * complication slot; a filled cell's opaque well simply covers it. Nothing is
 * declared under the left cell, so its recess is bare whenever it is cleared.
 *
 * Both expressions yield a bare number, so the template is what makes the
 * reading legible — `51` alone says neither degrees nor anything else. The
 * temperature takes its device-provided scale: TEMPERATURE_UNIT is an integer
 * enum, 1 for Celsius and 2 for Fahrenheit, so a condition selects the glyph.
 * An unsupported value keeps just the degree sign instead of guessing a scale
 * (`WATCH_RING_DESIGN.md`, Upper cells, revision 2026-10-13).
 *
 * Centre the complete reading, including its scale, just as the UV name is
 * centred with its number. The former two-unit degree-only correction would
 * not centre the digits once another glyph is added, and shifting by the
 * complete suffix would spend the cell's right-hand clearance.
 */
const CELL_CHROME = [
  { template: null, expression: null },
  { template: '%s°', expression: '[WEATHER.TEMPERATURE]', unit: '[WEATHER.TEMPERATURE_UNIT]' },
  { template: 'UV %s', expression: '[WEATHER.UV_INDEX]' },
]

/** Closed vocabulary shared with WatchComplicationText.splitPoolToken. */
const SPLIT_POOLS = [
  { token: 'cursor-other', color: '#67E8D4' },
  { token: 'spark', color: '#186020' },
]

/**
 * One slot now has two jobs and one `TITLE` to say both in, so the vocabulary
 * is the product of the two closed sets rather than either one
 * (`WATCH_RING_DESIGN.md`, Upper cells, rule 4). Only a split band carries a
 * pool token — a budget ring never shares — so the product is short: the band
 * token alone, plus `split` suffixed with each pool.
 *
 * Every branch below compares against the whole set it means, joined by `||`,
 * because WFF has no prefix test and a token is matched whole or not at all.
 */
function titleEquals(...tokens) {
  return tokens.map((token) => `[COMPLICATION.TITLE] == "${token}"`).join(' || ')
}

/** Every selected pair keeps its identity when one or both halves exhaust. */
const SPLIT_BASE_TITLES = [
  SPLIT_TOKEN,
  ...SPLIT_POOLS.map(({ token }) => `${SPLIT_TOKEN}${TOKEN_SEPARATOR}${token}`),
]
const SPLIT_TITLES = SPLIT_BASE_TITLES.flatMap((base) => [
  base,
  ...ZERO_STATES.map((state) => `${base}${TOKEN_SEPARATOR}${state}`),
])

/** Every slot names a service in the Wear app; nothing else may fill them. */
function provider(service) {
  return `app.wardpulse/app.wardpulse.wear.complication.${service}ComplicationDataSourceService`
}

const HEADER = `<?xml version="1.0" encoding="utf-8"?>
<!--
  Concentric remaining arcs + sunk % / credits strips
  (docs/product/WATCH_RING_DESIGN.md, baseline 2026-07-25).

  Visual target: apps/wear_android/design/round-*-plan*.svg
  — radial lift background, 20-unit ring stroke, equal-width sunk strips (132x26,
  rx=6) with bounded 20/18/16-unit labels. Ring slots are RANGED_VALUE so accents
  use the same ColorRamp as arcs ([COMPLICATION.RANGED_VALUE_COLORS]).

  Ring type: the budget period from COMPLICATION.TITLE (D / 7D / M) repeated around the
  band and punched out in the background colour at low alpha, so the arc underneath keeps
  the family and the type stays a shade in the band.

  Ring slots take a full-canvas BoundingBox: a BoundingArc clips a slot to its own
  band and halves its stroke, so each band declares the 20 units it paints. That clip
  is also what kept a strip out, so since 2026-10-09 each ring slot draws its own
  legend row and the three slots that freed carry the upper cells instead.
  Ring TEXT = full strip label (\`46%\` or \`100% · 500\` on the owning family).
  Ring TITLE = the band's own token, suffixed with the outer-pool token when the
  band is shared: one slot, two jobs, one string to say both in.
  Remaining melt: Transform startAngle (1 - value/max)*359.9, endAngle fixed 359.9
  so usage opens clockwise from 12 and remaining ends at 12. Exact full alone
  has no cap insets: one ROUND path from 0 to 359.9, retaining the live ColorRamp.
-->`

/** Radial lift, brighter above centre so the stack reads as sunk into it. */
function lift() {
  return `        <PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="lift">
            <Ellipse x="0" y="0" width="${FACE.size}" height="${FACE.size}">
                <Fill color="#ff101412">
                    <RadialGradient
                        centerX="${FACE.center}"
                        centerY="216"
                        radius="279"
                        colors="#ff18201C #ff101412 #ff0A0D0B"
                        positions="0.0 0.55 1.0" />
                </Fill>
            </Ellipse>
        </PartDraw>`
}

function cellChromeComment() {
  const rows = CELLS.map(({ x, y }) => `${x},${y}`).join('  ')
  return `        <!-- What lies under the cells, declared ahead of every slot so a filled
             cell's own opaque well covers it: ${rows} at ${CELL.size} units, centres on a
             curved row with the middle cell raised fourteen units.
             The middle and right cells
             carry the default weather, which costs no complication slot. -->`
}

function cellComment() {
  return `        <!-- Three cells the wearer fills, above the clock. The system owns what goes
             in them; this face owns only the declaration and how it is drawn.
             (docs/product/WATCH_RING_DESIGN.md, Upper cells, revision 2026-10-09) -->`
}

/**
 * A cell's text, in the face's own label voice — the provider gets no say.
 *
 * `template` is the WFF template the parameter lands in. It is `%s` for a
 * complication, whose text arrives ready to read, and carries the mark or the
 * name for a weather reading, which arrives as a bare number (`CELL_CHROME`).
 */
function cellText(template, parameter, pad, fontSize = CELL.fontSize) {
  return `${pad}<PartText x="${CELL.textX}" y="${CELL.textY}" width="${CELL.textWidth}" height="${CELL.textHeight}" alpha="255">
${pad}    <Variant mode="AMBIENT" target="alpha" value="140" />
${pad}    <Text align="CENTER" ellipsis="TRUE">
${pad}        <Font family="SYNC_TO_DEVICE" size="${fontSize}" weight="BOLD" color="${COLOR.text}">
${pad}            <Template>${template}
${pad}                <Parameter expression="${parameter}" />
${pad}            </Template>
${pad}        </Font>
${pad}    </Text>
${pad}</PartText>`
}

/** Select the scale from the weather source, whose unit is an integer enum. */
function cellReadingText({ template, expression, unit }, pad) {
  const reading = (template, pad) => cellSizedText(
    template, expression, pad,
    unit ? `${expression} < 0 || ${expression} >= 100` : `${expression} >= 10`,
    unit ? `${expression} <= -100` : 'false',
  )
  if (!unit) {
    return reading(template, pad)
  }
  return `${pad}<Condition>
${pad}    <Expressions>
${pad}        <Expression name="isCelsius"><![CDATA[${unit} == 1]]></Expression>
${pad}        <Expression name="isFahrenheit"><![CDATA[${unit} == 2]]></Expression>
${pad}    </Expressions>
${pad}    <Compare expression="isCelsius">
${reading('%s°C', `${pad}        `)}
${pad}    </Compare>
${pad}    <Compare expression="isFahrenheit">
${reading('%s°F', `${pad}        `)}
${pad}    </Compare>
${pad}    <Default>
${reading(template, `${pad}        `)}
${pad}    </Default>
${pad}</Condition>`
}

/** Finite WFF2 sizes; the narrowest branch takes precedence without changing data. */
function cellSizedText(template, parameter, pad, medium, small) {
  return `${pad}<Condition>
${pad}    <Expressions>
${pad}        <Expression name="smallText"><![CDATA[${small}]]></Expression>
${pad}        <Expression name="mediumText"><![CDATA[!(${small}) && (${medium})]]></Expression>
${pad}    </Expressions>
${pad}    <Compare expression="smallText">
${cellText(template, parameter, `${pad}        `, 12)}
${pad}    </Compare>
${pad}    <Compare expression="mediumText">
${cellText(template, parameter, `${pad}        `, 14)}
${pad}    </Compare>
${pad}    <Default>
${cellText(template, parameter, `${pad}        `)}
${pad}    </Default>
${pad}</Condition>`
}

/** The flat recess a cell shows while our own reading sits on it. */
function cellWellFlat(color, pad) {
  return `${pad}<PartDraw x="0" y="0" width="${CELL.size}" height="${CELL.size}">
${pad}    <Ellipse x="0" y="0" width="${CELL.size}" height="${CELL.size}">
${pad}        <Fill color="${color}" />
${pad}    </Ellipse>
${pad}</PartDraw>`
}

/**
 * The border a cell wears while it is showing something, whether that is the
 * wearer's complication or the face's own weather reading. Without it a filled
 * cell is a dark disc on a dark field and only the glyphs read, so the cell
 * itself goes unseen. An empty cell does not wear one: its recess already says
 * what it is, and the two together make the language exact — ring means
 * occupied, recess means free. Every border retains its radial outward fade;
 * only lateral borders multiply it by an additional vertical bottom fade.
 */
function cellRing({ x, y, name }, pad) {
  const centre = CELL.size / 2
  const radius = CELL.ringDiameter / 2
  const vx = x + centre - FACE.center
  const vy = y + centre - FACE.center
  const distance = Math.hypot(vx, vy)
  if ([centre, radius, CELL.ringThickness, distance].some((value) => !Number.isFinite(value) || value <= 0)) {
    throw new Error('Cell border geometry requires finite positive size, radius, stroke and distance from the face centre')
  }
  const coordinate = (value) => {
    if (!Number.isFinite(value)) {
      throw new Error('Cell border gradient coordinates must be finite')
    }
    return Number(value.toFixed(6))
  }
  const colors = CELL_RING_FADE
    .map(({ alpha }) => `#${alpha.toString(16).padStart(2, '0')}${COLOR.cellRing.slice(3)}`)
    .join(' ')
  const positions = CELL_RING_FADE.map(({ position }) => position).join(' ')
  // WFF gradient colours encode alpha on the eight-bit grid. Normalize before
  // encoding so the mask's upper half is opaque, preserving outward lighting.
  const maskColors = CELL_RING_FADE
    .map(({ alpha }) => `#${Math.round(alpha * 255 / 0xaa).toString(16).padStart(2, '0')}ffffff`)
    .join(' ')
  const border = (pad, ambient = '') => `${pad}<PartDraw x="0" y="0" width="${CELL.size}" height="${CELL.size}" alpha="255">${ambient}
${pad}    <Arc
${pad}        centerX="${centre}"
${pad}        centerY="${centre}"
${pad}        width="${CELL.ringDiameter}"
${pad}        height="${CELL.ringDiameter}"
${pad}        startAngle="${SWEEP.start}"
${pad}        endAngle="${SWEEP.end}">
${pad}        <Stroke thickness="${CELL.ringThickness}" color="${COLOR.text}" cap="BUTT">
${pad}            <LinearGradient
${pad}                startX="${coordinate(centre - radius * vx / distance)}"
${pad}                startY="${coordinate(centre - radius * vy / distance)}"
${pad}                endX="${coordinate(centre + radius * vx / distance)}"
${pad}                endY="${coordinate(centre + radius * vy / distance)}"
${pad}                colors="${colors}"
${pad}                positions="${positions}" />
${pad}        </Stroke>
${pad}    </Arc>
${pad}</PartDraw>`
  if (vx === 0) {
    return border(pad, `\n${pad}    <Variant mode="AMBIENT" target="alpha" value="${CELL.ringAmbientAlpha}" />`)
  }
  // MASK affects only its parent group. The well and content remain siblings;
  // ambient dims the composed border once, outside the source and mask.
  return `${pad}<Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${name}" alpha="255">
${pad}    <Variant mode="AMBIENT" target="alpha" value="${CELL.ringAmbientAlpha}" />
${border(pad + ' '.repeat(4))}
${pad}    <PartDraw x="0" y="0" width="${CELL.size}" height="${CELL.size}" renderMode="MASK">
${pad}        <Rectangle x="0" y="0" width="${CELL.size}" height="${CELL.size}">
${pad}            <Fill color="#ffffffff">
${pad}                <LinearGradient
${pad}                    startX="${centre}"
${pad}                    startY="${coordinate(centre - radius)}"
${pad}                    endX="${centre}"
${pad}                    endY="${coordinate(centre + radius)}"
${pad}                    colors="${maskColors}"
${pad}                    positions="${positions}" />
${pad}            </Fill>
${pad}        </Rectangle>
${pad}    </PartDraw>
${pad}</Group>`
}

/**
 * The recess a cell shows when it has nothing at all on it: the same well, lit
 * across its outer 45% so it reads as a dish waiting to be filled rather than
 * as a fault. It wears no ring, which is what separates it at a glance from a
 * cell that is holding something; depth here is stated with a radial gradient,
 * the voice the lift already uses.
 */
function cellWellGraded(pad) {
  const centre = CELL.size / 2
  return `${pad}<PartDraw x="0" y="0" width="${CELL.size}" height="${CELL.size}">
${pad}    <Ellipse x="0" y="0" width="${CELL.size}" height="${CELL.size}">
${pad}        <Fill color="${COLOR.cellWell}">
${pad}            <RadialGradient
${pad}                centerX="${centre}"
${pad}                centerY="${centre}"
${pad}                radius="${centre}"
${pad}                colors="${COLOR.cellWell} ${COLOR.cellWell} ${COLOR.cellRim}"
${pad}                positions="0.0 0.55 1.0" />
${pad}        </Fill>
${pad}    </Ellipse>
${pad}</PartDraw>`
}

/**
 * What lies under a cell, drawn ahead of every slot so a filled cell's own
 * opaque well simply covers it. Where the face declares a weather reading it
 * shows on a flat well while the data is there and falls back to the bare
 * recess when it is not — a cell reading `0` or nothing at all is worse than a
 * cell that is plainly empty.
 */
function cellChrome({ x, y, label }, index) {
  const chrome = CELL_CHROME[index]
  const { expression } = chrome
  const pad = ' '.repeat(12)
  const body = expression
    ? `            <Condition>
                <Expressions>
                    <Expression name="hasWeather"><![CDATA[[WEATHER.IS_AVAILABLE]]]></Expression>
                </Expressions>
                <Compare expression="hasWeather">
                    <Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${label}Reading">
${cellWellFlat(COLOR.strip, ' '.repeat(24))}
${cellRing({ x, y, name: `${label}ReadingBorder` }, ' '.repeat(24))}
${cellReadingText(chrome, ' '.repeat(24))}
                    </Group>
                </Compare>
                <Default>
                    <Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${label}Bare">
${cellWellGraded(' '.repeat(24))}
                    </Group>
                </Default>
            </Condition>`
    : cellWellGraded(pad)
  return `        <Group x="${x}" y="${y}" width="${CELL.size}" height="${CELL.size}" name="${label}Chrome">
${body}
        </Group>`
}

/**
 * A cell the wearer owns. Every visual decision here is the face's: WFF gives a
 * provider no say in how its data looks, so the cell draws `TEXT` alone in its
 * own voice and drops the provider's `TITLE` and icon — at four glyphs there is
 * no second line for a title, and an icon beside the text would halve the text.
 *
 * `RANGED_VALUE` is drawn as text, never as an arc: a small arc here would put
 * a second arc language on a face whose arcs already mean one ring, one metric,
 * and it would say it six units from the real ones.
 *
 * The well inside the slot is the occluder, and it is opaque for that reason.
 * It carries no ambient variant: switching it off would let the chrome back out
 * from under the complication, with two values in the same 52 units.
 */
function cellSlot({ slotId, x, y, label, provider: systemProvider, type }) {
  const pad = ' '.repeat(20)
  const well = (name) => `${cellWellFlat(COLOR.cellWell, pad)}
${cellRing({ x, y, name }, pad)}`
  const body = (parameter, name) => `            <Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${label}">
${well(name)}
${cellSizedText('%s', parameter, pad, `textLength(${parameter}) >= 5`, `textLength(${parameter}) >= 7`)}
            </Group>`
  const inset = (CELL.size - CELL.iconSize) / 2
  // The tint goes on a group of its own, not on the slot: tinting the slot
  // would take the well with it. It is the text colour rather than a family
  // colour — on this face a family colour means *this ring's provider*, and a
  // cell is not a ring — so an icon reads as face text rather than as a
  // foreign mark.
  const icon = `            <Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${label}Icon">
${well(`${label}IconBorder`)}
                <Group x="${inset}" y="${inset}" width="${CELL.iconSize}" height="${CELL.iconSize}" name="${label}Tint" tintColor="${COLOR.text}">
                    <PartImage x="0" y="0" width="${CELL.iconSize}" height="${CELL.iconSize}" alpha="255">
                        <Variant mode="AMBIENT" target="alpha" value="140" />
                        <Image resource="[COMPLICATION.MONOCHROMATIC_IMAGE]" />
                    </PartImage>
                </Group>
            </Group>`
  return `        <ComplicationSlot
            x="${x}"
            y="${y}"
            width="${CELL.size}"
            height="${CELL.size}"
            slotId="${slotId}"
            displayName="@string/${label}_complication"
            supportedTypes="SHORT_TEXT RANGED_VALUE MONOCHROMATIC_IMAGE EMPTY"
            isCustomizable="TRUE">
            <DefaultProviderPolicy
                defaultSystemProvider="${systemProvider}"
                defaultSystemProviderType="${type}" />
            <BoundingBox x="0" y="0" width="${CELL.size}" height="${CELL.size}" />
            <Complication type="SHORT_TEXT">
${body('[COMPLICATION.TEXT]', `${label}TextBorder`)}
            </Complication>
            <Complication type="RANGED_VALUE">
${body('[COMPLICATION.TEXT]', `${label}RangedBorder`)}
            </Complication>
            <Complication type="MONOCHROMATIC_IMAGE">
${icon}
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

/** The drawable a ring's period is baked into, and the name WFF resolves it by. */
function textureResource(index, period, count = 3) {
  const prefix = count === 3 ? 'ring' : `ring_n${count}_`
  return `${prefix}${index + 1}_type_${period.toLowerCase()}`
}

/**
 * A ring's type as an SVG, in that ring's own design units. Tokens are placed one
 * by one, each rotated onto its share of the sweep, so the spacing is uniform by
 * construction — which is the whole reason the type is baked rather than set.
 */
function textureImage(diameter, title, repeats, thickness = BAND_THICKNESS) {
  const centre = diameter / 2
  // Preserve the measured N3 placement byte for byte. Wider bands keep the same
  // glyph cap height, centred at their actual new radius, rather than stretching.
  const baseline = thickness === BAND_THICKNESS
    ? TEXTURE_BASELINE : Number(((thickness + TEXTURE_CAP) / 2).toFixed(2))
  const pitch = 360 / TEXTURE.sweeps
  const slot = (pitch - TEXTURE.sweepGap) / repeats
  // Half a sweep off 12, so the breaks fall on the diagonals: 12 is where both
  // ends of the melt live, and a break there frames the round cap instead of
  // letting the type close over it.
  const origin = pitch / 2 + TEXTURE.sweepGap / 2
  const tokens = Array.from({ length: TEXTURE.sweeps }, (_, sweep) =>
    Array.from({ length: repeats }, (_, repeat) => {
      const angle = (origin + sweep * pitch + (repeat + 0.5) * slot).toFixed(2)
      return `<text x="${centre}" y="${baseline}" transform="rotate(${angle} ${centre} ${centre})">${title}</text>`
    }).join(''),
  ).join('')
  // One user unit per design unit: a viewBox that scales makes the rasterizer
  // misplace the centre a token rotates about. The pixels come from the density.
  return `<svg xmlns="http://www.w3.org/2000/svg"
  width="${diameter}" height="${diameter}" viewBox="0 0 ${diameter} ${diameter}">
  <g font-family="${TEXTURE.font}" font-size="${TEXTURE_FONT_SIZE}" font-weight="${TEXTURE.weight}"
    fill="#${COLOR.background.slice(3)}" text-anchor="middle">${tokens}</g>
</svg>
`
}

/**
 * ImageMagick, as `just export-icons` already uses it; no new tool for this. The
 * density is what sizes the output: 96 is one pixel per SVG user unit, and the SVG
 * is written in design units, so the image lands at exactly the pixels its box
 * covers on the canvas and the renderer draws it one to one. Baking finer buys
 * nothing — the scene is rasterized at canvas size before it reaches the screen.
 *
 * Through a file, never a pipe: ImageMagick hands a named SVG to a real renderer
 * and falls back to its own on stdin, and that fallback drops the centre a
 * `rotate()` turns about — every token lands on a circle around the corner.
 *
 * `-strip` for the sake of the diff: it drops the render timestamp, without which
 * every run rewrites committed binaries whose pixels did not change.
 */
async function rasterize(file, png, signal) {
  const render = runFile('convert', ['-background', 'none', '-density', '96', '-strip', file, `png32:${png}`], { signal })
  const closed = new Promise((resolve) => render.child.once('close', resolve))
  try {
    await render
  } finally {
    // Abort rejects before close; the caller must not remove the SVG yet.
    await closed
  }
}

/** One drawable per ring and period: what the face draws instead of setting type. */
async function writeTextures() {
  await access(FONT_FILE).catch(() => {
    throw new Error(`${FONT_FILE} is missing; ring type would bake in a substituted font`)
  })
  await mkdir(drawables, { recursive: true })
  const controller = new AbortController()
  const interrupt = () => controller.abort()
  process.on('SIGINT', interrupt)
  process.on('SIGTERM', interrupt)
  let scratch
  try {
    scratch = await mkdtemp(join(tmpdir(), 'wardpulse-type-'))
    controller.signal.throwIfAborted()
    for (const layout of LAYOUTS.filter(({ name }) => name !== 'Legacy')) {
      for (let index = 0; index < layout.count; index += 1) {
        const { diameter, thickness } = bandGeometry(layout, index)
        for (const { period, title, repeats } of TOKENS) {
          const name = textureResource(index, period, layout.count)
          const svg = join(scratch, `${name}.svg`)
          const repeat = ADAPTIVE_REPEATS[layout.count]?.[title][index] ?? repeats[index]
          await writeFile(svg, textureImage(diameter, title, repeat, thickness))
          await rasterize(svg, join(drawables, `${name}.png`), controller.signal)
        }
      }
    }
    controller.signal.throwIfAborted()
  } finally {
    try {
      if (scratch) await rm(scratch, { recursive: true, force: true })
    } finally {
      process.off('SIGINT', interrupt)
      process.off('SIGTERM', interrupt)
    }
  }
}

/**
 * One period's texture as the image that carries it. The branch already knows
 * its token, so nothing is substituted at runtime: TITLE only chooses which
 * branch draws.
 *
 * The box is the ring's own square. The type sits on the band's centreline, well
 * inside that square, so a box sized to the ring needs no separate bounds and
 * lines the image up with the arc by construction.
 */
function ringTextureBranch(diameter, index, period, count) {
  const inset = Number(((FACE.size - diameter) / 2).toFixed(1))
  return `                                <Compare expression="is${period}">
                                    <PartImage x="${inset}" y="${inset}" width="${diameter}" height="${diameter}" alpha="${TEXTURE_ALPHA}">
                                        <Variant mode="AMBIENT" target="alpha" value="${TEXTURE_ALPHA_AMBIENT}" />
                                        <Image resource="${textureResource(index, period, count)}" />
                                    </PartImage>
                                </Compare>`
}

/**
 * No `Default`: a slot whose complication names no period gets no texture,
 * rather than being labelled with whichever token the fallback happened to be.
 * A ring past the cap gets none either — there is no image baked for it.
 */
function ringTexture(diameter, index, count = 3) {
  if (index >= TEXTURE_RINGS) return ''
  // A period token needs no combined spelling: only a split band carries a pool
  // token, and a budget ring is never shared (`WATCH_RING_DESIGN.md`, Split band).
  const expressions = TOKENS.map(
    ({ period, title }) =>
      `                                    <Expression name="is${period}"><![CDATA[${titleEquals(title)}]]></Expression>`,
  ).join('\n')
  return `
                            <!-- Cut-out: the glyphs are holes, so the arc under them keeps the family colour. -->
                            <Condition>
                                <Expressions>
${expressions}
                                </Expressions>
${TOKENS.map(({ period }) => ringTextureBranch(diameter, index, period, count)).join('\n')}
                            </Condition>`
}

/**
 * How far a `ROUND` cap reaches past the angle it is drawn to, in degrees of the
 * band it sits on. Measured on the watch 2026-08-16: a 40-unit band at radius
 * 159 lost 6.42° of gap per end, which is half the nominal thickness laid along
 * the arc. Without it a nearly full ring reads as closed — 4% used showed a 3°
 * gap instead of 14°.
 */
function capDegrees(diameter, thickness) {
  const radius = diameter / 2
  return Number(((thickness / 2 / radius) * (180 / Math.PI)).toFixed(2))
}

function meltGeometry(diameter, thickness) {
  const cap = capDegrees(diameter, thickness)
  const twoCapCutoff = (2 * cap) / SWEEP.end
  return {
    cap,
    twoCapCutoff,
    // Only Legacy/N3 use 20/10-unit strokes; retain their published branch boundary.
    cutoffLiteral: thickness === BAND_THICKNESS || thickness === BAND_THICKNESS / 2
      ? twoCapCutoff.toFixed(6) : String(twoCapCutoff),
    insetEnd: SWEEP.end - cap,
  }
}

function meltBranchAngles(geometry, remaining, nearEmpty) {
  return {
    nearEmpty,
    strokeCap: nearEmpty ? 'BUTT' : 'ROUND',
    start: (1 - remaining) * SWEEP.end + (nearEmpty ? 0 : geometry.cap),
    end: nearEmpty ? SWEEP.end : geometry.insetEnd,
  }
}

function meltAngles(diameter, thickness, remaining) {
  const geometry = meltGeometry(diameter, thickness)
  const nearEmpty = remaining <= geometry.twoCapCutoff
  return meltBranchAngles(geometry, remaining, nearEmpty)
}

function visibleSweep(angles, roundCap) {
  return angles.end - angles.start + (angles.strokeCap === 'ROUND' ? 2 * roundCap : 0)
}

/**
 * Conservative radial coverage at the midpoint between two ROUND endpoints.
 * Elsewhere in that gap the nearer cap covers more; outside it the stroke has
 * its complete annular envelope. This is ideal geometry, not a native AA test.
 */
function roundClosureEnvelope(diameter, thickness, start, end) {
  const radius = diameter / 2
  const halfGap = ((360 - (end - start)) * Math.PI) / 360
  const along = radius * Math.cos(halfGap)
  const across = radius * Math.sin(halfGap)
  const reach = Math.sqrt((thickness / 2) ** 2 - across ** 2)
  return { inner: along - reach, outer: along + reach }
}

function assertFullRing(diameter, thickness, full) {
  const arcs = [...full.matchAll(/<Arc\s+([\s\S]*?)<\/Arc>/g)]
  const attributes = Object.fromEntries(
    [...(arcs[0]?.[1] ?? '').matchAll(/(\w+)="([^"]*)"/g)].map((match) => [match[1], match[2]]),
  )
  const start = Number(attributes.startAngle)
  const end = Number(attributes.endAngle)
  const envelope = roundClosureEnvelope(diameter, thickness, start, end)
  const inner = (diameter - thickness) / 2
  const outer = (diameter + thickness) / 2
  // Bound the ideal edge deficit to a hundredth of one design unit, not a
  // fullness epsilon. The old asymmetric full path misses by 0.77–1.50 units.
  if (
    arcs.length !== 1 ||
    full.includes('<Transform') ||
    attributes.centerX !== String(FACE.center) ||
    attributes.centerY !== String(FACE.center) ||
    attributes.width !== String(diameter) ||
    attributes.height !== String(diameter) ||
    attributes.thickness !== String(thickness) ||
    attributes.cap !== 'ROUND' ||
    attributes.colors !== '[COMPLICATION.RANGED_VALUE_COLORS]' ||
    start !== SWEEP.start || end <= start || end >= 360 ||
    !Number.isFinite(envelope.inner) || !Number.isFinite(envelope.outer) ||
    envelope.inner < inner || envelope.inner - inner > 0.01 ||
    envelope.outer > outer || outer - envelope.outer > 0.01 ||
    !full.includes('alpha="255"') ||
    !full.includes('<Variant mode="AMBIENT" target="alpha" value="140" />')
  ) {
    throw new Error(`ring ${diameter}/${thickness}: full path must cover the centered annulus without an inset or added junction`)
  }
}

/** Legacy and N3 keep the published cutoff, including its six-decimal rounding. */
function assertLegacyCutoffs() {
  const emittedCutoff = (diameter, thickness) => Number(
    bandArcs(diameter, thickness, '').match(/name="isNearEmpty"[^\n]*<= ([\d.]+)/)?.[1],
  )
  // This Float lies between the analytical and published 336/20 cutoffs.
  // Both the old percentage range and binary-scaled N3 must still select BUTT.
  const percent = Math.fround(1.8949854373931885)
  const expression = bandArcs(336, 20, '').match(/name="isNearEmpty"><!\[CDATA\[([^\n]+)\]\]>/)?.[1] ?? ''
  const selectsTiny = new Function('value', 'max', `return ${expression
    .replaceAll('[COMPLICATION.RANGED_VALUE_VALUE]', 'value')
    .replaceAll('[COMPLICATION.RANGED_VALUE_MAX]', 'max')}`)
  for (const max of [100, 800]) {
    const value = Math.fround(percent * (max / 100))
    const ratio = Math.fround(value / max)
    if (!(ratio <= emittedCutoff(336, 20)) || !selectsTiny(value, max)) {
      throw new Error(`MAX${max}: the preserved boundary remainder must select BUTT`)
    }
  }
  for (const [diameter, thickness, cutoff] of [
    [384, 20, 0.016560], [336, 20, 0.018950], [288, 20, 0.022117],
    [374, 10, 0.008502], [326, 10, 0.009780], [278, 10, 0.011448],
    [394, 10, 0.008058], [346, 10, 0.009225], [298, 10, 0.010670],
  ]) {
    if (emittedCutoff(diameter, thickness) !== cutoff) {
      throw new Error(`ring ${diameter}/${thickness}: published Legacy/N3 cutoff changed`)
    }
  }
}

function assertNearExhaustedArcs() {
  const epsilon = 0.000001
  const tolerance = 0.000000001
  const geometries = LAYOUTS.filter(({ name }) => name !== 'Legacy').flatMap((layout) =>
    Array.from({ length: layout.count }, (_, index) => {
      const { full, inner, outer, thickness, half } = bandGeometry(layout, index)
      return [[full, thickness], [inner, half], [outer, half]]
    }).flat(),
  )
  for (const [centre, thickness] of geometries) {
    const geometry = meltGeometry(centre, thickness)
    const belowRemaining = geometry.twoCapCutoff - epsilon
    const below = meltAngles(centre, thickness, belowRemaining)
    const expectedBelowSweep = belowRemaining * SWEEP.end
    if (
      !below.nearEmpty ||
      below.strokeCap !== 'BUTT' ||
      below.end <= below.start ||
      Math.abs(visibleSweep(below, geometry.cap) - expectedBelowSweep) > tolerance
    ) {
      throw new Error(
        `ring ${centre}/${thickness}: a remainder below the two-cap cutoff must stay visible and proportional`,
      )
    }

    const aboveRemaining = geometry.twoCapCutoff + epsilon
    const above = meltAngles(centre, thickness, aboveRemaining)
    const expectedStart = (1 - aboveRemaining) * SWEEP.end + geometry.cap
    if (
      above.nearEmpty ||
      above.strokeCap !== 'ROUND' ||
      above.start !== expectedStart ||
      above.end !== geometry.insetEnd ||
      Math.abs(visibleSweep(above, geometry.cap) - aboveRemaining * SWEEP.end) > tolerance
    ) {
      throw new Error(`ring ${centre}/${thickness}: geometry above the two-cap cutoff must stay inset`)
    }

    const buttAtCutoff = meltBranchAngles(geometry, geometry.twoCapCutoff, true)
    const roundAtCutoff = meltBranchAngles(geometry, geometry.twoCapCutoff, false)
    const cutoffSweep = geometry.twoCapCutoff * SWEEP.end
    if (
      Math.abs(visibleSweep(buttAtCutoff, geometry.cap) - cutoffSweep) > tolerance ||
      Math.abs(visibleSweep(roundAtCutoff, geometry.cap) - cutoffSweep) > tolerance
    ) {
      throw new Error(`ring ${centre}/${thickness}: melt branches must meet at the two-cap cutoff`)
    }

    for (const remaining of [0.999, 0.996, 0.99, 0.37, 0.04, 0.01, 0.0000001]) {
      const angles = meltAngles(centre, thickness, remaining)
      if (
        angles.end <= angles.start ||
        Math.abs(visibleSweep(angles, geometry.cap) - remaining * SWEEP.end) > tolerance
      ) {
        throw new Error(`ring ${centre}/${thickness}: positive partials must remain proportional`)
      }
    }

    const markup = bandArcs(centre, thickness, '')
    assertFullRing(centre, thickness,
      markup.match(/<Compare expression="isFull">([\s\S]*?)<\/Compare>/)?.[1] ?? '')
    const rawStart = `(1 - ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX])) * ${SWEEP.end}`
    const caps = [...markup.matchAll(/cap="(ROUND|BUTT)"/g)].map((match) => match[1])
    if (
      !markup.includes(`<= ${geometry.cutoffLiteral}`) ||
      !markup.includes(`value="${rawStart}"`) ||
      !markup.includes(`* ${SWEEP.end} + ${geometry.cap}`) ||
      caps.join(',') !== 'ROUND,ROUND,BUTT,ROUND'
    ) {
      throw new Error(
        `ring ${centre}/${thickness}: generated markup does not preserve both melt branches`,
      )
    }
  }

  for (const [ordinal, slot] of OUTER_HALVES.entries()) {
    const markup = outerHalfSlot(slot, ordinal)
    const decisions = emittedExtraDecisions(markup)
    const clip = markup.match(/<BoundingArc\s+([\s\S]*?)\/>/)?.[1] ?? ''
    const attributes = Object.fromEntries(
      [...clip.matchAll(/(\w+)="([^"]*)"/g)].map((match) => [match[1], match[2]]),
    )
    const clipThickness = Number(attributes.thickness)
    const envelope = roundClosureEnvelope(
      Number(attributes.width) - clipThickness, clipThickness,
      Number(attributes.startAngle), Number(attributes.endAngle),
    )
    if (
      attributes.centerX !== String(FACE.center) || attributes.centerY !== String(FACE.center) ||
      attributes.width !== attributes.height || attributes.isRoundEdge !== 'TRUE' ||
      !Number.isFinite(envelope.inner) || !Number.isFinite(envelope.outer)
    ) {
      throw new Error(`slot ${slot.slotId}: outer-half clip must stay centered with round edges`)
    }
    for (const layout of LAYOUTS) {
      for (let index = 0; index < layout.count; index += 1) {
        const branch = decisions.find(({ predicate }) => predicate(0, layout.max, layout.max, String(index)))?.body
        if (index >= layout.count - ordinal) {
          if (branch !== undefined) throw new Error(`impossible split ordinal ${ordinal}/${layout.name}/${index}`)
          continue
        }
        const { outer, half } = bandGeometry(layout, index)
        const full = branch?.match(/<PartDraw[^>]*alpha="255">[\s\S]*?<\/PartDraw>/)?.[0] ?? ''
        assertFullRing(outer, half, full)
        if ((outer - half) / 2 <= envelope.inner || (outer + half) / 2 >= envelope.outer) {
          throw new Error(`slot ${slot.slotId}/${layout.name}/${index}: entire half must fit inside the clip`)
        }
      }
    }
  }
  for (const layout of LAYOUTS) {
    for (let index = 0; index < layout.count; index += 1) {
      const { diameter, full, inner, outer, thickness, half } = bandGeometry(layout, index)
      const edge = diameter / 2
      if ((full - thickness) / 2 < 133.8 || edge > 202 ||
          (outer - half) / 2 !== (inner + half) / 2 ||
          (inner - half) / 2 !== edge - thickness ||
          (outer + half) / 2 !== edge) {
        throw new Error(`${layout.name}/${index}: band envelope or gapless split drifted`)
      }
      if (index > 0) {
        const previous = bandGeometry(layout, index - 1)
        if ((previous.full - thickness) / 2 - edge !== 4) throw new Error('band gap must remain four')
      }
    }
    const last = bandGeometry(layout, layout.count - 1)
    if ((last.full - last.thickness) / 2 !== 134) throw new Error('belt must end at 134')
  }
}

function bandTrack(diameter, thickness, pad) {
  return `${pad}<PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}">
${pad}    <Arc
${pad}        centerX="${FACE.center}"
${pad}        centerY="${FACE.center}"
${pad}        width="${diameter}"
${pad}        height="${diameter}"
${pad}        startAngle="${SWEEP.start}"
${pad}        endAngle="${SWEEP.end}">
${pad}        <Stroke color="${COLOR.track}" thickness="${thickness}" cap="ROUND" />
${pad}    </Arc>
${pad}</PartDraw>`
}

/** The same three drawings serve main/inner selectors and combined extra decisions. */
function bandPaint(diameter, thickness, kind, pad) {
  const geometry = meltGeometry(diameter, thickness)
  const end = kind === 'round' ? geometry.insetEnd.toFixed(2) : SWEEP.end
  const rawStart = `(1 - ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX])) * ${SWEEP.end}`
  const start = kind === 'tiny' ? rawStart
    : `clamp(${rawStart} + ${geometry.cap}, ${SWEEP.start}, ${end})`
  const transform = kind === 'full' ? '' : `${pad}        <Transform
${pad}            target="startAngle"
${pad}            value="${start}" />
`
  return `${pad}<PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}" alpha="255">
${pad}    <Variant mode="AMBIENT" target="alpha" value="140" />
${pad}    <Arc
${pad}        centerX="${FACE.center}"
${pad}        centerY="${FACE.center}"
${pad}        width="${diameter}"
${pad}        height="${diameter}"
${pad}        startAngle="${SWEEP.start}"
${pad}        endAngle="${end}">
${transform}${pad}        <WeightedStroke
${pad}            thickness="${thickness}"
${pad}            colors="[COMPLICATION.RANGED_VALUE_COLORS]"
${pad}            cap="${kind === 'tiny' ? 'BUTT' : 'ROUND'}" />
${pad}    </Arc>
${pad}</PartDraw>`
}

/**
 * Track plus melt for one arc. The melt keeps its own `PartDraw` so ambient can
 * dim it without touching the track underneath.
 *
 * Above the cutoff, the melt is inset by one cap at each end, so the round caps
 * fill exactly the space the inset freed. At or below it, straight ends keep the
 * visible sweep equal to the proportional centreline. Exact full uses neither
 * inset: one almost-closed path keeps the ROUND endpoints together at 12.
 */
function bandArcs(diameter, thickness, pad) {
  const geometry = meltGeometry(diameter, thickness)
  return `${bandTrack(diameter, thickness, pad)}
${pad}<Condition>
${pad}    <Expressions>
${pad}        <Expression name="isFull"><![CDATA[[COMPLICATION.RANGED_VALUE_VALUE] > 0 && [COMPLICATION.RANGED_VALUE_VALUE] >= [COMPLICATION.RANGED_VALUE_MAX]]]></Expression>
${pad}        <Expression name="isNearEmpty"><![CDATA[[COMPLICATION.RANGED_VALUE_VALUE] > 0 && ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX]) <= ${geometry.cutoffLiteral}]]></Expression>
${pad}        <Expression name="hasRemaining"><![CDATA[[COMPLICATION.RANGED_VALUE_VALUE] > 0]]></Expression>
${pad}    </Expressions>
${pad}    <!-- First true wins: positive full, tiny, then round partial.
${pad}         Zero retains only the track; no coloured arc or cap is drawn. -->
${pad}    <!-- Exact full has no usage gap: omit BOTH cap insets, keeping the
${pad}         endpoints 0.1 degrees apart in one path. A literal 360-degree
${pad}         ROUND sweep historically collapsed to a tip on the watch. -->
${pad}    <Compare expression="isFull">
${bandPaint(diameter, thickness, 'full', `${pad}        `)}
${pad}    </Compare>
${pad}    <!-- The two-cap inset cannot represent a smaller positive remainder:
${pad}         its sweep would be zero or negative. Keep the proportional
${pad}         centreline without either inset and use straight ends so the
${pad}         visible sweep does not overstate the remainder. -->
${pad}    <Compare expression="isNearEmpty">
${bandPaint(diameter, thickness, 'tiny', `${pad}        `)}
${pad}    </Compare>
${pad}    <Compare expression="hasRemaining">
${bandPaint(diameter, thickness, 'round', `${pad}        `)}
${pad}    </Compare>
${pad}</Condition>`
}

// All six readout boxes are inside r139..171.25, below the clock, outside the
// preserved original-frame r137..159 measurement annulus at 360/450 scale.
function n1Text(template, column, row, parameter = null) {
  // Static Font content must not include XML formatting whitespace.
  const content = parameter === null ? `<![CDATA[${template}]]>` : `
            <Template>${template}<Parameter expression="${parameter}" /></Template>
        `
  return `<PartText x="${173 + column * 35}" y="${364 + row * 12}" width="34" height="12">
    <Text align="CENTER" ellipsis="TRUE">
        <Font family="SYNC_TO_DEVICE" size="10" weight="BOLD" color="${COLOR.text}">${content}</Font>
    </Text>
</PartText>`
}

function n1Group(name, content) {
  return `<Group x="0" y="0" width="450" height="450" name="n1Diag_${name}">${content}</Group>`
}

function n1Witness(name, text, column, row) {
  return n1Group(`add_${name}`, n1Text(text, column, row))
}

/** Fields are independent of admission, with no raw TITLE or unbounded literals. */
function n1ConsumerFields() {
  const numbers = [['VALUE', 'V'], ['MIN', 'm'], ['MAX', 'M']].map(([field, label], column) => {
    const value = `[COMPLICATION.RANGED_VALUE_${field}]`
    return `<Condition>
    <Expressions><Expression name="bounded${field}"><![CDATA[${value} >= 0 && ${value} <= 800]]></Expression></Expressions>
    <Compare expression="bounded${field}">${n1Group(`add_field_${field}`, n1Text(`${label}%s`, column, 0, value))}</Compare>
    <Default>${n1Witness(`field_${field}_other`, `${label}?`, column, 0)}</Default>
</Condition>`
  }).join('\n')
  const titles = ['0', '1', '2', ''].map((title, index) =>
    `<Expression name="title${index}"><![CDATA[[COMPLICATION.TITLE] == "${title}"]]></Expression>`,
  ).join('\n')
  const branches = ['T0', 'T1', 'T2', 'TE'].map((label, index) =>
    `<Compare expression="title${index}">${n1Witness(`title${index}`, label, 0, 1)}</Compare>`,
  ).join('\n')
  return n1Group('add_fields', `${numbers}
<Condition><Expressions>${titles}</Expressions>${branches}
    <Default>${n1Witness('titleOther', 'T?', 0, 1)}</Default>
</Condition>`)
}

/** Geometry is selected solely from this response; no sibling can supply a count. */
function mainBand(layout, index) {
  const { diameter, thickness, full, inner, half } = bandGeometry(layout, index)
  const name = `ring${index + 1}${layout.name}`
  return `                        <Compare expression="is${layout.name}">
                            <Condition>
                                <Expressions>
                                    <Expression name="isSplit"><![CDATA[${titleEquals(...SPLIT_TITLES)}]]></Expression>
                                </Expressions>
                                <Compare expression="isSplit">
                                    <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="${name}Half">
${bandArcs(inner, half, ' '.repeat(40))}
                                    </Group>
                                </Compare>
                                <Default>
                                    <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="${name}">
${bandArcs(full, thickness, ' '.repeat(40))}${ringTexture(diameter, index, layout.count)}
                                    </Group>
                                </Default>
                            </Condition>
                        </Compare>`
}

function ringSlot({ slotId, service }, index) {
  const layouts = LAYOUTS.filter(({ count }) => index < count)
  const titles = titleEquals('', ZERO_TOKEN, ...TOKENS.map(({ title }) => title), ...SPLIT_TITLES)
  const credits = index === CREDITS_RING_INDEX
    ? ` || (${rangeGuard(100)} && ${titleEquals(CREDITS_TOKEN)})` : ''
  const expressions = layouts.map(({ name, max }) =>
    `                        <Expression name="is${name}"><![CDATA[${rangeGuard(max)} && (${titles})]]></Expression>`,
  ).join('\n')
  // Keep existing subtree whitespace stable when adding the single-tree wrapper.
  return `        <ComplicationSlot
            x="0"
            y="0"
            width="${FACE.size}"
            height="${FACE.size}"
            slotId="${slotId}"
            displayName="@string/ring${index + 1}_complication"
            supportedTypes="RANGED_VALUE EMPTY"
            isCustomizable="FALSE">
            <DefaultProviderPolicy
                primaryProvider="${provider(service)}"
                primaryProviderType="RANGED_VALUE"
                defaultSystemProvider="EMPTY"
                defaultSystemProviderType="EMPTY" />
            <BoundingBox x="0" y="0" width="${FACE.size}" height="${FACE.size}" />
            <Complication type="RANGED_VALUE">
                <Condition>
                    <Expressions>
                        <Expression name="isValid"><![CDATA[((${layouts.map(({ max }) => `(${rangeGuard(max)})`).join(' || ')}) && (${titles}))${credits}]]></Expression>
                    </Expressions>
                    <!-- Invalid range, value, TITLE or position paints nothing, including the well. -->
                    <Compare expression="isValid">
                        <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="ring${index + 1}_main">
                        <Condition>
                            <Expressions>
${expressions}
                            </Expressions>
${layouts.map((layout) => mainBand(layout, index)).join('\n')}
                        </Condition>
${stripRow(index, ' '.repeat(24))}
                        </Group>
                    </Compare>
                </Condition>
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

/**
 * Each extra carries its own envelope and exact outside index. Ordinal one
 * cannot occupy the innermost band: an earlier pair must precede it in payload
 * order. No delivered main is required and no main paint/label is synthesized.
 */
function outerHalfSlot({ slotId, service, label }, ordinal, diagnostics = false) {
  const positions = LAYOUTS.flatMap((layout) =>
    Array.from({ length: layout.count - ordinal }, (_, index) => ({ layout, index })),
  )
  // Retain the accepted N3 clip, with margin around every new half as well.
  const clipOuter = 207
  const clipInner = 139
  const decisions = positions.flatMap(({ layout, index }) => {
    const { outer, half } = bandGeometry(layout, index)
    const value = '[COMPLICATION.RANGED_VALUE_VALUE]'
    const maximum = '[COMPLICATION.RANGED_VALUE_MAX]'
    return [
      ['Full', `${value} > 0 && ${value} >= ${maximum}`],
      ['Tiny', `${value} > 0 && (${value} / ${maximum}) <= ${meltGeometry(outer, half).cutoffLiteral}`],
      ['Round', `${value} > 0`],
      ['Zero', `${value} == 0`],
    ].map(([state, test]) => ({ layout, index, outer, half, state,
      name: `is${layout.name}Band${index}${state}`,
      predicate: `${rangeGuard(layout.max)} && [COMPLICATION.TITLE] == "${index}" && (${test})`,
    }))
  })
  const expressions = decisions.map(({ name, predicate }) =>
    `                        <Expression name="${name}"><![CDATA[${predicate}]]></Expression>`,
  ).join('\n')
  const branches = decisions.map(({ layout, index, outer, half, state, name }) => {
    const kind = state.toLowerCase()
    const paintToken = { full: 'PF', tiny: 'PT', round: 'PR', zero: 'PN' }[kind]
    return `                    <Compare expression="${name}">
                        <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="outerHalf${slotId}_${layout.name}_${index + 1}_${kind}">
${bandTrack(outer, half, ' '.repeat(28))}${kind === 'zero' ? '' : `
${bandPaint(outer, half, kind, ' '.repeat(28))}`}${diagnostics ? `
${n1Witness(`admit_${layout.name}_${index}_${kind}`, layout.name === 'N1' ? 'A1' : 'AO', 1, 1)}${layout.name === 'N1' ? `
${n1Witness(kind === 'zero' ? 'paintNone' : `paint_${kind}`, paintToken, 2, 1)}` : ''}` : ''}
                        </Group>
                    </Compare>`
  }).join('\n')
  return `        <ComplicationSlot
            x="0"
            y="0"
            width="${FACE.size}"
            height="${FACE.size}"
            slotId="${slotId}"
            displayName="@string/${label}"
            supportedTypes="RANGED_VALUE EMPTY"
            isCustomizable="FALSE">
            <DefaultProviderPolicy
                primaryProvider="${provider(service)}"
                primaryProviderType="RANGED_VALUE"
                defaultSystemProvider="EMPTY"
                defaultSystemProviderType="EMPTY" />
            <BoundingArc
                centerX="${FACE.center}"
                centerY="${FACE.center}"
                width="${clipOuter * 2}"
                height="${clipOuter * 2}"
                thickness="${clipOuter - clipInner}"
                startAngle="${SWEEP.start}"
                endAngle="${SWEEP.end}"
                isRoundEdge="TRUE" />
            <Complication type="RANGED_VALUE">${diagnostics ? `
${n1ConsumerFields()}` : ''}
                <Condition>
                    <Expressions>
${expressions}
                    </Expressions>
${branches}${diagnostics ? `
                    <Default>${n1Group('add_rejected', `${n1Text('AX', 1, 1)}${n1Text('PN', 2, 1)}`)}</Default>` : ''}
                </Condition>
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

function emittedExpressions(markup) {
  return new Map([...markup.matchAll(/<Expression name="([^"]+)"><!\[CDATA\[([\s\S]*?)\]\]><\/Expression>/g)]
    .map(([, name, expression]) => {
      const source = expression.replaceAll('[COMPLICATION.RANGED_VALUE_MIN]', 'min')
        .replaceAll('[COMPLICATION.RANGED_VALUE_MAX]', 'max')
        .replaceAll('[COMPLICATION.RANGED_VALUE_VALUE]', 'value')
        .replaceAll('[COMPLICATION.TITLE]', 'title')
      return [name, new Function('min', 'max', 'value', 'title', `return ${source}`)]
    }))
}

/** Normal extras have no nested comparisons; the XML checker enforces that structure. */
function emittedExtraDecisions(markup) {
  const predicates = emittedExpressions(markup)
  return [...markup.matchAll(/<Compare expression="([^"]+)">([\s\S]*?)<\/Compare>/g)]
    .map(([, name, body]) => ({ predicate: predicates.get(name), body }))
}

/** Exercise actual ordered decisions, including non-finite wire fields. */
function assertLowerContracts() {
  for (const [index, ring] of RINGS.entries()) {
    const markup = ringSlot(ring, index)
    const valid = emittedExpressions(markup).get('isValid')
    for (const [max, allowed] of [[100, true], [200, index === 0], [400, index < 2], [800, true]]) {
      if (valid(0, max, 0, 'zero') !== allowed || valid(0, max, max, '') !== allowed) {
        throw new Error(`main ${index}: legacy/adaptive position or endpoint admission drifted`)
      }
    }
    const malformed = [
      [0, 300, 50, ''], [1, 200, 50, ''], [0, 200, -1, ''], [0, 200, 201, ''],
      [0, 200, NaN, ''], [0, 200, Infinity, ''], [0, Infinity, 50, ''],
      [NaN, 200, 50, ''], [0, NaN, 50, ''], [0, 800, 50, 'split:unknown'],
    ]
    if (malformed.some((fields) => valid(...fields)) ||
        valid(0, 100, 100, CREDITS_TOKEN) !== (index === CREDITS_RING_INDEX) ||
        valid(0, 200, 100, CREDITS_TOKEN)) {
      throw new Error(`main ${index}: malformed data or count-bearing credits admitted`)
    }
    // Every drawing, including the row, is below the single valid-position gate.
    const body = markup.split('<Complication type="RANGED_VALUE">')[1].split('</Complication>')[0]
    if (body.indexOf('<Compare expression="isValid">') > body.indexOf('<PartDraw') ||
        !body.trimEnd().endsWith('</Compare>\n                </Condition>')) {
      throw new Error(`main ${index}: a lower component escaped its admission gate`)
    }
  }
  for (const [ordinal, slot] of OUTER_HALVES.entries()) {
    const decisions = emittedExtraDecisions(outerHalfSlot(slot, ordinal))
    const selected = (...fields) => decisions.find(({ predicate }) => predicate(...fields))?.body
    for (const [max, lastIndex] of [[100, 2], [200, 0], [400, 1], [800, 2]]) {
      for (let index = 0; index < 3; index += 1) {
        for (const value of [0, max * 2 ** -20, max * 0.37, max * 0.999, max]) {
          const body = selected(0, max, value, String(index))
          if ((body !== undefined) !== (index <= lastIndex - ordinal)) {
            throw new Error(`extra ${ordinal}/${max}/${index}: impossible ordinal or position admitted`)
          }
          if (body !== undefined && ((body.match(/<Stroke /g)?.length ?? 0) !== 1 ||
              (body.match(/<WeightedStroke/g)?.length ?? 0) !== (value > 0 ? 1 : 0) ||
              body.includes('<Condition>'))) {
            throw new Error(`extra ${ordinal}: selected decision must own its track and only its paint`)
          }
        }
      }
    }
    const malformed = [[0, 300, 50, '0'], [1, 800, 50, '0'],
      [0, 800, -1, '0'], [0, 800, 801, '0']]
    for (const invalid of [NaN, Infinity, -Infinity]) {
      malformed.push([invalid, 800, 50, '0'], [0, invalid, 50, '0'], [0, 800, invalid, '0'])
    }
    for (const title of ['', '00', '0.0', ' 0', '0 ', '3', 'split', '0:zero']) {
      malformed.push([0, 800, 50, title])
    }
    if (malformed.some((fields) => selected(...fields) !== undefined)) {
      throw new Error(`extra ${ordinal}: malformed response admitted`)
    }
  }
}

/** Two clocks, not one: the ambient copy is thinner and swaps in by alpha. */
function clock() {
  return `        <DigitalClock x="0" y="0" width="${FACE.size}" height="${FACE.size}">
            <TimeText
                x="0"
                y="${CLOCK.active.y}"
                width="${FACE.size}"
                height="${CLOCK.active.height}"
                alpha="255"
                align="CENTER"
                format="hh:mm"
                hourFormat="SYNC_TO_DEVICE">
                <Variant mode="AMBIENT" target="alpha" value="0" />
                <Font
                    family="SYNC_TO_DEVICE"
                    size="${CLOCK.active.fontSize}"
                    weight="BOLD"
                    slant="NORMAL"
                    color="${COLOR.text}" />
            </TimeText>
            <TimeText
                x="0"
                y="${CLOCK.ambient.y}"
                width="${FACE.size}"
                height="${CLOCK.ambient.height}"
                alpha="0"
                align="CENTER"
                format="hh:mm"
                hourFormat="SYNC_TO_DEVICE">
                <Variant mode="AMBIENT" target="alpha" value="255" />
                <Font
                    family="SYNC_TO_DEVICE"
                    size="${CLOCK.ambient.fontSize}"
                    weight="THIN"
                    slant="NORMAL"
                    color="${COLOR.text}" />
            </TimeText>
        </DigitalClock>`
}

/** The wordmark also carries the tap target into the Wear app. */
function wordmark() {
  const box = (size) =>
    `x="${WORDMARK.centerX - size / 2}" y="${WORDMARK.centerY - size / 2}" width="${size}" height="${size}"`
  return `        <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="wardpulse">
            <Launch target="app.wardpulse/app.wardpulse.wear.MainActivity" />
            <!-- Preserve the original padded PNG; visible clock clearance needs native measurement. -->
            <PartImage ${box(WORDMARK.size)} alpha="95">
                <Variant mode="AMBIENT" target="alpha" value="0" />
                <Image resource="wardpulse_mono" />
            </PartImage>
            <PartImage ${box(WORDMARK.ambientSize)} alpha="0">
                <Variant mode="AMBIENT" target="alpha" value="70" />
                <Image resource="wardpulse_mono" />
            </PartImage>
        </Group>`
}

/**
 * One legend row, drawn by the slot of the ring it belongs to rather than by a
 * slot of its own: that is what freed the three slots the cells took. The box
 * is placed in face coordinates because its group spans the whole canvas now,
 * and the row is fixed per slot — nothing here varies with the ring count.
 *
 * Ambient dims the whole row to alpha 90. The variant stays on this enclosing
 * group so it reaches the family accent painted from the complication's
 * ranged-value colours as well as the well, marker, and label.
 */
function stripRow(ringIndex, pad) {
  const y = stripRowY(ringIndex)
  const { x, width, height, radius } = STRIP
  return `${pad}<Group x="${x}" y="${y}" width="${width}" height="${height}" name="ring${ringIndex + 1}_strip" alpha="255">
${pad}    <Variant mode="AMBIENT" target="alpha" value="90" />
${pad}    <PartDraw x="0" y="0" width="${width}" height="${height}">
${pad}        <RoundRectangle x="0" y="0" width="${width}" height="${height}" cornerRadiusX="${radius}" cornerRadiusY="${radius}">
${pad}            <Fill color="${COLOR.strip}" />
${pad}        </RoundRectangle>
${pad}        <!-- Family accent from ColorRamp (same path as matching ring). -->
${pad}        <Arc
${pad}            centerX="1.5"
${pad}            centerY="${height / 2}"
${pad}            width="3"
${pad}            height="14"
${pad}            startAngle="${SWEEP.start}"
${pad}            endAngle="${SWEEP.end}">
${pad}            <WeightedStroke
${pad}                thickness="3"
${pad}                colors="[COMPLICATION.RANGED_VALUE_COLORS]"
${pad}                cap="BUTT" />
${pad}        </Arc>
${pad}    </PartDraw>
${splitMarker(pad + ' '.repeat(4))}
${stripText(pad + ' '.repeat(4))}
${pad}</Group>`
}

/** Mixed Font runs centre together; only exact exhausted percent tokens tint. */
function stripText(pad) {
  const { height, textInset, textWidth, fontSize } = STRIP
  const text = '[COMPLICATION.TEXT]'
  const length = `textLength(${text})`
  // WFF may evaluate inactive branches; keep both cut points ordered inside TEXT.
  const innerEnd = `clamp(2, 0, ${length})`
  const outerStart = `clamp(${length} - 2, ${innerEnd}, ${length})`
  const partAtSize = (runs, fontSize, innerPad) => `${innerPad}<PartText x="${textInset}" y="0" width="${textWidth}" height="${height}">
${innerPad}    <Text align="CENTER" ellipsis="TRUE">
${runs.map(([expression, exhausted]) => `${innerPad}        <Font family="SYNC_TO_DEVICE" size="${fontSize}" weight="BOLD" color="${exhausted ? COLOR.exhaustedPercent : COLOR.text}">
${innerPad}            <Template>%s
${innerPad}                <Parameter expression="${expression}" />
${innerPad}            </Template>
${innerPad}        </Font>`).join('\n')}
${innerPad}    </Text>
${innerPad}</PartText>`
  // Size the complete mixed-run label together, preserving its centre and baseline.
  const part = (runs, innerPad) => `${innerPad}<Condition>
${innerPad}    <Expressions>
${innerPad}        <Expression name="longLabel"><![CDATA[${length} == 11]]></Expression>
${innerPad}        <Expression name="longestLabel"><![CDATA[${length} >= 12]]></Expression>
${innerPad}    </Expressions>
${innerPad}    <Compare expression="longLabel">
${partAtSize(runs, 18, `${innerPad}        `)}
${innerPad}    </Compare>
${innerPad}    <Compare expression="longestLabel">
${partAtSize(runs, 16, `${innerPad}        `)}
${innerPad}    </Compare>
${innerPad}    <Default>
${partAtSize(runs, fontSize, `${innerPad}        `)}
${innerPad}    </Default>
${innerPad}</Condition>`
  const zeroTitles = (state) => SPLIT_BASE_TITLES.map((base) => `${base}${TOKEN_SEPARATOR}${state}`)
  const states = [
    {
      name: 'zeroInner',
      tokens: [ZERO_TOKEN, ...zeroTitles('zero-inner')],
      runs: [[`subText(${text}, 0, ${innerEnd})`, true], [`subText(${text}, ${innerEnd}, ${length})`, false]],
    },
    {
      name: 'zeroOuter',
      tokens: zeroTitles('zero-outer'),
      runs: [[`subText(${text}, 0, ${outerStart})`, false], [`subText(${text}, ${outerStart}, ${length})`, true]],
    },
    {
      name: 'zeroBoth',
      tokens: zeroTitles('zero-both'),
      runs: [[`subText(${text}, 0, ${innerEnd})`, true], [`subText(${text}, ${innerEnd}, ${outerStart})`, false], [`subText(${text}, ${outerStart}, ${length})`, true]],
    },
  ]
  return `${pad}<Condition>
${pad}    <Expressions>
${states.map(({ name, tokens }) => `${pad}        <Expression name="${name}"><![CDATA[${titleEquals(...tokens)}]]></Expression>`).join('\n')}
${pad}    </Expressions>
${states.map(({ name, runs }) => `${pad}    <Compare expression="${name}">
${part(runs, pad + ' '.repeat(8))}
${pad}    </Compare>`).join('\n')}
${pad}    <Default>
${part([[text, false]], pad + ' '.repeat(8))}
${pad}    </Default>
${pad}</Condition>`
}

/**
 * The strip owns both accents; only its inner pool uses the ColorRamp.
 *
 * The pool token now arrives suffixed to the band's own `split`, because one
 * slot says both in one `TITLE`, so each branch matches the whole combined
 * string rather than the pool name alone.
 */
function splitMarker(pad) {
  const { width, height } = STRIP
  const expressions = SPLIT_POOLS.map(
    ({ token }, index) =>
      `${pad}        <Expression name="isPool${index}"><![CDATA[${titleEquals(
        ...[`${SPLIT_TOKEN}${TOKEN_SEPARATOR}${token}`, ...ZERO_STATES.map((state) => `${SPLIT_TOKEN}${TOKEN_SEPARATOR}${token}${TOKEN_SEPARATOR}${state}`)],
      )}]]></Expression>`,
  ).join('\n')
  const branches = SPLIT_POOLS.map(
    ({ color }, index) => `${pad}    <Compare expression="isPool${index}">
${pad}        <PartDraw x="0" y="0" width="${width}" height="${height}">
${pad}            <Arc
${pad}                centerX="${width - 1.5}"
${pad}                centerY="${height / 2}"
${pad}                width="3"
${pad}                height="14"
${pad}                startAngle="${SWEEP.start}"
${pad}                endAngle="${SWEEP.end}">
${pad}                <Stroke thickness="3" color="${color}" cap="BUTT" />
${pad}            </Arc>
${pad}        </PartDraw>
${pad}    </Compare>`,
  ).join('\n')
  // No Default branch: an empty or unknown token paints no far marker.
  return `${pad}<Condition>
${pad}    <Expressions>
${expressions}
${pad}    </Expressions>
${branches}
${pad}</Condition>`
}

function face(diagnostics = false) {
  // A blank line means "a different slot starts here". The lift is the ground
  // the first ring sits on and the comment introduces the strip stack, so
  // neither is cut off from what follows it.
  const body = [
    [
      lift(),
      cellChromeComment(),
      CELLS.map(cellChrome).join('\n\n'),
    ].join('\n'),
    [
      RINGS.map(ringSlot).join('\n\n'),
      OUTER_HALVES.map((slot, ordinal) => outerHalfSlot(slot, ordinal, diagnostics && slot.slotId === 106)).join('\n\n'),
    ].join('\n\n'),
    clock(),
    wordmark(),
    [
      cellComment(),
      CELLS.map(cellSlot).join('\n\n'),
    ].join('\n'),
  ].join('\n\n')
  return `${HEADER}
<WatchFace width="${FACE.size}" height="${FACE.size}">
    <Metadata key="CLOCK_TYPE" value="DIGITAL" />
    <Metadata key="PREVIEW_TIME" value="10:08:00" />

    <Scene backgroundColor="${COLOR.background}">
${body}
    </Scene>
</WatchFace>
`
}

/** Parse the actual output before either writing it or comparing it with disk. */
async function assertConditionTrees(xml, baseline = null) {
  const check = runFile('python3', [join(root, 'tools/check-watchface-structure.py'),
    ...(baseline === null ? [] : ['--n1-pair-diagnostics'])])
  const closed = new Promise((resolve) => check.child.once('close', resolve))
  // Both trees come from this invocation, so canonical regeneration remains possible.
  const input = baseline === null ? xml : `<N1DiagnosticComparison>
${baseline.slice(baseline.indexOf('<WatchFace'))}
${xml.slice(xml.indexOf('<WatchFace'))}
</N1DiagnosticComparison>`
  try {
    await Promise.all([check, pipeline([input], check.child.stdin)])
  } finally {
    await closed
  }
}

const xml = face()
const diagnosticXml = face(true)

assertLegacyCutoffs()
assertNearExhaustedArcs()
assertLowerContracts()
await assertConditionTrees(xml)
await assertConditionTrees(diagnosticXml, xml)
const outputFlag = process.argv.indexOf('--n1-pair-diagnostics-output')
if (outputFlag !== -1) {
  const path = process.argv[outputFlag + 1]
  if (!path || path.startsWith('--') || process.argv.includes('--check')) {
    throw new Error('diagnostic output requires a build-directory path and cannot use --check')
  }
  const output = resolve(path)
  const withinBuild = relative(join(root, 'apps/watchface_wff/build'), output)
  if (isAbsolute(withinBuild) || withinBuild.startsWith('..') || !withinBuild.endsWith('/raw/watchface.xml')) {
    throw new Error('diagnostic XML must be a raw/watchface.xml overlay under apps/watchface_wff/build')
  }
  await mkdir(dirname(output), { recursive: true })
  await writeFile(output, diagnosticXml)
} else {
  await emit(target, xml, 'render-watchface')

  // Textures are rasterized, not compared: ImageMagick stamps metadata that
  // differs between runs on pixel-identical output (see design-output.mjs).
  if (!process.argv.includes('--check')) {
    await writeTextures()
    console.log(`wrote ${LAYOUTS.filter(({ name }) => name !== 'Legacy').reduce((total, { count }) => total + count, 0) * TOKENS.length} ring textures to ${drawables}`)
  }
}
