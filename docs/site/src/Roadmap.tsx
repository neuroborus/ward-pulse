'use client'

import * as React from 'react'
import { useRouter } from 'vocs'

// Fixed integer mixing keeps the constellation identical on the server and client.
const questionMarks = Array.from({ length: 72 }, (_, index) => {
  const seed = Math.imul(index + 1, 2654435761) >>> 0
  const mixed = Math.imul(seed ^ (seed >>> 16), 2246822507) >>> 0

  return {
    left: `${3 + (seed % 940) / 10}%`,
    top: `${2 + (mixed % 960) / 10}%`,
    fontSize: `${0.8 + (mixed % 5) / 10}rem`,
    opacity: 0.16 + (seed % 4) * 0.04,
  }
})

export function Roadmap({ children }: { children: React.ReactNode }) {
  const root = React.useRef<HTMLDivElement>(null)
  const { path, hash } = useRouter()

  React.useEffect(() => {
    let disposed = false
    let frame = 0

    // Native IDs come from Vocs. Revisit only this page's target after fonts/layout settle.
    function settleAnchor() {
      void document.fonts.ready.then(() => {
        if (disposed) return
        cancelAnimationFrame(frame)
        frame = requestAnimationFrame(() => {
          frame = requestAnimationFrame(() => {
            if (disposed) return
            let id: string
            try {
              id = decodeURIComponent(window.location.hash.slice(1))
            } catch {
              return
            }
            const target = document.getElementById(id)
            if (target && root.current?.contains(target))
              target.scrollIntoView({ block: 'start', behavior: 'instant' })
          })
        })
      })
    }

    function onPermalinkClick(event: MouseEvent) {
      if (event.button || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      if (event.target instanceof Element && event.target.closest('a.heading-anchor'))
        settleAnchor()
    }

    const element = root.current
    settleAnchor()
    element?.addEventListener('click', onPermalinkClick)
    window.addEventListener('hashchange', settleAnchor)
    window.addEventListener('popstate', settleAnchor)

    return () => {
      disposed = true
      cancelAnimationFrame(frame)
      element?.removeEventListener('click', onPermalinkClick)
      window.removeEventListener('hashchange', settleAnchor)
      window.removeEventListener('popstate', settleAnchor)
    }
  }, [path, hash])

  return (
    <div className="wardpulse-roadmap" ref={root}>
      <div className="wardpulse-roadmap__content">
        {children}
        <div className="wardpulse-roadmap__questions" aria-hidden="true">
          {questionMarks.map((style, index) => (
            <span key={index} style={style}>
              ?
            </span>
          ))}
        </div>
      </div>
    </div>
  )
}
