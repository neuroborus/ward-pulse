import { execFile } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { promisify } from 'node:util'
import type { Program } from 'estree'
import { defineConfig } from 'vocs/config'

type MarkdownNode = {
  type: string
  name?: string | null
  attributes?: Array<{ type: string; name?: string; value?: unknown }>
  children?: MarkdownNode[]
  value?: string
  url?: string
  alt?: string
}

type MarkdownProcessor = {
  parse: (source: string) => { children: MarkdownNode[] }
}

type MarkdownFile = {
  value?: unknown
}

type HtmlNode = {
  type: string
  tagName?: string
  properties?: Record<string, unknown>
  children?: HtmlNode[]
  value?: string
}

const screenshots = [
  {
    url: '/screenshots/phone-dashboard-overview-light.png',
    alt: 'WardPulse phone Dashboard showing demo usage data in the light theme.',
    caption: 'Phone Dashboard · Usage overview',
    darkOriginalUrl: '/screenshots/phone-dashboard-overview-dark.png',
  },
  {
    url: '/screenshots/wear-glance-overview.png',
    alt: 'WardPulse Watch Glance showing selected plan capacity and purchased credits.',
    caption: 'Watch Glance · Selected plan capacity and purchased credits',
  },
  {
    url: '/screenshots/wear-watch-face.png',
    alt: 'WardPulse watch face showing remaining-capacity rings, time and upper cells.',
    caption: 'WardPulse face · Capacity rings, time and upper cells',
  },
]

const approvedScreenshot =
  /^\/screenshots\/(?:phone-(?:alert-thresholds|budget-limits|cursor-(?:paste-token|sign-in-help)|dashboard(?:-overview)?|home-widget(?:-(?:percent-only|with-label|short))?|providers|openai-reporting-key|reporting-key|watch-settings|widget-settings)-(?:light|dark)|wear-(?:glance(?:-overview)?|plan-windows|watch-face(?:-(?:one-band|two-bands|utility))?))\.png$/

const requestedBasePath = process.env.WARDPULSE_DOCS_BASE_PATH

if (
  requestedBasePath &&
  requestedBasePath !== '/wardpulse-docs' &&
  requestedBasePath !== '/ward-pulse'
)
  throw new Error(
    'WARDPULSE_DOCS_BASE_PATH must be unset, empty, "/wardpulse-docs", or "/ward-pulse".',
  )

const basePath = requestedBasePath || '/'
const basePrefix = basePath === '/' ? '' : basePath

function withBasePath(url: string) {
  if (!basePrefix || !url.startsWith('/') || url.startsWith('//')) return url
  if (url === basePrefix || url.startsWith(`${basePrefix}/`)) return url
  return `${basePrefix}${url}`
}

function hasClassName(node: MarkdownNode, className: string) {
  return (
    node.type === 'mdxJsxFlowElement' &&
    node.attributes?.some(
      (attribute) => attribute.name === 'className' && attribute.value === className,
    )
  )
}

function homepageMarkdown() {
  return (tree: { children: MarkdownNode[] }) => {
    const galleryIndex = tree.children.findIndex((node) =>
      hasClassName(node, 'wardpulse-gallery'),
    )
    const actionIndex = tree.children.findIndex((node) =>
      hasClassName(node, 'wardpulse-gallery__action'),
    )
    if (galleryIndex === -1 || actionIndex !== galleryIndex + 1) return

    const gallery = screenshots.flatMap(({ url, alt, caption, darkOriginalUrl }) => [
      {
        type: 'paragraph',
        children: [
          {
            type: 'link',
            url,
            children: [{ type: 'image', url, alt }],
          },
        ],
      },
      {
        type: 'paragraph',
        children: [
          {
            type: 'emphasis',
            children: [{ type: 'text', value: caption }],
          },
        ],
      },
      ...(darkOriginalUrl
        ? [
            {
              type: 'paragraph',
              children: [
                {
                  type: 'link',
                  url: darkOriginalUrl,
                  children: [
                    { type: 'text', value: 'View dark Phone Dashboard original' },
                  ],
                },
              ],
            },
          ]
        : []),
    ])

    tree.children.splice(galleryIndex, 2, ...gallery, {
      type: 'paragraph',
      children: [
        {
          type: 'link',
          url: '/guide/getting-started',
          children: [{ type: 'text', value: 'Get started with WardPulse →' }],
        },
      ],
    })
  }
}

function standaloneScreenshot(node: MarkdownNode | undefined) {
  if (!node || node.type !== 'paragraph' || node.children?.length !== 1) return

  const [image] = node.children
  if (image.type !== 'image' || !image.url || !approvedScreenshot.test(image.url)) return

  return image
}

