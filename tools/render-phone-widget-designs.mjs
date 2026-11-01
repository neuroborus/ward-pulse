#!/usr/bin/env node
/**
 * SVG review exports for the phone home-screen widget
 * (`docs/product/PHONE_WIDGET_DESIGN.md`).
 *
 * Rows, not arcs: family accent bar, `%`, a two-line label carrying the
 * provider family over the pool name, and end-aligned compact credit balances.
 * Colours mirror `res/values{,-night}/colors_widget.xml` so the art cannot drift
 * from the app without the resource changing too.
 *
 * Usage: node tools/render-phone-widget-designs.mjs [--check]
 *
 * One UNAPPROVED host-only PNG board and provenance record, without default writes:
 *   node tools/render-phone-widget-designs.mjs \
 *     --own-font-preview-output LOCAL_ARTIFACTS/<new-directory> \
 *     --own-font-regular /usr/share/fonts/truetype/noto/NotoSans-Regular.ttf \
 *     --own-font-bold /usr/share/fonts/truetype/noto/NotoSans-Bold.ttf
 * The parent must exist; the new directory must resolve inside LOCAL_ARTIFACTS.
 * Preview flags cannot use --check. Fonts must match the pinned host files below;
 * nothing is bundled. ImageMagick renders at 72dpi: these are preview units only.
 * Sample ink fit proves neither universal text coverage nor native/device fit.
 * Root must SHOW this board and obtain approval before separate runtime adoption.
 */

import assert from 'node:assert/strict'
import { execFile } from 'node:child_process'
import { createHash } from 'node:crypto'
import { constants } from 'node:fs'
import { access, mkdir, readFile, realpath, rm, stat, writeFile } from 'node:fs/promises'
import { basename, delimiter, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

import { emit } from './design-output.mjs'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const designDir = join(root, 'apps/phone_flutter/design')
const resDir = join(root, 'apps/phone_flutter/android/app/src/main/res')
const runFile = promisify(execFile)
const ownFontPreview = parseOwnFontPreview(process.argv.slice(2))

const FONT = 'Noto Sans, sans-serif'

/** Family accents, matching `RingFamily` on the phone. */
const FAMILY = {
  codex: '#65D78A',
  claude: '#E8915A',
  cursor: '#67E8D4',
  // A Cursor plan's own models keep a color of their own; the external pool
  // stays the family teal (`WATCH_RING_DESIGN.md`, palette).
  cursorOwn: '#7E93B8',
}

/** `#AARRGGBB` from Android resources → SVG colour plus separate opacity. */
function argb(value) {
  if (value.length === 9) {
    return {
      color: `#${value.slice(3)}`,
      opacity: Number((parseInt(value.slice(1, 3), 16) / 255).toFixed(2)),
    }
  }
  return { color: value, opacity: 1 }
}

async function loadTheme(variant) {
  const file = join(resDir, variant, 'colors_widget.xml')
  const xml = await readFile(file, 'utf8')
  const read = (name) => {
    const match = xml.match(
      new RegExp(`<color name="ward_pulse_widget_${name}">(#[0-9A-Fa-f]+)</color>`),
    )
    if (!match) {
      throw new Error(`missing ward_pulse_widget_${name} in ${file}`)
    }
    return match[1]
  }
  const outline = argb(read('outline'))
  return {
    surface: read('surface'),
    onSurface: read('on_surface'),
    muted: read('muted'),
    stale: read('stale'),
    outlineColor: outline.color,
    outlineOpacity: outline.opacity,
  }
}

function esc(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
}

/** Quiet face watermark, top-end beside the first row. */
function watermark({ x, y, color, opacity }) {
  return `  <g transform="translate(${x}, ${y})" opacity="${opacity}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linecap="round">
    <text x="18" y="0" font-family="${FONT}" font-size="5" font-weight="700" letter-spacing="0.5" fill="${color}" stroke="none" text-anchor="middle">WARDPULSE</text>
    <path d="M2 10 L8 10 L12 4 L18 14 L24 8 L30 8"/>
  </g>`
}

/**
 * One metric row. `family` is null when the pool name already carries it
 * (`Cursor Models`), which keeps the second line empty instead of repeating.
 */
function row({ theme, geometry, y, entry }) {
  const { padX, percentX, labelX, creditsX, fontSize, lineGap } = geometry
  // Baseline centred in the two-line block, so single-line rows line up with it.
  const centerY = y + (fontSize + lineGap) / 2
  const parts = [
    `  <rect x="${padX}" y="${y - fontSize + 3}" width="3" height="${
      fontSize * 2 + lineGap - 4
    }" rx="1" fill="${entry.color}"/>`,
    `  <text x="${percentX}" y="${centerY}" font-family="${FONT}" font-size="${fontSize}" fill="${
      theme.onSurface
    }">${esc(entry.percent)}</text>`,
  ]
  if (entry.family) {
    parts.push(
      `  <text x="${labelX}" y="${y}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.onSurface
      }" text-anchor="middle">${esc(entry.family)}</text>`,
      `  <text x="${labelX}" y="${y + fontSize + lineGap}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.onSurface
      }" text-anchor="middle">${esc(entry.pool)}</text>`,
    )
  } else {
    parts.push(
      `  <text x="${labelX}" y="${centerY}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.onSurface
      }" text-anchor="middle">${esc(entry.pool)}</text>`,
    )
  }
  if (entry.credits) {
    parts.push(
      `  <text x="${creditsX}" y="${centerY}" font-family="${FONT}" font-size="${fontSize}" fill="${
        theme.muted
      }" text-anchor="end">${esc(entry.credits)}</text>`,
    )
  }
  return parts.join('\n')
}

function board({ theme, label, width, height, body }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(
    label,
  )}">
  <rect width="${width}" height="${height}" rx="20" fill="${theme.surface}" stroke="${
    theme.outlineColor
  }" stroke-opacity="${theme.outlineOpacity}"/>
