import { readFile, writeFile } from 'node:fs/promises'

const checking = process.argv.includes('--check')

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
 * between runs, so equal images differ as bytes.
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
