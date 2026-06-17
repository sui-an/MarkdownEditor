import './styles/theme-vars.css'
import './styles/global.css'
import './styles/titlebar.css'
import './styles/sidebar.css'
import './styles/editor.css'
import './styles/preview.css'
import './styles/outline.css'

import { WindowState } from './state'
import { Sidebar } from './sidebar'
import { Editor } from './editor'
import { Preview } from './preview'
import { OutlinePanel } from './outline'
import { ThemeManager } from './theme'

class App {
  private state: WindowState
  private sidebar: Sidebar
  private editor: Editor
  private preview: Preview
  private outline: OutlinePanel
  private theme: ThemeManager
  private sidebarVisible = true
  private debounceTimer: ReturnType<typeof setTimeout> | null = null

  constructor() {
    this.state = new WindowState()
    this.theme = new ThemeManager()
    this.outline = new OutlinePanel()

    const sidebarContainer = document.getElementById('sidebar')!
    this.sidebar = new Sidebar(sidebarContainer, {
      onSelectFile: (id) => {
        this.state.selectFile(id)
        this.syncUI()
      },
      onOpenFile: () => {
        this.state.openFileDialog()
      },
      onOpenFolder: () => {
        this.state.openFolderDialog()
      },
      onCloseFile: (id) => {
        this.state.closeFile(id)
        this.syncUI()
      },
      onRemoveFolder: (id) => {
        this.state.removeFolder(id)
        this.syncUI()
      },
      onShowInFolder: (filePath) => {
        window.electronAPI.showItemInFolder(filePath)
      },
      onRenameItem: async (id, newName) => {
        const ok = await this.state.renameItem(id, newName)
        if (ok) this.syncUI()
        return ok
      },
    })

    const editorContainer = document.getElementById('editor-pane')!
    this.editor = new Editor(editorContainer, '', (content) => {
      this.state.updateContent(content)
      this.debouncePreview(content)
    })

    const previewContainer = document.getElementById('preview-pane')!
    this.preview = new Preview(previewContainer)

    this.state.setOnChange(() => this.syncUI())

    this.theme.setOnThemeChange((isDark) => {
      this.editor.setTheme(isDark)
      this.preview.setTheme(isDark)
    })

    this.setupIPC()
    this.setupTitlebar()
    this.setupDragDividers()
    this.setupSearch()

    this.theme.setMode('system')

    this.restoreSession()
  }

  private setupIPC(): void {
    window.electronAPI.onFileChanged((_event, data) => {
      this.state.handleExternalChange(data.type, data.path)
    })

    const menuHandler = (event: string, handler: () => void) => {
      window.addEventListener(event, () => handler())
    }

    menuHandler('menu:openFile', () => this.state.openFileDialog())
    menuHandler('menu:openFolder', () => this.state.openFolderDialog())
    menuHandler('menu:save', () => this.state.saveCurrentFile())
    menuHandler('menu:togglePreviewOnly', () => this.togglePreviewOnly())
    menuHandler('menu:toggleSidebar', () => this.toggleSidebar())
    menuHandler('menu:newNote', () => this.newNote())
    menuHandler('menu:toggleOutline', () => {
      const headings = this.state.currentFileContent
        ? this.state.parseHeadings(this.state.currentFileContent)
        : []
      this.outline.toggle(headings, (pos) => {
        this.editor.scrollToLine(pos)
        this.preview.scrollToHeading(pos)
      })
    })
    menuHandler('menu:fontLarger', () => {
      this.state.pushFontSizeUndo(this.state.fontSize)
      this.state.fontSize = Math.min(72, this.state.fontSize + 1)
      this.editor.setFontSize(this.state.fontSize)
    })
    menuHandler('menu:fontSmaller', () => {
      this.state.pushFontSizeUndo(this.state.fontSize)
      this.state.fontSize = Math.max(9, this.state.fontSize - 1)
      this.editor.setFontSize(this.state.fontSize)
    })
    menuHandler('menu:find', () => this.toggleSearch())
    menuHandler('menu:findReplace', () => {
      this.toggleSearch()
      const replaceInput = document.getElementById('replace-input') as HTMLInputElement
      if (replaceInput) replaceInput.focus()
    })

    window.addEventListener('menu:theme', ((e: CustomEvent) => {
      this.theme.setMode(e.detail)
      this.preview.setTheme(this.theme.isDark())
    }) as EventListener)
  }

