import { EditorView, keymap, placeholder, Decoration, DecorationSet, lineNumbers } from '@codemirror/view'
import { EditorState, Compartment, StateEffect, StateField, Range, Transaction } from '@codemirror/state'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import { markdown, markdownLanguage } from '@codemirror/lang-markdown'
import { syntaxHighlighting, HighlightStyle, defaultHighlightStyle } from '@codemirror/language'
import { tags } from '@lezer/highlight'
import { highlightSelectionMatches } from '@codemirror/search'
import { closeBrackets } from '@codemirror/autocomplete'

const fontSizeCompartment = new Compartment()
const themeCompartment = new Compartment()
const languageCompartment = new Compartment()
const setHighlight = StateEffect.define<DecorationSet>()
const highlightField = StateField.define<DecorationSet>({
  create() { return Decoration.none },
  update(decos, tr) {
    for (const e of tr.effects) {
      if (e.is(setHighlight)) return e.value
    }
    return decos.map(tr.changes)
  },
  provide: f => EditorView.decorations.from(f),
})

const setSearchDecos = StateEffect.define<DecorationSet>()
const searchDecoField = StateField.define<DecorationSet>({
  create() { return Decoration.none },
  update(decos, tr) {
    for (const e of tr.effects) {
      if (e.is(setSearchDecos)) return e.value
    }
    return decos.map(tr.changes)
  },
  provide: f => EditorView.decorations.from(f),
})

const macOSLightHighlight = HighlightStyle.define([
  { tag: tags.heading1, color: '#007aff', fontWeight: '600' },
  { tag: tags.heading2, color: '#007aff', fontWeight: '600' },
  { tag: tags.heading3, color: '#007aff', fontWeight: '600' },
  { tag: tags.heading4, color: '#007aff', fontWeight: '600' },
  { tag: tags.heading5, color: '#007aff', fontWeight: '600' },
  { tag: tags.heading6, color: '#007aff', fontWeight: '600' },
  { tag: tags.emphasis, color: '#808080', fontStyle: 'italic' },
  { tag: tags.strong, color: '#cc7300', fontWeight: '700' },
  { tag: tags.strikethrough, color: '#9999a3', textDecoration: 'line-through' },
  { tag: tags.link, color: '#a659d9' },
  { tag: tags.url, color: '#a659d9' },
  { tag: tags.quote, color: '#7c7c82' },
  { tag: tags.monospace, color: '#009639' },
  { tag: tags.comment, color: '#7c7c82' },
  { tag: tags.keyword, color: '#007aff' },
  { tag: tags.string, color: '#009639' },
  { tag: tags.atom, color: '#a659d9' },
  { tag: tags.number, color: '#a659d9' },
  { tag: tags.definitionKeyword, color: '#007aff' },
  { tag: tags.list, color: '#007aff' },
])

const macOSDarkHighlight = HighlightStyle.define([
  { tag: tags.heading1, color: '#66b3ff', fontWeight: '600' },
  { tag: tags.heading2, color: '#66b3ff', fontWeight: '600' },
  { tag: tags.heading3, color: '#66b3ff', fontWeight: '600' },
  { tag: tags.heading4, color: '#66b3ff', fontWeight: '600' },
  { tag: tags.heading5, color: '#66b3ff', fontWeight: '600' },
  { tag: tags.heading6, color: '#66b3ff', fontWeight: '600' },
  { tag: tags.emphasis, color: '#a6a6a6', fontStyle: 'italic' },
  { tag: tags.strong, color: '#ff9933', fontWeight: '700' },
  { tag: tags.strikethrough, color: '#b3b3bb', textDecoration: 'line-through' },
  { tag: tags.link, color: '#cc88ff' },
  { tag: tags.url, color: '#cc88ff' },
  { tag: tags.quote, color: '#a6a6aa' },
  { tag: tags.monospace, color: '#33cc66' },
  { tag: tags.comment, color: '#a6a6aa' },
  { tag: tags.keyword, color: '#66b3ff' },
  { tag: tags.string, color: '#33cc66' },
  { tag: tags.atom, color: '#cc88ff' },
  { tag: tags.number, color: '#cc88ff' },
  { tag: tags.definitionKeyword, color: '#66b3ff' },
  { tag: tags.list, color: '#66b3ff' },
])

