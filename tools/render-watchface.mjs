#!/usr/bin/env node
/**
 * The watch face itself, not review art: writes
 * `apps/watchface_wff/src/main/res/raw/watchface.xml`
 * (geometry and language rules: `docs/product/WATCH_RING_DESIGN.md`).
 *
 * Four rings and four strips are the same block four times over, and ring type
 * multiplies the ring block again — one branch per period, so twelve copies of
 * it in an 832-line file. Hand-editing means editing one and missing eleven;
 * the next such feature multiplies the copies again, not the ideas.
 *
 * Usage: node tools/render-watchface.mjs [--check]
 *   --check  compare against the file on disk and exit non-zero on drift
 */

import { readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const target = join(root, 'apps/watchface_wff/src/main/res/raw/watchface.xml')

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
  { slotId: 106, diameter: 260, service: 'Ring4' },
]

const BAND_THICKNESS = 40

/**
 * Ring type as texture: the budget period repeated around the band.
 *
 * The glyphs are punched out in the background colour instead of being drawn in
 * the family colour, because `Font color` rejects
 * `[COMPLICATION.RANGED_VALUE_COLORS]` — the ramp is a colour list and the
 * attribute parses one ARGB. So the colour keeps coming from the arc
 * underneath, and as a bonus the melt boundary can never slice a glyph: it is
 * an edge in the arc, and the glyph is only ever a hole.
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
  /**
   * Cap height of SYNC_TO_DEVICE BOLD as a fraction of `size`, read off device
   * captures at three sizes (0.709-0.732). Not the 0.83 an early probe
   * reported — that one measured the em box, not the cap.
   */
  capRatio: 0.72,
}

/** The cap height is the design knob; `Font size` is what WFF takes. */
const TEXTURE_FONT_SIZE = Number(((TEXTURE.band * TEXTURE.capOfBand) / TEXTURE.capRatio).toFixed(1))

/**
 * Period tokens exactly as the complication writes them into TITLE, with the
 * advance of one repeat — the token plus the space after it — in ems, per ring
 * from the outside in.
 *
 * One number per token would be the honest model, and it is wrong: the same
 * glyph at the same `size` advances by a fraction of a pixel more on one ring
 * than on another, because the run is rasterized at the radius it is drawn on.
 * A fraction of a pixel times sixty repeats is degrees of arc, so each advance
 * is measured on device, from the leftover its own ring leaves at 12. Four
 * decimals for the same reason: the error multiplies by the repeat count.
 *
 * The innermost ring is unmeasured — the reference device binds only three ring
 * complications — so it borrows the innermost measurement rather than the
 * outermost, the drift being toward the centre.
 */
const TOKENS = [
  { period: 'Day', title: 'D', steps: [0.8407, 0.8371, 0.8312, 0.8312] },
  { period: 'Week', title: '7D', steps: [1.4159, 1.4136, 1.4164, 1.4164] },
  { period: 'Month', title: 'M', steps: [1.0498, 1.0518, 1.0510, 1.0510] },
]

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
  { slotId: 109, service: 'Strip4' },
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
  band and punched out in the background colour, so the arc underneath keeps the family.

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

/**
 * The circle the glyphs are centred on. `width`/`height` on `TextCircular` are
 * that centreline, not an outer edge as on `Arc` — so this is the band's
 * centreline and no baseline correction is needed.
 */
function textureCircle(diameter) {
  return Number((diameter - TEXTURE.band).toFixed(1))
}

/**
 * One period's run, as literal text plus the spacing that closes it. The branch
 * already knows its token, so nothing is substituted at runtime: TITLE only
 * chooses which branch draws.
 *
 * A whole number of repeats never measures out to a whole circle, and
 * `TextCircular` neither stretches a run nor wraps it — it centres it in the
 * sweep and leaves the remainder as one gap at 12: a seam, gaping when the
 * remainder is nearly a repeat and a collision when it is nearly none. So the
 * count is the nearest whole number of repeats, and `letterSpacing` spreads the
 * difference over every character until the run plus one word space is exactly
 * the circle — the gap at 12 then reads as one more gap between repeats.
 *
 * Only as exact as the `step` it is given, which is why `TOKENS` measures one
 * per ring: the font is the watch's own, so on a watch whose font is not the
 * reference one the fit drifts back and a ring ends a little open.
 */
