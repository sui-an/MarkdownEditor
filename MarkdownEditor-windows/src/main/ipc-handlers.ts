import { app, ipcMain, dialog, BrowserWindow, shell } from 'electron'
import fs from 'fs/promises'
import { Dirent } from 'fs'
import path from 'path'
import { FileWatcherManager } from './file-watcher'
import { SessionStore } from './session-store'

const watcherManager = new FileWatcherManager()
const sessionStore = new SessionStore()

interface FileNode {
  path: string
  name: string
  isDirectory: boolean
  children?: FileNode[]
}

export function stopAllWatchers(): void {
  watcherManager.stopAll()
}

export function registerIpcHandlers(): void {
  ipcMain.handle('dialog:openFile', async () => {
    const result = await dialog.showOpenDialog({
      properties: ['openFile'],
      filters: [
        { name: 'Markdown / HTML', extensions: ['md', 'markdown', 'mkd', 'html', 'htm'] },
        { name: 'All Files', extensions: ['*'] },
      ],
    })
    return result.canceled ? null : result.filePaths[0]
  })

  ipcMain.handle('dialog:openFolder', async () => {
    const result = await dialog.showOpenDialog({
      properties: ['openDirectory'],
    })
    return result.canceled ? null : result.filePaths[0]
  })

  ipcMain.handle('dialog:saveFile', async (_event, defaultName: string) => {
    const result = await dialog.showSaveDialog({
      defaultPath: defaultName,
      filters: [
        { name: 'Markdown', extensions: ['md'] },
        { name: 'HTML', extensions: ['html', 'htm'] },
        { name: 'All Files', extensions: ['*'] },
      ],
    })
    return result.canceled ? null : result.filePath
  })

  ipcMain.handle('dialog:messageBox', async (_event, options: Electron.MessageBoxOptions) => {
    const result = await dialog.showMessageBox(options)
    return result.response
  })

  ipcMain.handle('file:read', async (_event, filePath: string) => {
    try {
      const content = await fs.readFile(filePath, 'utf-8')
      return { success: true, content }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      return { success: false, error: message }
    }
  })

  ipcMain.handle('file:write', async (_event, filePath: string, content: string) => {
    try {
      await fs.writeFile(filePath, content, 'utf-8')
      return { success: true }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      return { success: false, error: message }
    }
  })

  ipcMain.handle('file:scanDirectory', async (_event, dirPath: string) => {
    try {
      const tree = await scanDirectorySafe(dirPath)
      return { success: true, tree }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      return { success: false, error: message }
    }
  })

  ipcMain.handle('watcher:start', async (_event, folderPath: string) => {
    const win = BrowserWindow.getFocusedWindow()
    if (!win) return null
    const id = watcherManager.start(folderPath, (eventType, filePath) => {
      if (!win.isDestroyed()) {
        win.webContents.send('file-changed', { type: eventType, path: filePath })
      }
    })
    return id
  })

  ipcMain.handle('watcher:stop', async (_event, id: string) => {
    watcherManager.stop(id)
  })

  ipcMain.handle('session:save', async (_event, data: { windows: string[][] }) => {
    try {
      sessionStore.save(data)
    } catch (error) {
      console.error('Failed to save session:', error)
    }
  })

  ipcMain.handle('session:restore', async () => {
    try {
      return sessionStore.restore()
    } catch (error) {
      console.error('Failed to restore session:', error)
      return { windows: [] }
    }
  })

  ipcMain.handle('app:version', () => {
    return app.getVersion()
  })

  ipcMain.handle('window:minimize', (event) => {
    BrowserWindow.fromWebContents(event.sender)?.minimize()
  })

  ipcMain.handle('window:maximize', (event) => {
    const win = BrowserWindow.fromWebContents(event.sender)
    if (win?.isMaximized()) {
      win.unmaximize()
    } else {
      win?.maximize()
    }
  })

  ipcMain.handle('window:close', (event) => {
    BrowserWindow.fromWebContents(event.sender)?.close()
  })

  ipcMain.handle('file:showInFolder', (_event, filePath: string) => {
    shell.showItemInFolder(filePath)
  })
}

async function scanDirectorySafe(dirPath: string): Promise<FileNode> {
  const name = path.basename(dirPath)
  const stat = await fs.stat(dirPath)
  if (!stat.isDirectory()) {
    return { path: dirPath, name, isDirectory: false }
  }

  let entries: Dirent[]
  try {
    entries = await fs.readdir(dirPath, { withFileTypes: true })
  } catch {
    // Permission denied or other error — return empty directory
    return { path: dirPath, name, isDirectory: true, children: [] }
  }

  const children: FileNode[] = []

  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue
    const fullPath = path.join(dirPath, entry.name)
    if (entry.isDirectory()) {
      try {
        children.push(await scanDirectorySafe(fullPath))
      } catch {
        // Skip inaccessible subdirectories
      }
    } else if (entry.name.endsWith('.md') || entry.name.endsWith('.html') || entry.name.endsWith('.htm')) {
      children.push({
        path: fullPath,
        name: entry.name,
        isDirectory: false,
      })
    }
  }

  children.sort((a, b) => {
    if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1
    return a.name.localeCompare(b.name)
  })

  return { path: dirPath, name, isDirectory: true, children }
}
