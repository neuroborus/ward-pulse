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

const screenshots = [
  {
    url: '/screenshots/phone-dashboard-light.png',
    alt: 'WardPulse phone Dashboard showing AI plan capacity and update status in the light theme.',
    caption: 'Phone Dashboard',
    darkOriginalUrl: '/screenshots/phone-dashboard-dark.png',
  },
  {
    url: '/screenshots/wear-glance.png',
    alt: 'WardPulse Watch Glance showing balances and refresh status.',
    caption: 'Watch Glance',
  },
  {
    url: '/screenshots/wear-watch-face.png',
    alt: 'WardPulse watch face showing usage rings and upper complications.',
    caption: 'Watch face',
  },
]

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

export default defineConfig({
  description:
    'WardPulse is a local-first AI usage dashboard for your phone, watch and watch face.',
  markdown: {
    outputRemarkPlugins: [homepageMarkdown],
  },
  redirects: [{ source: '/index', destination: '/', status: 308 }],
  renderStrategy: 'full-static',
  sidebar: [
    { text: 'Overview', link: '/' },
    {
      text: 'User guide',
      items: [
        { text: 'Getting started', link: '/guide/getting-started' },
        { text: 'Providers', link: '/guide/providers' },
        { text: 'Dashboard', link: '/guide/dashboard' },
        { text: 'Watch and watch face', link: '/guide/watch' },
        { text: 'Home widget', link: '/guide/widget' },
        { text: 'Sync and notifications', link: '/guide/sync' },
        { text: 'Settings and privacy', link: '/guide/settings' },
        { text: 'Troubleshooting', link: '/guide/troubleshooting' },
      ],
    },
    { text: 'Privacy policy', link: '/product/privacy-policy' },
  ],
  title: 'WardPulse',
})
