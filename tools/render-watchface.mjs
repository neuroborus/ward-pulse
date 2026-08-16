#!/usr/bin/env node
/**
 * The watch face itself, not review art: writes
 * `apps/watchface_wff/src/main/res/raw/watchface.xml` and the ring-type drawables
 * it names (geometry and language rules: `docs/product/WATCH_RING_DESIGN.md`).
 *
 * Four rings and four strips are the same block four times over, and ring type
 * multiplies the ring block again — one branch per period, one image per branch.
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
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

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
}

/**
 * Rings, outermost first. Diameters step by 48 because the band is thicker than
 * it declares: WFF paints about half the nominal `thickness`, so 40 draws close
 * to 20 units (`TEXTURE.band`) and neighbours touch at the old 18-unit pitch.
 */
const RINGS = [
  { slotId: 101, diameter: 404, service: 'Today' },
  { slotId: 102, diameter: 356, service: 'Week' },
  { slotId: 105, diameter: 308, service: 'Ring3' },
]

const BAND_THICKNESS = 40

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
 * One slot draws the outer half of whichever band is shared, because a WFF scene
 * holds at most eight `ComplicationSlot` elements and this face spends all eight
 * (`WATCH_RING_DESIGN.md`, Split band, rule 7). It takes the id the fourth ring
 * used to hold, and picks its radius from the band index the watch writes into
 * TITLE — counted from the outside, mirroring the payload order.
 */
const OUTER_HALF = { slotId: 106, service: 'RingSplit' }

/** The token a band's own slot sends when it draws only its inner half. */
const SPLIT_TOKEN = 'split'

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
   * What WFF paints of `BAND_THICKNESS` — about half, never the nominal. This
   * is the band measured off a device screenshot in `WATCH_RING_DESIGN.md`,
   * kept identical here so the texture cannot drift from the baseline.
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

const STRIPS = [
  { slotId: 104, service: 'Tokens' },
  { slotId: 107, service: 'Strip2' },
  { slotId: 108, service: 'Strip3' },
]

/**
 * The far end of a split band's strip: one slot for all three rows, the last
 * one the eight-slot budget had (`WATCH_RING_DESIGN.md`, Split band, rule 4).
 * `[COMPLICATION.RANGED_VALUE_COLORS]` is scoped to its own slot, so the second
 * colour cannot come from the strip that already carries the first; it comes
 * from here, and TITLE — the strip row, which is the payload index — says which
 * row to mark.
 */