${body}
</svg>
`
}

function metricsBoard({ theme, label, geometry, rows, staleBadge = false }) {
  const { padX, top, pitch, width } = geometry
  // Review-scale illustration; runtime measures its current 11sp badge line plus 2dp.
  const staleInset = staleBadge ? 17 : 0
  const height = top + staleInset + rows.length * pitch + 10
  const body = [
    watermark({
      x: width - 50,
      y: 12,
      color: theme.muted,
      opacity: 0.4,
    }),
    staleBadge
      ? `  <text x="${
          padX
        }" y="22" font-family="${FONT}" font-size="11" font-weight="700" letter-spacing="1" fill="${theme.stale}" text-anchor="start">STALE</text>`
      : null,
    ...rows.map((entry, index) =>
      row({
        theme,
        geometry,
        y: top + staleInset + index * pitch,
        entry,
      }),
    ),
  ]
    .filter(Boolean)
    .join('\n')
  return board({ theme, label, width, height, body })
}

/** Medium board geometry; the small board is the same table, one size down. */
function geometryFor(width, fontSize) {
  return {
    width,
    padX: 14,
    percentX: 24,
    labelX: Math.round(width * 0.5),
    creditsX: width - 28,
    top: 34,
    fontSize,
    lineGap: 3,
    pitch: fontSize * 2 + 12,
  }
}

/**
 * Two providers with the same pool name sit next to each other on purpose —
 * that collision is why the label carries its family.
 */
const MEDIUM_ROWS = [
  {
    percent: '22%',
    family: 'Claude',
    pool: 'Weekly plan',
    credits: '80',
    color: FAMILY.claude,
  },
  {
    percent: '46%',
    family: 'Codex',
    pool: 'Weekly plan',
    credits: '320',
    color: FAMILY.codex,
  },
  {
    percent: '71%',
    family: null,
    pool: 'Cursor Models',
    credits: '2.1K',
    color: FAMILY.cursorOwn,
  },
]

