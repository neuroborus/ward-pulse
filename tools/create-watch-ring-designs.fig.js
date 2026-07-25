// OpenPencil / Figma plugin script: ring layout compositions.
//
// Wear (default target below):
//   node tools/openpencil.mjs eval brand/icons/wardpulse.fig \
//     --stdin -w -o apps/wear_android/design/rings.fig < tools/create-watch-ring-designs.fig.js
//
// WFF:
//   sed "s/const target = 'wear'/const target = 'wff'/" tools/create-watch-ring-designs.fig.js | \
//     node tools/openpencil.mjs eval brand/icons/wardpulse.fig \
//     --stdin -w -o apps/watchface_wff/design/rings.fig

const target = 'wear'

const SURFACE = { r: 16 / 255, g: 20 / 255, b: 18 / 255 }
const TRACK = { r: 63 / 255, g: 73 / 255, b: 67 / 255 }
const SUCCESS = { r: 101 / 255, g: 215 / 255, b: 138 / 255 }
const WARNING = { r: 230 / 255, g: 195 / 255, b: 73 / 255 }
const ERROR = { r: 255 / 255, g: 180 / 255, b: 171 / 255 }
const LABEL = { r: 244 / 255, g: 251 / 255, b: 248 / 255 }
const MUTED = { r: 190 / 255, g: 201 / 255, b: 193 / 255 }

const STATUS = [SUCCESS, SUCCESS, WARNING, ERROR]
const SAMPLE = [0.25, 0.48, 0.72, 0.91]
const LABELS = ['Today', 'Week', 'Month', 'Plan']

function solid(color) {
  return [{ type: 'SOLID', color }]
}

async function loadFont() {
  await figma.loadFontAsync({ family: 'Inter', style: 'Regular' })
  await figma.loadFontAsync({ family: 'Inter', style: 'Medium' })
}

function addLabel(parent, text, y, size, color) {
  const node = figma.createText()
  node.fontName = { family: 'Inter', style: size >= 28 ? 'Medium' : 'Regular' }
  node.characters = text
  node.fontSize = size
  node.fills = solid(color)
  node.textAlignHorizontal = 'CENTER'
  node.resize(parent.width, size + 6)
  node.x = 0
  node.y = y
  parent.appendChild(node)
}

function addRingArc(parent, cx, cy, diameter, thickness, progress, color, ambient) {
  const inner = Math.max(0.05, 1 - (thickness * 2) / diameter)
  const track = figma.createEllipse()
  track.name = 'track'
  track.resize(diameter, diameter)
  track.x = cx - diameter / 2
  track.y = cy - diameter / 2
  track.fills = []
  track.strokes = [{ type: 'SOLID', color: TRACK }]
  track.strokeWeight = ambient ? thickness * 0.75 : thickness
  track.strokeAlign = 'CENTER'
  track.arcData = {
    startingAngle: -Math.PI / 2,
    endingAngle: -Math.PI / 2 + Math.PI * 2 * 0.999,
    innerRadius: inner,
  }
  parent.appendChild(track)

  const sweep = Math.max(0.02, Math.min(progress, 1))
  const value = figma.createEllipse()
  value.name = 'value'
  value.resize(diameter, diameter)
  value.x = cx - diameter / 2
  value.y = cy - diameter / 2
  value.fills = []
  value.strokes = [{ type: 'SOLID', color }]
  value.strokeWeight = ambient ? thickness * 0.75 : thickness
  value.strokeAlign = 'CENTER'
  value.strokeCap = 'ROUND'
  value.arcData = {
    startingAngle: -Math.PI / 2,
    endingAngle: -Math.PI / 2 + Math.PI * 2 * sweep,
    innerRadius: inner,
  }
  parent.appendChild(value)
}

