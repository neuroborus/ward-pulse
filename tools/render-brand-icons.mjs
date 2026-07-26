#!/usr/bin/env node
/**
 * Official WardPulse mark SVGs.
 *
 * Color app logo: metallic disc + provider-family framing ring.
 * Monochrome watermark: ringless wordmark + pulse/eye for the watch face.
 *
 * Usage: node tools/render-brand-icons.mjs
 */

import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

const GREEN = '#65D78A'
const TEAL = '#67E8D4'
const ORANGE = '#E8915A'
const MONO = '#C5CDD1'
const ON_METAL = '#F4FBF8'

function polar(cx, cy, r, a) {
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)]
}

function ringSegment(cx, cy, rOut, rIn, a0, a1, steps = 56) {
  const outer = []
  const inner = []
  for (let i = 0; i <= steps; i += 1) {
    const t = a0 + ((a1 - a0) * i) / steps
    outer.push(polar(cx, cy, rOut, t))
    inner.push(polar(cx, cy, rIn, t))
  }
  let d = `M ${outer[0][0].toFixed(2)} ${outer[0][1].toFixed(2)}`
  for (let i = 1; i < outer.length; i += 1) {
    d += ` L ${outer[i][0].toFixed(2)} ${outer[i][1].toFixed(2)}`
  }
  d += ` L ${inner[inner.length - 1][0].toFixed(2)} ${inner[inner.length - 1][1].toFixed(2)}`
  for (let i = inner.length - 2; i >= 0; i -= 1) {
    d += ` L ${inner[i][0].toFixed(2)} ${inner[i][1].toFixed(2)}`
  }
  return `${d} Z`
}

function familyRing(cx, cy, rOut, rIn) {
  const gap = 0.035
  const segs = [
    [-Math.PI / 2, -Math.PI / 2 + (2 * Math.PI) / 3, GREEN],
    [-Math.PI / 2 + (2 * Math.PI) / 3, -Math.PI / 2 + (4 * Math.PI) / 3, TEAL],
    [-Math.PI / 2 + (4 * Math.PI) / 3, -Math.PI / 2 + 2 * Math.PI, ORANGE],
  ]
  return segs
    .map(([a0, a1, color]) => {
      const mid = (a0 + a1) / 2
      const half = (a1 - a0) / 2 - gap
      const d = ringSegment(cx, cy, rOut, rIn, mid - half, mid + half)
      return `  <path d="${d}" fill="${color}"/>`
    })
    .join('\n')
}

function pulseEye(stroke, { scale = 1, opacity = 1, pupilR = 5 } = {}) {
  const cx = 256
  const cy = 256
  // Locked exploration placement: eye over the right pulse shelf.
  return `
  <g fill="none" stroke="${stroke}" stroke-opacity="${opacity}" fill-opacity="${opacity}"
    stroke-linecap="round" stroke-linejoin="round"
    transform="translate(${cx}, ${cy}) scale(${scale}) translate(${-cx}, ${-cy})">
    <path transform="translate(128, 214)" d="M0 44 L60 44 L96 0 L160 88 L200 36 L256 36"
      stroke-width="18"/>
    <path transform="translate(292, 196)" d="M0 10 C14 0 50 0 64 10 C50 20 14 20 0 10 Z"
      stroke-width="7"/>
    <circle cx="324" cy="206" r="${pupilR}" fill="${stroke}" stroke="none"/>
  </g>`
}

/** Geometry locked from the approved metal-ring exploration (512 canvas). */
function colorLogoSvg(size = 512) {
  const cx = size / 2
  const cy = size / 2
  const scale = size / 512
  const rOut = 236 * scale
  const rIn = 208 * scale
  const body = 198 * scale
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="WardPulse">
  <defs>
    <linearGradient id="metal" x1="16%" y1="10%" x2="84%" y2="90%">
      <stop offset="0%" stop-color="#8A9298"/>
      <stop offset="30%" stop-color="#4E555B"/>
      <stop offset="50%" stop-color="#A7AEB4"/>
      <stop offset="75%" stop-color="#3C4349"/>
      <stop offset="100%" stop-color="#2A3035"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.18"/>
      <stop offset="45%" stop-color="#FFFFFF" stop-opacity="0.04"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.28"/>
    </linearGradient>
  </defs>
${familyRing(cx, cy, rOut, rIn)}
  <circle cx="${cx}" cy="${cy}" r="${body}" fill="url(#metal)"/>
  <circle cx="${cx}" cy="${cy}" r="${body}" fill="url(#sheen)"/>
${pulseEye(ON_METAL, { scale })}
</svg>
`
}

/**
 * Quiet monochrome watermark for WFF — no framing ring.
 * Bottom dissolve toward strips is applied when rasterizing (see export-icons.sh):
 * SVG masks were unreliable against the packed glyph bounds.
 */
function monoLogoSvg(size = 512) {
  const cx = size / 2
  const fontSize = Math.round(size * 0.118)
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="WardPulse mono">
  <g transform="translate(${cx}, ${cx}) scale(1.22) translate(${-cx}, ${-cx})">
    <text x="${cx}" y="${(size * 0.34).toFixed(1)}"
      fill="${MONO}" fill-opacity="0.95"
      font-family="Noto Sans, DejaVu Sans, sans-serif"
      font-size="${fontSize}" font-weight="700"
      letter-spacing="${(size * 0.008).toFixed(1)}"
      text-anchor="middle" dominant-baseline="central">WARDPULSE</text>
${pulseEye(MONO, { scale: 0.92, opacity: 1, pupilR: 3.2 })}
  </g>
</svg>
`
}

const iconsDir = join(root, 'brand/icons')

await mkdir(iconsDir, { recursive: true })

await writeFile(join(iconsDir, 'wardpulse.svg'), colorLogoSvg(512))
await writeFile(join(iconsDir, 'wardpulse-mono.svg'), monoLogoSvg(512))
console.log('wrote brand/icons/wardpulse.svg')
console.log('wrote brand/icons/wardpulse-mono.svg')
