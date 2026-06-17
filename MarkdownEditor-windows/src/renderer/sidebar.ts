import type { FileTreeItem } from '../shared/types'

interface SidebarCallbacks {
  onSelectFile: (id: string) => void
  onOpenFile: () => void
  onOpenFolder: () => void
  onCloseFile: (id: string) => void
  onCloseFolder: (id: string) => void
  onShowInFolder: (filePath: string) => void
}

export class Sidebar {
  private container: HTMLElement
  private callbacks: SidebarCallbacks
  private openFiles: FileTreeItem[] = []
  private rootFolders: FileTreeItem[] = []
  private ctxMenu: HTMLDivElement | null = null
  private collapsedFolders: Set<string> = new Set()

  constructor(container: HTMLElement, callbacks: SidebarCallbacks) {
    this.container = container
    this.callbacks = callbacks
    this.render()
  }

  private findFileItem(id: string, items?: FileTreeItem[]): FileTreeItem | undefined {
    const all = items ?? [...this.openFiles, ...this.rootFolders]
    for (const item of all) {
      if (item.id === id) return item
      if (item.children) {
        const found = this.findFileItem(id, item.children)
        if (found) return found
      }
    }
    return undefined
  }

  private showContextMenu(e: MouseEvent, menuItems: Array<{ label: string; action: () => void }>): void {
    e.preventDefault()
    this.hideContextMenu()

    const menu = document.createElement('div')
    menu.className = 'sidebar-context-menu'
    menu.style.left = e.clientX + 'px'
    menu.style.top = e.clientY + 'px'

    menuItems.forEach((item, i) => {
      const el = document.createElement('div')
      el.className = 'ctx-menu-item' + (i > 0 ? ' ctx-menu-separator-top' : '')
      el.textContent = item.label
      el.addEventListener('click', (ev) => {
        ev.stopPropagation()
        item.action()
        this.hideContextMenu()
      })
      menu.appendChild(el)
    })

    document.body.appendChild(menu)
    this.ctxMenu = menu

    setTimeout(() => {
      document.addEventListener('click', this.hideContextMenu)
    }, 0)
  }

  private hideContextMenu = (): void => {
    if (this.ctxMenu) {
      this.ctxMenu.remove()
      this.ctxMenu = null
    }
    document.removeEventListener('click', this.hideContextMenu)
  }

  render(openFiles: FileTreeItem[] = [], rootFolders: FileTreeItem[] = [], selectedID: string | null = null): void {
    this.openFiles = openFiles
    this.rootFolders = rootFolders
    this.container.innerHTML = `
      <div class="sidebar-header">
        <button class="sidebar-icon-btn" id="open-file-btn">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M3 2.5a1 1 0 011-1h4.59a1 1 0 01.7.29l2.42 2.42a1 1 0 01.29.7V12.5a1 1 0 01-1 1H4a1 1 0 01-1-1V2.5z" stroke="currentColor" stroke-width="1" fill="none" stroke-linejoin="round"/>
            <path d="M8.5 2v2.5a.5.5 0 00.5.5H11" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M5.5 8h5" stroke="currentColor" stroke-width="0.9" stroke-linecap="round" opacity="0.35"/>
            <path d="M5.5 10h3.5" stroke="currentColor" stroke-width="0.9" stroke-linecap="round" opacity="0.35"/>
          </svg>
          Open File
        </button>
        <button class="sidebar-icon-btn" id="open-folder-btn">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M1.5 5.5a1.5 1.5 0 011.5-1.5h2.88a1.5 1.5 0 011.06.44l1.12 1.12a1.5 1.5 0 001.06.44H11.5A1.5 1.5 0 0113 7.5v4a1.5 1.5 0 01-1.5 1.5h-9A1.5 1.5 0 011 11.5V5.5z" stroke="currentColor" stroke-width="1" fill="none" stroke-linejoin="round"/>
            <path d="M1.5 7h12" stroke="currentColor" stroke-width="0.8" opacity="0.2"/>
          </svg>
          Open Folder
        </button>
      </div>
      ${this.renderOpenFiles(openFiles, selectedID)}
      ${this.renderFolders(rootFolders, selectedID)}
    `

    document.getElementById('open-file-btn')?.addEventListener('click', () => {
      this.callbacks.onOpenFile()
    })

    document.getElementById('open-folder-btn')?.addEventListener('click', () => {
      this.callbacks.onOpenFolder()
    })

    this.container.querySelectorAll('.file-item').forEach(el => {
      el.addEventListener('click', () => {
        const id = (el as HTMLElement).dataset.id
        if (id) this.callbacks.onSelectFile(id)
      })
      el.addEventListener('contextmenu', (ev: Event) => {
        const id = (el as HTMLElement).dataset.id
        if (!id) return
        const item = this.findFileItem(id)
        if (!item) return
        this.showContextMenu(ev as MouseEvent, [
          { label: 'Show in File Explorer', action: () => this.callbacks.onShowInFolder(item.url) },
          { label: 'Close File', action: () => this.callbacks.onCloseFile(id) },
        ])
      })
    })

    this.container.querySelectorAll('.folder-header, .subfolder-header').forEach(el => {
      el.addEventListener('dblclick', (ev: Event) => {
        ev.stopPropagation()
        const path = (el as HTMLElement).dataset.path
        if (!path) return
        this.toggleFolder(path)
      })
      el.addEventListener('contextmenu', (ev: Event) => {
        const id = (el as HTMLElement).dataset.id
        if (!id) return
        const item = this.findFileItem(id)
        if (!item) return
        this.showContextMenu(ev as MouseEvent, [
          { label: 'Show in File Explorer', action: () => this.callbacks.onShowInFolder(item.url) },
          { label: 'Close Folder', action: () => this.callbacks.onCloseFolder(id) },
        ])
      })
    })

    this.container.querySelectorAll('.collapse-chevron').forEach(el => {
      el.addEventListener('click', (ev: Event) => {
        ev.stopPropagation()
        const header = (el as HTMLElement).closest('.folder-header, .subfolder-header') as HTMLElement
        if (!header) return
        const path = header.dataset.path
        if (!path) return
        this.toggleFolder(path)
      })
    })
  }

