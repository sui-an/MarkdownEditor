export type ThemeMode = 'system' | 'light' | 'dark'

export class ThemeManager {
  private mode: ThemeMode = 'system'
  private mediaQuery: MediaQueryList
  private listener: () => void
  private onThemeChange?: (isDark: boolean) => void

  constructor() {
    this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    this.listener = () => this.apply()
    this.mediaQuery.addEventListener('change', this.listener)
  }

  setMode(mode: ThemeMode): void {
    this.mode = mode
    this.apply()
  }

  getMode(): ThemeMode {
    return this.mode
  }

  isDark(): boolean {
    if (this.mode === 'dark') return true
    if (this.mode === 'light') return false
    return this.mediaQuery.matches
  }

  setOnThemeChange(callback: (isDark: boolean) => void): void {
    this.onThemeChange = callback
  }

  private apply(): void {
    const isDark = this.isDark()
    document.documentElement.classList.toggle('dark', isDark)
    this.onThemeChange?.(isDark)
  }

  toggle(): void {
    if (this.mode === 'system') {
      this.setMode(this.isDark() ? 'light' : 'dark')
    } else {
      this.setMode(this.mode === 'dark' ? 'light' : 'dark')
    }
  }

  destroy(): void {
    this.mediaQuery.removeEventListener('change', this.listener)
  }
}
