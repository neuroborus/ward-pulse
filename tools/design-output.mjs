import { execFileSync } from 'node:child_process'
import { rmSync } from 'node:fs'
import { access, readFile, writeFile } from 'node:fs/promises'

const checking = process.argv.includes('--check')

/** SIL OFL-1.1. Bold for watch-scale labels; the boards name it and the previews bake it in. */
export const FONT_FILE = '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf'

/**
 * Write a generated design file, or — under `--check` — prove the one in the
 * tree still matches.
 *
 * Review art is read as evidence: a board that quietly drifts from its
 * generator argues for a layout nobody chose. The watch face had this guard
 * from the start; the other generators ran by hand and were trusted.
 *
 * SVG is compared byte for byte because it is text the generator wrote. PNG
 * previews are not compared here: ImageMagick stamps metadata that changes
 * between runs, so equal images differ as bytes. What stands in place of a byte
 * gate is `renderPreviews` below — every preview is rewritten from its board on
 * every render, so none of them can keep art the design has left behind.
 */
export async function emit(path, contents, recipe) {
  if (!checking) {
    await writeFile(path, contents)
    console.log(`wrote ${path}`)
    return
  }

  const current = await readFile(path, 'utf8').catch(() => null)
  if (current === contents) {
    console.log(`${path} is up to date`)
    return
  }

  const missing = current === null
  console.error(
    missing
      ? `${path} is missing; run \`just ${recipe}\``
      : `${path} differs from the generator; run \`just ${recipe}\` and review the diff`,
  )
  process.exitCode = 1
}

/**
 * Rasterize boards into the PNG previews a design document cites.
 *
 * Each preview is written from the same run that wrote its board, because a
 * preview nothing regenerates will lie: it keeps the art it was made from while
 * the design moves on, and it is read as current either way.
 *
 * Under `--check` this writes nothing and never reaches for ImageMagick, so the
 * gate stays runnable where the tool is absent.
 *
 * The board goes to `convert` as a named file, never on stdin: ImageMagick hands
 * a named SVG to a real renderer and falls back to its own on a pipe, and that
 * fallback drops the centre a `rotate()` turns about (`render-watchface.mjs`).
 * `-strip` keeps the render timestamp out of the bytes, so an image that did not
 * change does not churn the diff.
 *
 * The font check guards every caller at once: a substituted font silently
 * changes committed art, and the boards name one font. An overlay image is
 * guarded in the same place and for the same reason: missing it does not fail
 * the render in any legible way, it changes what ships, and ImageMagick's own
 * "unable to open image" names neither the generator that wanted the file nor
 * the recipe that writes it.
 *
 * A preview may name an `overlay` — an image, a box and an alpha — and then it
 * is composed rather than only rasterized. Only one does: the face's shipped
 * portrait, which carries the watermark the face draws while the review boards
 * it is rendered beside stay mark-free. The box belongs to the caller, which
 * reads it from the face rather than declaring it.
 */
export async function renderPreviews(previews) {
  if (checking) return

  await access(FONT_FILE).catch(() => {
    throw new Error(`${FONT_FILE} is missing; previews would use a substituted font`)
  })

  for (const { overlay } of previews) {
    if (!overlay) continue
    await access(overlay.image).catch(() => {
      throw new Error(`${overlay.image} is missing; run just export-icons first`)
    })
  }

  for (const { svg, png, density, overlay } of previews) {
    execFileSync('convert', [
      '-background',
      'none',
      '-density',
      String(density),
      '-strip',
      svg,
      `png32:${png}`,
    ])
    if (overlay) composeOverlay(png, overlay)
    console.log(`wrote ${png}`)
  }
}

/**
 * Lay a second image over a rendered preview at the box the caller gives.
 *
 * The mark is resized and faded in one pass into a temporary file, then
 * composed, because `-evaluate multiply` on the alpha channel has to see the
 * mark alone: run against the page it would fade the preview under it too.
 */
function composeOverlay(png, { image, x, y, width, height, alpha }) {
  const mark = `${png.replace(/\.png$/, '')}.overlay.tmp.png`
  try {
    execFileSync('convert', [
      image,
      '-resize',
      `${width}x${height}`,
      '-alpha',
      'set',
      '-channel',
      'A',
      '-evaluate',
      'multiply',
      alpha.toFixed(6),
      '+channel',
      mark,
    ])
    execFileSync('convert', [
      png,
      mark,
      '-geometry',
      `+${x}+${y}`,
      '-compose',
      'over',
      '-composite',
      '-strip',
      `png32:${png}`,
    ])
  } finally {
    rmSync(mark, { force: true })
  }
}
