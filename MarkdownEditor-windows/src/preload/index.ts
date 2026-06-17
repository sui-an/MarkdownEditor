import { contextBridge, ipcRenderer } from 'electron'
import type { FileChangeEvent, SessionData } from '../shared/types'

// Relay menu IPC messages as DOM CustomEvents so the renderer can listen via window.addEventListener
const menuEvents = [
  'menu:newNote', 'menu:openFile', 'menu:openFolder', 'menu:save',
  'menu:togglePreviewOnly', 'menu:toggleSidebar', 'menu:toggleOutline',
  'menu:fontLarger', 'menu:fontSmaller', 'menu:theme',
]
for (const event of menuEvents) {
  ipcRenderer.on(event, (_event, ...args) => {
    window.dispatchEvent(new CustomEvent(event, { detail: args[0] }))
  })
}

contextBridge.exposeInMainWorld('electronAPI', {
  openFileDialog: (): Promise<string | null> => ipcRenderer.invoke('dialog:openFile'),
  openFolderDialog: (): Promise<string | null> => ipcRenderer.invoke('dialog:openFolder'),
  saveFileDialog: (defaultName: string): Promise<string | null> => ipcRenderer.invoke('dialog:saveFile', defaultName),
  readFile: (path: string): Promise<{ success: boolean; content?: string; error?: string }> => ipcRenderer.invoke('file:read', path),
  writeFile: (path: string, content: string): Promise<{ success: boolean; error?: string }> => ipcRenderer.invoke('file:write', path, content),
  scanDirectory: (path: string): Promise<{ success: boolean; tree?: Record<string, unknown>; error?: string }> => ipcRenderer.invoke('file:scanDirectory', path),
  watchFolder: (path: string): Promise<string | null> => ipcRenderer.invoke('watcher:start', path),
  unwatchFolder: (id: string): Promise<void> => ipcRenderer.invoke('watcher:stop', id),
  onFileChanged: (callback: (event: Electron.IpcRendererEvent, data: FileChangeEvent) => void) => {
    ipcRenderer.removeAllListeners('file-changed')
    ipcRenderer.on('file-changed', callback)
  },
  removeFileChangedListener: () => {
    ipcRenderer.removeAllListeners('file-changed')
  },
  saveSession: (data: SessionData): Promise<void> => ipcRenderer.invoke('session:save', data),
  restoreSession: (): Promise<SessionData> => ipcRenderer.invoke('session:restore'),
  showMessageBox: (options: Electron.MessageBoxOptions): Promise<number> => ipcRenderer.invoke('dialog:messageBox', options),
  getAppVersion: (): Promise<string> => ipcRenderer.invoke('app:version'),
  showItemInFolder: (filePath: string): Promise<{success: boolean; error?: string}> => 
    ipcRenderer.invoke('file:showInFolder', filePath),
  renameFile: (oldPath: string, newName: string): Promise<{success: boolean; newPath?: string; error?: string}> =>
    ipcRenderer.invoke('file:rename', oldPath, newName),
  minimizeWindow: () => ipcRenderer.invoke('window:minimize'),
  maximizeWindow: () => ipcRenderer.invoke('window:maximize'),
  closeWindow: () => ipcRenderer.invoke('window:close'),
})
