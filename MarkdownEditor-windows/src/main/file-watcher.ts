import * as chokidar from 'chokidar'
import crypto from 'crypto'

type FileChangeCallback = (eventType: 'add' | 'change' | 'unlink', filePath: string) => void

export class FileWatcherManager {
  private watchers = new Map<string, chokidar.FSWatcher>()

  start(folderPath: string, callback: FileChangeCallback): string {
    const id = crypto.randomUUID()
    const watcher = chokidar.watch(folderPath, {
      ignored: /(^|[/\\])\./,
      persistent: true,
      ignoreInitial: true,
    })

    const isWatched = (fp: string) => fp.endsWith('.md') || fp.endsWith('.html') || fp.endsWith('.htm')
    watcher.on('add', (fp) => { if (isWatched(fp)) callback('add', fp) })
    watcher.on('change', (fp) => { if (isWatched(fp)) callback('change', fp) })
    watcher.on('unlink', (fp) => { if (isWatched(fp)) callback('unlink', fp) })
    watcher.on('error', (err) => {
      console.error(`Watcher ${id} error for ${folderPath}:`, err)
    })

    this.watchers.set(id, watcher)
    return id
  }

  stop(id: string): void {
    const watcher = this.watchers.get(id)
    if (watcher) {
      watcher.close()
      this.watchers.delete(id)
    }
  }

  stopAll(): void {
    for (const [id] of this.watchers) {
      this.stop(id)
    }
  }
}