const SPLIT_MARKER = { slotId: 109, service: 'StripSplit' }

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

  BoundingArc clips ring-slot content — strips use BoundingBox slots after clock.
  Strip TEXT = full label (\`46%\` or \`100% · 500\` on the owning family).
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
  const expressions = TOKENS.map(
    ({ period, title }) =>
      `                                    <Expression name="is${period}"><![CDATA[[COMPLICATION.TITLE] == "${title}"]]></Expression>`,
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

/**
 * Track plus melt for one arc. The melt keeps its own `PartDraw` so ambient can
 * dim it without touching the track underneath.
 *
 * The melt is drawn **inset by one cap at each end**, so what the eye sees ends
 * where the value does: the caps then fill exactly the space the inset freed.
 */
function bandArcs(diameter, thickness, pad) {
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
${pad}<PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}" alpha="255">
${pad}    <Variant mode="AMBIENT" target="alpha" value="140" />
${pad}    <Arc
${pad}        centerX="${FACE.center}"
${pad}        centerY="${FACE.center}"
${pad}        width="${diameter}"
${pad}        height="${diameter}"
${pad}        startAngle="${SWEEP.start}"
${pad}        endAngle="${(SWEEP.end - capDegrees(diameter, thickness)).toFixed(2)}">
${pad}        <Transform
${pad}            target="startAngle"
${pad}            value="clamp((1 - ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX])) * ${SWEEP.end} + ${capDegrees(diameter, thickness)}, ${SWEEP.start}, ${(SWEEP.end - capDegrees(diameter, thickness)).toFixed(2)})" />
${pad}        <WeightedStroke
${pad}            thickness="${thickness}"
${pad}            colors="[COMPLICATION.RANGED_VALUE_COLORS]"
${pad}            cap="ROUND" />
${pad}    </Arc>
${pad}</PartDraw>`
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
            <BoundingArc
                centerX="${FACE.center}"
                centerY="${FACE.center}"
                width="${diameter}"
                height="${diameter}"
                thickness="${BAND_THICKNESS}"
                startAngle="${SWEEP.start}"
                endAngle="${SWEEP.end}"
                isRoundEdge="TRUE" />
            <Complication type="RANGED_VALUE">
                <Condition>
                    <Expressions>
                        <Expression name="hasRing">
                            <![CDATA[[COMPLICATION.RANGED_VALUE_VALUE] > 0]]>
                        </Expression>
                    </Expressions>
                    <Compare expression="hasRing">
                        <!-- Shared band: this slot keeps the inner half, the outer one
                             comes from the slot that serves every band. -->
                        <Condition>
                            <Expressions>
                                <Expression name="isSplit"><![CDATA[[COMPLICATION.TITLE] == "${SPLIT_TOKEN}"]]></Expression>
                            </Expressions>
                            <Compare expression="isSplit">
                                <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="${name}Half">
${bandArcs(diameter - INNER_HALF_INSET, HALF_THICKNESS, ' '.repeat(36))}
                                </Group>
                            </Compare>
                            <Default>
                                <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="${name}">
${bandArcs(diameter, BAND_THICKNESS, ' '.repeat(36))}${ringTexture(diameter, index)}
                                </Group>
                            </Default>
                        </Condition>
                    </Compare>
                </Condition>
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

/**
 * The outer half of whichever band is shared. One slot, three radii: the watch
 * writes the band index — counted from the outside — into TITLE, and the branch
 * below turns it into a radius. `NoData` while no band is shared, which is the
 * usual state, and then this slot draws nothing at all.
 *
 * Its `BoundingArc` has to reach every band it may draw on, so it spans from the
 * outermost half down to the innermost one rather than hugging a single band.
 * A `BoundingArc` takes its **outer edge** in `width` — unlike the arcs inside a
 * slot, which take twice their centre line. Measured 2026-08-16: with `width`
 * set to twice the centre the clip cut the outermost half in half.
 */
function outerHalfSlot() {
  const centres = RINGS.map(({ diameter }) => (diameter - OUTER_HALF_INSET) / 2)
  const clipOuter = Math.max(...centres) + HALF_THICKNESS
  const clipInner = Math.min(...centres) - HALF_THICKNESS
  const branches = RINGS.map(
    ({ diameter }, index) => `                    <Compare expression="isBand${index}">
                        <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="outerHalf${index + 1}">
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
            slotId="${OUTER_HALF.slotId}"
            displayName="@string/outer_half_complication"
            supportedTypes="RANGED_VALUE EMPTY"
            isCustomizable="FALSE">
            <DefaultProviderPolicy
                primaryProvider="${provider(OUTER_HALF.service)}"
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

function stripComment() {
  const rows = STRIPS.map((_, index) => STRIP.top + index * STRIP.pitch).join('/')
  return `        <!-- Equal-width strips (${STRIP.width}) at x=${STRIP.x}; y=${rows} — kept inside the
             inner ring aperture after the 2026-08-02 band widening.
             Sized for "100% · 10.0M". RANGED_VALUE + ColorRamp accents match ring families. -->`
}

function stripSlot({ slotId, service }, index) {
  const y = STRIP.top + index * STRIP.pitch
  const { width, height, radius, textInset, textWidth, fontSize } = STRIP
  return `        <ComplicationSlot
            x="${STRIP.x}"
            y="${y}"
            width="${width}"
            height="${height}"
            slotId="${slotId}"
            displayName="@string/strip${index + 1}_complication"
            supportedTypes="RANGED_VALUE EMPTY"
            isCustomizable="FALSE">
            <DefaultProviderPolicy
                primaryProvider="${provider(service)}"
                primaryProviderType="RANGED_VALUE"
                defaultSystemProvider="EMPTY"
                defaultSystemProviderType="EMPTY" />
            <BoundingBox x="0" y="0" width="${width}" height="${height}" />
            <Complication type="RANGED_VALUE">
                <Group x="0" y="0" width="${width}" height="${height}" name="ring${
                  index + 1
                }_strip" alpha="255">
                    <Variant mode="AMBIENT" target="alpha" value="0" />
                    <PartDraw x="0" y="0" width="${width}" height="${height}">
                        <RoundRectangle x="0" y="0" width="${width}" height="${height}" cornerRadiusX="${radius}" cornerRadiusY="${radius}">
                            <Fill color="${COLOR.strip}" />
                        </RoundRectangle>
                        <!-- Family accent from ColorRamp (same path as matching ring). -->
                        <Arc
                            centerX="1.5"
                            centerY="${height / 2}"
                            width="3"
                            height="14"
                            startAngle="${SWEEP.start}"
                            endAngle="${SWEEP.end}">
                            <WeightedStroke
                                thickness="3"
                                colors="[COMPLICATION.RANGED_VALUE_COLORS]"
                                cap="BUTT" />
                        </Arc>
                    </PartDraw>
                    <PartText x="${textInset}" y="0" width="${textWidth}" height="${height}">
                        <Text align="CENTER" ellipsis="TRUE">
                            <Font family="SYNC_TO_DEVICE" size="${fontSize}" weight="BOLD" color="${
                              COLOR.text
                            }">
                                <Template>%s
                                    <Parameter expression="[COMPLICATION.TEXT]" />
                                </Template>
                            </Font>
                        </Text>
                    </PartText>
                </Group>
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

/** Mirrors the accent on the left of a strip, at the right edge of one row. */
function splitMarkerSlot() {
  const { width, height, pitch } = STRIP
  const rows = STRIPS.length
  const branches = STRIPS.map(
    (_, index) => `                    <Compare expression="isRow${index}">
                        <PartDraw x="0" y="${index * pitch}" width="${width}" height="${height}">
                            <Arc
                                centerX="${width - 1.5}"
                                centerY="${height / 2}"
                                width="3"
                                height="14"
                                startAngle="${SWEEP.start}"
                                endAngle="${SWEEP.end}">
                                <WeightedStroke
                                    thickness="3"
                                    colors="[COMPLICATION.RANGED_VALUE_COLORS]"
                                    cap="BUTT" />
                            </Arc>
                        </PartDraw>
                    </Compare>`,
  ).join('\n')
  const expressions = STRIPS.map(
    (_, index) =>
      `                        <Expression name="isRow${index}"><![CDATA[[COMPLICATION.TITLE] == "${index}"]]></Expression>`,
  ).join('\n')
  return `        <ComplicationSlot
            x="${STRIP.x}"
            y="${STRIP.top}"
            width="${width}"
            height="${(rows - 1) * pitch + height}"
            slotId="${SPLIT_MARKER.slotId}"
            displayName="@string/split_marker_complication"
            supportedTypes="RANGED_VALUE EMPTY"
            isCustomizable="FALSE">
            <DefaultProviderPolicy
                primaryProvider="${provider(SPLIT_MARKER.service)}"
                primaryProviderType="RANGED_VALUE"
                defaultSystemProvider="EMPTY"
                defaultSystemProviderType="EMPTY" />
            <BoundingBox x="0" y="0" width="${width}" height="${(rows - 1) * pitch + height}" />
            <Complication type="RANGED_VALUE">
                <Group x="0" y="0" width="${width}" height="${(rows - 1) * pitch + height}" name="split_marker" alpha="255">
                    <Variant mode="AMBIENT" target="alpha" value="0" />
                    <Condition>
                        <Expressions>
${expressions}
                        </Expressions>
${branches}
                    </Condition>
                </Group>
            </Complication>
            <Complication type="EMPTY" />
        </ComplicationSlot>`
}

function face() {
  // A blank line means "a different slot starts here". The lift is the ground
  // the first ring sits on and the comment introduces the strip stack, so
  // neither is cut off from what follows it.
  const body = [
    [lift(), RINGS.map(ringSlot).join('\n\n'), outerHalfSlot()].join('\n\n'),
    clock(),
    [
      wordmark(),
      stripComment(),
      STRIPS.map(stripSlot).join('\n\n'),
      splitMarkerSlot(),
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

if (process.argv.includes('--check')) {
  const current = await readFile(target, 'utf8')
  if (current !== xml) {
    console.error(
      `${target} differs from the generator; run \`just render-watchface\` and review the diff`,
    )
    process.exit(1)
  }
  console.log(`${target} is up to date`)
} else {
  await writeFile(target, xml)
  console.log(`wrote ${target}`)
  await writeTextures()
  console.log(`wrote ${TEXTURE_RINGS * TOKENS.length} ring textures to ${drawables}`)
}
