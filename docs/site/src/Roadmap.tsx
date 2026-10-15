'use client'

import * as React from 'react'
import { useRouter } from 'vocs'

// Scatter within the smallest safe size of each empty region, in rem. Larger
// regions spread the same whole pairs farther apart without changing hydration.
const questionFields = [
  { name: 'upper', width: 9, height: 2 },
  { name: 'release-gap', width: 9, height: 3.5 },
  { name: 'ios-gap', width: 9, height: 5 },
  { name: 'bridge-gap', width: 9, height: 2 },
  { name: 'release-side', width: 2, height: 4 },
  { name: 'multi-side', width: 2, height: 4 },
  { name: 'ios-side', width: 2, height: 4 },
  { name: 'bridge-side', width: 2, height: 4 },
  { name: 'providers-gap', width: 9, height: 5 },
  { name: 'providers-side', width: 2, height: 4 },
].map(({ name, width, height }, field) => {
  const points: { x: number; y: number }[] = []
  const marks: React.CSSProperties[] = []

  for (let index = 0; index < 72; index++) {
    const seed = Math.imul(field * 72 + index + 1, 2654435761) >>> 0
    const mixed = Math.imul(seed ^ (seed >>> 16), 2246822507) >>> 0
    const x = (seed % 1000) / 1000
    const y = (mixed % 1000) / 1000

    // Reserve the entire 1.5rem pair plus breathing room, not just its dot.
    const overlaps = points.some((point) =>
      Math.abs(point.x - x) * (width - 1.5) < 2 &&
      Math.abs(point.y - y) * (height - 1.5) < 1.875,
    )
    if (overlaps) continue

    points.push({ x, y })
    marks.push({
      left: `${x * 100}%`,
      top: `${y * 100}%`,
      transform: `translate(${-x * 100}%, ${-y * 100}%)`,
      fontSize: `${0.85 + (mixed % 4) / 10}rem`,
      opacity: (name === 'bridge-gap' ? 0.24 : 0.36) + (seed % 4) * 0.04,
    })
  }

  return { name, marks }
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
        <div className="wardpulse-roadmap__direction" aria-hidden="true" />
        {questionFields.map(({ name, marks }) => (
          <div
            key={name}
            className={`wardpulse-roadmap__questions wardpulse-roadmap__questions--${name}`}
            aria-hidden="true"
          >
            {marks.map((style, index) => (
              <span key={index} style={style}>?</span>
            ))}
          </div>
        ))}
      </div>
      <svg
        className="wardpulse-roadmap__fog"
        viewBox="0 0 820 400"
        aria-hidden="true"
        focusable="false"
      >
        <defs>
          <linearGradient id="roadmap-cloud-volume" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="currentColor" stopOpacity="0.1" />
            <stop offset="0.4" stopColor="currentColor" stopOpacity="0.25" />
            <stop offset="0.75" stopColor="currentColor" stopOpacity="0.13" />
            <stop offset="1" stopColor="currentColor" stopOpacity="0" />
          </linearGradient>
          <filter id="roadmap-cloud-near" x="-20%" y="-40%" width="140%" height="180%">
            <feGaussianBlur stdDeviation="7" />
          </filter>
          <filter id="roadmap-cloud-far" x="-20%" y="-40%" width="140%" height="180%">
            <feGaussianBlur stdDeviation="18" />
          </filter>
        </defs>
        <g fill="url(#roadmap-cloud-volume)" filter="url(#roadmap-cloud-far)" opacity="0.65">
          <path d="M104 252 C72 247 68 207 94 188 C81 156 112 123 145 133 C155 94 205 80 234 114 C254 75 310 77 333 114 C368 95 410 114 412 149 C452 138 486 166 482 198 C515 205 524 242 499 264 C466 294 417 287 390 296 C343 320 303 296 270 306 C222 319 203 290 169 294 C132 298 106 278 104 252Z" />
          <path d="M377 258 C351 238 360 205 390 194 C378 158 407 128 440 141 C452 104 496 100 519 130 C542 96 592 112 598 148 C630 124 668 144 670 177 C710 164 745 194 730 225 C757 247 735 282 706 282 C679 309 636 289 606 307 C573 326 531 301 502 310 C459 321 444 293 419 291 C393 290 377 278 377 258Z" />
        </g>
        <g fill="url(#roadmap-cloud-volume)" filter="url(#roadmap-cloud-near)">
          <path d="M143 275 C117 260 125 231 151 225 C147 193 180 176 204 193 C211 153 259 143 284 175 C306 152 341 161 350 187 C377 156 426 171 429 207 C459 191 493 209 493 238 C525 232 548 258 532 280 C509 306 476 295 451 310 C420 327 385 305 360 316 C326 332 301 309 277 317 C244 327 222 303 198 309 C171 314 145 298 143 275Z" />
          <path d="M414 289 C394 269 405 246 430 242 C419 214 444 189 471 199 C487 167 529 174 541 203 C573 182 606 202 606 231 C639 217 671 238 665 264 C696 275 687 304 659 310 C633 332 605 314 581 326 C551 340 524 317 502 327 C470 337 454 314 439 314 C423 311 414 302 414 289Z" />
        </g>
      </svg>
    </div>
  )
}
