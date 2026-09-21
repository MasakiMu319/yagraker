import AppKit

/// Weak registry so the panel can focus the embedded NSTextView editor.
final class EditorRegistry {
    static let shared = EditorRegistry()
    weak var textView: NSTextView?
    private init() {}
}
