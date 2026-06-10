import type { FileTreeItem, HeadingItem } from '../shared/types'
import type { FileChangeEvent, SessionData } from '../shared/types'

export class WindowState {
  rootFolders: FileTreeItem[] = []
  openFiles: FileTreeItem[] = []
  selectedFileID: string | null = null
  currentFileContent = ''
  currentFilePath: string | null = null
  isFileDirty = false
  previewOnly = false
  previewContentWidth = 0 // 0=720px, 1=960px, 2=full
  sidebarVisible = true
  searchQuery = ''
  outlineHeadings: HeadingItem[] = []
  themeMode: 'system' | 'light' | 'dark' = 'system'
  fontSize = 14
  isLoadingFile = false
  isHtmlFile = false

  private folderWatcherIDs: Map<string, string> = new Map()
  private fileContentCache: Map<string, string> = new Map()
  private onStateChange?: () => void

  setOnChange(callback: () => void): void {
    this.onStateChange = callback
  }

  private notifyChange(): void {
    this.onStateChange?.()
  }

  async openFileDialog(): Promise<void> {
    const filePath = await window.electronAPI.openFileDialog()
    if (!filePath) return
    await this.openFile(filePath)
  }

  async openFolderDialog(): Promise<void> {
    const folderPath = await window.electronAPI.openFolderDialog()
    if (!folderPath) return
    await this.openFolder(folderPath)
  }

  async openFile(filePath: string): Promise<void> {
    if (this.openFiles.some(f => f.url === filePath)) {
      const found = this.openFiles.find(f => f.url === filePath)
      if (found) this.selectFile(found.id)
      return
    }

    const result = await window.electronAPI.readFile(filePath)
    if (!result.success) {
      await window.electronAPI.showMessageBox({
        type: 'warning',
        title: 'Cannot Open File',
        message: result.error || 'Unknown error',
      })
      return
    }

    const item: FileTreeItem = {
      id: crypto.randomUUID(),
      url: filePath,
      name: filePath.split(/[/\\]/).pop() || '',
      isDirectory: false,
      parentID: null,
    }

    this.openFiles.push(item)
    this.fileContentCache.set(filePath, result.content!)
    this.selectedFileID = item.id
    this.currentFilePath = filePath
    this.currentFileContent = result.content!
    this.isHtmlFile = filePath.endsWith('.html') || filePath.endsWith('.htm')
    this.isFileDirty = false
    this.notifyChange()
  }

  private convertFileNode(node: any, parentID: string | null = null): FileTreeItem {
    const id = crypto.randomUUID()
    return {
      id,
      url: node.path,
      name: node.name,
      isDirectory: node.isDirectory,
      parentID,
      children: node.children
        ? node.children.map((c: any) => this.convertFileNode(c, id))
        : undefined,
    }
  }

  async openFolder(folderPath: string): Promise<void> {
    if (this.rootFolders.some(f => f.url === folderPath)) return

    const result = await window.electronAPI.scanDirectory(folderPath)
    if (!result.success) {
      await window.electronAPI.showMessageBox({
        type: 'warning',
        title: 'Cannot Open Folder',
        message: result.error || 'Unknown error',
      })
      return
    }

    const root = this.convertFileNode(result.tree)
    this.rootFolders.push(root)
    const watcherID = await window.electronAPI.watchFolder(folderPath)
    if (watcherID) {
      this.folderWatcherIDs.set(root.id, watcherID)
    }
    this.notifyChange()
  }

  async saveCurrentFile(): Promise<void> {
    if (!this.currentFilePath) return
    const result = await window.electronAPI.writeFile(this.currentFilePath, this.currentFileContent)
    if (!result.success) {
      await window.electronAPI.showMessageBox({
        type: 'warning',
        title: 'Cannot Save File',
        message: result.error || 'Unknown error',
      })
      return
    }
    this.isFileDirty = false
    this.fileContentCache.set(this.currentFilePath, this.currentFileContent)
    this.notifyChange()
  }

  closeFile(id: string): void {
    const file = this.openFiles.find(f => f.id === id)
    this.openFiles = this.openFiles.filter(f => f.id !== id)
    if (file) {
      this.fileContentCache.delete(file.url)
    }
    if (this.selectedFileID === id) {
      this.selectedFileID = null
      this.currentFilePath = null
      this.currentFileContent = ''
      this.isFileDirty = false
    }
    this.notifyChange()
  }

  closeFolder(id: string): void {
    const idx = this.rootFolders.findIndex(f => f.id === id)
    if (idx === -1) return
    const watcherID = this.folderWatcherIDs.get(id)
    if (watcherID) {
      window.electronAPI.unwatchFolder(watcherID)
      this.folderWatcherIDs.delete(id)
    }
    this.rootFolders.splice(idx, 1)
    if (this.selectedFileID && !this.findItem(this.selectedFileID)) {
      this.selectedFileID = null
      this.currentFilePath = null
      this.currentFileContent = ''
      this.isFileDirty = false
    }
    this.notifyChange()
  }

