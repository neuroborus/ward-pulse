#!/usr/bin/env node
/**
 * The watch face itself, not review art: writes
 * `apps/watchface_wff/src/main/res/raw/watchface.xml`
 * (geometry and language rules: `docs/product/WATCH_RING_DESIGN.md`).
 *
 * Four rings and four strips are the same block four times over — 557 lines of
 * which about 460 are copies. Hand-editing them means editing one and missing
 * three, and every planned change (ring-type lettering, a boundary fade) adds
 * bands per ring, multiplying the copies rather than the ideas.
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
 * it declares: WFF paints roughly 0.44 of the nominal `thickness`, so 40 draws
 * about 18 units and neighbours touch at the old 18-unit pitch.
 */
const RINGS = [
  { slotId: 101, diameter: 404, service: 'Today' },
  { slotId: 102, diameter: 356, service: 'Week' },
  { slotId: 105, diameter: 308, service: 'Ring3' },
  { slotId: 106, diameter: 260, service: 'Ring4' },
]

const BAND_THICKNESS = 40

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
  — radial lift background, ~25px ring stroke (~+30% again), equal-width sunk strips (96, rx=6)
  sized for "100% · 10.0M". Strip slots are RANGED_VALUE so accents use the same
  ColorRamp as arcs ([COMPLICATION.RANGED_VALUE_COLORS]).

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
  return `        <Group x="0" y="0" width="${FACE.size}" height="${FACE.size}" name="wardpulse">
            <Launch target="app.wardpulse/app.wardpulse.wear.MainActivity" />
            <!-- Between time and strips; keep bottom edge above strip stack (y=291). -->
            <PartImage x="192" y="237" width="66" height="55" alpha="95">
                <Variant mode="AMBIENT" target="alpha" value="0" />
                <Image resource="wardpulse_mono" />
            </PartImage>
            <PartImage x="198" y="242" width="54" height="45" alpha="0">
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
