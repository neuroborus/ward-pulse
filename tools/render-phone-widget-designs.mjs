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
 * One UNAPPROVED host-only PNG board with a six-row main and two reduced illustrations,
 * plus provenance, without default writes:
 *   node tools/render-phone-widget-designs.mjs \
 *     --own-font-preview-output LOCAL_ARTIFACTS/<new-directory> \
 *     --own-font-regular /usr/share/fonts/truetype/noto/NotoSans-Regular.ttf \
 *     --own-font-bold /usr/share/fonts/truetype/noto/NotoSans-Bold.ttf
 * The parent must exist; the new directory must resolve inside LOCAL_ARTIFACTS.
 * Preview flags cannot use --check. Fonts must match the pinned host files below;
 * this archived proposal route uses host fonts. ImageMagick renders at 72dpi: preview units only.
 * Full labels and proposed absolute resets use fixed mixed-source illustrative inputs.
 * Root reviews the complete original and measurements before showing the board.
 * Sample ink fit proves neither universal text coverage nor native/device fit.
 * The original hash-specific board is approved provenance; new proposals still require approval.
 * Default exports below use the bundled fonts and stay separate from that historical board.
 *
 * One new PRIVATE, UNAPPROVED six-panel responsive illustration (no default writes):
 *   node tools/render-phone-widget-designs.mjs \
 *     --own-font-preview-profile responsive-six \
 *     --own-font-preview-output LOCAL_ARTIFACTS/<new-directory> \
 *     --own-font-regular apps/phone_flutter/android/app/src/main/assets/fonts/NotoSans-Regular.ttf \
 *     --own-font-bold apps/phone_flutter/android/app/src/main/assets/fonts/NotoSans-Bold.ttf
 * Omit the profile to retain the historical route above. The responsive profile uses
 * frozen historical values/measured reset instants, explicit UTC and synthetic USD money.
 * It paints at 2.625 pixels per preview unit; host ink fit is not native acceptance.
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

/** Family accents follow the widget payload palette. */
const FAMILY = {
  codex: '#65D78A', claude: '#E8915A', cursor: '#67E8D4', cursorOwn: '#7E93B8',
}

function argb(value) {
  if (value.length === 9) {
    return { color: `#${value.slice(3)}`,
      opacity: Number((parseInt(value.slice(1, 3), 16) / 255).toFixed(2)) }
  }
  return { color: value, opacity: 1 }
}

async function loadTheme(variant) {
  const xml = await readFile(join(resDir, variant, 'colors_widget.xml'), 'utf8')
  const read = (name) => {
    const match = xml.match(new RegExp(`<color name="ward_pulse_widget_${name}">(#[0-9A-Fa-f]+)</color>`))
    if (!match) throw new Error(`missing widget ${name} in ${variant}`)
    return match[1]
  }
  const outline = argb(read('outline'))
  return { surface: read('surface'), onSurface: read('on_surface'), muted: read('muted'),
    stale: read('stale'), outlineColor: outline.color, outlineOpacity: outline.opacity,
    watermark: read('watermark') }
}

/** Sanitized illustration only; these values never enter a runtime payload. */
const REVIEW_ROWS = [
  { family: 'Cursor', pool: 'Other Models', percent: '0%', color: FAMILY.cursor,
    reset: 'Reset 12 Feb 09:15' },
  { family: 'Claude', pool: '5-hour session', percent: '22%', color: FAMILY.claude,
    reset: 'Reset 10 Feb 11:45' },
  { family: 'Codex', pool: 'Weekly plan', percent: '46%', credits: '32.4K', color: FAMILY.codex,
    reset: 'Reset 17 Feb 14:30' },
  { family: 'Claude', pool: 'Weekly plan', percent: '71%', color: FAMILY.claude },
  { family: 'Codex', pool: '5-hour session', percent: '85%', credits: '32.4K', color: FAMILY.codex,
    reset: 'Reset 10 Feb 16:00' },
  { family: 'Cursor', pool: 'Models', percent: '100%', color: FAMILY.cursorOwn,
    reset: 'Reset 12 Feb 09:15' },
]

const light = await loadTheme('values')
const dark = await loadTheme('values-night')
const variants = [
  { file: 'widget-medium.svg', theme: light, width: 360, height: 344, columns: 3, rows: 6 },
  { file: 'widget-dark.svg', theme: dark, width: 360, height: 344, columns: 3, rows: 6 },
  { file: 'widget-small.svg', theme: light, width: 266, height: 184, columns: 2, rows: 3 },
  { file: 'widget-narrow.svg', theme: light, width: 150, height: 184, columns: 1, rows: 3 },
  { file: 'widget-empty.svg', theme: light, width: 220, height: 88, columns: 1, rows: 0,
    message: 'No metrics' },
  { file: 'widget-stale.svg', theme: light, width: 360, height: 344, columns: 3, rows: 5, stale: true },
  { file: 'widget-stale-dark.svg', theme: dark, width: 360, height: 344, columns: 3, rows: 5, stale: true },
  { file: 'widget-stale-narrow.svg', theme: light, width: 150, height: 184, columns: 1, rows: 2, stale: true },
  { file: 'widget-stale-short.svg', theme: light, width: 150, height: 88, columns: 1, rows: 0,
    stale: true, message: 'Resize widget' },
]