function linkedScreenshot(image: MarkdownNode) {
  return {
    type: 'link',
    url: image.url,
    children: [image],
  }
}

function inlineGuideMarkdown(this: MarkdownProcessor) {
  const processor = this

  return (tree: { children: MarkdownNode[] }, file: MarkdownFile) => {
    const source = typeof file.value === 'string' ? file.value : undefined
    const isRoadmap = /^import\s+\{ Roadmap \}\s+from\s+['"]\.\.\/Roadmap['"]$/m.test(
      source ?? '',
    )
    const guideImport = source?.match(
      /^import\s+([A-Z][A-Za-z0-9_$]*)\s+from\s+['"](\.\.\/\.\.\/\.\.\/\.\.\/product\/user-guide\/[A-Z_]+\.md)['"]$/m,
    )
    if (!guideImport && !isRoadmap) return

    // React keeps the imports and supplies the image override through the component prop.
    if (tree.children.some((node) => node.type === 'mdxjsEsm')) return

    // The root wrapper may already contain expanded Markdown; replace it once for exports/search.
    if (isRoadmap) {
      const roadmap = processor.parse(
        readFileSync(resolve(import.meta.dirname, '../product/user-guide/ROADMAP.md'), 'utf8'),
      )
      tree.children.splice(0, tree.children.length, ...roadmap.children)
      return
    }

    if (!guideImport) return
    const [, componentName, importPath] = guideImport
    const guide = processor.parse(
      readFileSync(resolve(import.meta.dirname, 'src/pages/guide', importPath), 'utf8'),
    )
    const componentIndex = tree.children.findIndex(
      (node) => node.type === 'mdxJsxFlowElement' && node.name === componentName,
    )

    if (componentIndex === -1) tree.children.push(...guide.children)
    else tree.children.splice(componentIndex, 1, ...guide.children)
  }
}

const runFile = promisify(execFile)

async function committedDate(filePath: string) {
  try {
    const { stdout } = await runFile(
      'git',
      ['log', '-1', '--format=%cI', '--', filePath],
      {
        cwd: import.meta.dirname,
        encoding: 'utf8',
      },
    )
    return stdout.trim() || undefined
  } catch {
    return undefined
  }
}

function guideCommittedDates() {
  return async (tree: Program, file: { path?: string }) => {
    if (!file.path) return

    const sourcePath = resolve(file.path)
    const guideDirectory = resolve(import.meta.dirname, '../product/user-guide')
    const guides = tree.body.flatMap((node) => {
      if (
        node.type !== 'ImportDeclaration' ||
        typeof node.source.value !== 'string' ||
        !node.source.value.endsWith('.md')
      )
        return []

      const guide = resolve(dirname(sourcePath), node.source.value)
      return dirname(guide) === guideDirectory ? [guide] : []
    })
    if (!guides.length) return

    // Vocs runs this hook after generating Page's _frontmatter metadata.
    const page = tree.body.find(
      (node) =>
        node.type === 'ExportNamedDeclaration' &&
        node.declaration?.type === 'FunctionDeclaration' &&
        node.declaration.id?.name === 'Page',
    )
    if (
      page?.type !== 'ExportNamedDeclaration' ||
      page.declaration?.type !== 'FunctionDeclaration'
    )
      return

    const frontmatter = page.declaration.body.body
      .flatMap((node) => (node.type === 'VariableDeclaration' ? node.declarations : []))
      .find((node) => node.id.type === 'Identifier' && node.id.name === '_frontmatter')
      ?.init
    if (frontmatter?.type !== 'ObjectExpression') return

    const lastModified = frontmatter.properties.find(
      (node) =>
        node.type === 'Property' &&
        node.key.type === 'Identifier' &&
        node.key.name === 'lastModified',
    )
    if (lastModified?.type !== 'Property') return

    const dates = await Promise.all([sourcePath, ...guides].map(committedDate))
    const latest = dates
      .filter((date): date is string => Boolean(date))
      .sort((left, right) => Date.parse(right) - Date.parse(left))[0]
    lastModified.value = latest
      ? { type: 'Literal', value: latest }
      : { type: 'Identifier', name: 'undefined' }
  }
}

function guideScreenshotMarkdown() {
  return (tree: { children: MarkdownNode[] }) => {
    for (let index = 0; index < tree.children.length; index += 1) {
      const image = standaloneScreenshot(tree.children[index])
      if (!image) continue

      const darkUrl = image.url?.replace(/-light\.png$/, '-dark.png')
      const darkImage = standaloneScreenshot(tree.children[index + 1])

      tree.children[index].children = [linkedScreenshot(image)]

      if (!darkUrl || darkImage?.url !== darkUrl) continue

      tree.children[index + 1] = {
        type: 'paragraph',
        children: [
          {
            type: 'link',
            url: darkUrl,
            children: [{ type: 'text', value: 'View the dark-theme original' }],
          },
        ],
      }
      index += 1
    }
  }
}

function prefixMarkdownUrls() {
  return (tree: MarkdownNode) => {
    const visit = (node: MarkdownNode) => {
      if (node.url) node.url = withBasePath(node.url)
      node.children?.forEach(visit)
    }

    visit(tree)
  }
}

function renderCompatibilityAliases() {
  const aliasesByFile = new Map([
    [
      resolve(import.meta.dirname, '../product/user-guide/PROVIDERS.md'),
      new Set([
        'codex-subscription',
        'claude-subscription',
        'cursor-plan',
        'openai-platform-reporting',
        'anthropic-organization-reporting',
        'cursor-team-admin-api',
        'chrome',
        'firefox',
        'safari',
        'save-the-token',
      ]),
    ],
    [
      resolve(import.meta.dirname, '../product/user-guide/PROVIDERS_CURSOR.md'),
      new Set(['create-team', 'team-key-permissions']),
    ],
    [
      resolve(import.meta.dirname, '../product/user-guide/WIDGET.md'),
      new Set([
        'earlier-launcher-appearance',
        'earlier-wide-widget',
        'earlier-labeled-widget',
        'earlier-percentage-only-widget',
        'earlier-short-widget',
      ]),
    ],
  ])

  return (tree: HtmlNode, file: { path?: string }) => {
    const aliases = file.path && aliasesByFile.get(resolve(file.path))
    if (!aliases) return

    const visit = (node: HtmlNode) => {
      const children = node.children
      if (!children) return

      for (let index = 0; index < children.length; index += 1) {
        const opening = children[index]
        const content = children[index + 1]
        const closing = children[index + 2]
        const id =
          opening.type === 'raw'
            ? opening.value?.match(/^<span id="([a-z0-9-]+)">$/)?.[1]
            : undefined
        const empty = content?.type === 'raw' && content.value === '</span>'

        // MDX discards raw HTML in .md imports; preserve only these existing aliases.
        if (
          id &&
          aliases.has(id) &&
          (empty ||
            (content?.type === 'element' &&
              (content.tagName === 'a' || content.tagName === 'strong') &&
              closing?.type === 'raw' &&
              closing.value === '</span>'))
        )
          children.splice(index, empty ? 2 : 3, {
            type: 'element',
            tagName: 'span',
            properties: { id },
            children: empty ? [] : [content],
          })

        visit(children[index])
      }
    }

    visit(tree)
  }
}

export default defineConfig({
  basePath,
  description:
    'WardPulse is a local-first AI usage dashboard for your phone, watch and watch face.',
  iconUrl: withBasePath('/favicon.svg'),
  markdown: {
    remarkPlugins: [inlineGuideMarkdown],
    rehypePlugins: [renderCompatibilityAliases],
    recmaPlugins: [guideCommittedDates],
    outputRemarkPlugins: [
      homepageMarkdown,
      guideScreenshotMarkdown,
      prefixMarkdownUrls,
    ],
  },
  redirects: [{ source: '/index', destination: '/', status: 308 }],
  renderStrategy: 'full-static',
  sidebar: [
    { text: 'Overview', link: '/' },
    { text: 'Roadmap', link: '/roadmap' },
    {
      text: 'User guide',
      items: [
        { text: 'Getting started', link: '/guide/getting-started' },
        {
          text: 'Providers',
          items: [
            { text: 'Overview', link: '/guide/providers' },
            { text: 'OpenAI', link: '/guide/providers-openai' },
            { text: 'Anthropic', link: '/guide/providers-anthropic' },
            { text: 'Cursor', link: '/guide/providers-cursor' },
          ],
        },
        { text: 'Dashboard', link: '/guide/dashboard' },
        { text: 'Watch and watch face', link: '/guide/watch' },
        { text: 'Home widget', link: '/guide/widget' },
        { text: 'Sync and notifications', link: '/guide/sync' },
        { text: 'Settings and privacy', link: '/guide/settings' },
        { text: 'Troubleshooting', link: '/guide/troubleshooting' },
        { text: 'Report an issue', link: '/guide/report-an-issue' },
      ],
    },
    { text: 'Privacy policy', link: '/product/privacy-policy' },
  ],
  socials: [{ icon: 'github', link: 'https://github.com/neuroborus/ward-pulse' }],
  title: 'WardPulse',
})