  selectFile(id: string): void {
    this.selectedFileID = id
    const item = this.findItem(id)
    if (item && !item.isDirectory) {
      this.currentFilePath = item.url
      this.isHtmlFile = item.url.endsWith('.html') || item.url.endsWith('.htm')
      const cached = this.fileContentCache.get(item.url)
      if (cached !== undefined) {
        this.currentFileContent = cached
        this.outlineHeadings = this.parseHeadings(cached)
      } else {
        this.loadFileContent(item.url)
      }
    }
    this.notifyChange()
  }

  private async loadFileContent(filePath: string): Promise<void> {
    this.isLoadingFile = true
    this.notifyChange()
    const result = await window.electronAPI.readFile(filePath)
    if (result.success && result.content !== undefined) {
      this.currentFileContent = result.content
      this.fileContentCache.set(filePath, result.content)
      this.isHtmlFile = filePath.endsWith('.html') || filePath.endsWith('.htm')
      this.outlineHeadings = this.parseHeadings(result.content)
      this.isFileDirty = false
    }
    this.isLoadingFile = false
    this.notifyChange()
  }

  updateContent(content: string): void {
    this.currentFileContent = content
    this.isFileDirty = true
    if (this.currentFilePath) {
      this.fileContentCache.set(this.currentFilePath, content)
    }
    this.outlineHeadings = this.parseHeadings(content)
    this.notifyChange()
  }

  parseHeadings(content: string): HeadingItem[] {
    if (this.isHtmlFile) {
      return this.parseHTMLHeadings(content)
    }
    const headings: HeadingItem[] = []
    const lines = content.split('\n')
    let inFence = false
    let fenceChar = ''

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]

      if (/^```/.test(line) || /^~~~/.test(line)) {
        if (!inFence) {
          inFence = true
          fenceChar = line.startsWith('```') ? '```' : '~~~'
        } else if (line.startsWith(fenceChar)) {
          inFence = false
        }
        continue
      }

      if (!inFence) {
        const match = line.match(/^(#{1,6})\s+(.+)$/)
        if (match) {
          headings.push({
            level: match[1].length as 1 | 2 | 3 | 4 | 5 | 6,
            text: match[2].trim(),
            position: i,
          })
        }
      }
    }

    return headings
  }

  private parseHTMLHeadings(html: string): HeadingItem[] {
    const headings: HeadingItem[] = []
    const cleaned = html.replace(/<!--[\s\S]*?-->/g, '')
    const regex = /<h([1-6])(?:\s[^>]*)?>(.*?)<\/h\1>/gi
    let match: RegExpExecArray | null
    while ((match = regex.exec(cleaned)) !== null) {
      const level = parseInt(match[1], 10) as 1 | 2 | 3 | 4 | 5 | 6
      const rawTitle = match[2]
      const text = rawTitle.replace(/<[^>]+>/g, '').trim()
      if (!text) continue
      const beforeText = cleaned.slice(0, match.index)
      const position = beforeText.split('\n').length - 1
      headings.push({ level, text, position })
    }
    return headings
  }

  private findItem(id: string): FileTreeItem | undefined {
    for (const file of this.openFiles) {
      if (file.id === id) return file
    }
    for (const folder of this.rootFolders) {
      const found = this.findInTree(folder, id)
      if (found) return found
    }
    return undefined
  }

  private findInTree(item: FileTreeItem, id: string): FileTreeItem | undefined {
    if (item.id === id) return item
    if (item.children) {
      for (const child of item.children) {
        const found = this.findInTree(child, id)
        if (found) return found
      }
    }
    return undefined
  }

  handleExternalChange(type: string, filePath: string): void {
    if (filePath !== this.currentFilePath) return

    if (type === 'unlink') {
      this.currentFileContent = ''
      this.currentFilePath = null
      this.selectedFileID = null
      this.isFileDirty = false
      this.notifyChange()
      return
    }

    this.reloadFileWithPrompt(filePath)
  }

  private async reloadFileWithPrompt(filePath: string): Promise<void> {
    const response = await window.electronAPI.showMessageBox({
      type: 'question',
      buttons: ['Reload', 'Keep Current'],
      defaultId: 0,
      title: 'File Changed Externally',
      message: `"${filePath.split(/[/\\]/).pop()}" was modified by another application. Reload?`,
    })

    if (response === 0) {
      const result = await window.electronAPI.readFile(filePath)
      if (result.success && result.content !== undefined) {
        this.currentFileContent = result.content
        this.fileContentCache.set(filePath, result.content)
        this.isFileDirty = false
        this.notifyChange()
      }
    }
  }

  destroy(): void {
    for (const [, watcherID] of this.folderWatcherIDs) {
      window.electronAPI.unwatchFolder(watcherID)
    }
    this.folderWatcherIDs.clear()
    window.electronAPI.removeFileChangedListener()
  }
}