function makeFace(page, name, size, ringCount, ambient) {
  const frame = figma.createFrame()
  frame.name = name
  frame.resize(size, size)
  frame.fills = solid(SURFACE)
  frame.clipsContent = true
  page.appendChild(frame)

  const cx = size / 2
  const cy = size / 2 - (ambient ? 0 : 8)
  const outer = size * (ambient ? 0.78 : 0.72)
  const gap = size * 0.055
  const thickness = Math.max(6, size * (ambient ? 0.028 : 0.036))

  for (let i = 0; i < ringCount; i += 1) {
    const diameter = outer - i * (thickness + gap) * 2
    addRingArc(
      frame,
      cx,
      cy,
      diameter,
      thickness,
      SAMPLE[i],
      ambient ? MUTED : STATUS[i],
      ambient,
    )
  }

  if (!ambient) {
    addLabel(frame, 'WARDPULSE', size * 0.08, Math.round(size * 0.045), MUTED)
    if (ringCount === 1) {
      addLabel(
        frame,
        `${Math.round(SAMPLE[0] * 100)}%`,
        cy - size * 0.04,
        Math.round(size * 0.12),
        LABEL,
      )
      addLabel(frame, LABELS[0], cy + size * 0.08, Math.round(size * 0.04), MUTED)
    } else {
      addLabel(frame, `${ringCount} rings`, cy - size * 0.02, Math.round(size * 0.055), LABEL)
      addLabel(
        frame,
        LABELS.slice(0, ringCount)
          .map((label, i) => `${label} ${Math.round(SAMPLE[i] * 100)}%`)
          .join(' · '),
        size * 0.86,
        Math.round(size * 0.032),
        MUTED,
      )
    }
  } else {
    addLabel(frame, '10:08', cy - size * 0.06, Math.round(size * 0.14), LABEL)
    addLabel(frame, 'WARDPULSE', size * 0.78, Math.round(size * 0.04), MUTED)
  }
}

function makeWffSlots(page) {
  const frame = figma.createFrame()
  frame.name = 'WFF round · 2 ring slots'
  frame.resize(450, 450)
  frame.fills = solid(SURFACE)
  page.appendChild(frame)

  addLabel(frame, 'WARDPULSE', 92, 24, LABEL)
  addLabel(frame, '10:08', 150, 72, LABEL)
  addRingArc(frame, 125, 300, 120, 10, SAMPLE[0], SUCCESS, false)
  addRingArc(frame, 325, 300, 120, 10, SAMPLE[1], SUCCESS, false)
  const left = figma.createText()
  left.fontName = { family: 'Inter', style: 'Regular' }
  left.characters = 'RING 1\n25%'
  left.fontSize = 16
  left.fills = solid(MUTED)
  left.textAlignHorizontal = 'CENTER'
  left.resize(150, 48)
  left.x = 50
  left.y = 360
  frame.appendChild(left)

  const right = figma.createText()
  right.fontName = { family: 'Inter', style: 'Regular' }
  right.characters = 'RING 2\n49%'
  right.fontSize = 16
  right.fills = solid(MUTED)
  right.textAlignHorizontal = 'CENTER'
  right.resize(150, 48)
  right.x = 250
  right.y = 360
  frame.appendChild(right)

  addLabel(frame, 'OPENAI · OK', 410, 14, SUCCESS)
}

await loadFont()

for (const page of [...figma.root.children]) {
  page.remove()
}

if (target === 'wff') {
  const wff = figma.createPage()
  wff.name = 'Watch Face Format'
  figma.currentPage = wff
  makeWffSlots(wff)
} else {
  const wear = figma.createPage()
  wear.name = 'Wear OS rings'
  figma.currentPage = wear
  for (const count of [1, 2, 3, 4]) {
    makeFace(wear, `Round · ${count} ring${count === 1 ? '' : 's'}`, 450, count, false)
    makeFace(wear, `Square · ${count} ring${count === 1 ? '' : 's'}`, 390, count, false)
  }
  makeFace(wear, 'Round · ambient · 3 rings', 450, 3, true)
  makeFace(wear, 'Square · ambient · 3 rings', 390, 3, true)
}

return {
  target,
  pages: figma.root.children.map((page) => page.name),
  frames: figma.root.children.flatMap((page) => page.children.map((child) => child.name)),
}
