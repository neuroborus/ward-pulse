// OpenPencil frame-map inventory only — NOT the visual source of truth.
// Locked baseline + review SVGs: docs/product/WATCH_RING_DESIGN.md
//   node tools/render-watch-ring-designs.mjs
//
// OpenPencil drops ellipse arcData on .fig write (arcs flatten to full circles).
//
// Wear:
//   node tools/openpencil.mjs eval brand/icons/wardpulse.fig \
//     --stdin -w -o apps/wear_android/design/rings.fig < tools/create-watch-ring-designs.fig.js
// WFF:
//   sed "s/const target = 'wear'/const target = 'wff'/" tools/create-watch-ring-designs.fig.js | \
//     node tools/openpencil.mjs eval brand/icons/wardpulse.fig \
//     --stdin -w -o apps/watchface_wff/design/rings.fig

const target = 'wear'

const SURFACE = { r: 16 / 255, g: 20 / 255, b: 18 / 255 }
const TRACK = { r: 63 / 255, g: 73 / 255, b: 67 / 255 }
const LABEL = { r: 244 / 255, g: 251 / 255, b: 248 / 255 }
const MUTED = { r: 190 / 255, g: 201 / 255, b: 193 / 255 }

const CODEX = { r: 101 / 255, g: 215 / 255, b: 138 / 255 } // OpenAI / Codex — green
const CLAUDE = { r: 232 / 255, g: 145 / 255, b: 90 / 255 } // Anthropic — orange
const CURSOR = { r: 103 / 255, g: 232 / 255, b: 212 / 255 } // Cursor — teal
const BUDGET = { r: 138 / 255, g: 180 / 255, b: 248 / 255 }

/** Outer → inner by tightest remaining. Arc = remaining. Exhausted omitted. */
const PROVIDER_LAYERS = [
  { label: 'Codex', used: 0.92, color: CODEX },
  { label: 'Claude', used: 0.61, color: CLAUDE },
  { label: 'Cursor', used: 0.28, color: CURSOR },
]

function solid(color) {
  return [{ type: 'SOLID', color }]
}

async function loadFont() {
  await figma.loadFontAsync({ family: 'Inter', style: 'Regular' })
  await figma.loadFontAsync({ family: 'Inter', style: 'Medium' })
}

function addLabel(parent, text, y, size, color, style) {
  const node = figma.createText()
  node.fontName = {
    family: 'Inter',
    style: style || (size >= 28 ? 'Medium' : 'Regular'),
  }
  node.characters = text
  node.fontSize = size
  node.fills = solid(color)
  node.textAlignHorizontal = 'CENTER'
  node.resize(parent.width, size + 6)
  node.x = 0
  node.y = y
  parent.appendChild(node)
  return node
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
  track.strokeWeight = ambient ? thickness * 0.7 : thickness
  track.strokeAlign = 'CENTER'
  track.arcData = {
    startingAngle: -Math.PI / 2,
    endingAngle: -Math.PI / 2 + Math.PI * 2 * 0.999,
    innerRadius: inner,
  }
  parent.appendChild(track)

  // `progress` is remaining fraction (1 - used).
  const sweep = Math.max(0.02, Math.min(progress, 0.999))
  const value = figma.createEllipse()
  value.name = 'value'
  value.resize(diameter, diameter)
  value.x = cx - diameter / 2
  value.y = cy - diameter / 2
  value.fills = []
  value.strokes = [{ type: 'SOLID', color }]
  value.strokeWeight = ambient ? thickness * 0.7 : thickness
  value.strokeAlign = 'CENTER'
  value.strokeCap = 'ROUND'
  value.arcData = {
    startingAngle: -Math.PI / 2,
    endingAngle: -Math.PI / 2 + Math.PI * 2 * sweep,
    innerRadius: inner,
  }
  parent.appendChild(value)
}

function visibleLayers(count) {
  return PROVIDER_LAYERS.filter((layer) => layer.used < 1).slice(0, count)
}

/**
 * One composition: rings fill the face; type lives in the aperture only.
 * No orphan caption bands above/below the ring stack.
 */