const light = await loadTheme('values')
const dark = await loadTheme('values-night')

const variants = [
  {
    file: 'widget-medium.svg',
    svg: () =>
      metricsBoard({
        theme: light,
        label: 'Phone widget · medium · light · tightest-first',
        geometry: geometryFor(280, 12),
        rows: MEDIUM_ROWS,
      }),
  },
  {
    file: 'widget-dark.svg',
    svg: () =>
      metricsBoard({
        theme: dark,
        label: 'Phone widget · medium · dark · tightest-first',
        geometry: geometryFor(280, 12),
        rows: MEDIUM_ROWS,
      }),
  },
  {
    file: 'widget-small.svg',
    svg: () =>
      metricsBoard({
        theme: light,
        label: 'Phone widget · small · light · tightest-first',
        geometry: geometryFor(240, 11),
        rows: MEDIUM_ROWS.slice(0, 2),
      }),
  },
  {
    file: 'widget-stale.svg',
    svg: () =>
      metricsBoard({
        theme: light,
        label: 'Phone widget · stale',
        geometry: geometryFor(240, 11),
        rows: MEDIUM_ROWS.slice(0, 2).map((entry) => ({ ...entry, credits: null })),
        staleBadge: true,
      }),
  },
  {
    file: 'widget-stale-dark.svg',
    svg: () =>
      metricsBoard({
        theme: dark,
        label: 'Phone widget · stale · dark',
        geometry: geometryFor(240, 11),
        rows: MEDIUM_ROWS.slice(0, 2).map((entry) => ({ ...entry, credits: null })),
        staleBadge: true,
      }),
  },
  {
    file: 'widget-stale-narrow.svg',
    svg: () =>
      metricsBoard({
        theme: light,
        label: 'Phone widget · stale · percent column only',
        geometry: geometryFor(125, 11),
        rows: MEDIUM_ROWS.slice(0, 2).map((entry) => ({
          ...entry, family: null, pool: '', credits: null,
        })),
        staleBadge: true,
      }),
  },
  {
    file: 'widget-stale-short.svg',
    svg: () =>
      board({
        theme: light,
        label: 'Phone widget · stale · no complete metric row fits',
        width: 130,
        height: 56,
        body: [
          watermark({ x: 80, y: 12, color: light.muted, opacity: 0.4 }),
          `  <text x="14" y="22" font-family="${FONT}" font-size="11" font-weight="700" letter-spacing="1" fill="${light.stale}">STALE</text>`,
          `  <text x="14" y="44" font-family="${FONT}" font-size="13" fill="${light.muted}">Resize widget</text>`,
        ].join('\n'),
      }),
  },
  {
    file: 'widget-empty.svg',
    svg: () =>
      board({
        theme: light,
        label: 'Phone widget · empty',
        width: 220,
        height: 88,
        body: [
          watermark({ x: 150, y: 20, color: light.muted, opacity: 0.28 }),
          `  <text x="14" y="46" font-family="${FONT}" font-size="13" fill="${light.muted}">No metrics</text>`,
        ].join('\n'),
      }),
  },
]

/** Preview inputs are illustrative, attributed to the historical owner photo. */
const OWN_FONT_ROWS = [
  { family: 'Codex', pool: 'Weekly', percent: '85%', credits: '59.5K', color: FAMILY.codex },
  { family: 'Claude', pool: '5h', percent: '100%', color: FAMILY.claude },
  { family: 'Claude', pool: 'Weekly', percent: '100%', color: FAMILY.claude },
]

