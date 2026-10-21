'use client'

import { useConfig, useRouter } from 'vocs'

export function SkipToContent(props: SkipToContent.Props) {
  const { className } = props
  const { basePath } = useConfig()
  const { path } = useRouter()
  const currentPath = path.split('#')[0] || '/'
  const basePrefix = basePath === '/' ? '' : basePath.replace(/\/$/, '')
  const publishedPath =
    !basePrefix ||
    currentPath === basePrefix ||
    currentPath.startsWith(`${basePrefix}/`)
      ? currentPath
      : `${basePrefix}${currentPath}`

  return (
    <a
      className={[
        'vocs:fixed vocs:top-3 vocs:left-3 vocs:z-50',
        'vocs:px-4 vocs:py-2',
        'vocs:text-accent8 vocs:text-sm vocs:font-medium',
        'vocs:bg-surface vocs:border-2 vocs:border-dashed vocs:border-accent8 vocs:rounded-lg',
        'vocs:outline-none',
        'vocs:opacity-0 vocs:pointer-events-none vocs:-translate-y-full',
        'vocs:focus:opacity-100 vocs:focus:pointer-events-auto vocs:focus:translate-y-0',
        'vocs:transition-all vocs:duration-150',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      data-v-skip-to-content
      href={`${publishedPath}#vocs-content`}
    >
      Skip to content
    </a>
  )
}

export declare namespace SkipToContent {
  export type Props = {
    className?: string | undefined
  }
}
