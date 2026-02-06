/**
 * build.mjs
 *
 * Builds the browser bundle for Flutter WebView integration.
 * Uses esbuild to bundle all dependencies into a single IIFE.
 */

import * as esbuild from 'esbuild'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const __dirname = dirname(fileURLToPath(import.meta.url))

const isProd = process.env.NODE_ENV === 'production'

async function build() {
  try {
    const result = await esbuild.build({
      entryPoints: [resolve(__dirname, 'src/bridge/entry-browser.ts')],
      bundle: true,
      outfile: resolve(__dirname, 'dist/browser/core_lib.js'),
      format: 'iife',
      globalName: 'CoreLib',
      platform: 'browser',
      target: ['es2020'],
      define: {
        'process.env.NODE_ENV': JSON.stringify(isProd ? 'production' : 'development'),
        'global': 'globalThis'
      },
      external: [],
      minify: isProd,
      sourcemap: true,
      metafile: true,
      logLevel: 'info'
    })

    // Log bundle size
    const outputs = Object.values(result.metafile.outputs)
    const mainOutput = outputs.find(o => o.entryPoint)
    if (mainOutput) {
      const sizeKB = (mainOutput.bytes / 1024).toFixed(2)
      console.log(`\nBundle size: ${sizeKB} KB`)
    }

    console.log('\nBrowser bundle built successfully!')
    console.log(`Output: dist/browser/core_lib.js`)

  } catch (err) {
    console.error('Build failed:', err)
    process.exit(1)
  }
}

build()