  private setupTitlebar(): void {
    document.getElementById('btn-close')?.addEventListener('click', () => {
      this.state.saveCurrentFile()
      window.electronAPI.closeWindow()
    })
    document.getElementById('btn-minimize')?.addEventListener('click', () => {
      window.electronAPI.minimizeWindow()
    })
    document.getElementById('btn-maximize')?.addEventListener('click', () => {
      window.electronAPI.maximizeWindow()
    })
    document.getElementById('btn-sidebar-toggle')?.addEventListener('click', () => {
      this.toggleSidebar()
    })
    document.getElementById('btn-new-note')?.addEventListener('click', () => {
      this.newNote()
    })
    document.getElementById('btn-preview-toggle')?.addEventListener('click', () => {
      this.togglePreviewOnly()
    })
    document.getElementById('btn-outline-toggle')?.addEventListener('click', (e) => {
      e.stopPropagation()
      const headings = this.state.currentFileContent
        ? this.state.parseHeadings(this.state.currentFileContent)
        : []
      this.outline.toggle(headings, (pos) => {
        this.editor.scrollToLine(pos)
        this.preview.scrollToHeading(pos)
      })
      this.syncUI()
    })
    document.getElementById('btn-content-width')?.addEventListener('click', () => {
      this.cycleContentWidth()
    })
  }

  private dragState: { isDragging: boolean; type: 'sidebar' | 'split'; startX: number; currentX: number } = { isDragging: false, type: 'split', startX: 0, currentX: 0 }
  private dragTarget: HTMLElement | null = null

  private dragHandler = (e: PointerEvent) => this.onDrag(e)
  private endDragHandler = (e: PointerEvent) => this.endDrag(e)

  private setupDragDividers(): void {
    const sidebarDiv = document.getElementById('divider-sidebar')
    const splitDiv = document.getElementById('divider-preview')
    if (sidebarDiv) sidebarDiv.addEventListener('pointerdown', (e) => this.startDrag(e, 'sidebar'))
    if (splitDiv) splitDiv.addEventListener('pointerdown', (e) => this.startDrag(e, 'split'))
  }

  private startDrag(e: PointerEvent, type: 'sidebar' | 'split'): void {
    if (e.button !== 0) return
    e.preventDefault()
    const target = e.currentTarget as HTMLElement
    target.setPointerCapture(e.pointerId)
    this.dragTarget = target
    this.dragState = { isDragging: true, type, startX: e.clientX, currentX: e.clientX }
    target.classList.add('active')
    document.body.style.cursor = 'col-resize'
    document.body.style.userSelect = 'none'
    target.addEventListener('pointermove', this.dragHandler)
    target.addEventListener('pointerup', this.endDragHandler)
  }

  private onDrag(e: PointerEvent): void {
    if (!this.dragState.isDragging) return
    this.dragState.currentX = e.clientX

    if (this.dragState.type === 'sidebar') {
      const sidebar = document.getElementById('sidebar')
      if (sidebar) {
        sidebar.style.width = Math.max(160, Math.min(360, e.clientX)) + 'px'
      }
    } else {
      const editorPane = document.getElementById('editor-pane')
      if (!editorPane) return
      const contentArea = document.getElementById('content-area')
      if (!contentArea) return
      const rect = contentArea.getBoundingClientRect()
      const newWidth = Math.max(150, Math.min(rect.width - 158, e.clientX - rect.left))
      editorPane.style.width = newWidth + 'px'
    }
  }

  private endDrag(e: PointerEvent): void {
    this.dragState.isDragging = false
    document.querySelectorAll('.divider.active').forEach(el => el.classList.remove('active'))
    document.body.style.cursor = ''
    document.body.style.userSelect = ''
    if (this.dragTarget) {
      this.dragTarget.removeEventListener('pointermove', this.dragHandler)
      this.dragTarget.removeEventListener('pointerup', this.endDragHandler)
      this.dragTarget.releasePointerCapture(e.pointerId)
      this.dragTarget = null
    }
  }

  private searchState = { active: false, query: '', index: 0, count: 0 }

