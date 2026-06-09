import { Marked } from 'marked'
import previewCss from './preview-assets/preview.css?raw'
import mermaidJs from './preview-assets/mermaid.min.js?raw'
import highlightJs from './preview-assets/highlight.min.js?raw'
import searchJs from './preview-assets/search.js?raw'

const marked = new Marked()

marked.use({ gfm: true, breaks: false })

const CONTENT_WIDTHS = ['720px', '960px', 'none']

function parseHeadings(content: string): Array<{ text: string; level: number; line: number }> {
  const headings: Array<{ text: string; level: number; line: number }> = []
  const lines = content.split('\n')
  let inFence = false
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (/^```/.test(line) || /^~~~/.test(line)) {
      inFence = !inFence
      continue
    }
    if (!inFence) {
      const match = line.match(/^(#{1,6})\s+(.+)$/)
      if (match) {
        headings.push({ level: match[1].length, text: match[2].trim(), line: i })
      }
    }
  }
  return headings
}

export function parseMarkdown(content: string, contentWidth: number = 0): { bodyHTML: string; fullHTML: string } {
  const headings = parseHeadings(content)
  let bodyHTML = marked.parse(content) as string
  const maxWidth = CONTENT_WIDTHS[contentWidth] || '720px'

  {
    let hi = 0
    bodyHTML = bodyHTML.replace(/<h([1-6])([^>]*)>/g, (_m, level, rest) => {
      const line = hi < headings.length ? headings[hi].line : 0
      hi++
      return `<h${level} data-line="${line}"${rest}>`
    })
  }

  const fullHTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>${previewCss}</style>
  <style id="theme-style"></style>
</head>
<body class="markdown-body" style="max-width:${maxWidth}">
  <div id="md-content">${bodyHTML}</div>
  <script>${mermaidJs}<\/script>
  <script>${highlightJs}<\/script>
  <script>${searchJs}<\/script>
  <script>
    try { mermaid.initialize({ startOnLoad: true, theme: 'default' }); mermaid.run({ nodes: document.querySelectorAll('.mermaid') }).catch(function(){}); } catch(e) {}
    document.querySelectorAll('pre code').forEach(function(block) { try { hljs.highlightElement(block); } catch(e) {} });
  <\/script>
</body>
</html>`

  return { bodyHTML, fullHTML }
}