function makeFace(page, name, size, ringCount, ambient, options) {
  const opts = options || {}
  const layers = visibleLayers(ringCount)
  const frame = figma.createFrame()
  frame.name = name
  frame.resize(size, size)
  frame.fills = solid(SURFACE)
  frame.clipsContent = true
  page.appendChild(frame)

  const cx = size / 2
  const cy = size / 2
  const outer = size * (ambient ? 0.84 : 0.86)
  const gap = size * 0.042
  const thickness = Math.max(7, size * (ambient ? 0.03 : 0.038))

  for (let i = 0; i < layers.length; i += 1) {
    const diameter = outer - i * (thickness + gap) * 2
    addRingArc(
      frame,
      cx,
      cy,
      diameter,
      thickness,
      1 - layers[i].used,
      ambient ? MUTED : layers[i].color,
      ambient,
    )
  }

  // Inner hole roughly after the innermost stroke.
  const innerHole =
    outer - layers.length * (thickness + gap) * 2 + gap + thickness

  if (ambient) {
    addLabel(frame, '10:08', cy - size * 0.07, Math.round(size * 0.16), LABEL, 'Medium')
    return
  }

  const outerLayer = layers[0]
  const remaining = Math.round((1 - outerLayer.used) * 100)
  const hero = Math.round(layers.length === 1 ? size * 0.15 : size * 0.1)
  const stackTop = cy - hero * 0.55
  addLabel(frame, `${remaining}%`, stackTop, hero, LABEL, 'Medium')
  addLabel(
    frame,
    `${outerLayer.label} left`,
    stackTop + hero * 0.95,
    Math.round(size * 0.042),
    MUTED,
  )
  if (opts.tokens) {
    addLabel(
      frame,
      opts.tokens,
      stackTop + hero * 1.35,
      Math.round(size * 0.04),
      outerLayer.color,
      'Medium',
    )
  }

  // Tiny time tucked in the top crescent — secondary to the ring stack.
  addLabel(frame, '10:08', size * 0.11, Math.round(size * 0.04), MUTED, 'Medium')

  // Keep innerHole referenced so layout stays honest if we tighten further.
  void innerHole
}

function makeBudgetFace(page, name, size) {
  const frame = figma.createFrame()
  frame.name = name
  frame.resize(size, size)
  frame.fills = solid(SURFACE)
  frame.clipsContent = true
  page.appendChild(frame)
  // Arc = remaining (75% of Today budget left).
  addRingArc(frame, size / 2, size / 2, size * 0.86, Math.max(7, size * 0.038), 0.75, BUDGET, false)
  addLabel(frame, '10:08', size * 0.11, Math.round(size * 0.04), MUTED, 'Medium')
  addLabel(frame, '75%', size * 0.395, Math.round(size * 0.15), LABEL, 'Medium')
  addLabel(frame, 'Today left', size * 0.575, Math.round(size * 0.042), MUTED)
}

function makeWffPage(page) {
  makeFace(page, 'WFF round · 1 layer + tokens', 450, 1, false, {
    tokens: '1.4B TOK',
  })
  makeFace(page, 'WFF round · 3 providers', 450, 3, false, {
    tokens: '1.4B TOK',
  })
  makeFace(page, 'WFF round · ambient · 2 layers', 450, 2, true)
  makeFace(page, 'WFF square · 3 providers', 390, 3, false, {
    tokens: '67K TOK',
  })
  makeBudgetFace(page, 'WFF round · budget layer', 450)
}

await loadFont()

for (const page of [...figma.root.children]) {
  page.remove()
}

if (target === 'wff') {
  const wff = figma.createPage()
  wff.name = 'Watch Face Format'
  figma.currentPage = wff
  makeWffPage(wff)
} else {
  const wear = figma.createPage()
  wear.name = 'Wear OS rings'
  figma.currentPage = wear
  for (const count of [1, 2, 3, 4]) {
    makeFace(wear, `Round · ${count} layer${count === 1 ? '' : 's'}`, 450, count, false, {
      tokens: '1.4B TOK',
    })
    makeFace(wear, `Square · ${count} layer${count === 1 ? '' : 's'}`, 390, count, false, {
      tokens: '67K TOK',
    })
  }
  makeFace(wear, 'Round · ambient · 3 layers', 450, 3, true)
  makeFace(wear, 'Square · ambient · 3 layers', 390, 3, true)
}

return {
  target,
  pages: figma.root.children.map((page) => page.name),
  frames: figma.root.children.flatMap((page) =>
    page.children.map((child) => child.name),
  ),
}