  private setupSearch(): void {
    const panel = document.createElement('div')
    panel.id = 'search-bar'
    panel.className = 'search-floating-panel'
    panel.style.display = 'none'
    panel.innerHTML = `
      <input type="text" id="search-input" placeholder="Search..." spellcheck="false">
      <input type="text" id="replace-input" placeholder="Replace..." spellcheck="false">
      <span id="search-count" class="search-count"></span>
      <button id="search-prev" class="search-nav-btn" title="Previous (Shift+Enter)">
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M9 8L6 5 3 8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>
      <button id="search-next" class="search-nav-btn" title="Next (Enter)">
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 4l3 3 3-3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>
      <button id="replace-btn" class="replace-btn" title="Replace">Replace</button>
      <button id="replace-all-btn" class="replace-btn" title="Replace All">All</button>
      <button id="search-close" class="search-close-btn" title="Close (Escape)">
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 3l6 6M9 3l-6 6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
      </button>
    `

    this.makeDraggable(panel)
    document.body.appendChild(panel)


    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'w') {
        e.preventDefault()
        e.stopPropagation()
        this.state.closeCurrentFile()
        return
      }
      if (!this.searchState.active && (e.metaKey || e.ctrlKey) && e.key === 'z' && !e.shiftKey) {
        const newSize = this.state.undoFontSize()
        if (newSize !== null) {
          e.preventDefault()
          this.state.fontSize = newSize
          this.editor.setFontSize(newSize)
          return
        }
      }
      if (!this.searchState.active && (e.metaKey || e.ctrlKey) && e.key === 'z' && e.shiftKey) {
        const newSize = this.state.redoFontSize()
        if (newSize !== null) {
          e.preventDefault()
          this.state.fontSize = newSize
          this.editor.setFontSize(newSize)
          return
        }
      }
      if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
        e.preventDefault()
        this.toggleSearch()
        return
      }
      if ((e.metaKey || e.ctrlKey) && e.key === 'h') {
        e.preventDefault()
        this.toggleSearch()
        const replaceInput = document.getElementById('replace-input') as HTMLInputElement
        if (replaceInput) replaceInput.focus()
        return
      }
      if ((e.metaKey || e.ctrlKey) && e.key === 'g') {
        if (this.searchState.active) {
          e.preventDefault()
          if (e.shiftKey) this.searchPrev()
          else this.searchNext()
        }
        return
      }
      if (this.searchState.active && e.key === 'Escape') {
        e.preventDefault()
        this.closeSearch()
        return
      }
    })

    const searchInput = document.getElementById('search-input') as HTMLInputElement
    if (searchInput) {
      let isComposing = false
      searchInput.addEventListener('compositionstart', () => { isComposing = true })
      searchInput.addEventListener('compositionend', () => {
        isComposing = false
        this.doSearch(searchInput.value)
      })
      searchInput.addEventListener('input', () => {
        if (!isComposing) {
          this.doSearch(searchInput.value)
        }
      })
      searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault()
          e.stopPropagation()
          if (e.shiftKey) this.searchPrev()
          else this.searchNext()
        }
        if (e.key === 'Escape') {
          this.closeSearch()
        }
      })
    }
    document.getElementById('search-next')?.addEventListener('click', () => this.searchNext())
    document.getElementById('search-prev')?.addEventListener('click', () => this.searchPrev())
    document.getElementById('search-close')?.addEventListener('click', () => this.closeSearch())
    document.getElementById('replace-btn')?.addEventListener('click', () => this.replaceCurrent())
    document.getElementById('replace-all-btn')?.addEventListener('click', () => this.replaceAll())
  }

  private toggleSearch(): void {
    const bar = document.getElementById('search-bar')
    if (!bar) return
    if (this.searchState.active) {
      this.closeSearch()
    } else {
      this.searchState.active = true
      bar.style.display = ''
      bar.style.top = '60px'
      bar.style.left = '50%'
      bar.style.transform = 'translateX(-50%)'
      const input = document.getElementById('search-input') as HTMLInputElement
      if (input) {
        input.value = ''
        input.focus()
      }
    }
  }

  private doSearch(query: string): void {
    this.searchState.query = query
    this.searchState.index = 0

    if (!query) {
      this.editor.clearSearch()
      this.preview.clearSearch()
      this.searchState.count = 0
      this.updateSearchCount()
      return
    }

    const editorCount = this.editor.search(query)
    const result = this.preview.search(query, 0)
    this.searchState.count = Math.max(editorCount, result?.count ?? 0)

    if (this.searchState.count > 0) {
      this.editor.selectMatch(0, query)
    }
    this.updateSearchCount()

    const input = document.getElementById('search-input') as HTMLInputElement
    if (input && document.activeElement !== input && this.searchState.active) {
      input.focus()
    }
  }

  private searchNext(): void {
    if (!this.searchState.query || this.searchState.count === 0) return
    this.searchState.index = (this.searchState.index + 1) % this.searchState.count
    this.editor.selectMatch(this.searchState.index, this.searchState.query)
    this.preview.search(this.searchState.query, this.searchState.index)
    this.updateSearchCount()
  }

  private searchPrev(): void {
    if (!this.searchState.query || this.searchState.count === 0) return
    this.searchState.index = (this.searchState.index - 1 + this.searchState.count) % this.searchState.count
    this.editor.selectMatch(this.searchState.index, this.searchState.query)
    this.preview.search(this.searchState.query, this.searchState.index)
    this.updateSearchCount()
  }

  private closeSearch(): void {
    this.searchState = { active: false, query: '', index: 0, count: 0 }
    const bar = document.getElementById('search-bar')
    if (bar) bar.style.display = 'none'
    this.editor.clearSearch()
    this.preview.clearSearch()
    this.updateSearchCount()
    this.editor.focus()
  }

  private updateSearchCount(): void {
    const el = document.getElementById('search-count')
    if (!el) return
    if (this.searchState.count > 0) {
      el.textContent = (this.searchState.index + 1) + ' / ' + this.searchState.count
    } else {
      el.textContent = ''
    }
  }

  private replaceCurrent(): void {
    if (!this.searchState.query || this.searchState.count === 0) return
    const replaceInput = document.getElementById('replace-input') as HTMLInputElement
    if (!replaceInput) return
    const replacement = replaceInput.value
    const replaced = this.editor.replaceAt(this.searchState.index, this.searchState.query, replacement)
    if (replaced) {
      this.state.updateContent(this.editor.getContent())
      this.doSearch(this.searchState.query)
    }
  }

  private replaceAll(): void {
    if (!this.searchState.query || this.searchState.count === 0) return
    const replaceInput = document.getElementById('replace-input') as HTMLInputElement
    if (!replaceInput) return
    const replacement = replaceInput.value
    const replaced = this.editor.replaceAll(this.searchState.query, replacement)
    if (replaced > 0) {
      this.state.updateContent(this.editor.getContent())
      this.doSearch(this.searchState.query)
    }
  }

  private makeDraggable(el: HTMLElement): void {
    let isDragging = false, startX = 0, startY = 0, origLeft = 0, origTop = 0
    el.addEventListener('pointerdown', (e) => {
      const tag = (e.target as HTMLElement).tagName
      if (tag === 'INPUT' || tag === 'BUTTON' || (e.target as HTMLElement).closest('button')) return
      isDragging = true
      startX = e.clientX
      startY = e.clientY
      const rect = el.getBoundingClientRect()
      origLeft = rect.left
      origTop = rect.top
      el.style.transform = 'none'
      el.style.left = origLeft + 'px'
      el.style.top = origTop + 'px'
      el.setPointerCapture(e.pointerId)
    })
    el.addEventListener('pointermove', (e) => {
      if (!isDragging) return
      el.style.left = (origLeft + e.clientX - startX) + 'px'
      el.style.top = (origTop + e.clientY - startY) + 'px'
    })
    el.addEventListener('pointerup', () => { isDragging = false })
  }

  private syncUI(): void {
    this.sidebar.render(
      this.state.openFiles,
      this.state.rootFolders,
      this.state.selectedFileID
    )

    if (this.state.selectedFileID && this.state.currentFilePath) {
      if (this.editor.getContent() !== this.state.currentFileContent) {
        this.editor.setContent(this.state.currentFileContent)
      }
      this.editor.setLanguage(this.state.isHtmlFile)
      this.editor.setFontSize(this.state.fontSize)
      this.editor.setTheme(this.theme.isDark())

      const fileName = this.state.currentFilePath.split(/[/\\]/).pop() || ''
      const dirty = this.state.isFileDirty ? '  Edited' : ''
      const titlebarText = document.getElementById('titlebar-text')
      if (titlebarText) titlebarText.textContent = fileName + dirty

      const noFileOverlay = document.getElementById('no-file-overlay')
      if (noFileOverlay) noFileOverlay.classList.add('hidden')
    } else {
      const titlebarText = document.getElementById('titlebar-text')
      if (titlebarText) titlebarText.textContent = 'MarkdownEditor'

      const noFileOverlay = document.getElementById('no-file-overlay')
      if (noFileOverlay) noFileOverlay.classList.remove('hidden')

      if (this.editor.getContent() !== '') {
        this.editor.setContent('')
        this.preview.clear()
      }
    }

    const editorPane = document.getElementById('editor-pane')
    const previewPane = document.getElementById('preview-pane')
    const previewDivider = document.getElementById('divider-preview')
    if (editorPane) {
      editorPane.classList.toggle('hidden', this.state.previewOnly)
    }
    if (previewPane) {
      previewPane.classList.remove('hidden')
    }
    if (previewDivider) {
      previewDivider.style.display = this.state.previewOnly ? 'none' : ''
    }

    const sidebar = document.getElementById('sidebar')
    if (sidebar) sidebar.style.display = this.sidebarVisible ? '' : 'none'

    const sidebarDivider = document.getElementById('divider-sidebar')
    if (sidebarDivider) sidebarDivider.style.display = this.sidebarVisible ? '' : 'none'

    const previewBtn = document.getElementById('btn-preview-toggle')
    if (previewBtn) {
      previewBtn.classList.toggle('active', this.state.previewOnly)
      previewBtn.title = this.state.previewOnly ? 'Exit Preview Only' : 'Toggle Preview Only'
    }

    const contentWidthBtn = document.getElementById('btn-content-width')
    if (contentWidthBtn) {
      contentWidthBtn.style.display = this.state.previewOnly ? '' : 'none'
      const svgs = [
        '<svg width="16" height="16" viewBox="0 0 18 18" fill="none"><rect x="4" y="3" width="10" height="12" rx="1.5" stroke="currentColor" stroke-width="1.3" stroke-dasharray="2 2"/></svg>',
        '<svg width="16" height="16" viewBox="0 0 18 18" fill="none"><rect x="2.5" y="3" width="13" height="12" rx="1.5" stroke="currentColor" stroke-width="1.3"/></svg>',
        '<svg width="16" height="16" viewBox="0 0 18 18" fill="none"><rect x="1" y="3" width="16" height="12" rx="1.5" stroke="currentColor" stroke-width="1.3"/><path d="M1 6h16" stroke="currentColor" stroke-width="0.8" opacity="0.3"/></svg>'
      ]
      contentWidthBtn.innerHTML = svgs[this.state.previewContentWidth]
      const labels = ['720px', '960px', 'Full Width']
      contentWidthBtn.title = 'Content Width: ' + labels[this.state.previewContentWidth]
    }

    const outlineBtn = document.getElementById('btn-outline-toggle')
    if (outlineBtn) {
      outlineBtn.classList.toggle('active', this.outline.isVisible())
      if (this.outline.isVisible() && this.state.currentFileContent) {
        this.outline.updateHeadings(this.state.parseHeadings(this.state.currentFileContent))
      }
    }

    const sidebarBtn = document.getElementById('btn-sidebar-toggle')
    if (sidebarBtn) sidebarBtn.classList.toggle('active', this.sidebarVisible)
  }

  private debouncePreview(content: string): void {
    if (this.debounceTimer !== null) clearTimeout(this.debounceTimer)
    const delay = content.length > 100000 ? 500 : 200
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null
      this.preview.update(content, this.state.previewContentWidth, this.state.isHtmlFile)
    }, delay)
  }

  private togglePreviewOnly(): void {
    this.state.previewOnly = !this.state.previewOnly
    if (!this.state.previewOnly) {
      this.state.previewContentWidth = 0
    }
    this.syncUI()
  }

  private cycleContentWidth(): void {
    this.state.previewContentWidth = (this.state.previewContentWidth + 1) % 3
    if (this.state.currentFileContent) {
      this.preview.update(this.state.currentFileContent, this.state.previewContentWidth, this.state.isHtmlFile)
    }
    this.syncUI()
  }

  private refreshPreview(): void {
    if (this.state.currentFileContent) {
      this.preview.update(this.state.currentFileContent, this.state.previewContentWidth, this.state.isHtmlFile)
    }
  }

  private toggleSidebar(): void {
    this.sidebarVisible = !this.sidebarVisible
    this.syncUI()
  }

  private async newNote(): Promise<void> {
    const filePath = await window.electronAPI.saveFileDialog('Untitled.md')
    if (!filePath) return
    const result = await window.electronAPI.writeFile(filePath, '')
    if (result.success) {
      await this.state.openFile(filePath)
    }
  }

  private async restoreSession(): Promise<void> {
    try {
      const data = await window.electronAPI.restoreSession()
      if (data.windows && data.windows.length > 0 && data.windows[0]) {
        for (const fp of data.windows[0]) {
          await this.state.openFile(fp)
        }
      }
    } catch {
      // No session to restore  start fresh
    }
  }
}

new App()
