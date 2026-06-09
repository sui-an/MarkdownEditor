import Store from 'electron-store'

interface SessionData {
  windows: string[][]
}

export class SessionStore {
  private store: Store<SessionData>

  constructor() {
    try {
      this.store = new Store<SessionData>({
        name: 'session',
        defaults: { windows: [] },
      })
    } catch (error) {
      console.error('Failed to initialize session store, using in-memory fallback:', error)
      this.store = new Store<SessionData>({
        name: 'session',
        defaults: { windows: [] },
        accessPropertiesByDotNotation: false,
      })
    }
  }

  save(data: SessionData): void {
    this.store.set('windows', data.windows)
  }

  restore(): SessionData {
    return {
      windows: this.store.get('windows', []),
    }
  }
}
