import { readFile, writeFile } from 'node:fs/promises'
import { createRequire, registerHooks } from 'node:module'
import { pathToFileURL } from 'node:url'

globalThis.Bun = {
  file: (path) => ({ arrayBuffer: () => readFile(path) }),
  write: writeFile,
}

const require = createRequire(import.meta.url)
const cli = require.resolve('@open-pencil/cli/bin/openpencil.js')
const core = require.resolve('@open-pencil/core')
const corePackage = new URL('../package.json', pathToFileURL(core)).href

registerHooks({
  resolve: (specifier, context, nextResolve) =>
    specifier === '@open-pencil/core/package.json'
      ? { shortCircuit: true, url: corePackage }
      : nextResolve(specifier, context),
})

await import(pathToFileURL(cli).href)
