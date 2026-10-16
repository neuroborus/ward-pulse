import * as React from 'react'

const approvedScreenshot =
  /^\/screenshots\/(?:phone-(?:alert-thresholds|budget-limits|cursor-(?:paste-token|sign-in-help)|dashboard|home-widget|providers|reporting-key|watch-settings|widget-settings)-(?:light|dark)|wear-(?:glance|plan-windows|watch-face))\.png$/

const providerActionsScreenshot =
  /^\/screenshots\/phone-providers-(?:light|dark)\.png$/

const basePath = import.meta.env.BASE_URL.replace(/\/$/, '')

export function docsPath(path: string) {
  if (!basePath || !path.startsWith('/') || path.startsWith('//')) return path
  if (path === basePath || path.startsWith(`${basePath}/`)) return path
  return `${basePath}${path}`
}

type GuideScreenshotProps = React.ComponentProps<'img'> & {
  providerActionsOverlay?: boolean
}

export function GuideScreenshot({
  providerActionsOverlay = false,
  ...props
}: GuideScreenshotProps) {
  const { src } = props

  if (!src || !approvedScreenshot.test(src)) return <img {...props} />

  const resolvedSrc = docsPath(src)
  const theme = src.endsWith('-light.png')
    ? 'light'
    : src.endsWith('-dark.png')
      ? 'dark'
      : 'fixed'

  return (
    <a
      className="wardpulse-guide-screenshot"
      data-wardpulse-screenshot-theme={theme}
      href={resolvedSrc}
    >
      <img {...props} src={resolvedSrc} loading="lazy" />
      {providerActionsOverlay && providerActionsScreenshot.test(src) ? (
        <svg
          aria-hidden="true"
          className="wardpulse-guide-screenshot__overlay"
          focusable="false"
        >
          <foreignObject width="100%" height="100%">
            <div className="wardpulse-guide-screenshot__overlay-frame">
              <span
                className="wardpulse-guide-screenshot__provider-action wardpulse-guide-screenshot__provider-action--budget"
              />
              <span
                className="wardpulse-guide-screenshot__provider-action wardpulse-guide-screenshot__provider-action--alert"
              />
            </div>
          </foreignObject>
        </svg>
      ) : null}
    </a>
  )
}

export function DashboardGuideScreenshot(props: React.ComponentProps<'img'>) {
  return <GuideScreenshot {...props} providerActionsOverlay />
}
