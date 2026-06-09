import { parseMarkdown } from './markdown-parser'

export class Preview {
  private iframe: HTMLIFrameElement
  private container: HTMLElement
  private currentContent = ''
  private currentWidth = 0

  constructor(container: HTMLElement) {
    this.container = container

    this.iframe = document.createElement('iframe')
    this.iframe.id = 'preview-iframe'
    this.iframe.style.cssText = 'width:100%;height:100%;border:none;'
    this.container.appendChild(this.iframe)
  }

  update(content: string, contentWidth: number = 0): void {
    this.currentContent = content
    this.currentWidth = contentWidth
    const { fullHTML } = parseMarkdown(content, contentWidth)
    this.iframe.srcdoc = fullHTML
  }

  setTheme(isDark: boolean): void {
    try {
      const doc = this.iframe.contentDocument
      if (doc && doc.body) {
        doc.body.style.background = isDark ? '#1c1c21' : '#ffffff'
        doc.body.style.color = isDark ? '#ebebeb' : '#141414'
      }
    } catch {
      // Cross-origin restrictions — ignore
    }
  }

  scrollToHeading(lineNumber: number): void {
    try {
      const doc = this.iframe.contentDocument
      if (!doc) return
      const el = doc.querySelector(`[data-line="${lineNumber}"]`) as HTMLElement
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' })
    } catch {
      // cross-origin
    }
  }

  search(query: string, currentIndex: number): { count: number } | null {
    try {
      const doc = this.iframe.contentDocument
      if (!doc || !doc.defaultView || !(doc.defaultView as any).SearchJS) return null
      const result = (doc.defaultView as any).SearchJS.highlight(query, currentIndex)
      return result ? JSON.parse(result) : null
    } catch {
      return null
    }
  }

  clearSearch(): void {
    try {
      const doc = this.iframe.contentDocument
      if (!doc || !doc.defaultView || !(doc.defaultView as any).SearchJS) return
      ;(doc.defaultView as any).SearchJS.clearHighlights()
    } catch {}
  }

  clear(): void {
    this.currentContent = ''
    this.iframe.srcdoc = ''
  }
}
