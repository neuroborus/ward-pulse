import react from '@vitejs/plugin-react'
import { createBuilder } from 'vite'
import { resolveConfig } from 'vocs/config'
import { vocs } from 'vocs/vite'

const config = await resolveConfig()
const emptyOpenApiModule = '\0wardpulse:empty-openapi'
const maxChunkBytes = 1_000_000

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
    vocs(),
    ...(!config.openapi?.length ? [omitUnusedOpenApi] : []),
    enforceChunkBudget,
  ],
  build: { outDir: config.outDir },
})

await builder.buildApp()