async function renderDefaults() {
  const fonts = Object.fromEntries(['regular', 'bold'].map((weight) =>
    [weight, join(resDir, '../assets/fonts', `NotoSans-${weight === 'bold' ? 'Bold' : 'Regular'}.ttf`)]))
  for (const weight of ['regular', 'bold']) {
    assert.equal(await hashFile(fonts[weight]), OWN_FONT_HASHES[weight],
      `default review art requires the bundled ${weight} font`)
  }
  // Pillow already owns font measurement in the design gate. Rasterize glyphs into
  // SVG images too, so a viewer cannot silently substitute its own font family.
  const renderer = String.raw`
import base64, html, io, json, sys
from PIL import Image, ImageColor, ImageDraw, ImageFont

config = json.loads(sys.argv[1])
scale = 3
fonts, glyphs = {}, {}

def rgba(color):
    if len(color) == 9:
        return tuple(int(color[i:i+2], 16) for i in (3, 5, 7, 1))
    return ImageColor.getrgb(color) + (255,)

def encoded(image):
    output = io.BytesIO()
    image.save(output, format='PNG', compress_level=9)
    return base64.b64encode(output.getvalue()).decode('ascii')

def glyph(value, size, weight, color):
    key = (value, size, weight, color)
    if key not in glyphs:
        if (size, weight) not in fonts:
            fonts[(size, weight)] = ImageFont.truetype(config['fonts'][weight], size * scale)
        font = fonts[(size, weight)]
        left, top, right, bottom = font.getbbox(value, anchor='ls')
        left, top, right, bottom = left - 1, top - 1, right + 1, bottom + 1
        image = Image.new('RGBA', (right-left, bottom-top))
        ImageDraw.Draw(image).text((-left, -top), value, font=font, anchor='ls', fill=rgba(color))
        glyphs[key] = {'image': image, 'png': encoded(image), 'w': image.width/scale, 'h': image.height/scale}
    return glyphs[key]

logo = Image.open(config['mark']).convert('RGBA')
logo = logo.crop(logo.getchannel('A').getbbox())
frames = []
for frame in config['variants']:
    width, height, theme = frame['width'], frame['height'], frame['theme']
    canvas = Image.new('RGBA', (width*scale, height*scale))
    draw = ImageDraw.Draw(canvas)
    outline = rgba(theme['outlineColor'])[:3] + (round(theme['outlineOpacity']*255),)
    draw.rounded_rectangle((1, 1, width*scale-2, height*scale-2), radius=20*scale,
        fill=rgba(theme['surface']), outline=outline, width=scale)
    label = 'Illustrative bundled-font widget review: ' + frame['file']
    svg = ['<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s" role="img" aria-label="%s">' % (width, height, width, height, html.escape(label, quote=True)),
        '<title>Illustrative review art; not native device acceptance or live provider data</title>',
        '<rect x="0.5" y="0.5" width="%s" height="%s" rx="20" fill="%s" stroke="%s" stroke-opacity="%s"/>' % (width-1, height-1, theme['surface'], theme['outlineColor'], theme['outlineOpacity'])]
    boxes = []
    def place(item, x, y, bounds):
        assert x >= bounds[0] and y >= bounds[1] and x+item['w'] <= bounds[2]+0.01 and y+item['h'] <= bounds[3]+0.01, 'complete review glyph must fit'
        svg.append('<image x="%.3f" y="%.3f" width="%.3f" height="%.3f" href="data:image/png;base64,%s"/>' % (x, y, item['w'], item['h'], item['png']))
        canvas.alpha_composite(item['image'], (round(x*scale), round(y*scale)))
        boxes.append((x, y, x+item['w'], y+item['h']))
    tint = rgba(theme['watermark'])
    mark = Image.new('RGBA', logo.size, tint[:3]+(255,))
    mark.putalpha(logo.getchannel('A').point(lambda value: round(value*tint[3]/255*0.55)))
    mark_width, mark_height = 36, 36*mark.height/mark.width
    mark_box = (width-16-mark_width, 2, width-16, 2+mark_height)
    mark_item = {'image': mark.resize((round(mark_width*scale), round(mark_height*scale)), Image.Resampling.LANCZOS),
        'png': encoded(mark), 'w': mark_width, 'h': mark_height}
    place(mark_item, mark_box[0], mark_box[1], (0, 0, width, height))
    row_height, row_gap, top, bottom = 44, 8, 19, 16
    badge_inset = 0
    if frame.get('stale'):
        badge = glyph('STALE', 11, 'bold', theme['stale'])
        badge_font = fonts[(11, 'bold')]
        ascent, descent = badge_font.getmetrics()
        badge_inset = (ascent+descent)/scale + 2
        place(badge, 16, top, (0, 0, width, top+badge_inset))
    start = top + badge_inset
    if frame['rows'] == 0:
        message = glyph(frame['message'], 12, 'regular', theme['muted'])
        place(message, (width-message['w'])/2, start+(height-start-bottom-message['h'])/2,
            (16, start, width-16, height-bottom))
    else:
        rows = config['rows'][:frame['rows']]
        measured = []
        for row in rows:
            measured.append({
                'percent': glyph(row['percent'], 30, 'bold', theme['onSurface']),
                'family': glyph(row['family'], 18, 'bold', theme['onSurface']),
                'pool': glyph(row['pool'], 16, 'regular', theme['muted']),
                'credits': glyph(row['credits'], 26, 'bold', theme['onSurface']) if row.get('credits') else None,
                'reset': glyph(row['reset'], 11, 'regular', theme['muted']) if row.get('reset') else None})
        percent_width = max(item['percent']['w'] for item in measured)
        label_width = max(max(item['family']['w'], item['pool']['w']) for item in measured)
        detail_width = max([item[k]['w'] for item in measured for k in ('credits', 'reset') if item[k]] or [0])
        columns = frame['columns']
        group_width = 12+percent_width + (6+label_width if columns >= 2 else 0) + (6+detail_width if columns == 3 else 0)
        group_height = len(rows)*row_height + (len(rows)-1)*row_gap
        x = (width-group_width)/2
        y = start+(height-start-bottom-group_height)/2
        assert x >= 16 and y >= start and y+group_height <= height-bottom, 'complete review rows and columns must fit'
        for row, item in zip(rows, measured):
            draw.rounded_rectangle((round(x*scale), round((y+2)*scale), round((x+3)*scale), round((y+row_height-2)*scale)), radius=1.5*scale, fill=rgba(row['color']))
            svg.append('<rect x="%.3f" y="%.3f" width="3" height="40" rx="1.5" fill="%s"/>' % (x, y+2, row['color']))
            place(item['percent'], x+12, y+(row_height-item['percent']['h'])/2, (x+12, y, x+12+percent_width, y+row_height))
            if columns >= 2:
                label_x = x+12+percent_width+6
                family, pool = item['family'], item['pool']
                label_y = y+(row_height-family['h']-3-pool['h'])/2
                place(family, label_x+(label_width-family['w'])/2, label_y, (label_x, y, label_x+label_width, y+row_height))
                place(pool, label_x+(label_width-pool['w'])/2, label_y+family['h']+3, (label_x, y, label_x+label_width, y+row_height))
            if columns == 3:
                end = x+group_width
                if item['credits']:
                    credit = item['credits']
                    credit_y = y+29-3-credit['h'] if item['reset'] else y+(row_height-credit['h'])/2
                    place(credit, end-credit['w'], credit_y, (end-detail_width, y, end, y+row_height))
                if item['reset']:
                    reset = item['reset']
                    place(reset, end-reset['w'], y+29, (end-detail_width, y, end, y+row_height))
            y += row_height+row_gap
    # Actual ink boxes must stay disjoint from one another and the quiet mark.
    for index, a in enumerate(boxes):
        for b in boxes[index+1:]:
            assert a[2] <= b[0]+0.01 or b[2] <= a[0]+0.01 or a[3] <= b[1]+0.01 or b[3] <= a[1]+0.01, 'review ink collision'
    svg.append('</svg>')
    frames.append({'file': frame['file'], 'svg': '\n'.join(svg)+'\n', 'png': encoded(canvas),
        'picker': encoded(canvas.resize((width*2, height*2), Image.Resampling.LANCZOS)) if frame['file'] in ('widget-medium.svg', 'widget-dark.svg') else None})
print(json.dumps(frames))
`
  const { stdout, stderr } = await runFile('python3', ['-B', '-c', renderer, JSON.stringify({
    fonts, rows: REVIEW_ROWS, variants,
    mark: join(resDir, 'drawable/wardpulse_mono.png'),
  })], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
  assert.equal(stderr.trim(), '', 'default review rendering must not hide font/image warnings')
  const frames = JSON.parse(stdout)
  const checking = process.argv.includes('--check')
  for (const frame of frames) {
    await emit(join(designDir, frame.file), frame.svg, 'render-designs')
    if (!checking) {
      await writeFile(join(designDir, frame.file.replace('.svg', '.png')), Buffer.from(frame.png, 'base64'))
      if (frame.picker) {
        const variant = frame.file === 'widget-dark.svg' ? 'drawable-night-nodpi' : 'drawable-nodpi'
        await mkdir(join(resDir, variant), { recursive: true })
        await writeFile(join(resDir, variant, 'ward_pulse_widget_preview_image.png'), Buffer.from(frame.picker, 'base64'))
      }
    }
  }
  await emit(join(resDir, 'layout/ward_pulse_app_widget_preview.xml'), `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tools/render-phone-widget-designs.mjs; illustrative picker art. -->
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:contentDescription="@string/ward_pulse_widget_preview_description">
    <ImageView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:src="@drawable/ward_pulse_widget_preview_image"
        android:scaleType="fitCenter"
        android:importantForAccessibility="no"
        android:contentDescription="@null" />
</FrameLayout>
`, 'render-designs')
  const stringsPath = join(resDir, 'values/strings_widget.xml')
  const strings = await readFile(stringsPath, 'utf8')
  const description = 'Widget preview. Illustrative example only. ' + REVIEW_ROWS.map((row) =>
    `${row.family}, ${row.pool}, ${row.percent} remaining` +
    (row.credits ? `, ${row.credits} purchased credits` : '') +
    (row.reset ? `, ${row.reset}` : '')).join('. ') + '.'
  const pattern = /<string name="ward_pulse_widget_preview_description"[^>]*>[^<]*<\/string>/
  assert.ok(pattern.test(strings), 'picker accessibility description must retain its owning resource')
  await emit(stringsPath, strings.replace(pattern,
    `<string name="ward_pulse_widget_preview_description" formatted="false">${description}</string>`), 'render-designs')
}

/** One mixed-source illustrative selection, not a matched provider/native snapshot. */
const OWN_FONT_ROWS = [
  { id: 'allowance.cursor.cursor-plan-other', family: 'Cursor', pool: 'Other Models',
    percent: '64%', color: FAMILY.cursor, valueSource: 'Root illustration',
    resetsAt: '2026-11-13T12:00:00Z' },
  { id: 'allowance.codex.codex-secondary', family: 'Codex', pool: 'Weekly plan',
    percent: '85%', credits: '59.5K', color: FAMILY.codex, valueSource: 'Historical owner photo',
    resetsAt: '2026-11-04T12:00:00Z' },
  { id: 'allowance.claude.claude-seven-day-opus', family: 'Claude', pool: 'Weekly Opus',
    percent: '88%', color: FAMILY.claude, valueSource: 'Claude OAuth fixture: 12% utilized',
    resetsAt: '2026-11-07T12:00:00Z' },
  { id: 'allowance.claude.claude-five-hour', family: 'Claude', pool: '5-hour session',
    percent: '100%', color: FAMILY.claude, valueSource: 'Historical owner photo',
    resetsAt: '2026-11-01T14:00:00Z' },
  { id: 'allowance.claude.claude-seven-day', family: 'Claude', pool: 'Weekly plan',
    percent: '100%', color: FAMILY.claude, valueSource: 'Historical owner photo',
    resetsAt: '2026-11-07T12:00:00Z' },
  { id: 'allowance.cursor.cursor-plan-models', family: 'Cursor', pool: 'Models',
    percent: '100%', color: FAMILY.cursorOwn, valueSource: 'Root illustration',
    resetsAt: '2026-11-13T12:00:00Z' },
]

// Exact approved binaries shared by bundled defaults and the historical proposal route.
const OWN_FONT_HASHES = {
  regular: '89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d',
  bold: 'e83493c945848ecd4a9ad0f6d19164541a0d3e23a9c952304a00a46e00272ac5',
}
const PHOTO = 'LOCAL_ARTIFACTS/backlog-2026-10-24-screenshots/phone-widget-truncated-columns.png'
const PHOTO_HASH = 'cb24a7b1eb3be4d38e8f368f4f9aa3cdd7a620fdc55bd3f58fe35ec4fc4ba9bf'
const HOST_FRAME = 'LOCAL_ARTIFACTS/phone-widget-host-frame-2026-11-01/CURRENT_LAUNCHER_FRAME.json'
const WIDGET_BRIEF = 'LOCAL_ARTIFACTS/phone-widget-label-reset-refinement-2026-11-01/DESIGN_BRIEF.md'
const CLAUDE_FIXTURE = 'fixtures/providers/claude/oauth_usage.json'
const OWN_FONT_AS_OF = '2026-11-01T12:00:00Z'

const RESPONSIVE_INPUT_DIR = 'LOCAL_ARTIFACTS/widget-private-preview-authoring-2026-11-03/inputs'
const RESPONSIVE_INPUTS = Object.fromEntries(Object.entries({
  'DESIGN_PREPARATION.md': '845b27b9b1782c98af6f0b581d58a69e34f0711f8e01003d21df7d3ea1917391',
  'NATIVE_STALE_HEADER_ADDENDUM.md': 'd9568fb18d9312151ed02d95a49aaa7e441e3b3fea97582d8425027be67202d0',
  'CURRENT_WIDGET_RESETS.json': 'eb1e7c0bd9741c4dcde387c4f8f19f4ae90d19b31bece8e81993ae5f6d0933d0',
  'CURRENT_WIDGET_GEOMETRY.json': '43f219cc3a3cfb03dfdce5658e0d76be3b4e3ac1970579283e795cd00ec0db4c',
  'AFTER_HOME_SETTLED.private.png': '519f5d9de4dc18f477d444f2ca53e26eedd3bacbd5f002710a6da875492beb7a',
  'AFTER_EDITOR_BACK_IMMEDIATE.private.png': '1cea22344abf412d2a2c56aa0a9031931f5a59b050e051002c250adbb67cff34',
}).map(([file, sha256]) => [`${RESPONSIVE_INPUT_DIR}/${file}`, sha256]))
const RESPONSIVE_MONEY = { currency: 'USD', spentMinor: 1234, limitMinor: 1_000_000 }
const RESPONSIVE_REMAINING = (RESPONSIVE_MONEY.limitMinor - RESPONSIVE_MONEY.spentMinor) * 100 /
  RESPONSIVE_MONEY.limitMinor
// Generator-local illustration only. These rows never replace the shared/runtime catalogue.
const RESPONSIVE_ROWS = [
  { id: 'allowance.codex.codex-secondary', family: 'Codex', pool: 'Weekly plan',
    percent: '0%', credits: '42.6K', color: FAMILY.codex, resetsAt: '2026-11-06T07:25:19.000Z' },
  { id: 'allowance.cursor.cursor-plan-other', family: 'Cursor', pool: 'Other Models',
    percent: '64%', color: FAMILY.cursor, resetsAt: '2026-11-18T18:52:15.000Z' },
  { id: 'allowance.claude.claude-seven-day', family: 'Claude', pool: 'Weekly plan',
    percent: '66%', color: FAMILY.claude, resetsAt: '2026-11-08T08:00:00.000Z' },
  { id: 'allowance.claude.claude-seven-day-fable', family: 'Claude', pool: 'Fable weekly',
    percent: '100%', color: '#FF603D', resetsAt: '2026-11-08T08:00:00.000Z' },
  { id: 'allowance.cursor.cursor-plan-models', family: 'Cursor', pool: 'Models',
    percent: '100%', color: FAMILY.cursorOwn, resetsAt: '2026-11-18T18:52:15.000Z' },
  { id: 'budget.openai.today', family: 'OpenAI', pool: 'Today',
    percent: `${Math.round(RESPONSIVE_REMAINING)}%`, color: FAMILY.codex, money: RESPONSIVE_MONEY,
    sourceFamily: 'OpenAI platform' },
].map((row) => ({ ...row,
  valueSource: row.money ? 'Synthetic money; rounded percentage also matches the historical sample' :
    `${RESPONSIVE_INPUT_DIR}/AFTER_HOME_SETTLED.private.png`,
  resetSource: row.resetsAt ? `${RESPONSIVE_INPUT_DIR}/CURRENT_WIDGET_RESETS.json` : null,
}))

function parseOwnFontPreview(args) {
  if (args.length === 0 || (args.length === 1 && args[0] === '--check')) return null
  const flags = ['--own-font-preview-output', '--own-font-regular', '--own-font-bold']
  const profileFlag = '--own-font-preview-profile'
  const values = new Map()
  for (let index = 0; index < args.length; index += 2) {
    const flag = args[index]
    const value = args[index + 1]
    if ((!flags.includes(flag) && flag !== profileFlag) || values.has(flag) || !value || value.startsWith('--')) {
      throw new Error('use all three own-font preview flags exactly once, with one optional profile and without --check or other flags')
    }
    values.set(flag, value)
  }
  assert.ok(flags.every((flag) => values.has(flag)), 'own-font preview requires an output directory and both font files')
  const profile = values.get(profileFlag)
  assert.ok(profile === undefined || profile === 'responsive-six', 'unknown own-font preview profile')
  return {
    profile,
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
  const responsive = options.profile === 'responsive-six'
  const scale = responsive ? 2.625 : 1
  const horizontal = (value) => Math.round(value * scale)
  const vertical = (value) => responsive ? Math.ceil(value * scale) : value
  const rows = responsive ? RESPONSIVE_ROWS : OWN_FONT_ROWS
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
  const host = JSON.parse(await readFile(join(root, HOST_FRAME), 'utf8'))
  const hostViews = host.hostViews.filter(({ ownWardPulseDescendant }) => ownWardPulseDescendant)
  assert.equal(hostViews.length, 1, 'the recorded widget host must be unique')
  const roots = hostViews[0].ownNodes.filter((node) => node['resource-id'] === 'app.wardpulse:id/widget_root')
  assert.equal(roots.length, 1, 'the recorded widget root must be unique')
  assert.equal(roots[0].bounds, hostViews[0].bounds, 'root and launcher allocation must agree')
  const allocation = /^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/.exec(roots[0].bounds)
  assert.ok(allocation && host.pxPerDp > 0, 'recorded allocation and density must be measurable')
  const [, left, top, right, bottom] = allocation.map(Number)
  const measuredAllocation = { width: (right - left) / host.pxPerDp, height: (bottom - top) / host.pxPerDp }
  assert.equal(Math.round(measuredAllocation.width), 360, 'main width is a nominal rounding of the recorded host')
  assert.equal(measuredAllocation.height, 344, 'main height follows the recorded host')
  const hostPng = join(dirname(HOST_FRAME), host.png)
  assert.equal(await hashFile(join(root, hostPng)), host.pngSha256, 'native reference PNG identity must match')
  const claude = JSON.parse(await readFile(join(root, CLAUDE_FIXTURE), 'utf8'))
  assert.equal(`${100 - claude.seven_day_opus.utilization}%`, OWN_FONT_ROWS[2].percent,
    'illustrative Opus remaining must match the cited fixture')
  if (responsive) {
    for (const [path, expected] of Object.entries(RESPONSIVE_INPUTS)) {
      assert.equal(await hashFile(join(root, path)), expected, `responsive reference identity must match: ${path}`)
    }
    const resets = JSON.parse(await readFile(join(root, RESPONSIVE_INPUT_DIR, 'CURRENT_WIDGET_RESETS.json'), 'utf8'))
    assert.equal(resets.rows.length, rows.length, 'frozen reset projection must retain six independent rows')
    for (const [index, row] of rows.entries()) {
      const source = resets.rows[index]
      assert.equal(source.family, row.sourceFamily ?? row.family)
      assert.equal(source.pool, row.pool)
      assert.equal(source.resetIso, row.resetsAt ?? null)
      assert.equal(source.creditsPresent, Boolean(row.credits))
    }
  }
  const directory = await ownFontDirectory(options.output)
  const convert = await previewExecutable('convert')
  const node = await realpath(process.execPath)
  const { stdout: imageMagickVersion, stderr: versionWarnings } = await runFile(convert, ['-version'], { encoding: 'utf8' })
  if (responsive) assert.equal(versionWarnings.trim(), '', 'ImageMagick version warnings must not be silently accepted')
  const toolIdentities = async () => ({
    node: { executable: node, version: process.version, sha256: await hashFile(node) },
    imageMagick: { executable: convert, version: imageMagickVersion.trim(), sha256: await hashFile(convert) },
  })
  const toolsBefore = responsive ? await toolIdentities() : null
  const watermarkPath = 'apps/phone_flutter/android/app/src/main/res/drawable/wardpulse_mono.png'
  const protectedPaths = [
    ...variants.flatMap(({ file }) => [file, file.replace('.svg', '.png')]
      .map((name) => relative(root, join(designDir, name)))),
    ...['drawable-nodpi/ward_pulse_widget_preview_image.png',
      'drawable-night-nodpi/ward_pulse_widget_preview_image.png', 'values/strings_widget.xml']
      .map((path) => relative(root, join(resDir, path))),
    'apps/phone_flutter/android/app/src/main/kotlin/app/wardpulse/PhoneWidgetRenderer.kt',
    ...['NotoSans-Regular.ttf', 'NotoSans-Bold.ttf', 'OFL.txt'].map((name) =>
      `apps/phone_flutter/android/app/src/main/assets/fonts/${name}`),
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
  const inputHashes = await hashes(['tools/render-phone-widget-designs.mjs', 'docs/DESIGN_ASSETS.md',
    PHOTO, HOST_FRAME, hostPng, WIDGET_BRIEF, CLAUDE_FIXTURE, 'core/ward-pulse-providers/src/claude/mod.rs',
    ...(responsive ? Object.keys(RESPONSIVE_INPUTS) : [])])

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
  const measurements = []
  const requireFit = (condition, claim, dimensions) => {
    if (!condition) {
      const error = new Error(`${claim}: ${JSON.stringify(dimensions)}`)
      error.fit = { claim, dimensions }
      throw error
    }
  }
  const alphaInk = async (file) => {
    const bounds = (await image([file, '-alpha', 'extract', '-threshold', '0', '-format', '%@', 'info:'])).toString()
    const match = /^(\d+)x(\d+)\+(\d+)\+(\d+)$/.exec(bounds)
    assert.ok(match, 'raster alpha must have measurable ink')
    const [, width, height, x, y] = match.map(Number)
    return { x, y, width, height }
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
        const argumentsBeforeTrim = ['-background', 'none', '-density', '72', '-font', fonts[weight].path,
          '-pointsize', String(size * scale), '-fill', color, `label:${literal}`]
        let line
        if (responsive) {
          // Retain the complete label line before trimming; STALE fitting and painting
          // must share this padded line and its measured visible-ink offset.
          await image([...argumentsBeforeTrim, '-strip', `png32:${file}`])
          line = { ...pngSize(await readFile(file)), ink: await alphaInk(file) }
          await image([file, '-trim', '+repage', '-strip', `png32:${file}`])
        } else {
          await image([...argumentsBeforeTrim, '-trim', '+repage', '-strip', `png32:${file}`])
        }
        glyphs.set(key, { file, text: value, size, weight: fonts[weight].weight,
          ...pngSize(await readFile(file)), ...(responsive ? { line } : {}) })
      }
      return glyphs.get(key)
    }
    const boardSize = responsive ? { width: horizontal(1152), height: vertical(1140) } : { width: 488, height: 792 }
    const drawing = ['-size', `${boardSize.width}x${boardSize.height}`, 'xc:#080C0A']
    const composite = (file, x, y) => drawing.push(file, '-geometry', `+${Math.round(x)}+${Math.round(y)}`, '-composite')
    const captions = []
    const caption = async (value, y, center, size = 12, weight = 'regular') => {
      const ink = await text(value, size, weight, dark.muted)
      const box = { x: Math.round(center - ink.width / 2), y, width: ink.width, height: ink.height }
      const fits = box.x >= horizontal(24) && box.x + box.width <= boardSize.width - horizontal(24) &&
        box.y >= 0 && box.y + box.height <= boardSize.height
      if (responsive) requireFit(fits, 'complete caption must fit the board', { text: value, box, boardSize })
      else assert.ok(fits, 'complete captions must fit the board')
      composite(ink.file, box.x, box.y)
      captions.push({ text: value, size, weight: ink.weight, box })
    }
    if (responsive) {
      await caption('PRIVATE · UNAPPROVED · RESPONSIVE-SIX', vertical(20), boardSize.width / 2, 16, 'bold')
      await caption('Retained historical plan values + measured reset instants · explicitly displayed in UTC',
        vertical(48), boardSize.width / 2)
      await caption('Synthetic USD 12.34 spent / USD 10,000.00 cap · 99.8766% remaining, rounded 100%',
        vertical(70), boardSize.width / 2)
      await caption('2.625 px per preview unit · host art only · no Android Paint/native/font-independence acceptance',
        vertical(92), boardSize.width / 2, 11)
    } else {
      await caption('UNAPPROVED · OWN-FONT PROPOSAL', 20, boardSize.width / 2, 13, 'bold')
      await caption('Mixed-source illustration · not current native data', 42, boardSize.width / 2)
      await caption('Fixed reference: 01 Nov 2026 12:00 UTC', 62, boardSize.width / 2, 11)
    }

    const marks = new Map()
    const watermark = async (theme) => {
      if (!marks.has(theme)) {
        const file = join(work, responsive ? `watermark-${marks.size}.png` : 'watermark.png')
        const tint = responsive ? argb(theme.watermark) : { color: dark.muted, opacity: 0.55 }
        const size = horizontal(36)
        await image([join(root, watermarkPath), '-resize', `${size}x${size}`, '-fill', tint.color, '-colorize', '100',
          '-channel', 'A', '-evaluate', 'multiply', String(tint.opacity), '+channel', '-trim', '+repage', '-strip', `png32:${file}`])
        marks.set(theme, { file, ...await alphaInk(file) })
      }
      return marks.get(theme)
    }
    const frames = responsive ? [
      { name: 'Light main', width: 360, height: 344, x: 24, y: 124, columns: 3, rows: 6,
        cardWidth: 360, theme: 'light', captionY: 484 },
      { name: 'Dark main', width: 360, height: 344, x: 396, y: 124, columns: 3, rows: 6,
        cardWidth: 360, theme: 'dark', captionY: 484 },
      { name: 'Light STALE', width: 360, height: 344, x: 768, y: 124, columns: 3, rows: 6,
        cardWidth: 360, theme: 'light', stale: true, captionY: 484 },
      { name: 'Illustrative tall host', width: 360, height: 480, x: 24, y: 548, columns: 3, rows: 6,
        cardWidth: 360, theme: 'light', captionY: 1044 },
      { name: 'No detail column', width: 266, height: 184, x: 456, y: 548, columns: 2, rows: 3,
        cardWidth: 242, theme: 'light', captionY: 748 },
      { name: 'Percent only', width: 150, height: 184, x: 820, y: 548, columns: 1, rows: 3,
        cardWidth: 128, theme: 'light', captionY: 748 },
    ].map((nominal) => ({ ...nominal, nominal,
      width: horizontal(nominal.width), height: vertical(nominal.height),
      x: horizontal(nominal.x), y: vertical(nominal.y), captionY: vertical(nominal.captionY) })) : [
      { width: 360, height: 344, x: 64, y: 88, columns: 3, rows: 6, captionY: 448 },
      { width: 266, height: 184, x: 24, y: 504, columns: 2, rows: 3, captionY: 704 },
      { width: 150, height: 184, x: 314, y: 504, columns: 1, rows: 3, captionY: 704 },
    ]
    const extent = (boxes) => ({ left: Math.min(...boxes.map(({ x }) => x)),
      right: Math.max(...boxes.map(({ x, width }) => x + width)),
      top: Math.min(...boxes.map(({ y }) => y)),
      bottom: Math.max(...boxes.map(({ y, height }) => y + height)) })
    const separation = (a, b) => ({ horizontal: Math.max(a.x - b.x - b.width, b.x - a.x - a.width),
      vertical: Math.max(a.y - b.y - b.height, b.y - a.y - a.height) })
    const roundedClearance = (box, card, radius) => {
      // Signed distance at all four corners proves the complete box is inside the
      // convex rounded fill, using the same 0.5px inset as its painted path.
      const corners = [box.x, box.x + box.width].flatMap((px) => [box.y, box.y + box.height].map((py) => {
        const dx = Math.abs(px - card.x - card.width / 2) - card.width / 2 + 0.5 + radius
        const dy = Math.abs(py - card.y - card.height / 2) - card.height / 2 + 0.5 + radius
        return radius - Math.hypot(Math.max(dx, 0), Math.max(dy, 0)) - Math.min(Math.max(dx, dy), 0)
      }))
      return { left: box.x - card.x, right: card.x + card.width - box.x - box.width,
        top: box.y - card.y, bottom: card.y + card.height - box.y - box.height,
        roundedEdge: Math.min(...corners) }
    }
    const checkerFields = new Map()
    const checker = async (width, height) => {
      const key = `${width}x${height}`
      if (!checkerFields.has(key)) {
        const tile = join(work, 'checker-tile.png')
        if (checkerFields.size === 0) {
          const side = horizontal(16)
          const half = Math.floor(side / 2)
          await image(['-size', `${side}x${side}`, 'xc:#CCD2CE', '-fill', '#E0E5E1', '-draw',
            `rectangle 0,0 ${half - 1},${half - 1} rectangle ${half},${half} ${side - 1},${side - 1}`,
            '-strip', `png32:${tile}`])
        }
        const file = join(work, `checker-${key}.png`)
        await image(['-size', key, `tile:${tile}`, '-strip', `png32:${file}`])
        checkerFields.set(key, file)
      }
      return checkerFields.get(key)
    }
    for (const frame of frames) {
      const { x, y, width, height, columns } = frame
      const theme = responsive && frame.theme === 'light' ? light : dark
      const rowHeight = vertical(44)
      const rowGap = vertical(8)
      const contentHeight = frame.rows * rowHeight + (frame.rows - 1) * rowGap
      const headerHeight = vertical(19)
      const cardLeft = responsive ? (frame.nominal.width - frame.cardWidth) / 2 : 0
      const card = responsive ? { x: horizontal(cardLeft), y: Math.floor((height - headerHeight - contentHeight - vertical(16)) / 2),
        width: horizontal(cardLeft + frame.cardWidth) - horizontal(cardLeft),
        height: headerHeight + contentHeight + vertical(16) } : { x: 0, y: 0, width, height }
      const radius = horizontal(20)
      const marginY = responsive ? card.y + headerHeight : (height - contentHeight) / 2
      const groupUnits = columns === 3 ? 328 : columns === 2 ? (responsive ? 210 : 222) : (responsive ? 96 : 89)
      const groupOrigin = ((frame.nominal?.width ?? width) - groupUnits) / 2
      const groupLeft = responsive ? horizontal(groupOrigin) : groupOrigin
      const groupWidth = responsive ? horizontal(groupOrigin + groupUnits) - groupLeft : groupUnits
      // Round each horizontal boundary once; independent rounded column widths can drift.
      const percentColumn = responsive ? { left: horizontal(groupOrigin + 12), right: horizontal(groupOrigin + 96) } :
        { left: (width - groupWidth) / 2 + 12, right: (width - groupWidth) / 2 + 89 }
      const labelColumn = columns >= 2 ? (responsive ?
        { left: horizontal(groupOrigin + 102), right: horizontal(groupOrigin + 210) } :
        { left: (width - groupWidth) / 2 + 95, right: (width - groupWidth) / 2 + 222 }) : null
      const detailColumn = columns === 3 ? (responsive ?
        { left: horizontal(groupOrigin + 216), right: horizontal(groupOrigin + 328) } :
        { left: (width - groupWidth) / 2 + 228, right: (width - groupWidth) / 2 + 328 }) : null
      const outline = theme.outlineColor.match(/\w\w/g).map((part) => parseInt(part, 16))
      if (responsive) {
        requireFit(card.x >= 0 && card.y >= 0 && card.x + card.width <= width && card.y + card.height <= height,
          'intrinsic card must fit its host', { frame: frame.nominal, card, contentHeight, headerHeight })
        composite(await checker(width, height), x, y)
      }
      drawing.push('-fill', theme.surface, '-stroke', `rgba(${outline.join(',')},${theme.outlineOpacity})`,
        '-strokewidth', '1', '-draw',
        `roundrectangle ${x + card.x + 0.5},${y + card.y + 0.5} ${x + card.x + card.width - 0.5},${y + card.y + card.height - 0.5} ${radius},${radius}`)
      if (responsive) drawing.push('-fill', 'none', '-stroke', 'rgba(95,103,92,0.35)', '-draw',
        `rectangle ${x + 0.5},${y + 0.5} ${x + width - 0.5},${y + height - 0.5}`)
      const mark = await watermark(theme)
      const markInk = { x: card.x + card.width - horizontal(16) - mark.width, y: card.y + vertical(2),
        width: mark.width, height: mark.height }
      let header
      if (responsive) {
        header = { bounds: { x: card.x, y: card.y, width: card.width, height: headerHeight },
          firstRowTop: marginY, mark: { box: markInk, clearance: roundedClearance(markInk, card, radius),
            firstRowGap: marginY - markInk.y - markInk.height } }
        requireFit(header.mark.clearance.roundedEdge >= 0 && header.mark.firstRowGap >= 0,
          'quiet mark must fit the shared header and rounded card', { frame: frame.nominal, card, header })
        if (frame.stale) {
          const glyph = await text('STALE', 11, 'bold', theme.stale)
          const line = { x: card.x + horizontal(16), y: card.y + Math.floor((headerHeight - glyph.line.height) / 2),
            width: glyph.line.width, height: glyph.line.height }
          const visible = { x: line.x + glyph.line.ink.x, y: line.y + glyph.line.ink.y,
            width: glyph.width, height: glyph.height }
          header.stale = { text: 'STALE', size: 11, weight: 700, color: theme.stale, line, ink: visible,
            lineClearance: roundedClearance(line, card, radius), inkClearance: roundedClearance(visible, card, radius),
            markSeparation: separation(line, markInk), visibleMarkSeparation: separation(visible, markInk),
            firstRowGap: marginY - line.y - line.height, visibleFirstRowGap: marginY - visible.y - visible.height }
          const stale = header.stale
          requireFit(stale.line.y >= header.bounds.y && stale.firstRowGap >= 0 && stale.visibleFirstRowGap > 0 &&
            stale.lineClearance.roundedEdge >= 0 && stale.inkClearance.roundedEdge >= 0 &&
            (stale.markSeparation.horizontal >= 0 || stale.markSeparation.vertical >= 0),
            'complete padded STALE line and ink must fit the unchanged compact header', { frame: frame.nominal, card, header })
          // Paint the very boxes that were measured above, including the padded-line ink offset.
          composite(glyph.file, x + stale.ink.x, y + stale.ink.y)
        }
      }
      composite(mark.file, x + markInk.x - mark.x, y + markInk.y - mark.y)
      assert.ok(markInk.x >= 0 && markInk.y >= 0 && markInk.x + mark.width <= width &&
        markInk.y + mark.height <= height, 'watermark overlay ink must stay inside its frame')
      assert.ok(marginY >= vertical(16) && groupLeft >= horizontal(16),
        'complete centered row/column groups must retain content margins')
      const ink = []
      const place = (glyph, left, top, bounds, row, kind) => {
        const box = { x: Math.round(left), y: Math.round(top), width: glyph.width, height: glyph.height }
        const clearance = { left: box.x - bounds.left, right: bounds.right - box.x - box.width,
          top: box.y - bounds.top, bottom: bounds.bottom - box.y - box.height }
        const fits = Object.values(clearance).every((gap) => gap >= 0)
        if (responsive) requireFit(fits, 'complete string ink must fit its column/row',
          { frame: frame.nominal, row, kind, text: glyph.text, box, bounds, clearance, line: glyph.line })
        else assert.ok(fits, `complete ${glyph.text} ink must fit its column/row`)
        composite(glyph.file, x + box.x, y + box.y)
        ink.push({ row, kind, text: glyph.text, size: glyph.size, weight: glyph.weight, box, bounds, clearance })
        return box
      }
      const rowBlocks = []
      for (const [index, entry] of rows.slice(0, frame.rows).entries()) {
        const top = marginY + index * (rowHeight + rowGap)
        drawing.push('-stroke', 'none', '-fill', entry.color, '-draw',
          `roundrectangle ${x + Math.round(groupLeft)},${y + top} ${x + Math.round(groupLeft) + horizontal(3) - 1},${y + top + rowHeight - 1} ${1.5 * scale},${1.5 * scale}`)
        const bounds = { top, bottom: top + rowHeight }
        const percent = await text(entry.percent, 30, 'bold', theme.onSurface)
        const percentBox = place(percent, Math.floor(percentColumn.right) - percent.width,
          top + (rowHeight - percent.height) / 2, { ...bounds, ...percentColumn }, index, 'percent')
        const labelBoxes = []
        if (labelColumn) {
          const center = (labelColumn.left + labelColumn.right) / 2
          const pool = await text(entry.pool, entry.family ? 16 : 18, entry.family ? 'regular' : 'bold',
            entry.family ? theme.muted : theme.onSurface)
          if (entry.family) {
            const family = await text(entry.family, 18, 'bold', theme.onSurface)
            const familyTop = top + (rowHeight - family.height - pool.height - vertical(4)) / 2
            labelBoxes.push(place(family, center - family.width / 2, familyTop,
              { ...bounds, ...labelColumn }, index, 'family'))
            labelBoxes.push(place(pool, center - pool.width / 2, familyTop + family.height + vertical(4),
              { ...bounds, ...labelColumn }, index, 'pool'))
          } else {
            labelBoxes.push(place(pool, center - pool.width / 2, top + (rowHeight - pool.height) / 2,
              { ...bounds, ...labelColumn }, index, 'pool'))
          }
        }
        const detailBoxes = []
        if (detailColumn) {
          const money = (minor) => `${entry.money.currency} ${(minor / 100).toLocaleString('en-US',
            { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
          const credits = entry.money ? await text(money(entry.money.spentMinor), 18, 'bold', theme.onSurface) :
            entry.credits ? await text(entry.credits, 26, 'bold', theme.onSurface) : null
          let reset = null
          if (entry.resetsAt) {
            const instant = new Date(entry.resetsAt)
            const month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][instant.getUTCMonth()]
            const day = String(instant.getUTCDate()).padStart(2, '0')
            const time = `${String(instant.getUTCHours()).padStart(2, '0')}:${String(instant.getUTCMinutes()).padStart(2, '0')}`
            reset = await text(`Reset ${day} ${month} ${time}`, 11, 'regular', theme.muted)
          }
          if (entry.money) reset = await text(`/ ${money(entry.money.limitMinor)}`, 11, 'regular', theme.muted)
          const detailHeight = (credits?.height ?? 0) + (reset?.height ?? 0) + (credits && reset ? vertical(3) : 0)
          let detailTop = responsive && credits && reset ? top + vertical(29) - vertical(3) - credits.height :
            top + (rowHeight - detailHeight) / 2
          for (const [kind, glyph] of [[entry.money ? 'budgetSpent' : 'purchasedBalance', credits],
            [entry.money ? 'budgetLimit' : 'reset', reset]]) {
            if (!glyph) continue
            if (kind === 'reset' || kind === 'budgetLimit') detailTop = top + vertical(29)
            detailBoxes.push(place(glyph, detailColumn.right - glyph.width, detailTop,
              { ...bounds, ...detailColumn }, index, kind))
            detailTop += glyph.height + vertical(3)
          }
        }
        const rowInk = ink.filter(({ row }) => row === index).map(({ box }) => box)
        const previous = rowBlocks.at(-1)
        const actualInk = extent(rowInk)
        rowBlocks.push({ id: entry.id, top, bottom: top + rowHeight, family: entry.family, pool: entry.pool,
          accent: { x: Math.round(groupLeft), y: top, width: horizontal(3), height: rowHeight },
          inkBounds: actualInk,
          inkGaps: { percentToLabel: labelBoxes.length ? extent(labelBoxes).left - percentBox.x - percentBox.width : null,
            labelToDetail: detailBoxes.length && labelBoxes.length ? extent(detailBoxes).left - extent(labelBoxes).right : null,
            familyToPool: labelBoxes.length === 2 ? labelBoxes[1].y - labelBoxes[0].y - labelBoxes[0].height : null,
            balanceToReset: detailBoxes.length === 2 ? detailBoxes[1].y - detailBoxes[0].y - detailBoxes[0].height : null,
            fromPreviousRow: previous ? actualInk.top - previous.inkBounds.bottom : null } })
      }
      const boxes = ink.map(({ box }) => box)
      if (responsive) {
        header.firstRowInkTop = rowBlocks[0].inkBounds.top
        if (header.stale) header.stale.firstRowInkGap = header.firstRowInkTop - header.stale.ink.y - header.stale.ink.height
      }
      for (const [index, box] of boxes.entries()) {
        if (responsive) {
          const clearance = roundedClearance(box, card, radius)
          requireFit(clearance.left >= horizontal(16) && clearance.right >= horizontal(16) &&
            clearance.bottom >= vertical(16) && clearance.roundedEdge >= 0,
            'all complete row ink must retain card padding', { frame: frame.nominal, card, box, clearance })
        } else {
          assert.ok(box.x >= 16 && box.y >= 16 && box.x + box.width <= width - 16 &&
            box.y + box.height <= height - 16, 'all actual ink must retain inner padding')
        }
        for (const other of [...boxes.slice(index + 1), markInk, ...(header?.stale ? [header.stale.ink] : [])]) {
          const gap = separation(box, other)
          if (responsive) requireFit(gap.horizontal >= 0 || gap.vertical >= 0,
            'text and decoration ink must not overlap', { frame: frame.nominal, box, other, gap })
          else assert.ok(gap.horizontal >= 0 || gap.vertical >= 0, 'text/watermark ink must not overlap')
        }
      }
      const description = responsive ?
        `${columns === 3 ? `${frame.name} · ` : ''}${frame.nominal.width} × ${frame.nominal.height} · ${frame.rows} rows${columns === 1 ? ' · % only' : ''}` :
        `${width} × ${height} · ${columns === 1 ? '% only' : `${columns} columns`} / ${frame.rows} rows${columns === 3 ? ' · nominal' : ''}`
      await caption(description, frame.captionY, x + width / 2, 11)
      measurements.push({ ...frame, padding: horizontal(16), rowHeight, rowGap, marginY, groupLeft, groupWidth,
        columnBounds: { percent: percentColumn, label: labelColumn, rightDetail: detailColumn },
        ...(responsive ? { card, radius, contentHeight, header,
          exterior: 'Transparent proposed exterior, composited over a review-only checker; full-host outline is review chrome.',
          nominalGeometry: { host: { width: frame.nominal.width, height: frame.nominal.height },
            card: { width: frame.cardWidth, height: 19 + frame.rows * 44 + (frame.rows - 1) * 8 + 16 },
            rowHeight: 44, rowGap: 8, headerHeight: 19, bottomPadding: 16, gridWidth: groupUnits },
        } : {}),
        rowBlocks, ink, watermarkInk: markInk,
        watermarkClearances: ink.map(({ row, kind, box }) => ({ row, kind, ...separation(box, markInk) })) })
    }
    if (responsive) {
      await caption(`Historical measured host ${measuredAllocation.width.toFixed(3)} × 344 dp · 480 height is illustrative · checker shows proposed transparency`,
        vertical(1092), boardSize.width / 2, 11)
      await caption('PRIVATE preview · exact-image Owner approval required before runtime/canonical/baseline adoption',
        vertical(1114), boardSize.width / 2, 11)
    } else {
      await caption(`Measured host ${measuredAllocation.width.toFixed(3)} × 344 dp · old layout unchanged`, 468, boardSize.width / 2, 11)
      await caption('Optional absolute resets · UTC · not implemented', 736, boardSize.width / 2, 11)
      await caption('Host art only · approval pending', 756, boardSize.width / 2)
    }
    for (const [index, { box }] of captions.entries()) {
      for (const other of [...frames, ...captions.slice(index + 1).map(({ box }) => box)]) {
        const gap = separation(box, other)
        assert.ok(gap.horizontal >= 0 || gap.vertical >= 0, 'captions must remain outside frames and other captions')
      }
    }
    const png = join(directory, 'UNAPPROVED-PREVIEW-ONLY.png')
    await image([...drawing, '-strip', `png32:${png}`])
    assert.deepEqual(pngSize(await readFile(png)), boardSize, 'board must retain nominal preview dimensions')
    const decoded = (await image([png, '-format', '%w %h', 'info:'])).toString()
    assert.equal(decoded, `${boardSize.width} ${boardSize.height}`, 'completed PNG must decode')
    const protectedAfter = await hashes(protectedPaths)
    assert.deepEqual(protectedAfter, protectedBefore, 'preview must not modify protected default inputs/exports')
    const tools = await toolIdentities()
    let inputHashesAfter, fontHashesAfter
    if (responsive) {
      inputHashesAfter = await hashes(Object.keys(inputHashes))
      fontHashesAfter = Object.fromEntries(await Promise.all(Object.entries(fonts).map(async ([weight, font]) =>
        [weight, await hashFile(font.path)])))
      assert.deepEqual(inputHashesAfter, inputHashes, 'responsive source and reference inputs must stay unchanged')
      assert.deepEqual(fontHashesAfter, OWN_FONT_HASHES, 'responsive font bytes must stay pinned')
      assert.deepEqual(tools, toolsBefore, 'responsive executable identities must stay unchanged')
    }
    controller.signal.throwIfAborted()
    const metadata = {
      status: 'UNAPPROVED PREVIEW ONLY',
      evidence: 'One host-art proposal; not current native data, device fit, runtime approval or font adoption.',
      reference: { file: PHOTO, sha256: PHOTO_HASH, meaning: 'Historical owner photo; illustrative rows only.' },
      nativeReference: { file: HOST_FRAME, png: hostPng, pngSha256: host.pngSha256,
        bounds: roots[0].bounds, pxPerDp: host.pxPerDp, systemFontScale: host.systemFontScale,
        allocationDp: measuredAllocation, meaning: 'Existing old native layout; not a repair or resized-state proof.' },
      illustrativeReference: responsive ? { timezone: 'UTC',
        valueSource: `${RESPONSIVE_INPUT_DIR}/AFTER_HOME_SETTLED.private.png`,
        resetSource: `${RESPONSIVE_INPUT_DIR}/CURRENT_WIDGET_RESETS.json`,
        staleObservation: `${RESPONSIVE_INPUT_DIR}/AFTER_EDITOR_BACK_IMMEDIATE.private.png`,
        observedDeviceOffset: '+01:00; separate historical observation, not a measured timezone name or preview display zone',
        moneySource: 'Explicit synthetic USD illustration; the native widget did not carry these amounts.',
        measuredHost: '360.381 × 344 dp is historical provenance; nominal 360 width rounds to 945 preview pixels, not the measured 946 native pixels.',
        illustrativeSizes: '480 height and reduced hosts illustrate this proposal; no native resized-state acceptance.',
      } : { asOf: OWN_FONT_AS_OF, timezone: 'UTC',
        resetSource: 'Fixed proposed absolute instants from DESIGN_BRIEF.md, not photo/provider reset facts.',
        reducedSizes: '266 is a nominal historical width reference; 150 and 184 are illustrative, not resized-state acceptance.' },
      invocation: { cwd: process.cwd(), argv: [process.execPath, ...process.argv.slice(1)] },
      tools,
      units: responsive ? 'Nominal preview units at 2.625 raster pixels per unit, not Android Paint or native fit acceptance.' :
        'Nominal host preview units at 72dpi, not Android dp/sp or an adopted native sizing strategy.',
      fonts, inputHashes,
      ...(responsive ? { profile: options.profile, scale, inputHashesAfter, fontHashesAfter, toolsBefore,
        protectedBefore, protectedAfter,
        rasterization: { horizontal: 'Round each nominal boundary once.',
          vertical: 'Ceil component heights individually; center the resulting intrinsic card on integer pixels.',
          ink: 'Complete ImageMagick label alpha bounds; full untrimmed padded line additionally retained for STALE.' },
        nominalGrid: { accent: 12, percent: 84, label: 108, details: 112, gaps: [6, 6], sidePadding: 16, width: 328 },
        syntheticMoney: { ...RESPONSIVE_MONEY, remainingMinor: RESPONSIVE_MONEY.limitMinor - RESPONSIVE_MONEY.spentMinor,
          remainingPercent: RESPONSIVE_REMAINING, roundedRemainingPercent: Math.round(RESPONSIVE_REMAINING),
          calculation: '(limitMinor - spentMinor) * 100 / limitMinor; display rounds only the percentage', synthetic: true },
      } : { protectedInputsUnchanged: protectedBefore }),
      rows, theme: responsive ? { light, dark } : dark,
      typography: { percent: [30, 700], purchasedBalance: [26, 700], family: [18, 700], pool: [16, 400],
        familyContainedLabel: [18, 700], reset: [11, 400],
        ...(responsive ? { budgetSpent: [18, 700], budgetLimit: [11, 400], stale: [11, 700] } : {}) },
      measurements, captions,
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
  } catch (error) {
    if (responsive && error.fit) {
      // A failed measurement is evidence, never an implicitly adjusted or approved board.
      await writeFile(join(directory, 'UNAPPROVED-PREVIEW-ONLY.json'), `${JSON.stringify({
        status: 'FAILED PRIVATE PREVIEW FIT; no successful candidate or native acceptance',
        profile: options.profile, scale, units: 'Raster pixels at 2.625 per nominal preview unit',
        failure: error.fit, measurements, fonts, toolsBefore, inputHashes, rows, commands,
        protectedBefore, protectedAfter: await hashes(protectedPaths),
      }, null, 2)}\n`, { flag: 'wx' })
    }
    throw error
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
  await renderDefaults()
}
