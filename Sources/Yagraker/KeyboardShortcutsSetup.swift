import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⇧⌘G — check the current selection.
    static let checkGrammar = Self("checkGrammar", default: .init(.g, modifiers: [.command, .shift]))
    /// ⌥⌘T — translate selection, formats preserved.
    static let translate = Self("translate", default: .init(.t, modifiers: [.command, .option]))
    /// ⌘2 — open the translation workspace.
    static let openTranslation = Self("openTranslation", default: .init(.two, modifiers: [.command]))
    /// ⌘3 — open the Deep Read workspace.
    static let openDeepRead = Self("openDeepRead", default: .init(.three, modifiers: [.command]))
}
