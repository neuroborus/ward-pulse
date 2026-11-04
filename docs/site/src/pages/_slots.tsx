'use client'

import * as React from 'react'
import { useRouter } from 'vocs'

const basePath = import.meta.env.BASE_URL.replace(/\/$/, '')

// Original: apps/phone_flutter/android/app/src/main/res/raw/wardpulse_notification_click.wav.
// Apache-2.0 per apps/phone_flutter/README.md; brand rights remain separate.
// SHA-256: c056547acf175ddc7e46c0e35fdb586f8737dc83e533e5391de6e366885f9306.
const audioUrl = `${basePath}/audio/wardpulse_notification_click.wav`

// Accepted clips outlive Footer effects and client navigation.
const activeAudio = new Set<HTMLAudioElement>()

function requestRoadmapAudio() {
  let audio: HTMLAudioElement | undefined

  function release() {
    if (!audio) return
    const finished = audio
    audio = undefined
    activeAudio.delete(finished)
    finished.onended = null
    finished.onerror = null
    try {
      finished.pause()
      finished.removeAttribute('src')
      finished.load()
    } catch {}
  }

  try {
    audio = new Audio(audioUrl)
    activeAudio.add(audio)
    audio.onended = release
    audio.onerror = release
    void audio.play().catch(release)
  } catch {
    release()
  }
}

export function Footer() {
  const { push } = useRouter()

  React.useEffect(() => {
    const roadmapUrl = new URL(`${basePath}/roadmap`, window.location.origin)
    const armed = new Set<() => void>()
    const navigationTimers = new Set<number>()
    let disposed = false

    function qualify(event: MouseEvent) {
      if (
        !event.isTrusted ||
        !event.cancelable ||
        event.defaultPrevented ||
        event.cancelBubble ||
        event.button !== 0 ||
        event.altKey ||
        event.ctrlKey ||
        event.metaKey ||
        event.shiftKey
      )
        return

      const anchor =
        event.target instanceof Element
          ? event.target.closest('a[data-v-sidebar-item]')
          : null
      if (
        !(anchor instanceof HTMLAnchorElement) ||
        !anchor.isConnected ||
        anchor.hasAttribute('download') ||
        anchor.href !== roadmapUrl.href
      )
        return

      const nav = anchor.closest('nav[data-v-sidebar]')
      if (!nav) return

      const target =
        anchor.target ||
        document.querySelector<HTMLBaseElement>('base[target]')?.target ||
        '_self'
      const keyword = target.toLowerCase()
      const currentWindow =
        keyword === '_self' ||
        (keyword === '_parent' && window.parent === window) ||
        (keyword === '_top' && window.top === window) ||
        (!target.startsWith('_') &&
          target === window.name &&
          !/(?:^|\s)(?:noopener|noreferrer)(?:\s|$)/i.test(anchor.rel))
      if (!currentWindow) return

      return { anchor, nav }
    }

    function onClick(event: MouseEvent) {
      const match = qualify(event)
      if (!match) return
      const { anchor, nav } = match

      function disarm() {
        nav.removeEventListener('click', accept)
        window.clearTimeout(cleanupTimer)
        armed.delete(disarm)
      }

      function accept(bubbled: Event) {
        if (bubbled !== event) return
        disarm()
        if (disposed) return
        const current = qualify(event)
        if (!current || current.anchor !== anchor || current.nav !== nav) return

        // Own navigation before React handles the click, retaining mobile menu closing.
        event.preventDefault()
        if (roadmapUrl.href !== window.location.href) {
          const timer = window.setTimeout(() => {
            navigationTimers.delete(timer)
            if (disposed) return
            React.startTransition(() => {
              void push('/roadmap').catch(() => {})
            })
          }, 0)
          navigationTimers.add(timer)
        }
        requestRoadmapAudio()
      }

      const cleanupTimer = window.setTimeout(disarm, 0)
      armed.add(disarm)
      nav.addEventListener('click', accept)
    }

    document.addEventListener('click', onClick, true)
    return () => {
      disposed = true
      document.removeEventListener('click', onClick, true)
      for (const disarm of armed) disarm()
      for (const timer of navigationTimers) window.clearTimeout(timer)
      navigationTimers.clear()
    }
  }, [push])

  return <span hidden data-wardpulse-roadmap-audio />
}
