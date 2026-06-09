import { app, BrowserWindow } from 'electron'
import path from 'path'
import { buildMenu } from './menu'
import { registerIpcHandlers, stopAllWatchers } from './ipc-handlers'

let mainWindow: BrowserWindow | null = null

export function createWindow(): BrowserWindow {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 500,
    frame: false,
    icon: path.join(__dirname, '../../resources/icon.png'),
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  if (process.env.NODE_ENV === 'development') {
    mainWindow.loadURL('http://localhost:5173').catch((err) => {
      console.error('Failed to load dev server:', err.message)
    })
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html')).catch((err) => {
      console.error('Failed to load renderer:', err.message)
    })
  }

  return mainWindow
}

app.whenReady().then(() => {
  registerIpcHandlers()
  buildMenu(createWindow)
  mainWindow = createWindow()
}).catch((err) => {
  console.error('App initialization failed:', err.message)
  app.quit()
})

app.on('before-quit', () => {
  stopAllWatchers()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    try {
      createWindow()
    } catch (err) {
      console.error('Failed to create window on activate:', err)
    }
  }
})
