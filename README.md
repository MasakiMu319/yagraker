# Yagraker

A native macOS 15+ menu-bar workspace for grammar checking, translation, and close reading.

## Features

- `⇧⌘G`: check selected text and paste accepted corrections back
- `⌥⌘T`: stream-translate the selected text in the Translate workspace
- `⌘2` / `⌘3`: open the Translate / Deep Read workspaces
- Grammar Check, Translate, and Deep Read are separate tabs; Deep Read streams a natural translation plus useful sentence structure, clause, expression, and ambiguity analysis
- Gemini, Qwen / Qwen-MT, DeepSeek, Xiaomi MiMo, and custom OpenAI-compatible endpoints
- BYOK credentials stored in Keychain; settings in UserDefaults; recent checks stay in memory only
- Runtime English / Simplified Chinese / Traditional Chinese UI
- Sparkle update plumbing (feed and EdDSA key are supplied at distribution build time)

## Build and test

```bash
swift build
swift test
```

Translation, Deep Read, and Grammar Check have independent provider and model routes. Settings loads the provider's official model catalog through its model-list API; Qwen-MT entries are offered for translation while general-purpose entries are offered for Deep Read and Grammar Check. Custom OpenAI-compatible endpoints can still enter a model ID manually when they do not expose `/models`.

Qwen-MT translation uses the Alibaba Cloud Model Studio OpenAI-compatible endpoint. The default model is `qwen-mt-flash`; `qwen-mt-plus`, `qwen-mt-lite`, and `qwen-mt-turbo` are also supported. Configure the provider and API key in Settings. Qwen-MT models are translation-only, so choose separate general-purpose models for Deep Read and Grammar Check.

Build a universal Apple Silicon + Intel app bundle:

```bash
bash Scripts/build-app.sh
open dist/Yagraker.app
```

Local builds require a stable code-signing identity because macOS Accessibility permission is bound to the app's code identity. Create a self-signed Code Signing certificate named `Yagraker Local Development` once in Keychain Access, or provide an existing Apple Development identity:

```bash
SIGN_IDENTITY='Apple Development: …' bash Scripts/build-app.sh
```

Ad-hoc signing is intentionally unsupported because every rebuild changes its designated requirement and invalidates Accessibility permission. When switching an existing installation from ad-hoc to stable signing, reset the stale permission once, reopen Yagraker, and grant access again:

```bash
tccutil reset Accessibility com.yagraker.app
```

For a Developer ID distribution build, first store App Store Connect credentials with `notarytool store-credentials`, then run:

```bash
SIGN_IDENTITY='Developer ID Application: …' \
NOTARYTOOL_PROFILE='yagraker-notary' \
YAGRAKER_FEED_URL='https://example.com/appcast.xml' \
YAGRAKER_PUBLIC_ED_KEY='BASE64_PUBLIC_KEY' \
bash Scripts/build-app.sh
```

Developer ID mode requires all three release settings, submits the app for notarization, staples and validates the ticket, runs Gatekeeper assessment, and emits `dist/Yagraker.zip`. Sparkle requires a publisher-owned appcast and EdDSA key; release credentials are never embedded in source.

## Privacy

Selected text is sent directly from the Mac to the configured model provider. Yagraker has no relay server. API keys are stored as one generic-password Keychain item under service `com.yagraker.app`; history is capped at ten entries and is never persisted. Provider traffic requires HTTPS, except that custom endpoints may use HTTP on loopback or private networks.
