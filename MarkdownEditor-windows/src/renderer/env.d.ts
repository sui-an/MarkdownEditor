/// <reference types="vite/client" />

import type { FileChangeEvent, SessionData } from '../shared/types'

interface ElectronAPI {
  openFileDialog: () => Promise<string | null>
  openFolderDialog: () => Promise<string | null>
  saveFileDialog: (defaultName: string) => Promise<string | null>
  readFile: (path: string) => Promise<{ success: boolean; content?: string; error?: string }>
  writeFile: (path: string, content: string) => Promise<{ success: boolean; error?: string }>
  scanDirectory: (path: string) => Promise<{ success: boolean; tree?: any; error?: string }>
  watchFolder: (path: string) => Promise<string | null>
  unwatchFolder: (id: string) => Promise<void>
  onFileChanged: (callback: (event: Electron.IpcRendererEvent, data: FileChangeEvent) => void) => void
  removeFileChangedListener: () => void
  saveSession: (data: SessionData) => Promise<void>
  restoreSession: () => Promise<SessionData>
  showMessageBox: (options: Electron.MessageBoxOptions) => Promise<number>
  getAppVersion: () => Promise<string>
  showItemInFolder: (filePath: string) => Promise<{success: boolean; error?: string}>
  renameFile: (oldPath: string, newName: string) => Promise<{success: boolean; newPath?: string; error?: string}>
  minimizeWindow: () => void
  maximizeWindow: () => void
  closeWindow: () => void
}

declare global {
  interface Window {
    electronAPI: ElectronAPI
  }
}

export {}