const macOSSyntaxTheme = new Compartment()

export class Editor {
  view: EditorView
  private onChange: (content: string) => void

  constructor(container: HTMLElement, content: string, onChange: (content: string) => void) {
    this.onChange = onChange

    const startState = EditorState.create({
      doc: content,
      extensions: [
        keymap.of([...defaultKeymap, ...historyKeymap]),
        history(),
        languageCompartment.of(markdown({ base: markdownLanguage })),
        macOSSyntaxTheme.of(syntaxHighlighting(macOSLightHighlight)),
        highlightSelectionMatches(),
        closeBrackets(),
        lineNumbers(),
        placeholder('Start writing markdown...'),
        fontSizeCompartment.of(EditorView.theme({
          '&': { fontSize: '14px' },
          '.cm-scroller': {
            fontFamily: "'SF Mono', 'Cascadia Code', 'JetBrains Mono', Consolas, monospace",
            lineHeight: '1.6',
          },
          '.cm-content': {
            caretColor: '#007aff',
            padding: '16px 20px',
          },
          '.cm-gutters': {
            backgroundColor: 'transparent',
            border: 'none',
            color: 'var(--text-tertiary)',
            paddingRight: '4px',
            paddingLeft: '8px',
          },
          '.cm-activeLineGutter': {
            backgroundColor: 'transparent',
          },
          '.cm-lineNumbers': {
            minWidth: '24px',
            fontSize: '11px',
          },
          '.cm-foldGutter': {
            display: 'none',
          },
        })),
        themeCompartment.of([]),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            this.onChange(update.state.doc.toString())
          }
        }),
        EditorView.domEventHandlers({
          drop: (event) => this.handleDrop(event),
          paste: (event) => this.handlePaste(event),
        }),
        highlightField,
        searchDecoField,
      ],
    })

    this.view = new EditorView({
      state: startState,
      parent: container,
    })
  }

  getContent(): string {
    return this.view?.state.doc.toString() || ''
  }

  setContent(content: string): void {
    const current = this.view.state.doc.toString()
    if (content !== current) {
      this.view.dispatch({
        changes: {
          from: 0,
          to: current.length,
          insert: content,
        },
        annotations: Transaction.addToHistory.of(false),
      })
    }
  }

  setLanguage(isHtml: boolean): void {
    this.view.dispatch({
      effects: languageCompartment.reconfigure(
        isHtml ? [] : markdown({ base: markdownLanguage })
      ),
    })
  }

  setFontSize(size: number): void {
    this.view.dispatch({
      effects: fontSizeCompartment.reconfigure(
        EditorView.theme({
          '&': { fontSize: `${size}px` },
        })
      ),
    })
  }

  setTheme(isDark: boolean): void {
    this.view.dispatch({
      effects: [
        themeCompartment.reconfigure(
          isDark ? EditorView.theme({
            '.cm-content': { color: '#ebebeb' },
            '.cm-cursor': { borderLeftColor: '#0a84ff' },
            '.cm-selectionBackground': { background: 'rgba(10, 132, 255, 0.3)' },
            '.cm-activeLine': { backgroundColor: 'transparent' },
          }) : EditorView.theme({
            '.cm-content': { color: '#141414' },
            '.cm-cursor': { borderLeftColor: '#007aff' },
            '.cm-selectionBackground': { background: 'rgba(0, 122, 255, 0.15)' },
            '.cm-activeLine': { backgroundColor: 'transparent' },
          })
        ),
        macOSSyntaxTheme.reconfigure(
          syntaxHighlighting(isDark ? macOSDarkHighlight : macOSLightHighlight)
        ),
      ],
    })
  }

  scrollToLine(lineNumber: number): void {
    const doc = this.view.state.doc
    if (lineNumber < 0 || lineNumber >= doc.lines) return
    const line = doc.line(lineNumber + 1)
    this.view.dispatch({
      selection: { anchor: line.from },
      effects: EditorView.scrollIntoView(line.from, { y: 'center' }),
    })
    this.view.focus()

    const highlightDeco = Decoration.line({ class: 'cm-outline-highlight' })
    const deco = Decoration.set([highlightDeco.range(line.from)])
    this.view.dispatch({ effects: setHighlight.of(deco) })
    setTimeout(() => {
      this.view.dispatch({ effects: setHighlight.of(Decoration.none) })
    }, 1500)
  }

  search(query: string): number {
    if (!query) {
      this.clearSearch()
      return 0
    }
    const decos: Range<Decoration>[] = []
    const lowerQ = query.toLowerCase()
    const fullText = this.view.state.doc.sliceString(0).toLowerCase()
    let pos = 0, count = 0
    while ((pos = fullText.indexOf(lowerQ, pos)) !== -1) {
      decos.push(Decoration.mark({ class: 'cm-searchMatch' }).range(pos, pos + query.length))
      count++
      pos = pos + query.length
    }
    this.view.dispatch({ effects: setSearchDecos.of(Decoration.set(decos)) })
    return count
  }

  selectMatch(index: number, query: string): void {
    const lowerQ = query.toLowerCase()
    const fullText = this.view.state.doc.sliceString(0).toLowerCase()
    let pos = 0, matchIdx = 0
    while ((pos = fullText.indexOf(lowerQ, pos)) !== -1) {
      if (matchIdx === index) {
        this.view.dispatch({
          selection: { anchor: pos, head: pos + query.length },
          effects: EditorView.scrollIntoView(pos, { y: 'center' }),
        })
        return
      }
      pos = pos + query.length
      matchIdx++
    }
  }

  clearSearch(): void {
    this.view.dispatch({ effects: setSearchDecos.of(Decoration.none) })
  }

  replaceAt(index: number, query: string, replacement: string): boolean {
    if (!query) return false
    const lowerQ = query.toLowerCase()
    const fullText = this.view.state.doc.sliceString(0).toLowerCase()
    let pos = 0, matchIdx = 0
    while ((pos = fullText.indexOf(lowerQ, pos)) !== -1) {
      if (matchIdx === index) {
        this.view.dispatch({
          changes: { from: pos, to: pos + query.length, insert: replacement },
          annotations: Transaction.addToHistory.of(false),
        })
        return true
      }
      pos = pos + query.length
      matchIdx++
    }
    return false
  }

  replaceAll(query: string, replacement: string): number {
    if (!query) return 0
    const lowerQ = query.toLowerCase()
    const fullText = this.view.state.doc.sliceString(0)
    const lowerFullText = fullText.toLowerCase()
    let pos = 0, count = 0
    const replacements: {from: number, to: number, insert: string}[] = []
    while ((pos = lowerFullText.indexOf(lowerQ, pos)) !== -1) {
      replacements.push({from: pos, to: pos + query.length, insert: replacement})
      count++
      pos = pos + query.length
    }
    if (replacements.length > 0) {
      this.view.dispatch({
        changes: replacements,
        annotations: Transaction.addToHistory.of(false),
      })
    }
    return count
  }

  focus(): void {
    this.view.focus()
  }

  destroy(): void {
    this.view.destroy()
  }

  private handleDrop(event: DragEvent): void {
    const files = event.dataTransfer?.files
    if (!files || files.length === 0) return
    event.preventDefault()

    for (const file of Array.from(files)) {
      if (file.type.startsWith('image/')) {
        this.fileToBase64(file).then((base64) => {
          this.insertAtDrop(event, `![${file.name}](${base64})`)
        })
      }
    }
  }

  private handlePaste(event: ClipboardEvent): void {
    const items = event.clipboardData?.items
    if (!items) return

    for (const item of Array.from(items)) {
      if (item.type.startsWith('image/')) {
        event.preventDefault()
        const file = item.getAsFile()
        if (file) {
          this.fileToBase64(file).then((base64) => {
            this.insertAtCursor(`![${file.name}](${base64})`)
          })
        }
      }
    }
  }

  private fileToBase64(file: File): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => resolve(reader.result as string)
      reader.onerror = reject
      reader.readAsDataURL(file)
    })
  }

  private insertAtDrop(event: DragEvent, text: string): void {
    const coords = { x: event.clientX, y: event.clientY }
    const pos = this.view.posAtCoords(coords)
    if (pos !== null) {
      this.view.dispatch({
        changes: { from: pos, insert: text },
      })
    }
  }

  private insertAtCursor(text: string): void {
    const pos = this.view.state.selection.main.head
    this.view.dispatch({
      changes: { from: pos, insert: text },
    })
  }
}