// Exact existing host inputs, not runtime font selection or license/asset adoption.
const OWN_FONT_HASHES = {
  regular: '89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d',
  bold: 'e83493c945848ecd4a9ad0f6d19164541a0d3e23a9c952304a00a46e00272ac5',
}
const PHOTO = 'LOCAL_ARTIFACTS/backlog-2026-10-24-screenshots/phone-widget-truncated-columns.png'
const PHOTO_HASH = 'cb24a7b1eb3be4d38e8f368f4f9aa3cdd7a620fdc55bd3f58fe35ec4fc4ba9bf'

function parseOwnFontPreview(args) {
  if (args.length === 0 || (args.length === 1 && args[0] === '--check')) return null
  const flags = ['--own-font-preview-output', '--own-font-regular', '--own-font-bold']
  const values = new Map()
  for (let index = 0; index < args.length; index += 2) {
    const flag = args[index]
    const value = args[index + 1]
    if (!flags.includes(flag) || values.has(flag) || !value || value.startsWith('--')) {
      throw new Error('use all three own-font preview flags exactly once, without --check or other flags')
    }
    values.set(flag, value)
  }
  assert.equal(values.size, flags.length, 'own-font preview requires an output directory and both font files')
  return {
    output: values.get(flags[0]),
    regular: resolve(values.get(flags[1])),
    bold: resolve(values.get(flags[2])),
  }
}

async function ownFontDirectory(output) {
  const localRoot = join(root, 'LOCAL_ARTIFACTS')
  assert.equal(await realpath(localRoot), localRoot, 'LOCAL_ARTIFACTS must not redirect outside the repository')
  const insideLocal = (path) => {
    const fromLocal = relative(localRoot, path)
    return fromLocal !== '' && fromLocal !== '..' &&
      !fromLocal.startsWith(`..${sep}`) && !isAbsolute(fromLocal)
  }
  const requested = resolve(root, output)
  assert.ok(insideLocal(requested), 'own-font preview output must be a new directory inside LOCAL_ARTIFACTS')
  const directory = join(await realpath(dirname(requested)), basename(requested))
  assert.ok(insideLocal(directory), 'own-font preview output resolves outside LOCAL_ARTIFACTS')
  return directory
}

async function hashFile(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex')
}

async function previewExecutable(name) {
  for (const directory of (process.env.PATH ?? '').split(delimiter)) {
    const path = resolve(directory, name)
    try {
      await access(path, constants.X_OK)
      if ((await stat(path)).isFile()) return realpath(path)
    } catch {
      // Continue the normal PATH search; record the actual resolved executable.
    }
  }
  throw new Error(`own-font preview requires the existing ${name} executable`)
}

function pngSize(bytes) {
  assert.ok(bytes.length >= 24 &&
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
    bytes.toString('ascii', 12, 16) === 'IHDR', 'preview renderer must produce PNG bytes')
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) }
}

