/**
 * Build script for core_lib_js bundle.
 * Bundles for browser with Buffer polyfill.
 */

import * as esbuild from 'esbuild';

const isDev = process.argv.includes('--dev');

console.log('Building core_lib.js bundle...');
console.log('Mode:', isDev ? 'development' : 'production');

try {
  await esbuild.build({
    entryPoints: ['src/bridge/entry.ts'],
    bundle: true,
    outfile: '../assets/js/core_lib.js',
    format: 'iife',
    platform: 'browser',
    target: 'es2020',
    sourcemap: isDev,
    minify: !isDev,
    define: {
      'global': 'globalThis',
      'process.env.NODE_ENV': isDev ? '"development"' : '"production"',
    },
    inject: ['./shims/buffer-shim.js'],
    logLevel: 'info',
  });

  console.log('Build successful!');
} catch (error) {
  console.error('Build failed:', error);
  process.exit(1);
}
