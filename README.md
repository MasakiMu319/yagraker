# Yagraker

<p align="center">
  <strong>A native macOS menu-bar workspace for streaming translation, close reading, and grammar checking.</strong>
</p>

<p align="center">
  <img src="Sources/Yagraker/Resources/yagraker-mark.svg" alt="Yagraker Logo" width="80" height="80" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue.svg?style=flat" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat" alt="Swift" />
  <img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat" alt="License" />
</p>

---

**Yagraker** is a native, keyboard-first macOS workspace built for writers, researchers, and multilingual readers. Combining a warm **Paper & Ink** visual aesthetic with modern macOS translucent materials, Yagraker floats alongside your active workflow to deliver real-time AI translations, in-depth syntactic and cultural sentence breakdowns, and in-place grammar repairs.

---

## ✨ Features

- ⚡️ **Instant Floating Workspace**: Summon with global shortcuts (`⌥⌘T`, `⇧⌘G`) or from the menu bar to process selected text immediately.
- 📖 **Three Focused Workspaces**:
  - **Translate**: Low-latency, streaming multi-language translation.
  - **Deep Read**: Detailed analysis breaking down sentence structure, clauses, nuances, idioms, and potential ambiguities.
  - **Grammar**: Inline diffing of grammar, spelling, and phrasing with one-click in-place text replacement.
- 🔀 **Independent Provider & Model Routing**: Configure different LLMs for different tasks (e.g., dedicated `Qwen-MT` for fast translations, `DeepSeek` or `Gemini` for deep linguistic analysis).
- 🎨 **Thoughtful UI & Craftsmanship**:
  - Translucent macOS material overlay with continuous smooth corners.
  - Integrated input card with auto-expanding editor, word counter, and clear button.
  - Live pulsing streaming indicators, one-click regeneration, and visual copy confirmation.
  - Drag-anywhere header with ample grab area even at minimum window width.
- 🔒 **Privacy-First (BYOK)**: No telemetry, no intermediate proxies. All API requests travel directly from your Mac to provider endpoints over HTTPS. API keys stay securely inside your macOS Keychain.
- 🌐 **Multilingual UI**: Seamless runtime switching between English, Simplified Chinese (简体中文), and Traditional Chinese (繁體中文).
- 🔄 **Sparkle Updates**: Built-in silent and interactive application update plumbing.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Scope | Action |
| :--- | :--- | :--- |
| `⌥⌘T` | Global | Capture selected text and open the **Translate** workspace |
| `⇧⌘G` | Global | Capture selected text and run a **Grammar Check** |
| `⌘1` | Inside App | Switch to **Grammar** workspace |
| `⌘2` | Inside App | Switch to **Translate** workspace |
| `⌘3` | Inside App | Switch to **Deep Read** workspace |
| `Return` (`↵`) | Editor | Submit input text for processing |
| `Shift + Return` (`⇧↵`) | Editor | Insert a new line in the text editor |
| `Esc` | Window | Dismiss the floating panel (when unpinned) |

*All global shortcuts can be customized in **Settings → Shortcuts**.*

---

## 🤖 Supported Providers & Model Routing

Yagraker allows you to pair each task with the model best suited for it:

| Provider | Supported Workspaces | Notes & Suggested Models |
| :--- | :--- | :--- |
| **Aliyun Qwen / Qwen-MT** | Translate, Deep Read, Grammar | Official specialized machine translation models (`qwen-mt-flash`, `qwen-mt-plus`, etc.) for translation; general-purpose models for deep reading. |
| **Google Gemini** | Translate, Deep Read, Grammar | Official model list integration (`gemini-2.5-flash`, `gemini-1.5-pro`). High throughput with native SSE streaming. |
| **DeepSeek** | Translate, Deep Read, Grammar | High reasoning and analysis fidelity (`deepseek-chat`). |
| **Xiaomi MiMo** | Translate, Deep Read, Grammar | Supports regional clusters (China, Singapore, Europe). |
| **Custom OpenAI-Compatible** | Translate, Deep Read, Grammar | Any OpenAI-compatible endpoint (OpenAI, Moonshot Kimi, MiniMax, Doubao, Ollama, etc.). |

Settings automatically fetches official model catalogs from supported providers, allowing one-click selection.

---

## 🎨 Design & Interaction Details

Yagraker avoids cold generic UI in favor of an artisanal tactile experience:
- **Paper & Ink Theme**: Calibrated light and dark tones reminiscent of warm parchment and ink.
- **Card-Based Visual Hierarchy**: Input sections and result outputs are nested within clear, structured cards with subtle borders.
- **Fluid Layout**: Window resizing smoothly distributes space between the input and output views. The editor hugs content on compact queries while granting ample breathing room for longer essays.
- **Instant Micro-Feedback**: Interactive elements feature soft spring physics, and copy actions trigger immediate visual feedback.

---

## 🛠️ Build & Installation

### Requirements
- macOS 15.0 or later
- Xcode 16.0+ (or Swift 5.10+ command-line tools)

### 1. Quick Build & Test
Clone the repository and build using Swift Package Manager:

```bash
git clone https://github.com/MasakiMu319/yagraker.git
cd yagraker

swift build
swift test
```

### 2. Universal Application Bundle (`.app`)
Build a universal binary (`arm64` + `x86_64`) signed for local development:

```bash
# By default, creates or uses a 'Yagraker Local Development' self-signed cert in Keychain
bash Scripts/build-app.sh

# Launch the built application
open dist/Yagraker.app
```

> **Note on Accessibility Permissions:**
> macOS Accessibility permission is bound to the application's code signature. Ad-hoc signatures change designated requirements upon rebuilds and invalidate granted permissions. `build-app.sh` automatically signs with a persistent development identity so you do not have to re-grant permissions every rebuild.
>
> If you need to reset stale system permissions:
> ```bash
> tccutil reset Accessibility com.yagraker.app
> ```

### 3. Developer ID & Notarization (Release Distribution)
For release distribution with Developer ID signing and Apple notary service:

```bash
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARYTOOL_PROFILE='yagraker-notary' \
YAGRAKER_FEED_URL='https://example.com/appcast.xml' \
YAGRAKER_PUBLIC_ED_KEY='BASE64_PUBLIC_KEY' \
bash Scripts/build-app.sh
```

This compiles, packages Sparkle, signs nested binaries, submits for notarization, staples the notarization ticket, and outputs `dist/Yagraker.zip`.

---

## 🔒 Privacy & Security

- **Direct Connections**: All network requests connect directly to your chosen AI provider. There are no tracking servers, telemetry services, or data collection relays.
- **Keychain Storage**: API keys are securely persisted in the macOS Keychain under the service identifier `com.yagraker.app`.
- **Ephemeral State**: Text history is capped in memory only and is discarded upon quitting the application.

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
