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
 *
 * `--check` covers the XML only: the images are what a rasterizer made of it, and
 * comparing bytes would fail on a different ImageMagick rather than on a real
 * drift. A missing one still stops the build — the face names each by resource.
 */

import { execFileSync } from 'node:child_process'
import { access, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { emit } from './design-output.mjs'

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
 * `359.9` rather than a closed circle — at 360 the ROUND tip collapses.
 */
const SWEEP = { start: 0, end: 359.9 }

const COLOR = {
  background: '#ff0a0d0b',
  track: '#ff2e3632',
  strip: '#eb0b0e0c',
  text: '#fff4fbf8',
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
   * The hairline a cell draws while it is showing something. The face's own
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

/**
 * An arc inside a slot takes **twice its centre line** in `width`, so a band
 * whose outer edge is `diameter / 2` is drawn one half-thickness further in.
 */
function bandCentre(diameter) {
  return diameter - BAND_THICKNESS
}

/**
 * Halves of a shared band, measured on the watch 2026-08-13
 * (`WATCH_RING_DESIGN.md`, Ring geometry): centre lines at `outer - 5` and
 * `outer - 15`, both at thickness 10, and inside a slot `width` is **twice the
 * centre line**. A band's `diameter` here is twice its outer edge, so the two
 * halves are `diameter - 10` and `diameter - 30`.
 */
const HALF_THICKNESS = 10
const OUTER_HALF_INSET = 10
const INNER_HALF_INSET = 30

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
 * band's centreline leaves the cap centred on it. One number for every ring —
 * what changes between them is the square, not where the type sits in the band.
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
 * Strips, one per ring, stacked below the wordmark. Measured off the face, not
 * sized to content: 88x18 boxes stepping 21 from y=283, wide enough for
 * "100% · 10.0M" and kept inside the inner ring aperture.
 */
const STRIP = {
  x: 181,
  top: 283,
  pitch: 21,
  width: 88,
  height: 18,
  radius: 6,
  textInset: 6,
  // Its own measured value, not `width - 2 * textInset`: the label box is
  // pulled off the accent bar on the left and runs closer to the right edge.
  textWidth: 78,
  fontSize: 12,
}

/**
 * The wordmark, centred between the clock and the strip stack. Both boxes are
 * square because the asset is — WFF stretches the image to fill its box, and
 * the earlier 66x55 / 54x45 boxes flattened the mark by 17%. The PNG carries
 * its own padding, so the ink lands at 243-268: clear of the clock, which ends
 * at 229, and of the strips, which start at 283.
 */
const WORDMARK = { centerX: FACE.center, centerY: 260, size: 66, ambientSize: 54 }

/**
 * Which row of the stack a ring's own slot paints, counted from the top.
 *
 * The stack anchors to its **bottom** row, so the outermost ring — which binds
 * the loosest payload when several are active — takes the lowest row, and the
 * innermost takes the highest. Arc slots fill from the outside, so the occupied
 * rows are always contiguous and always end at y=325, whatever the ring count
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
 * The three cells above the clock, on a circle concentric with the face rather
 * than in a row: a constant radius against a band that is itself a circle keeps
 * the clearance equal by construction, with nothing left to tune. Origins are
 * the integers `WATCH_RING_DESIGN.md` rule 1 locks — WFF rejects a fractional
 * coordinate outright — and the middle cell is the highest because it is the
 * one on the vertical axis.
 */
const CELL = {
  size: 42,
  /** The 18-unit line box the strips use, centred by `(42 - 18) / 2`. */
  textY: 12,
  /**
   * Inset to where the well still admits that box's full height: a circle of
   * radius 21 is `sqrt(441 - 81)` = 18.97 wide at 9 units off its midline. The
   * exact inset is 2.5 and the grid is integral, so the box sits half a unit
   * left of the cell's own centre.
   */
  textX: 2,
  textWidth: 37,
  fontSize: 14,
  /**
   * Half the diameter, so an icon leaves the rim of a round recess clear. It
   * cannot sit exactly centred for the same reason the line box cannot: 21 in
   * 42 leaves 10.5 a side and the grid is integral.
   */
  iconSize: 21,
  /**
   * The hairline that says a cell is holding something. A stroke of 1 centred
   * on a path of 41 runs from radius 20.0 to 21.0, so it is inscribed in the
   * well whose own edge is at 21: the ring covers the well's outermost half
   * unit and no part of it falls outside onto the lift. Corrected 2026-10-11 —
   * this read "20.25 to 20.75, a quarter of a unit inside", which is the span
   * of a half-unit stroke; the geometry never moved.
   */
  ringDiameter: 41,
  ringThickness: 1,
  /**
   * The ring dims in ambient with everything else a cell carries. Rule 12 keeps
   * the well because a well darkens, and switching a darkening off would raise
   * the luminance; a ring lights, so the same reasoning dims it rather than
   * leaving the brightest thing on an ambient face around a cell's edge. The
   * proportion is the arcs' own, 255 to 140.
   */
  ringAmbientAlpha: 140,
}

/**
 * A trailing mark is not part of the number. Centring the whole string puts the
 * string on the cell's axis and drags the digits left by half the mark's
 * advance, measured at 2 units for the degree sign, so the box moves back by
 * that much and the digits land centred whatever their count.
 */
const CELL_MARK_SHIFT = 2

const CELLS = [
  { slotId: 201, x: 152, y: 111, label: 'cell1', provider: 'DAY_OF_WEEK', type: 'SHORT_TEXT' },
  { slotId: 202, x: 204, y: 97, label: 'cell2', provider: 'EMPTY', type: 'EMPTY' },
  { slotId: 203, x: 256, y: 111, label: 'cell3', provider: 'EMPTY', type: 'EMPTY' },
]

/**
 * What the face draws under a cell when the wearer has not filled it. WFF reads
 * weather from a built-in source in an expression, so the default costs no
 * complication slot; a filled cell's opaque well simply covers it. Nothing is
 * declared under the left cell, so its recess is bare whenever it is cleared.
 */
const CELL_CHROME = [
  { expression: null, shift: 0 },
  { expression: '[WEATHER.TEMPERATURE]', shift: CELL_MARK_SHIFT },
  { expression: '[WEATHER.UV_INDEX]', shift: 0 },
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

/** Every spelling of `split`: bare, or carrying one of the pool tokens. */
const SPLIT_TITLES = [
  SPLIT_TOKEN,
  ...SPLIT_POOLS.map(({ token }) => `${SPLIT_TOKEN}${TOKEN_SEPARATOR}${token}`),
]

/** Every slot names a service in the Wear app; nothing else may fill them. */
function provider(service) {
  return `app.wardpulse/app.wardpulse.wear.complication.${service}ComplicationDataSourceService`
}

const HEADER = `<?xml version="1.0" encoding="utf-8"?>
<!--
  Concentric remaining arcs + sunk % / credits strips
  (docs/product/WATCH_RING_DESIGN.md, baseline 2026-07-25).

  Visual target: apps/wear_android/design/round-*-plan*.svg
  — radial lift background, 40-unit ring stroke (WFF paints about half of it), equal-width
  sunk strips (88, rx=6) sized for "100% · 10.0M". Strip slots are RANGED_VALUE so accents
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
  so usage opens clockwise from 12 and remaining ends at 12.
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
             circle of radius 106.8 about the face centre. The middle and right cells
             carry the default weather, which costs no complication slot. -->`
}

function cellComment() {
  return `        <!-- Three cells the wearer fills, above the clock. The system owns what goes
             in them; this face owns only the declaration and how it is drawn.
             (docs/product/WATCH_RING_DESIGN.md, Upper cells, revision 2026-10-09) -->`
}

/** A cell's text, in the face's own label voice — the provider gets no say. */
function cellText(parameter, shift, pad) {
  return `${pad}<PartText x="${CELL.textX + shift}" y="${CELL.textY}" width="${CELL.textWidth}" height="18" alpha="255">
${pad}    <Variant mode="AMBIENT" target="alpha" value="140" />
${pad}    <Text align="CENTER" ellipsis="TRUE">
${pad}        <Font family="SYNC_TO_DEVICE" size="${CELL.fontSize}" weight="BOLD" color="${COLOR.text}">
${pad}            <Template>%s
${pad}                <Parameter expression="${parameter}" />
${pad}            </Template>
${pad}        </Font>
${pad}    </Text>
${pad}</PartText>`
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
 * The hairline a cell wears while it is showing something, whether that is the
 * wearer's complication or the face's own weather reading. Without it a filled
 * cell is a dark disc on a dark field and only the glyphs read, so the cell
 * itself goes unseen. An empty cell does not wear one: its recess already says
 * what it is, and the two together make the language exact — ring means
 * occupied, recess means free.
 */
function cellRing(pad) {
  const centre = CELL.size / 2
  return `${pad}<PartDraw x="0" y="0" width="${CELL.size}" height="${CELL.size}" alpha="255">
${pad}    <Variant mode="AMBIENT" target="alpha" value="${CELL.ringAmbientAlpha}" />
${pad}    <Arc
${pad}        centerX="${centre}"
${pad}        centerY="${centre}"
${pad}        width="${CELL.ringDiameter}"
${pad}        height="${CELL.ringDiameter}"
${pad}        startAngle="${SWEEP.start}"
${pad}        endAngle="${SWEEP.end}">
${pad}        <Stroke thickness="${CELL.ringThickness}" color="${COLOR.cellRing}" cap="BUTT" />
${pad}    </Arc>
${pad}</PartDraw>`
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
  const { expression, shift } = CELL_CHROME[index]
  const pad = ' '.repeat(12)
  const body = expression
    ? `            <Condition>
                <Expressions>
                    <Expression name="hasWeather"><![CDATA[[WEATHER.IS_AVAILABLE]]]></Expression>
                </Expressions>
                <Compare expression="hasWeather">
                    <Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${label}Reading">
${cellWellFlat(COLOR.strip, ' '.repeat(24))}
${cellRing(' '.repeat(24))}
${cellText(expression, shift, ' '.repeat(24))}
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
 * from under the complication, with two values in the same 42 units.
 */
function cellSlot({ slotId, x, y, label, provider: systemProvider, type }) {
  const pad = ' '.repeat(20)
  const well = `${cellWellFlat(COLOR.cellWell, pad)}
${cellRing(pad)}`
  const body = (parameter) => `            <Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${label}">
${well}
${cellText(parameter, 0, pad)}
            </Group>`
  // 21 in 42 leaves 10.5 a side and the grid is integral, so the icon sits half
  // a unit in from centre — the same rounding, in the same direction, that
  // rule 7 records for the line box.
  const inset = Math.floor((CELL.size - CELL.iconSize) / 2)
  // The tint goes on a group of its own, not on the slot: tinting the slot
  // would take the well with it. It is the text colour rather than a family
  // colour — on this face a family colour means *this ring's provider*, and a
  // cell is not a ring — so an icon reads as face text rather than as a
  // foreign mark.
  const icon = `            <Group x="0" y="0" width="${CELL.size}" height="${CELL.size}" name="${label}Icon">
${well}
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
${body('[COMPLICATION.TEXT]')}
            </Complication>
            <Complication type="RANGED_VALUE">
${body('[COMPLICATION.TEXT]')}
            </Complication>
            <Complication type="MONOCHROMATIC_IMAGE">
${icon}
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

/** The drawable a ring's period is baked into, and the name WFF resolves it by. */
function textureResource(index, period) {
  return `ring${index + 1}_type_${period.toLowerCase()}`
}

/**
 * A ring's type as an SVG, in that ring's own design units. Tokens are placed one
 * by one, each rotated onto its share of the sweep, so the spacing is uniform by
 * construction — which is the whole reason the type is baked rather than set.
 */
function textureImage(diameter, title, repeats) {
  const centre = diameter / 2
  const pitch = 360 / TEXTURE.sweeps
  const slot = (pitch - TEXTURE.sweepGap) / repeats
  // Half a sweep off 12, so the breaks fall on the diagonals: 12 is where both
  // ends of the melt live, and a break there frames the round cap instead of
  // letting the type close over it.
  const origin = pitch / 2 + TEXTURE.sweepGap / 2
  const tokens = Array.from({ length: TEXTURE.sweeps }, (_, sweep) =>
    Array.from({ length: repeats }, (_, repeat) => {
      const angle = (origin + sweep * pitch + (repeat + 0.5) * slot).toFixed(2)
      return `<text x="${centre}" y="${TEXTURE_BASELINE}" transform="rotate(${angle} ${centre} ${centre})">${title}</text>`
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
 * every run rewrites nine committed binaries whose pixels did not change.
 */
function rasterize(file, png) {
  execFileSync('convert', ['-background', 'none', '-density', '96', '-strip', file, `png32:${png}`])
}

/** One drawable per ring and period: what the face draws instead of setting type. */
async function writeTextures() {
  await access(FONT_FILE).catch(() => {
    throw new Error(`${FONT_FILE} is missing; ring type would bake in a substituted font`)
  })
  await mkdir(drawables, { recursive: true })
  const scratch = await mkdtemp(join(tmpdir(), 'wardpulse-type-'))
  try {
    for (const [index, { diameter }] of RINGS.slice(0, TEXTURE_RINGS).entries()) {
      for (const { period, title, repeats } of TOKENS) {
        const name = textureResource(index, period)
        const svg = join(scratch, `${name}.svg`)
        await writeFile(svg, textureImage(diameter, title, repeats[index]))
        rasterize(svg, join(drawables, `${name}.png`))
      }
    }
  } finally {
    await rm(scratch, { recursive: true, force: true })
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
function ringTextureBranch(diameter, index, period) {
  const inset = Number(((FACE.size - diameter) / 2).toFixed(1))
  return `                                <Compare expression="is${period}">
                                    <PartImage x="${inset}" y="${inset}" width="${diameter}" height="${diameter}" alpha="${TEXTURE_ALPHA}">
                                        <Variant mode="AMBIENT" target="alpha" value="${TEXTURE_ALPHA_AMBIENT}" />
                                        <Image resource="${textureResource(index, period)}" />
                                    </PartImage>
                                </Compare>`
}

/**
 * No `Default`: a slot whose complication names no period gets no texture,
 * rather than being labelled with whichever token the fallback happened to be.
 * A ring past the cap gets none either — there is no image baked for it.
 */
function ringTexture(diameter, index) {
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
${TOKENS.map(({ period }) => ringTextureBranch(diameter, index, period)).join('\n')}
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
  return {
    cap,
    twoCapCutoff: (2 * cap) / SWEEP.end,
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

function assertNearExhaustedArcs() {
  const epsilon = 0.000001
  const tolerance = 0.000000001
  for (const { diameter } of RINGS) {
    const centre = bandCentre(diameter)
    const geometry = meltGeometry(centre, BAND_THICKNESS)
    const belowRemaining = geometry.twoCapCutoff - epsilon
    const below = meltAngles(centre, BAND_THICKNESS, belowRemaining)
    const expectedBelowSweep = belowRemaining * SWEEP.end
    if (
      !below.nearEmpty ||
      below.strokeCap !== 'BUTT' ||
      below.end <= below.start ||
      Math.abs(visibleSweep(below, geometry.cap) - expectedBelowSweep) > tolerance
    ) {
      throw new Error(
        `ring ${diameter}: a remainder below the two-cap cutoff must stay visible and proportional`,
      )
    }

    const aboveRemaining = geometry.twoCapCutoff + epsilon
    const above = meltAngles(centre, BAND_THICKNESS, aboveRemaining)
    const expectedStart = (1 - aboveRemaining) * SWEEP.end + geometry.cap
    if (
      above.nearEmpty ||
      above.strokeCap !== 'ROUND' ||
      above.start !== expectedStart ||
      above.end !== geometry.insetEnd ||
      Math.abs(visibleSweep(above, geometry.cap) - aboveRemaining * SWEEP.end) > tolerance
    ) {
      throw new Error(`ring ${diameter}: geometry above the two-cap cutoff must stay inset`)
    }

    const buttAtCutoff = meltBranchAngles(geometry, geometry.twoCapCutoff, true)
    const roundAtCutoff = meltBranchAngles(geometry, geometry.twoCapCutoff, false)
    const cutoffSweep = geometry.twoCapCutoff * SWEEP.end
    if (
      Math.abs(visibleSweep(buttAtCutoff, geometry.cap) - cutoffSweep) > tolerance ||
      Math.abs(visibleSweep(roundAtCutoff, geometry.cap) - cutoffSweep) > tolerance
    ) {
      throw new Error(`ring ${diameter}: melt branches must meet at the two-cap cutoff`)
    }

    const markup = bandArcs(centre, BAND_THICKNESS, '')
    const rawStart = `(1 - ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX])) * ${SWEEP.end}`
    const caps = [...markup.matchAll(/cap="(ROUND|BUTT)"/g)].map((match) => match[1])
    if (
      !markup.includes(`<= ${geometry.twoCapCutoff.toFixed(6)}`) ||
      !markup.includes('<Compare expression="isNearEmpty">') ||
      !markup.includes(`value="${rawStart}"`) ||
      !markup.includes(`* ${SWEEP.end} + ${geometry.cap}`) ||
      caps.join(',') !== 'ROUND,ROUND,BUTT,ROUND'
    ) {
      throw new Error(
        `ring ${diameter}: generated markup does not preserve both melt branches`,
      )
    }
  }
}

/**
 * Track plus melt for one arc. The melt keeps its own `PartDraw` so ambient can
 * dim it without touching the track underneath.
 *
 * Above the cutoff, the melt is inset by one cap at each end, so the round caps
 * fill exactly the space the inset freed. At or below it, straight ends keep the
 * visible sweep equal to the proportional centreline.
 */
function bandArcs(diameter, thickness, pad) {
  const geometry = meltGeometry(diameter, thickness)
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
${pad}</PartDraw>
${pad}<Condition>
${pad}    <Expressions>
${pad}        <Expression name="isFull"><![CDATA[[COMPLICATION.RANGED_VALUE_VALUE] >= [COMPLICATION.RANGED_VALUE_MAX]]]></Expression>
${pad}        <Expression name="isNearEmpty"><![CDATA[([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX]) <= ${geometry.twoCapCutoff.toFixed(6)}]]></Expression>
${pad}    </Expressions>
${pad}    <!-- Nothing spent yet: there is no melt to inset, and the inset would
${pad}         leave a seam at 12 on a ring that has spent nothing. Drawn without
${pad}         the transform so the two round caps close over each other. -->
${pad}    <Compare expression="isFull">
${pad}        <PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}" alpha="255">
${pad}            <Variant mode="AMBIENT" target="alpha" value="140" />
${pad}            <Arc
${pad}                centerX="${FACE.center}"
${pad}                centerY="${FACE.center}"
${pad}                width="${diameter}"
${pad}                height="${diameter}"
${pad}                startAngle="${SWEEP.start}"
${pad}                endAngle="${geometry.insetEnd.toFixed(2)}">
${pad}                <WeightedStroke
${pad}                    thickness="${thickness}"
${pad}                    colors="[COMPLICATION.RANGED_VALUE_COLORS]"
${pad}                    cap="ROUND" />
${pad}            </Arc>
${pad}        </PartDraw>
${pad}    </Compare>
${pad}    <!-- The two-cap inset cannot represent a smaller positive remainder:
${pad}         its sweep would be zero or negative. Keep the proportional
${pad}         centreline without either inset and use straight ends so the
${pad}         visible sweep does not overstate the remainder. -->
${pad}    <Compare expression="isNearEmpty">
${pad}        <PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}" alpha="255">
${pad}            <Variant mode="AMBIENT" target="alpha" value="140" />
${pad}            <Arc
${pad}                centerX="${FACE.center}"
${pad}                centerY="${FACE.center}"
${pad}                width="${diameter}"
${pad}                height="${diameter}"
${pad}                startAngle="${SWEEP.start}"
${pad}                endAngle="${SWEEP.end}">
${pad}                <Transform
${pad}                    target="startAngle"
${pad}                    value="(1 - ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX])) * ${SWEEP.end}" />
${pad}                <WeightedStroke
${pad}                    thickness="${thickness}"
${pad}                    colors="[COMPLICATION.RANGED_VALUE_COLORS]"
${pad}                    cap="BUTT" />
${pad}            </Arc>
${pad}        </PartDraw>
${pad}    </Compare>
${pad}    <Default>
${pad}        <PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}" alpha="255">
${pad}            <Variant mode="AMBIENT" target="alpha" value="140" />
${pad}            <Arc
${pad}                centerX="${FACE.center}"
${pad}                centerY="${FACE.center}"
${pad}                width="${diameter}"
${pad}                height="${diameter}"
${pad}                startAngle="${SWEEP.start}"
${pad}                endAngle="${geometry.insetEnd.toFixed(2)}">
${pad}                <Transform
${pad}                    target="startAngle"
${pad}                    value="clamp((1 - ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX])) * ${SWEEP.end} + ${geometry.cap}, ${SWEEP.start}, ${geometry.insetEnd.toFixed(2)})" />
${pad}                <WeightedStroke
${pad}                    thickness="${thickness}"
${pad}                    colors="[COMPLICATION.RANGED_VALUE_COLORS]"
${pad}                    cap="ROUND" />
${pad}            </Arc>
${pad}        </PartDraw>
${pad}    </Default>
${pad}</Condition>`
}

function ringSlot({ slotId, diameter, service }, index) {
  const name = `ring${index + 1}`
  return `        <ComplicationSlot
            x="0"
            y="0"
            width="${FACE.size}"
            height="${FACE.size}"
            slotId="${slotId}"
            displayName="@string/${name}_complication"
            supportedTypes="RANGED_VALUE EMPTY"
            isCustomizable="FALSE">
            <DefaultProviderPolicy
                primaryProvider="${provider(service)}"
                primaryProviderType="RANGED_VALUE"
                defaultSystemProvider="EMPTY"
                defaultSystemProviderType="EMPTY" />
            <BoundingBox x="0" y="0" width="${FACE.size}" height="${FACE.size}" />
            <Complication type="RANGED_VALUE">
                <!-- The band, unless this is the lone credits row: that one has a
                     reading but no ring behind it, so it draws its strip only. -->
                <Condition>
                    <Expressions>
                        <Expression name="hasBand">
                            <![CDATA[[COMPLICATION.RANGED_VALUE_VALUE] > 0 && !(${titleEquals(CREDITS_TOKEN)})]]>
                        </Expression>
                    </Expressions>
                    <Compare expression="hasBand">
                        <!-- Shared band: this slot keeps the inner half, the outer one
                             comes from the slot that serves every band. -->
                        <Condition>
                            <Expressions>
                                <Expression name="isSplit"><![CDATA[${titleEquals(...SPLIT_TITLES)}]]></Expression>
                            </Expressions>
                            <Compare expression="isSplit">
                                <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="${name}Half">
${bandArcs(diameter - INNER_HALF_INSET, HALF_THICKNESS, ' '.repeat(36))}
                                </Group>
                            </Compare>
                            <Default>
                                <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="${name}">
${bandArcs(bandCentre(diameter), BAND_THICKNESS, ' '.repeat(36))}${ringTexture(diameter, index)}
                                </Group>
                            </Default>
                        </Condition>
                    </Compare>
                </Condition>
                <!-- The legend row this ring owns. Its own slot since 2026-10-09:
                     the three the strips held are the three the cells took. -->
${stripRow(index, ' '.repeat(16))}
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

/**
 * One selected split ordinal, three possible radii: the watch
 * writes the band index — counted from the outside — into TITLE, and the branch
 * below turns it into a radius. A missing split ordinal yields `NoData`, so
 * that slot draws nothing.
 *
 * Its `BoundingArc` has to reach every band it may draw on, so it spans from the
 * outermost half down to the innermost one rather than hugging a single band.
 * A `BoundingArc` takes its **outer edge** in `width` — unlike the arcs inside a
 * slot, which take twice their centre line. Measured 2026-08-16: with `width`
 * set to twice the centre the clip cut the outermost half in half.
 */
function outerHalfSlot({ slotId, service, label }) {
  const centres = RINGS.map(({ diameter }) => (diameter - OUTER_HALF_INSET) / 2)
  const clipOuter = Math.max(...centres) + HALF_THICKNESS
  const clipInner = Math.min(...centres) - HALF_THICKNESS
  const branches = RINGS.map(
    ({ diameter }, index) => `                    <Compare expression="isBand${index}">
                        <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="outerHalf${slotId}_${index + 1}">
${bandArcs(diameter - OUTER_HALF_INSET, HALF_THICKNESS, ' '.repeat(28))}
                        </Group>
                    </Compare>`,
  ).join('\n')
  const expressions = RINGS.map(
    (_, index) =>
      `                        <Expression name="isBand${index}"><![CDATA[[COMPLICATION.TITLE] == "${index}"]]></Expression>`,
  ).join('\n')
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
            <Complication type="RANGED_VALUE">
                <Condition>
                    <Expressions>
${expressions}
                    </Expressions>
${branches}
                </Condition>
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

/** Two clocks, not one: the ambient copy is thinner and swaps in by alpha. */
function clock() {
  return `        <DigitalClock x="0" y="0" width="${FACE.size}" height="${FACE.size}">
            <TimeText
                x="0"
                y="160"
                width="${FACE.size}"
                height="90"
                alpha="255"
                align="CENTER"
                format="hh:mm"
                hourFormat="SYNC_TO_DEVICE">
                <Variant mode="AMBIENT" target="alpha" value="0" />
                <Font
                    family="SYNC_TO_DEVICE"
                    size="70"
                    weight="BOLD"
                    slant="NORMAL"
                    color="${COLOR.text}" />
            </TimeText>
            <TimeText
                x="0"
                y="160"
                width="${FACE.size}"
                height="90"
                alpha="0"
                align="CENTER"
                format="hh:mm"
                hourFormat="SYNC_TO_DEVICE">
                <Variant mode="AMBIENT" target="alpha" value="255" />
                <Font
                    family="SYNC_TO_DEVICE"
                    size="81"
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
            <!-- The asset is padded: the box runs to 293, the ink stops at 268. -->
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
  const { x, width, height, radius, textInset, textWidth, fontSize } = STRIP
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
${pad}    <PartText x="${textInset}" y="0" width="${textWidth}" height="${height}">
${pad}        <Text align="CENTER" ellipsis="TRUE">
${pad}            <Font family="SYNC_TO_DEVICE" size="${fontSize}" weight="BOLD" color="${COLOR.text}">
${pad}                <Template>%s
${pad}                    <Parameter expression="[COMPLICATION.TEXT]" />
${pad}                </Template>
${pad}            </Font>
${pad}        </Text>
${pad}    </PartText>
${pad}</Group>`
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
        `${SPLIT_TOKEN}${TOKEN_SEPARATOR}${token}`,
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

function face() {
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
      OUTER_HALVES.map(outerHalfSlot).join('\n\n'),
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

const xml = face()

assertNearExhaustedArcs()
await emit(target, xml, 'render-watchface')

// Textures are rasterized, not compared: ImageMagick stamps metadata that
// differs between runs on pixel-identical output (see design-output.mjs).
if (!process.argv.includes('--check')) {
  await writeTextures()
  console.log(`wrote ${TEXTURE_RINGS * TOKENS.length} ring textures to ${drawables}`)
}