function textureRun(circle, title, step) {
  const ems = (Math.PI * circle) / TEXTURE_FONT_SIZE
  const repeats = Math.round(ems / step)
  // Each repeat pays for its own glyphs and for the space that follows it.
  const spacing = (ems / repeats - step) / (title.length + 1)
  return { text: Array(repeats).fill(title).join(' '), spacing: spacing.toFixed(4) }
}

function ringTextureBranch(circle, period, { text, spacing }) {
  return `                                <Compare expression="is${period}">
                                    <PartText x="0" y="0" width="${FACE.size}" height="${FACE.size}" alpha="255">
                                        <Variant mode="AMBIENT" target="alpha" value="140" />
                                        <TextCircular
                                            centerX="${FACE.center}"
                                            centerY="${FACE.center}"
                                            width="${circle}"
                                            height="${circle}"
                                            startAngle="${SWEEP.start}"
                                            endAngle="${SWEEP.end}"
                                            direction="CLOCKWISE"
                                            align="CENTER">
                                            <Font
                                                family="SYNC_TO_DEVICE"
                                                size="${TEXTURE_FONT_SIZE}"
                                                weight="BOLD"
                                                letterSpacing="${spacing}"
                                                color="${COLOR.background}">${text}</Font>
                                        </TextCircular>
                                    </PartText>
                                </Compare>`
}

/**
 * No `Default`: a slot whose complication names no period gets no texture,
 * rather than being labelled with whichever token the fallback happened to be.
 */
function ringTexture(diameter, ring) {
  const circle = textureCircle(diameter)
  const expressions = TOKENS.map(
    ({ period, title }) =>
      `                                    <Expression name="is${period}"><![CDATA[[COMPLICATION.TITLE] == "${title}"]]></Expression>`,
  ).join('\n')
  return `                            <!-- Cut-out: the glyphs are holes, so the arc under them keeps the family colour. -->
                            <Condition>
                                <Expressions>
${expressions}
                                </Expressions>
${TOKENS.map(({ period, title, steps }) =>
  ringTextureBranch(circle, period, textureRun(circle, title, steps[ring])),
).join('\n')}
                            </Condition>`
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
                        <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="${name}">
                            <PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}">
                                <Arc
                                    centerX="${FACE.center}"
                                    centerY="${FACE.center}"
                                    width="${diameter}"
                                    height="${diameter}"
                                    startAngle="${SWEEP.start}"
                                    endAngle="${SWEEP.end}">
                                    <Stroke color="${COLOR.track}" thickness="${BAND_THICKNESS}" cap="ROUND" />
                                </Arc>
                            </PartDraw>
                            <PartDraw x="0" y="0" width="${FACE.size}" height="${FACE.size}" alpha="255">
                                <Variant mode="AMBIENT" target="alpha" value="140" />
                                <Arc
                                    centerX="${FACE.center}"
                                    centerY="${FACE.center}"
                                    width="${diameter}"
                                    height="${diameter}"
                                    startAngle="${SWEEP.start}"
                                    endAngle="${SWEEP.end}">
                                    <Transform
                                        target="startAngle"
                                        value="(1 - ([COMPLICATION.RANGED_VALUE_VALUE] / [COMPLICATION.RANGED_VALUE_MAX])) * ${SWEEP.end}" />
                                    <WeightedStroke
                                        thickness="${BAND_THICKNESS}"
                                        colors="[COMPLICATION.RANGED_VALUE_COLORS]"
                                        cap="ROUND" />
                                </Arc>
                            </PartDraw>
${ringTexture(diameter, index)}
                        </Group>
                    </Compare>
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

function face() {
  // A blank line means "a different slot starts here". The lift is the ground
  // the first ring sits on and the comment introduces the strip stack, so
  // neither is cut off from what follows it.
  const body = [
    [lift(), RINGS.map(ringSlot).join('\n\n')].join('\n'),
    clock(),
    [wordmark(), stripComment(), STRIPS.map(stripSlot).join('\n\n')].join('\n'),
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
}
