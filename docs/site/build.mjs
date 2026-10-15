import { copyFile, glob, mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import react from '@vitejs/plugin-react'
import { createBuilder } from 'vite'
import { resolveConfig } from 'vocs/config'
import { vocs } from 'vocs/vite'

const config = await resolveConfig()
const publicDir = resolve(config.rootDir, config.outDir, 'public')
const emptyOpenApiModule = '\0wardpulse:empty-openapi'
const skipToContentModule = resolve(config.rootDir, 'src', 'SkipToContent.tsx')
const maxChunkBytes = 1_000_000

function publicationPath(url) {
  if (config.basePath === '/') return url

  const basePath = config.basePath.replace(/\/$/, '')
  if (url === '/index' || url === `${basePath}/index`) return `${basePath}/`
  if (!url.startsWith('/') || url.startsWith('//')) return url
  if (url === basePath || url.startsWith(`${basePath}/`)) return url
  return `${basePath}${url}`
}

async function publishLlmsNavigation(fileName) {
  if (config.basePath === '/') return

  const filePath = resolve(publicDir, fileName)
  const content = await readFile(filePath, 'utf8')
  const published = content.replace(
    /^(- \[[^\n]*\]\()([^)]+)(\)(?::[^\n]*)?)$/gm,
    (_line, opening, url, closing) =>
      `${opening}${publicationPath(url)}${closing}`,
  )

  if (published !== content) await writeFile(filePath, published)
}

async function publishMarkdownAliases() {
  if (config.basePath === '/') return

  const markdownDir = resolve(publicDir, 'assets/md')
  const markdownPaths = await Array.fromAsync(glob('**/*.md', { cwd: markdownDir }))

  await Promise.all(
    markdownPaths.map(async (markdownPath) => {
      const aliasPath = resolve(publicDir, markdownPath)
      await mkdir(dirname(aliasPath), { recursive: true })
      await copyFile(resolve(markdownDir, markdownPath), aliasPath)
    }),
  )
}

// Vocs bundles its optional OpenAPI UI even when no specification is configured.
const omitUnusedOpenApi = {
  name: 'wardpulse:omit-unused-openapi',
  enforce: 'pre',
  resolveId(source, importer) {
    if (
      source.endsWith('/react/internal/openapi/OpenApiPage.js') &&
      importer
        ?.replaceAll('\\', '/')
        .endsWith('/vocs/dist/waku/internal/patches/router.js')
    )
      return emptyOpenApiModule
  },
  load(id) {
    if (id === emptyOpenApiModule)
      return 'export const OpenApiGuide = () => null; export const OpenApiPage = () => null'
  },
}

// Vocs' native skip link needs the deployment base in its current-page href.
const replaceSkipToContent = {
  name: 'wardpulse:base-aware-skip-to-content',
  enforce: 'pre',
  resolveId(source, importer) {
    if (
      source === './internal/SkipToContent.client.js' &&
      importer
        ?.replaceAll('\\', '/')
        .endsWith('/vocs/dist/react/Layout.client.js')
    )
      return skipToContentModule
  },
}

const enforceChunkBudget = {
  name: 'wardpulse:chunk-budget',
  apply: 'build',
  generateBundle(_options, bundle) {
    const oversized = Object.values(bundle).filter(
      (output) =>
        output.type === 'chunk' &&
        Buffer.byteLength(output.code) > maxChunkBytes,
    )

    if (oversized.length)
      this.error(
        `Chunks exceed 1 MB: ${oversized.map(({ fileName }) => fileName).join(', ')}`,
      )
  },
}

const builder = await createBuilder({
  configFile: false,
  plugins: [
    react(),
    replaceSkipToContent,
    vocs(),
    ...(!config.openapi?.length ? [omitUnusedOpenApi] : []),
    enforceChunkBudget,
  ],
  build: { outDir: config.outDir },
})

await builder.buildApp()

await Promise.all([
  publishLlmsNavigation('llms.txt'),
  publishLlmsNavigation('llms-full.txt'),
  publishMarkdownAliases(),
])
