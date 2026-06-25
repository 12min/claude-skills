#!/usr/bin/env node
// visual-plan renderer: compile a plan.mdx -> self-contained HTML (no hosted service, no account).
// Usage: node render.mjs <path-to-plan.mdx> [--open]
import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { execFile } from 'node:child_process'
import { evaluate } from '@mdx-js/mdx'
import * as runtime from 'react/jsx-runtime'
import React from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import remarkGfm from 'remark-gfm'
import remarkFrontmatter from 'remark-frontmatter'
import remarkMdxFrontmatter from 'remark-mdx-frontmatter'
import { components, page } from './components.mjs'

const arg = process.argv[2]
if (!arg) {
  console.error('usage: render.mjs <plan.mdx> [--open]')
  process.exit(1)
}
const mdxPath = resolve(arg)
const wantOpen = process.argv.includes('--open')
const src = readFileSync(mdxPath, 'utf8')

const plugins = [remarkGfm, remarkFrontmatter, [remarkMdxFrontmatter, { name: 'frontmatter' }]]

let result
try {
  const mod = await evaluate(src, { ...runtime, remarkPlugins: plugins })
  const body = renderToStaticMarkup(React.createElement(mod.default, { components }))
  const out = mdxPath.replace(/\.mdx$/, '.html')
  writeFileSync(out, page(mod.frontmatter, body))
  result = { ok: true, out, title: mod.frontmatter?.title ?? null }
  console.log(JSON.stringify(result))
  if (wantOpen) {
    const cmd = process.platform === 'darwin' ? 'open' : 'xdg-open'
    execFile(cmd, [out], () => {})
  }
} catch (err) {
  console.error(JSON.stringify({ ok: false, error: String(err && err.message || err) }))
  process.exit(1)
}
