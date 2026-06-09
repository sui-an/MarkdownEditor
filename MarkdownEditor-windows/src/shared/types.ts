export interface FileTreeItem {
  id: string
  url: string
  name: string
  isDirectory: boolean
  parentID: string | null
  children?: FileTreeItem[]
}

export interface HeadingItem {
  level: number
  text: string
  position: number
}

export interface WindowStateData {
  rootFolders: FileTreeItem[]
  openFiles: FileTreeItem[]
  selectedFileID: string | null
  currentFileContent: string
  currentFilePath: string | null
  isFileDirty: boolean
  previewOnly: boolean
  previewWidth: number
  sidebarVisible: boolean
  searchQuery: string
  outlineHeadings: HeadingItem[]
  themeMode: 'system' | 'light' | 'dark'
  fontSize: number
}

export interface IpcFileResult {
  success: boolean
  content?: string
  error?: string
}

export interface IpcFileInfo {
  path: string
  name: string
  isDirectory: boolean
  children?: IpcFileInfo[]
}

export interface FileChangeEvent {
  type: 'add' | 'change' | 'unlink'
  path: string
}

export interface SessionData {
  windows: string[][]
}