  private renderOpenFiles(files: FileTreeItem[], selectedID: string | null): string {
    if (files.length === 0) return ''
    return `
      <div class="sidebar-section">
        <div class="section-title">Opened Files</div>
        ${files.map(f => this.renderFileItem(f, selectedID, 0)).join('')}
      </div>
    `
  }

  private renderFolders(folders: FileTreeItem[], selectedID: string | null): string {
    return folders.map(f => this.renderFolderTree(f, selectedID, 0)).join('')
  }

  private escapeHtml(text: string): string {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  private toggleFolder(path: string): void {
    if (this.collapsedFolders.has(path)) {
      this.collapsedFolders.delete(path)
    } else {
      this.collapsedFolders.add(path)
    }
    this.render(this.openFiles, this.rootFolders, document.querySelector('.file-item.selected')?.getAttribute('data-id') ?? null)
  }

  private fileIcon(): string {
    return `<svg class="file-icon" width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M3 3a1 1 0 011-1h3.38a1 1 0 01.7.3l1.12 1.12a1 1 0 00.7.3H10a1 1 0 011 1v5.28a1 1 0 01-1 1H4a1 1 0 01-1-1V3z" fill="#8e8e93" opacity="0.55"/>
      <path d="M3.5 5h7M3.5 7h5M3.5 9h6" stroke="#8e8e93" stroke-width="0.8" stroke-linecap="round" opacity="0.35"/>
    </svg>`
  }

  private folderIcon(): string {
    return `<svg class="folder-icon" width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M1.5 4A1.5 1.5 0 013 2.5h2.88a1.5 1.5 0 011.06.44l1.12 1.12A1.5 1.5 0 009.12 4.5H11a1.5 1.5 0 011.5 1.5v4.5A1.5 1.5 0 0111 12H3A1.5 1.5 0 011.5 10.5V4z" fill="#007aff" opacity="0.75"/>
    </svg>`
  }

  private renderFileItem(item: FileTreeItem, selectedID: string | null, depth: number = 0): string {
    const isSelected = item.id === selectedID
    const pad = 10 + depth * 14
    return `
      <div class="file-item ${isSelected ? 'selected' : ''}" data-id="${item.id}" style="padding-left: ${pad}px">
        ${this.fileIcon()}
        <span class="file-name">${item.name}</span>
      </div>
    `
  }

  private renderFolderTree(item: FileTreeItem, selectedID: string | null, depth: number): string {
    if (item.isDirectory) {
      const children = item.children || []
      const isCollapsed = this.collapsedFolders.has(item.url)
      return `
        <div class="folder-section${isCollapsed ? ' collapsed' : ''}">
          <div class="folder-header" data-id="${item.id}" data-path="${item.url}">
            ${this.folderIcon()}
            <span class="folder-name">${this.escapeHtml(item.name)}</span>
            <span class="collapse-chevron"><svg class="chevron-icon${isCollapsed ? '' : ' rotated'}" viewBox="0 0 10 10" width="10" height="10"><path d="M3.5 2l3 3-3 3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
          </div>
          ${isCollapsed ? '' : children.map(c => this.renderTreeItem(c, selectedID, depth + 1)).join('')}
        </div>
      `
    }
    return this.renderFileItem(item, selectedID, depth)
  }

  private renderTreeItem(item: FileTreeItem, selectedID: string | null, depth: number): string {
    if (item.isDirectory) {
      const children = item.children || []
      const isCollapsed = this.collapsedFolders.has(item.url)
      return `
        <div class="folder-children-wrapper${isCollapsed ? ' collapsed' : ''}">
          <div class="subfolder-header" data-id="${item.id}" data-path="${item.url}">
            ${this.folderIcon()}
            <span class="folder-name">${this.escapeHtml(item.name)}</span>
            <span class="collapse-chevron"><svg class="chevron-icon${isCollapsed ? '' : ' rotated'}" viewBox="0 0 10 10" width="10" height="10"><path d="M3.5 2l3 3-3 3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
          </div>
          ${isCollapsed ? '' : children.map(c => this.renderTreeItem(c, selectedID, depth + 1)).join('')}
        </div>
      `
    }
    return this.renderFileItem(item, selectedID, depth)
  }
}
