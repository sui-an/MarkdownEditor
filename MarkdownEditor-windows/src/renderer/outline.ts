import type { HeadingItem } from '../shared/types'

export class OutlinePanel {
  private element: HTMLDivElement
  private visible = false
  private onNavigate: ((position: number) => void) | null = null

  constructor() {
    this.element = document.createElement('div')
    this.element.id = 'outline-panel'
    this.element.style.display = 'none'
    document.body.appendChild(this.element)

    document.addEventListener('click', (e) => {
      const target = e.target as HTMLElement
      if (this.visible && !this.element.contains(target) && target.id !== 'btn-outline-toggle') {
        this.hide()
      }
    })
  }

  show(headings: HeadingItem[], onNavigate: (position: number) => void): void {
    this.visible = true
    this.onNavigate = onNavigate
    this.element.style.display = 'block'

    if (headings.length === 0) {
      this.element.innerHTML = '<div class="outline-empty">No headings found</div>'
      return
    }

    this.element.innerHTML = `
      <div class="outline-header">Outline</div>
      ${headings.map(h => `
        <div class="outline-item" style="padding-left: ${(h.level - 1) * 16 + 12}px" data-pos="${h.position}">
          <span class="outline-level">H${h.level}</span>
          <span class="outline-text">${this.escapeHtml(h.text)}</span>
        </div>
      `).join('')}
    `

    this.element.querySelectorAll('.outline-item').forEach(el => {
      el.addEventListener('click', () => {
        const pos = parseInt((el as HTMLElement).dataset.pos || '0')
        this.onNavigate?.(pos)
        this.hide()
      })
    })
  }

  isVisible(): boolean {
    return this.visible
  }

  updateHeadings(headings: HeadingItem[]): void {
    if (!this.visible) return
    this.show(headings, this.onNavigate || ((_pos: number) => {}))
  }

  hide(): void {
    this.visible = false
    this.element.style.display = 'none'
  }

  toggle(headings: HeadingItem[], onNavigate: (position: number) => void): void {
    if (this.visible) {
      this.hide()
    } else {
      this.show(headings, onNavigate)
    }
  }

  private escapeHtml(text: string): string {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
