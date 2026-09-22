import AppKit
import SwiftUI
import YagrakerCore

enum ReIconAsset {
    static let settings = load("reicon-settings")
    static let sparkles = load("reicon-sparkles")
    static let keyboard = load("reicon-keyboard")
    static let infoCircle = load("reicon-info-circle")
    static let yagrakerMark = load("yagraker-mark", template: false)
    private static let providerGemini = load("reicon-gemini", size: 13)
    private static let providerQwen = load("reicon-qwen", size: 13)
    private static let providerMiMo = load("reicon-xiaomi-mimo", size: 13)
    private static let providerDeepSeek = load("reicon-deepseek", size: 13)
    private static let providerServer = load("reicon-server", size: 13)
    /// Menu-bar template image: the handwritten "y" from yagraker-mark.svg,
    /// redrawn at status-bar stroke weight so it stays crisp at 17pt.
    static let menuBarMark: NSImage = {
        let image = load("yagraker-menubar")
        image.size = NSSize(width: 17, height: 17)
        return image
    }()

    static func providerIcon(for kind: LLMProviderKind) -> NSImage {
        switch kind {
        case .gemini: return providerGemini
        case .qwen: return providerQwen
        case .mimo: return providerMiMo
        case .deepseek: return providerDeepSeek
        case .custom: return providerServer
        }
    }

    private static func load(
        _ name: String,
        size: CGFloat? = nil,
        template: Bool = true
    ) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing ReIcon asset: \(name).svg")
        }
        if let size {
            image.size = NSSize(width: size, height: size)
        }
        image.isTemplate = template
        return image
    }
}

struct ProviderIcon: View {
    let provider: LLMProviderKind
    var size: CGFloat = 13

    var body: some View {
        Image(nsImage: ReIconAsset.providerIcon(for: provider))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
