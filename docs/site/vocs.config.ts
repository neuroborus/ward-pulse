import { defineConfig } from 'vocs/config'

export default defineConfig({
  description: 'Product and development documentation for WardPulse.',
  sidebar: [
    { text: 'Overview', link: '/' },
    {
      text: 'Project',
      items: [
        { text: 'Documentation workflow', link: '/project/documentation' },
        { text: 'Design assets', link: '/project/design-assets' },
        { text: 'Development plan', link: '/project/development-plan' },
        { text: 'Android toolchain', link: '/project/android-toolchain' },
      ],
    },
    {
      text: 'Product',
      items: [
        { text: 'Android goals', link: '/product/android-goals' },
        { text: 'Provider notes', link: '/product/provider-notes' },
        { text: 'Security model', link: '/product/security-model' },
        { text: 'Release checklist', link: '/product/release-checklist' },
      ],
    },
    {
      text: 'Applications',
      items: [
        { text: 'Phone', link: '/apps/phone' },
        { text: 'Wear OS', link: '/apps/wear-os' },
        { text: 'Watch face', link: '/apps/watch-face' },
      ],
    },
    {
      text: 'Bindings',
      items: [
        { text: 'Dart', link: '/bindings/dart' },
        { text: 'Kotlin', link: '/bindings/kotlin' },
        { text: 'Swift', link: '/bindings/swift' },
      ],
    },
  ],
  title: 'WardPulse',
  topNav: [
    {
      text: 'GitHub',
      link: 'https://github.com/neuroborus/ward-pulse',
    },
  ],
})
