import React from 'react'
const h = React.createElement

// Self-contained page styles — no external CSS, no CDN (except mermaid runtime).
export const PAGE_CSS = `
:root{--bg:#fff;--fg:#1a1a1a;--muted:#6b7280;--border:#e5e7eb;--accent:#2e9b5b;--code:#f6f8fa;--card:#fafafa}
*{box-sizing:border-box}
body{font-family:system-ui,-apple-system,sans-serif;color:var(--fg);background:var(--bg);max-width:820px;margin:0 auto;padding:48px 24px;line-height:1.6}
h1,h2,h3{line-height:1.25;margin:1.6em 0 .5em}
h1{font-size:2rem;border-bottom:1px solid var(--border);padding-bottom:.3em}
h2{font-size:1.4rem}h3{font-size:1.08rem}
a{color:#2563eb}
code{background:var(--code);padding:.15em .4em;border-radius:4px;font-size:.9em}
pre{background:var(--code);padding:14px;border-radius:8px;overflow:auto}
pre code{background:none;padding:0}
pre[class*="language-"]{background:#2d2d2d;padding:14px;border-radius:8px;margin:1em 0}
code[class*="language-"]{background:none;padding:0;font-size:.88em}
ul,ol{padding-left:1.4em}
table{border-collapse:collapse;width:100%;margin:14px 0}
th,td{border:1px solid var(--border);padding:6px 10px;text-align:left}
th{background:var(--card)}
.pl-meta{color:var(--muted);font-size:12px;margin:0 0 28px;font-family:ui-monospace,monospace}
.pl-callout{border-left:4px solid var(--accent);background:#f3fbf6;padding:10px 16px;border-radius:6px;margin:16px 0}
.pl-callout[data-tone=warn]{border-color:#d97706;background:#fffbeb}
.pl-callout[data-tone=danger]{border-color:#dc2626;background:#fef2f2}
.pl-ft{border:1px solid var(--border);border-radius:8px;overflow:hidden;margin:16px 0}
.pl-ft .row{display:flex;gap:10px;align-items:center;padding:8px 14px;border-top:1px solid var(--border);font-family:ui-monospace,monospace;font-size:.85rem}
.pl-ft .row:first-child{border-top:none}
.pl-ft .tag{font-size:.65rem;text-transform:uppercase;padding:2px 6px;border-radius:4px;font-weight:600}
.pl-ft .added{background:#dcfce7;color:#166534}
.pl-ft .modified{background:#fef9c3;color:#854d0e}
.pl-ft .removed{background:#fee2e2;color:#991b1b}
.pl-ft .note{color:var(--muted)}
.diagram-panel{display:flex;gap:12px;flex-wrap:wrap;align-items:center;padding:16px;background:var(--card);border:1px solid var(--border);border-radius:8px}
.diagram-node{background:#fff;border:1px solid var(--border);border-radius:8px;padding:10px 14px;font-size:.9rem}
.diagram-cap{color:var(--muted);font-size:12px;margin-top:6px}
.mermaid{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:16px;margin:16px 0;text-align:center}
`

const RichText = ({ children }) => h('div', { className: 'pl-richtext' }, children)

const Callout = ({ tone = 'info', children }) =>
  h('aside', { className: 'pl-callout', 'data-tone': tone }, children)

const FileTree = ({ title, entries = [] }) =>
  h('div', {},
    title ? h('div', { style: { fontWeight: 600, margin: '16px 0 6px' } }, title) : null,
    h('div', { className: 'pl-ft' },
      entries.map((e, i) =>
        h('div', { className: 'row', key: i },
          h('span', { className: `tag ${e.change || 'modified'}` }, e.change || 'mod'),
          h('span', {}, e.path),
          e.note ? h('span', { className: 'note' }, '— ' + e.note) : null,
        ),
      ),
    ),
  )

// Spatial diagram: raw HTML/CSS using diagram-* classes (mirrors Agent-Native's data.html/css shape).
const Diagram = ({ data = {} }) =>
  h('figure', { style: { margin: '16px 0' } },
    data.css ? h('style', { dangerouslySetInnerHTML: { __html: data.css } }) : null,
    h('div', { dangerouslySetInnerHTML: { __html: data.html || '' } }),
    data.caption ? h('figcaption', { className: 'diagram-cap' }, data.caption) : null,
  )

// Mermaid: emits <pre class="mermaid">; rendered client-side by the runtime injected in page().
const Mermaid = ({ chart }) => h('pre', { className: 'mermaid' }, chart)

export const components = { RichText, Callout, FileTree, Diagram, Mermaid }

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))

export function page(frontmatter, body) {
  const title = frontmatter?.title ?? 'Plan'
  return `<!doctype html><html lang="pt-br"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title>` +
    `<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/prismjs@1/themes/prism-tomorrow.min.css">` +
    `<style>${PAGE_CSS}</style></head><body>` +
    `<p class="pl-meta">${frontmatter ? esc(JSON.stringify(frontmatter)) : ''}</p>` +
    body +
    `<script src="https://cdn.jsdelivr.net/npm/prismjs@1/prism.min.js"></script>` +
    `<script src="https://cdn.jsdelivr.net/npm/prismjs@1/plugins/autoloader/prism-autoloader.min.js"></script>` +
    `<script type="module">import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';mermaid.initialize({startOnLoad:true,theme:'neutral'});</script>` +
    `</body></html>`
}