async function renderOwnFontPreview(options) {
  // All preflight failures precede exclusive output creation. Never substitute a font.
  const fonts = {}
  for (const weight of ['regular', 'bold']) {
    const path = await realpath(options[weight]).catch(() => {
      throw new Error(`missing ${weight} font file: ${options[weight]}; no font substitution is allowed`)
    })
    const sha256 = await hashFile(path)
    assert.equal(sha256, OWN_FONT_HASHES[weight], `preview requires the pinned Noto Sans ${weight} font bytes`)
    fonts[weight] = { path, sha256, weight: weight === 'bold' ? 700 : 400 }
  }
  assert.equal(await hashFile(join(root, PHOTO)), PHOTO_HASH, 'historical reference identity must match')
  const directory = await ownFontDirectory(options.output)
  const convert = await previewExecutable('convert')
  const node = await realpath(process.execPath)
  const { stdout: imageMagickVersion } = await runFile(convert, ['-version'], { encoding: 'utf8' })
  const watermarkPath = 'apps/phone_flutter/android/app/src/main/res/drawable/wardpulse_mono.png'
  const protectedPaths = [
    ...variants.map(({ file }) => relative(root, join(designDir, file))),
    'tools/design-output.mjs',
    'docs/product/PHONE_WIDGET_DESIGN.md',
    'apps/phone_flutter/lib/widget/phone_widget_payload.dart',
    'apps/phone_flutter/lib/widget/phone_widget_preferences.dart',
    'apps/phone_flutter/android/app/src/main/java/app/wardpulse/PhoneWidgetLayout.java',
    'apps/phone_flutter/android/app/src/main/kotlin/app/wardpulse/WardPulseAppWidget.kt',
    ...['layout/ward_pulse_app_widget.xml', 'layout/ward_pulse_app_widget_preview.xml',
      'xml/ward_pulse_app_widget_info.xml', 'drawable/ward_pulse_widget_background.xml',
      'values/colors_widget.xml', 'values-night/colors_widget.xml'].map((path) => relative(root, join(resDir, path))),
    watermarkPath,
  ]
  const hashes = async (paths) => Object.fromEntries(await Promise.all(paths.map(async (path) =>
    [path, await hashFile(join(root, path))])))
  const protectedBefore = await hashes(protectedPaths)
  const inputHashes = await hashes(['tools/render-phone-widget-designs.mjs', 'docs/DESIGN_ASSETS.md', PHOTO])

  await mkdir(directory, { mode: 0o700 })
  const work = join(directory, '.rendering')
  const controller = new AbortController()
  const interrupt = () => controller.abort()
  process.on('SIGINT', interrupt)
  process.on('SIGTERM', interrupt)
  let closed = Promise.resolve()
  const commands = []
  const image = async (args) => {
    controller.signal.throwIfAborted()
    commands.push({ executable: convert, arguments: args })
    const operation = runFile(convert, args, { encoding: 'buffer', signal: controller.signal })
    closed = new Promise((resolve) => operation.child.once('close', resolve))
    const result = await operation
    await closed
    assert.equal(result.stderr.toString().trim(), '', 'ImageMagick warnings must not be silently accepted')
    return result.stdout
  }
  try {
    await mkdir(work)
    const glyphs = new Map()
    const text = async (value, size, weight, color) => {
      const key = JSON.stringify([value, size, weight, color])
      if (!glyphs.has(key)) {
        const file = join(work, `text-${glyphs.size}.png`)
        // ImageMagick labels interpret percent properties and backslash escapes.
        const literal = value.replaceAll('\\', '\\\\').replaceAll('%', '%%')
        await image(['-background', 'none', '-density', '72', '-font', fonts[weight].path,
          '-pointsize', String(size), '-fill', color, `label:${literal}`, '-trim', '+repage', '-strip', `png32:${file}`])
        glyphs.set(key, { file, text: value, size, weight: fonts[weight].weight,
          ...pngSize(await readFile(file)) })
      }
      return glyphs.get(key)
    }
    const boardSize = { width: 472, height: 492 }
    const drawing = ['-size', `${boardSize.width}x${boardSize.height}`, 'xc:#080C0A']
    const composite = (file, x, y) => drawing.push(file, '-geometry', `+${Math.round(x)}+${Math.round(y)}`, '-composite')
    const caption = async (value, y, center, size = 12, weight = 'regular') => {
      const ink = await text(value, size, weight, dark.muted)
      composite(ink.file, center - ink.width / 2, y)
    }
    await caption('UNAPPROVED · OWN-FONT PROPOSAL', 20, 236, 13, 'bold')
    await caption('Historical reference · illustrative data', 40, 236)

    const mark = join(work, 'watermark.png')
    await image([join(root, watermarkPath), '-resize', '36x36', '-fill', dark.muted, '-colorize', '100',
      '-channel', 'A', '-evaluate', 'multiply', '0.55', '+channel', '-strip', `png32:${mark}`])
    const markBounds = (await image([mark, '-alpha', 'extract', '-threshold', '0', '-format', '%@', 'info:'])).toString()
    const match = /^(\d+)x(\d+)\+(\d+)\+(\d+)$/.exec(markBounds)
    assert.ok(match, 'watermark alpha must have measurable ink')
    const [, markWidth, markHeight, markX, markY] = match.map(Number)
    const frames = [
      { width: 360, height: 192, x: 56, y: 64, columns: 3, rows: 3, captionY: 272 },
      { width: 250, height: 120, x: 24, y: 316, columns: 2, rows: 2, captionY: 452 },
      { width: 150, height: 120, x: 298, y: 316, columns: 1, rows: 2, captionY: 452 },
    ]
    const measurements = []
    for (const frame of frames) {
      const { x, y, width, height, columns } = frame
      const outline = dark.outlineColor.match(/\w\w/g).map((part) => parseInt(part, 16))
      drawing.push('-fill', dark.surface, '-stroke', `rgba(${outline.join(',')},${dark.outlineOpacity})`,
        '-strokewidth', '1', '-draw', `roundrectangle ${x + 0.5},${y + 0.5} ${x + width - 0.5},${y + height - 0.5} 20,20`)
      composite(mark, x + width - 52, y + 8)
      const markInk = { x: width - 52 + markX, y: 8 + markY, width: markWidth, height: markHeight }
      const rowHeight = 32
      const surplus = height - 32 - frame.rows * rowHeight - (frame.rows - 1) * 8
      assert.ok(surplus >= 0, 'only complete row blocks may be shown')
      const breathing = surplus / (frame.rows + 1)
      const rowGap = 8 + breathing
      const ink = []
      const place = (glyph, left, top, bounds, row, kind) => {
        const box = { x: Math.round(left), y: Math.round(top), width: glyph.width, height: glyph.height }
        const clearance = { left: box.x - bounds.left, right: bounds.right - box.x - box.width,
          top: box.y - bounds.top, bottom: bounds.bottom - box.y - box.height }
        assert.ok(Object.values(clearance).every((gap) => gap >= 0), `complete ${glyph.text} ink must fit its column/row`)
        composite(glyph.file, x + box.x, y + box.y)
        ink.push({ row, kind, text: glyph.text, size: glyph.size, weight: glyph.weight, box, bounds, clearance })
      }
      const rowBlocks = []
      for (const [index, entry] of OWN_FONT_ROWS.slice(0, frame.rows).entries()) {
        const top = 16 + breathing + index * (rowHeight + rowGap)
        rowBlocks.push({ top, bottom: top + rowHeight, family: entry.family, pool: entry.pool })
        drawing.push('-stroke', 'none', '-fill', entry.color, '-draw',
          `roundrectangle ${x + 16},${y + top} ${x + 19},${y + top + rowHeight} 1.5,1.5`)
        const bounds = { left: 28, right: 98, top, bottom: top + rowHeight }
        const percent = await text(entry.percent, 20, 'bold', dark.onSurface)
        place(percent, 28, top + (rowHeight - percent.height) / 2, bounds, index, 'percent')
        if (columns >= 2) {
          const label = columns === 3 ? { left: 117, right: 243 } : { left: 109, right: width - 16 }
          const center = (label.left + label.right) / 2
          const family = await text(entry.family, 13, 'bold', dark.onSurface)
          const pool = await text(entry.pool, 12, 'regular', dark.muted)
          const familyTop = top + (rowHeight - family.height - pool.height - 4) / 2
          place(family, center - family.width / 2, familyTop, { ...bounds, ...label }, index, 'family')
          place(pool, center - pool.width / 2, familyTop + family.height + 4, { ...bounds, ...label }, index, 'pool')
        }
        if (columns === 3 && entry.credits) {
          const credits = await text(entry.credits, 18, 'bold', dark.onSurface)
          place(credits, width - 16 - credits.width, top + (rowHeight - credits.height) / 2,
            { ...bounds, left: 260, right: width - 16 }, index, 'purchasedBalance')
        }
      }
      const boxes = [...ink.map(({ box }) => box), markInk]
      for (const [index, box] of boxes.entries()) {
        assert.ok(box.x >= 16 && box.y >= 16 && box.x + box.width <= width - 16 &&
          box.y + box.height <= height - 16, 'all actual ink must retain inner padding')
        for (const other of boxes.slice(index + 1)) {
          assert.ok(box.x + box.width <= other.x || other.x + other.width <= box.x ||
            box.y + box.height <= other.y || other.y + other.height <= box.y, 'text/watermark ink must not overlap')
        }
      }
      const description = `${width} × ${height} · ${columns === 1 ? '% only' : `${columns} columns`} / ${frame.rows} rows`
      await caption(description, frame.captionY, x + width / 2, 11)
      measurements.push({ ...frame, padding: 16, rowHeight, rowGap, rowBlocks, ink, watermarkInk: markInk })
    }
    await caption('Host art only · approval pending', 476, 236)
    const png = join(directory, 'UNAPPROVED-PREVIEW-ONLY.png')
    await image([...drawing, '-strip', `png32:${png}`])
    assert.deepEqual(pngSize(await readFile(png)), boardSize, 'board must retain nominal preview dimensions')
    const decoded = (await image([png, '-format', '%w %h', 'info:'])).toString()
    assert.equal(decoded, `${boardSize.width} ${boardSize.height}`, 'completed PNG must decode')
    assert.deepEqual(await hashes(protectedPaths), protectedBefore, 'preview must not modify protected default inputs/exports')
    controller.signal.throwIfAborted()
    const metadata = {
      status: 'UNAPPROVED PREVIEW ONLY',
      evidence: 'One host-art proposal; not current native data, device fit, runtime approval or font adoption.',
      reference: { file: PHOTO, sha256: PHOTO_HASH, meaning: 'Historical owner photo; illustrative rows only.' },
      invocation: { cwd: process.cwd(), argv: [process.execPath, ...process.argv.slice(1)] },
      tools: { node: { executable: node, version: process.version, sha256: await hashFile(node) },
        imageMagick: { executable: convert, version: imageMagickVersion.trim(), sha256: await hashFile(convert) } },
      units: 'Nominal host preview units at 72dpi, not Android dp/sp or an adopted native sizing strategy.',
      fonts, inputHashes, protectedInputsUnchanged: protectedBefore,
      rows: OWN_FONT_ROWS, theme: dark,
      typography: { percent: [20, 700], purchasedBalance: [18, 700], family: [13, 700], pool: [12, 400] },
      measurements,
      uncertainty: [
        'Explicit pinned font files render the shown samples; no system family fallback is requested.',
        'Measured trimmed raster ink covers these exact strings only; it is not proof of all Unicode coverage or shaping.',
        'Signs, currencies and other labels are not rewritten; unsupported text outside these samples remains unverified.',
        'No native raster identity, system-font/fontScale/force-bold independence or universal device-pixel identity is established.',
      ],
      commands,
      outputs: { board: { file: basename(png), ...boardSize, sha256: await hashFile(png) } },
    }
    await writeFile(join(directory, 'UNAPPROVED-PREVIEW-ONLY.json'), `${JSON.stringify(metadata, null, 2)}\n`, { flag: 'wx' })
    console.log(`UNAPPROVED PREVIEW ONLY: ${png}`)
  } finally {
    // Abort rejects before child close; retire the child before removing owned intermediates.
    await closed
    await rm(work, { recursive: true, force: true })
    process.off('SIGINT', interrupt)
    process.off('SIGTERM', interrupt)
  }
}

if (ownFontPreview) {
  await renderOwnFontPreview(ownFontPreview)
} else {
  for (const variant of variants) {
    await emit(join(designDir, variant.file), variant.svg(), 'render-designs')
  }
}
