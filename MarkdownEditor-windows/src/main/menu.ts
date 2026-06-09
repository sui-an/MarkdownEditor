import { app, Menu, BrowserWindow, MenuItemConstructorOptions } from 'electron'

function getFocusedWindow(): BrowserWindow | null {
  return BrowserWindow.getFocusedWindow()
}

export function buildMenu(createWindow?: () => Electron.BrowserWindow): void {
  const template: MenuItemConstructorOptions[] = [
    {
      label: 'File',
      submenu: [
        {
          label: 'New Note',
          accelerator: 'CmdOrCtrl+N',
          click: () => getFocusedWindow()?.webContents.send('menu:newNote'),
        },
        {
          label: 'New Window',
          accelerator: 'CmdOrCtrl+Shift+N',
          click: () => {
            if (createWindow) createWindow()
          },
        },
        { type: 'separator' },
        {
          label: 'Open File...',
          accelerator: 'CmdOrCtrl+O',
          click: () => getFocusedWindow()?.webContents.send('menu:openFile'),
        },
        {
          label: 'Open Folder...',
          click: () => getFocusedWindow()?.webContents.send('menu:openFolder'),
        },
        { type: 'separator' },
        {
          label: 'Save',
          accelerator: 'CmdOrCtrl+S',
          click: () => getFocusedWindow()?.webContents.send('menu:save'),
        },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        {
          label: 'Toggle Preview Only',
          accelerator: 'CmdOrCtrl+Shift+P',
          click: () => getFocusedWindow()?.webContents.send('menu:togglePreviewOnly'),
        },
        {
          label: 'Toggle Sidebar',
          accelerator: 'CmdOrCtrl+Shift+S',
          click: () => getFocusedWindow()?.webContents.send('menu:toggleSidebar'),
        },
        { type: 'separator' },
        {
          label: 'Toggle Outline',
          accelerator: 'CmdOrCtrl+Shift+O',
          click: () => getFocusedWindow()?.webContents.send('menu:toggleOutline'),
        },
        { type: 'separator' },
        {
          label: 'Larger Text',
          accelerator: 'CmdOrCtrl+=',
          click: () => getFocusedWindow()?.webContents.send('menu:fontLarger'),
        },
        {
          label: 'Smaller Text',
          accelerator: 'CmdOrCtrl+-',
          click: () => getFocusedWindow()?.webContents.send('menu:fontSmaller'),
        },
        { type: 'separator' },
        {
          label: 'Appearance',
          submenu: [
            {
              label: 'System',
              type: 'radio',
              checked: true,
              click: () => getFocusedWindow()?.webContents.send('menu:theme', 'system'),
            },
            {
              label: 'Light',
              type: 'radio',
              click: () => getFocusedWindow()?.webContents.send('menu:theme', 'light'),
            },
            {
              label: 'Dark',
              type: 'radio',
              click: () => getFocusedWindow()?.webContents.send('menu:theme', 'dark'),
            },
          ],
        },
      ],
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'close' },
      ],
    },
  ]

  const menu = Menu.buildFromTemplate(template)
  Menu.setApplicationMenu(menu)
}
