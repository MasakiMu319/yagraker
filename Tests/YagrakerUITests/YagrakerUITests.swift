import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI
import XCTest
@testable import Yagraker
@testable import YagrakerCore

final class YagrakerUITests: XCTestCase {
    private static let longCJKFixture =
        "这是用于验证中文长文本换行与窗口布局的合成内容，不含真实信息。"

    func testShortcutRecorderBeginsRecordingOnMouseDown() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            MainMenuController.shared.install()
            let originalShortcut = KeyboardShortcuts.getShortcut(for: .checkGrammar)
            defer { KeyboardShortcuts.setShortcut(originalShortcut, for: .checkGrammar) }

            let hostingView = NSHostingView(
                rootView: ShortcutRecorder(name: .checkGrammar)
                    .frame(width: 150, height: 24)
                    .padding(20)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 190, height: 64),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)

            let recorder = try XCTUnwrap(
                firstDescendant(of: KeyboardShortcuts.RecorderCocoa.self, in: hostingView)
            )
            let recorderCenter = hostingView.convert(
                NSPoint(x: recorder.bounds.midX, y: recorder.bounds.midY),
                from: recorder
            )
            let placeholderBeforeClick = recorder.placeholderString
            sendMouseEvent(
                .leftMouseDown,
                at: recorderCenter,
                in: hostingView,
                window: window
            )
            XCTAssertNotEqual(recorder.placeholderString, placeholderBeforeClick)
        }
    }

    func testShortcutRecorderCapturesKeyBeforeMouseUp() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            MainMenuController.shared.install()
            let originalShortcut = KeyboardShortcuts.getShortcut(for: .checkGrammar)
            defer { KeyboardShortcuts.setShortcut(originalShortcut, for: .checkGrammar) }
            KeyboardShortcuts.setShortcut(nil, for: .checkGrammar)

            let hostingView = NSHostingView(
                rootView: ShortcutRecorder(name: .checkGrammar)
                    .frame(width: 150, height: 24)
                    .padding(20)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 190, height: 64),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)

            let recorder = try XCTUnwrap(
                firstDescendant(of: KeyboardShortcuts.RecorderCocoa.self, in: hostingView)
            )
            let recorderCenter = hostingView.convert(
                NSPoint(x: recorder.bounds.midX, y: recorder.bounds.midY),
                from: recorder
            )
            sendMouseEvent(
                .leftMouseDown,
                at: recorderCenter,
                in: hostingView,
                window: window
            )
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_K)
            ))
            NSApp.sendEvent(event)
            sendMouseEvent(.leftMouseUp, at: recorderCenter, in: hostingView, window: window)
            waitForViewUpdate(hostingView)

            XCTAssertEqual(
                KeyboardShortcuts.getShortcut(for: .checkGrammar),
                KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
            )
        }
    }

    func testEmptyShortcutRecorderUsesImmediateRecordHitAreaAcrossFullWidth() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            MainMenuController.shared.install()
            let originalShortcut = KeyboardShortcuts.getShortcut(for: .checkGrammar)
            defer { KeyboardShortcuts.setShortcut(originalShortcut, for: .checkGrammar) }
            KeyboardShortcuts.setShortcut(nil, for: .checkGrammar)

            let recorderView = ShortcutRecorder.RecorderView(name: .checkGrammar)
            recorderView.frame = NSRect(x: 0, y: 0, width: 150, height: 24)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 150, height: 24),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = recorderView
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            waitForViewUpdate(recorderView)

            let edgePoint = NSPoint(x: recorderView.bounds.maxX - 2, y: recorderView.bounds.midY)
            let hitView = recorderView.hitTest(edgePoint)

            XCTAssertNotNil(hitView)
            XCTAssertFalse(hitView === recorderView.recorder)
        }
    }

    func testSettingsShortcutRecorderAcceptsEveryFirstKeyPress() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            MainMenuController.shared.install()
            let originalShortcut = KeyboardShortcuts.getShortcut(for: .checkGrammar)
            defer { KeyboardShortcuts.setShortcut(originalShortcut, for: .checkGrammar) }
            KeyboardShortcuts.setShortcut(.init(.g, modifiers: [.command, .shift]), for: .checkGrammar)

            let appState = AppState()
            appState.openSettings()
            waitForViewUpdate()

            let window = try XCTUnwrap(
                NSApp.windows.first { $0.title == L10n.shared.t("settings.title") }
            )
            defer {
                window.orderOut(nil)
                appState.settingsController = nil
            }
            window.makeKeyAndOrderFront(nil)
            let contentView = try XCTUnwrap(window.contentView)
            let tabCenterY = contentView.isFlipped ? 31 : contentView.bounds.height - 31
            click(
                at: NSPoint(x: 366, y: tabCenterY),
                in: contentView,
                window: window
            )
            waitForAnimation(in: contentView)

            let recorder = try XCTUnwrap(
                firstDescendant(of: KeyboardShortcuts.RecorderCocoa.self, in: contentView)
            )
            let recorderCenter = contentView.convert(
                NSPoint(x: recorder.bounds.midX, y: recorder.bounds.midY),
                from: recorder
            )

            let keys: [(String, UInt16, KeyboardShortcuts.Key)] = [
                ("k", UInt16(kVK_ANSI_K), .k),
                ("j", UInt16(kVK_ANSI_J), .j),
                ("l", UInt16(kVK_ANSI_L), .l),
                ("u", UInt16(kVK_ANSI_U), .u),
                ("i", UInt16(kVK_ANSI_I), .i),
            ]
            for key in keys {
                click(at: recorderCenter, in: contentView, window: window)
                let event = try XCTUnwrap(NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.command, .option],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: key.0,
                    charactersIgnoringModifiers: key.0,
                    isARepeat: false,
                    keyCode: key.1
                ))
                NSApp.sendEvent(event)
                waitForViewUpdate(contentView)

                XCTAssertEqual(
                    KeyboardShortcuts.getShortcut(for: .checkGrammar),
                    KeyboardShortcuts.Shortcut(key.2, modifiers: [.command, .option])
                )
            }
        }
    }

    func testEverySettingsShortcutRowAcceptsItsFirstKeyPress() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            MainMenuController.shared.install()
            let names: [KeyboardShortcuts.Name] = [
                .checkGrammar, .translate, .openTranslation, .openDeepRead,
            ]
            let originalShortcuts = names.map { ($0, KeyboardShortcuts.getShortcut(for: $0)) }
            defer {
                for (name, shortcut) in originalShortcuts {
                    KeyboardShortcuts.setShortcut(shortcut, for: name)
                }
            }
            for name in names {
                KeyboardShortcuts.setShortcut(nil, for: name)
            }

            let appState = AppState()
            appState.openSettings()
            waitForViewUpdate()
            let window = try XCTUnwrap(
                NSApp.windows.first { $0.title == L10n.shared.t("settings.title") }
            )
            defer {
                window.orderOut(nil)
                appState.settingsController = nil
            }
            window.makeKeyAndOrderFront(nil)
            let contentView = try XCTUnwrap(window.contentView)
            let tabCenterY = contentView.isFlipped ? 31 : contentView.bounds.height - 31
            click(
                at: NSPoint(x: 366, y: tabCenterY),
                in: contentView,
                window: window
            )
            waitForAnimation(in: contentView)

            let recorders = allDescendants(
                of: KeyboardShortcuts.RecorderCocoa.self,
                in: contentView
            )
            XCTAssertEqual(recorders.count, names.count)
            let keys: [(String, UInt16, KeyboardShortcuts.Key)] = [
                ("k", UInt16(kVK_ANSI_K), .k),
                ("j", UInt16(kVK_ANSI_J), .j),
                ("l", UInt16(kVK_ANSI_L), .l),
                ("u", UInt16(kVK_ANSI_U), .u),
                ("i", UInt16(kVK_ANSI_I), .i),
            ]

            for (index, recorder) in recorders.enumerated() {
                let point = contentView.convert(
                    NSPoint(x: recorder.bounds.midX, y: recorder.bounds.midY),
                    from: recorder
                )
                click(at: point, in: contentView, window: window)
                let key = keys[index]
                let event = try XCTUnwrap(NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.command, .option],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: key.0,
                    charactersIgnoringModifiers: key.0,
                    isARepeat: false,
                    keyCode: key.1
                ))
                NSApp.sendEvent(event)
                waitForViewUpdate(contentView)
                XCTAssertEqual(
                    KeyboardShortcuts.getShortcut(for: names[index]),
                    KeyboardShortcuts.Shortcut(key.2, modifiers: [.command, .option])
                )
            }
        }
    }

    func testSettingsShortcutClearButtonClearsAndResignsFocus() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            MainMenuController.shared.install()
            let originalShortcut = KeyboardShortcuts.getShortcut(for: .checkGrammar)
            defer { KeyboardShortcuts.setShortcut(originalShortcut, for: .checkGrammar) }
            KeyboardShortcuts.setShortcut(
                .init(.g, modifiers: [.command, .shift]),
                for: .checkGrammar
            )

            let appState = AppState()
            appState.openSettings()
            waitForViewUpdate()

            let window = try XCTUnwrap(
                NSApp.windows.first { $0.title == L10n.shared.t("settings.title") }
            )
            defer {
                window.orderOut(nil)
                appState.settingsController = nil
            }
            window.makeKeyAndOrderFront(nil)
            let contentView = try XCTUnwrap(window.contentView)
            let tabCenterY = contentView.isFlipped ? 31 : contentView.bounds.height - 31
            click(
                at: NSPoint(x: 366, y: tabCenterY),
                in: contentView,
                window: window
            )
            waitForAnimation(in: contentView)

            let recorder = try XCTUnwrap(
                firstDescendant(of: KeyboardShortcuts.RecorderCocoa.self, in: contentView)
            )
            let searchFieldCell = try XCTUnwrap(recorder.cell as? NSSearchFieldCell)
            let cancelRect = searchFieldCell.cancelButtonRect(forBounds: recorder.bounds)
            let clearPoint = contentView.convert(
                NSPoint(x: cancelRect.midX, y: cancelRect.midY),
                from: recorder
            )
            click(at: clearPoint, in: contentView, window: window)
            waitForViewUpdate(contentView)

            XCTAssertNil(KeyboardShortcuts.getShortcut(for: .checkGrammar))
            XCTAssertTrue(recorder.stringValue.isEmpty)
            XCTAssertNil(recorder.currentEditor())
        }
    }

    func testShortcutRecorderRecordsAndAllowsEmptyShortcut() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            MainMenuController.shared.install()
            let originalShortcut = KeyboardShortcuts.getShortcut(for: .checkGrammar)
            defer { KeyboardShortcuts.setShortcut(originalShortcut, for: .checkGrammar) }

            let hostingView = NSHostingView(
                rootView: ShortcutRecorder(name: .checkGrammar)
                    .frame(width: 150, height: 24)
                    .padding(20)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 190, height: 64),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)

            let recorder = try XCTUnwrap(
                firstDescendant(of: KeyboardShortcuts.RecorderCocoa.self, in: hostingView)
            )
            let recorderCenter = hostingView.convert(
                NSPoint(x: recorder.bounds.midX, y: recorder.bounds.midY),
                from: recorder
            )
            let placeholderBeforeClick = recorder.placeholderString
            click(at: recorderCenter, in: hostingView, window: window)
            waitForViewUpdate(hostingView)
            XCTAssertNotEqual(recorder.placeholderString, placeholderBeforeClick)

            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_K)
            ))
            NSApp.sendEvent(event)
            waitForViewUpdate(hostingView)

            XCTAssertEqual(
                KeyboardShortcuts.getShortcut(for: .checkGrammar),
                KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
            )

            let searchFieldCell = try XCTUnwrap(recorder.cell as? NSSearchFieldCell)
            let cancelRect = searchFieldCell.cancelButtonRect(forBounds: recorder.bounds)
            let cancelCenter = hostingView.convert(
                NSPoint(x: cancelRect.midX, y: cancelRect.midY),
                from: recorder
            )
            click(at: cancelCenter, in: hostingView, window: window)
            waitForViewUpdate(hostingView)

            XCTAssertNil(KeyboardShortcuts.getShortcut(for: .checkGrammar))
            let reloadedName = KeyboardShortcuts.Name(
                "checkGrammar",
                default: .init(.g, modifiers: [.command, .shift])
            )
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: reloadedName))
        }
    }

    func testPopupPanelIsResizableInBothDimensions() {
        MainActor.assumeIsolated {
            XCTAssertTrue(PopupWindow.panelStyleMask.contains(.resizable))
            XCTAssertEqual(PopupWindow.defaultSize, NSSize(width: 481, height: 373))
            XCTAssertEqual(
                PopupWindow.constrainedSize(
                    NSSize(width: 700, height: 400),
                    minimumSize: NSSize(width: 440, height: 240),
                    maximumSize: NSSize(width: 1_200, height: 800)
                ),
                NSSize(width: 700, height: 400)
            )
            XCTAssertEqual(
                PopupWindow.constrainedSize(
                    NSSize(width: 1, height: 1),
                    minimumSize: NSSize(width: 440, height: 240),
                    maximumSize: NSSize(width: 1_200, height: 800)
                ),
                NSSize(width: 440, height: 240)
            )
            XCTAssertEqual(
                PopupWindow.constrainedSize(
                    NSSize(width: 10_000, height: 10_000),
                    minimumSize: NSSize(width: 440, height: 240),
                    maximumSize: NSSize(width: 1_200, height: 800)
                ),
                NSSize(width: 1_200, height: 800)
            )
        }
    }

    func testGrammarInputEditorUsesIntendedHeight() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let appState = AppState()
            appState.toolPanelModel.activate(
                mode: .grammar,
                input: "Models are out. Harnesses are in. Cheap open source models have taken the wind out of the big AI labs.",
                clearResults: true
            )
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let contentView = try XCTUnwrap(panel.contentView)
            let textView = try XCTUnwrap(
                firstDescendant(of: QuickTranslationTextEditor.PasteAwareTextView.self, in: contentView)
            )
            let scrollView = try XCTUnwrap(textView.enclosingScrollView)

            XCTAssertEqual(scrollView.frame.height, 96, accuracy: 1)
        }
    }

    func testGrammarLoadingTextWrapsLongCJKContent() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let source = Array(
                repeating: Self.longCJKFixture,
                count: 3
            ).joined()
            let hostingView = NSHostingView(
                rootView: TextScanLoadingView(text: source)
                    .frame(width: 400, alignment: .leading)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)

            XCTAssertGreaterThan(hostingView.fittingSize.height, 32)
        }
    }

    func testGrammarLoadingWithBoxDrawingTablePerformsFast() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let source = """
            审计日志里对该配置块的完整时间线：

            ┌─────────────────────────────────────┬─────────────┬──────────────────────────────────────────────────────────────────────────────────┬──────────────────────┐
            │             时间 (UTC)              │     人      │                                     写入内容                                     │         结果         │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-06 10:34                         │ ping        │ 10.96.0.0/11，enforcement=true                                                   │ 成功                 │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-10 13:48                         │ soren       │ 启用 agentSandbox                                                                │ 成功                 │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-10 14:09 / 14:27 / 15:06 / 15:11 │ soren       │ desiredControlPlaneEndpointsConfig 走 v1alpha1，日志里请求体为空，内容不可见     │ 成功                 │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-12 14:31                         │ soren       │ master 升 1.36.2-gke.2064000                                                     │ 成功                 │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-12 16:02                         │ soren       │ 启用 podSnapshotConfig（你的清单里漏了这一笔）                                   │ 成功                 │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-20 07:30                         │ houzhenhuan │ 10.96.0.0/11 + 23.142.224.78/32 (hzh-mac)，enabled=true                          │ 成功                 │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-20 08:13                         │ houzhenhuan │ authorizedNetworksConfig 只含 privateEndpointEnforcementEnabled: false，整块替换 │ 成功，这就是清空动作 │
            ├─────────────────────────────────────┼─────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────────────────┤
            │ 08-20 09:05                         │ darrent     │ 恢复 10.96.0.0/11，enabled=true                                                  │ 被 GKE 拒绝          │
            └─────────────────────────────────────┴─────────────┴──────────────────────────────────────────────────────────────────────────────────┴──────────────────────┘

            08-20 之后没有任何人为的 UpdateCluster，只有 GKE 内部 PatchCluster。soren 08-10 那四笔不管改了什么，都被 houzhenhuan 08-20 07:30 那笔覆盖了，与当前状态无因果关系。
            """
            let start = CFAbsoluteTimeGetCurrent()
            let hostingView = NSHostingView(
                rootView: TextScanLoadingView(text: source)
                    .frame(width: 400, alignment: .leading)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            XCTAssertGreaterThan(hostingView.fittingSize.height, 32)
            // Even in debug mode without compiler optimizations, initial layout and render must take under 1 second (previously >9s).
            XCTAssertLessThan(elapsed, 1.0)
        }
    }

    func testGrammarLoadingPopupHasOnlyHeaderDivider() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let previousAppearance = NSApp.appearance
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            NSApp.appearance = NSAppearance(named: .aqua)
            store.panelSize = PopupWindow.defaultSize
            defer {
                NSApp.appearance = previousAppearance
                store.panelSize = previousSize
            }

            let source = Array(
                repeating: Self.longCJKFixture,
                count: 3
            ).joined()
            let appState = AppState()
            appState.toolPanelModel.activate(mode: .grammar, input: source, clearResults: true)
            appState.originalText = source
            appState.isLoading = true
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let contentView = try XCTUnwrap(panel.contentView)
            contentView.displayIfNeeded()
            let image = try XCTUnwrap(contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
            contentView.cacheDisplay(in: contentView.bounds, to: image)

            XCTAssertEqual(horizontalHairlineClusterCount(in: image), 1)
        }
    }

    func testCleanGrammarResultUsesContentHeightWithoutDiscardingSavedSize() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            let savedSize = PopupWindow.defaultSize
            store.panelSize = savedSize
            defer { store.panelSize = previousSize }

            let source = "Harnesses make the client-server distinction clear."
            let appState = AppState()
            appState.toolPanelModel.activate(mode: .grammar, input: source, clearResults: true)
            appState.originalText = source
            appState.correctionResult = CorrectionResult(
                corrections: [],
                tip: ""
            )
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()
            appState.popupWindow.resizePanel(animated: false)

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            XCTAssertEqual(panel.frame.height, PopupWindow.minimumHeight, accuracy: 1)
            XCTAssertEqual(store.panelSize?.height ?? 0, savedSize.height, accuracy: 1)

            appState.toolPanelModel.selectMode(.translation)
            waitForViewUpdate()
            waitForViewUpdate()

            XCTAssertEqual(panel.frame.height, savedSize.height, accuracy: 1)
        }
    }

    func testNewTranslationResetsScrollAndKeepsOriginalSummaryMultiline() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            store.panelSize = NSSize(width: 840, height: PopupWindow.minimumHeight)
            defer { store.panelSize = previousSize }

            let source = Array(
                repeating: Self.longCJKFixture,
                count: 4
            ).joined()
            let service = EchoingOpenStreamService()
            let appState = AppState()
            let toolPanel = ToolPanelModel { kind, task in
                ProviderResolver.Resolved(
                    kind: kind,
                    task: task,
                    apiKey: "test-key",
                    model: "test-model",
                    service: service
                )
            }
            appState.toolPanelModel = toolPanel
            toolPanel.activate(mode: .translation, input: source, clearResults: true)
            appState.popupWindow.show()
            toolPanel.startGeneration(mode: .translation, text: source)
            defer {
                service.finish()
                appState.dismissPopup(restoreFocus: false)
            }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let contentView = try XCTUnwrap(panel.contentView)
            let initialScrollView = try XCTUnwrap(allDescendants(of: NSScrollView.self, in: contentView).first)
            let initialDocumentView = try XCTUnwrap(initialScrollView.documentView)
            let maximumOffset = max(initialDocumentView.frame.height - initialScrollView.contentSize.height, 0)
            XCTAssertGreaterThan(maximumOffset, 20)
            initialScrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumOffset))
            initialScrollView.reflectScrolledClipView(initialScrollView.contentView)
            XCTAssertGreaterThan(initialScrollView.documentVisibleRect.minY, 20)

            toolPanel.startGeneration(mode: .translation, text: source)
            waitForViewUpdate()

            let scrollView = try XCTUnwrap(allDescendants(of: NSScrollView.self, in: contentView).first)
            let documentView = try XCTUnwrap(scrollView.documentView)
            let sourceView = try XCTUnwrap(
                allDescendants(of: NSView.self, in: contentView).first {
                    ($0.accessibilityValue() as? String) == source
                }
            )
            let sourceRect = sourceView.convert(sourceView.bounds, to: documentView)
            let visibleSource = sourceRect.intersection(scrollView.documentVisibleRect)

            XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 1)
            XCTAssertLessThanOrEqual(sourceView.frame.width, panel.contentLayoutRect.width - 27)
            XCTAssertGreaterThan(sourceView.frame.height, 20)
            XCTAssertEqual(visibleSource.height, sourceRect.height, accuracy: 1)
        }
    }

    /// The source editor must hug its laid-out content (no dead space) and
    /// claim its panel-proportional budget when the panel grows taller.
    func testSourceEditorHugsContentAndGrowsWithPanel() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            let previousTopLeft = store.panelTopLeft
            let previousPinned = store.isPinned
            store.panelSize = NSSize(width: 840, height: PopupWindow.minimumHeight)
            store.panelTopLeft = nil
            store.isPinned = true
            defer {
                store.panelSize = previousSize
                store.panelTopLeft = previousTopLeft
                store.isPinned = previousPinned
            }

            // ~6 lines at this width: taller than the compact cap at minimum
            // panel height, shorter than the cap of a tall panel.
            let source = Array(
                repeating: Self.longCJKFixture,
                count: 14
            ).joined()
            let service = EchoingOpenStreamService()
            let appState = AppState()
            let toolPanel = ToolPanelModel { kind, task in
                ProviderResolver.Resolved(
                    kind: kind,
                    task: task,
                    apiKey: "test-key",
                    model: "test-model",
                    service: service
                )
            }
            appState.toolPanelModel = toolPanel
            toolPanel.activate(mode: .translation, input: source, clearResults: true)
            appState.popupWindow.show()
            toolPanel.startGeneration(mode: .translation, text: source)
            defer {
                service.finish()
                appState.dismissPopup(restoreFocus: false)
            }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let contentView = try XCTUnwrap(panel.contentView)
            let textView = try XCTUnwrap(
                firstDescendant(of: QuickTranslationTextEditor.PasteAwareTextView.self, in: contentView)
            )
            let editorScrollView = try XCTUnwrap(textView.enclosingScrollView)

            // At minimum panel height the compact cap (72pt) clamps the editor.
            XCTAssertEqual(editorScrollView.frame.height, 72, accuracy: 2)

            // After resizing the panel taller (same begin/resize/end sequence
            // as the resize grip), the editor grows toward its content height
            // instead of staying stuck at the old cap.
            appState.popupWindow.beginManualResize()
            appState.popupWindow.resizeManually(to: NSSize(width: 840, height: 600))
            appState.popupWindow.endManualResize()
            waitForViewUpdate()
            XCTAssertGreaterThan(editorScrollView.frame.height, 80)
            // …but it hugs content rather than filling the whole new budget.
            XCTAssertLessThan(editorScrollView.frame.height, 150)
        }
    }

    func testModeSelectorProvidesRoomAroundAllLabels() {
        MainActor.assumeIsolated {
            let hostingView = NSHostingView(
                rootView: GlassModeSelector(selectedMode: .grammar, onSelect: { _ in })
                    .environmentObject(L10n.shared)
            )

            XCTAssertGreaterThanOrEqual(hostingView.fittingSize.width, 220)
            XCTAssertLessThanOrEqual(hostingView.fittingSize.width, 260)
            XCTAssertGreaterThanOrEqual(hostingView.fittingSize.height, 38)
        }
    }

    func testWindowDragHandleReportsPointerTranslation() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let state = DragHarnessState()
            let hostingView = NSHostingView(
                rootView: WindowDragHandle(
                    onChanged: { state.translation = $0 },
                    onEnded: { state.didEnd = true }
                )
                .frame(width: 120, height: 32)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 120, height: 32),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)

            sendMouseEvent(.leftMouseDown, at: NSPoint(x: 60, y: 16), in: hostingView, window: window)
            sendMouseEvent(.leftMouseDragged, at: NSPoint(x: 90, y: 12), in: hostingView, window: window)
            sendMouseEvent(.leftMouseUp, at: NSPoint(x: 90, y: 12), in: hostingView, window: window)

            XCTAssertEqual(state.translation.width, 30, accuracy: 1)
            XCTAssertEqual(state.translation.height, -4, accuracy: 1)
            XCTAssertTrue(state.didEnd)
        }
    }

    func testPopupWindowManualMoveUpdatesFrameAndPersistsPosition() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            let previousTopLeft = store.panelTopLeft
            let previousPinned = store.isPinned
            store.panelSize = NSSize(width: PopupWindow.minimumWidth, height: 300)
            store.panelTopLeft = nil
            store.isPinned = true
            defer {
                store.panelSize = previousSize
                store.panelTopLeft = previousTopLeft
                store.isPinned = previousPinned
            }

            let appState = AppState()
            appState.isPinned = true
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let start = panel.frame.origin
            appState.popupWindow.moveManually(by: CGSize(width: 40, height: -20))

            XCTAssertEqual(panel.frame.origin.x, start.x + 40, accuracy: 1)
            XCTAssertEqual(panel.frame.origin.y, start.y + 20, accuracy: 1)

            appState.popupWindow.endManualMove()
            XCTAssertEqual(store.panelTopLeft?.x ?? 0, panel.frame.minX, accuracy: 1)
            XCTAssertEqual(store.panelTopLeft?.y ?? 0, panel.frame.maxY, accuracy: 1)
        }
    }

    func testPopupHeaderDragMovesPanelThroughGesture() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            let previousTopLeft = store.panelTopLeft
            let previousPinned = store.isPinned
            store.panelSize = NSSize(width: PopupWindow.minimumWidth, height: 300)
            store.panelTopLeft = nil
            store.isPinned = true
            defer {
                store.panelSize = previousSize
                store.panelTopLeft = previousTopLeft
                store.isPinned = previousPinned
            }

            let appState = AppState()
            appState.isPinned = true
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let contentView = try XCTUnwrap(panel.contentView)
            let start = panel.frame.origin
            let y = contentView.isFlipped ? 27 : contentView.bounds.height - 27
            let point = NSPoint(x: contentView.bounds.width * 0.68, y: y)
            let moved = point.applying(CGAffineTransform(translationX: 40, y: -20))
            sendMouseEvent(.leftMouseDown, at: point, in: contentView, window: panel)
            waitForViewUpdate()
            sendMouseEvent(.leftMouseDragged, at: moved, in: contentView, window: panel)
            waitForViewUpdate()
            sendMouseEvent(.leftMouseUp, at: moved, in: contentView, window: panel)
            waitForViewUpdate()

            XCTAssertEqual(panel.frame.origin.x, start.x + 40, accuracy: 1)
            XCTAssertEqual(panel.frame.origin.y, start.y + 20, accuracy: 1)
        }
    }

    /// Regression: the gesture's `translation` is measured in the window's own
    /// coordinate space, which moves together with the window. Simulate how the
    /// window server actually computes `locationInWindow` — against the window's
    /// *current* origin — and verify the panel keeps tracking the pointer across
    /// multiple drag updates instead of snapping back or oscillating.
    func testPopupHeaderDragFollowsPointerAcrossWindowMoves() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            let previousTopLeft = store.panelTopLeft
            let previousPinned = store.isPinned
            store.panelSize = NSSize(width: PopupWindow.minimumWidth, height: 300)
            store.panelTopLeft = nil
            store.isPinned = true
            defer {
                store.panelSize = previousSize
                store.panelTopLeft = previousTopLeft
                store.isPinned = previousPinned
            }

            let appState = AppState()
            appState.isPinned = true
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let start = panel.frame.origin

            // Pointer positions in *screen* coordinates (AppKit, y-up), grabbing
            // the header drag area at 75% width, 27pt below the top edge.
            var pointer = NSPoint(
                x: start.x + panel.frame.width * 0.68,
                y: start.y + panel.frame.height - 27
            )
            sendMouseEventAtScreenPoint(.leftMouseDown, screenPoint: pointer, window: panel)
            waitForViewUpdate()

            pointer.x += 40
            pointer.y += 20
            sendMouseEventAtScreenPoint(.leftMouseDragged, screenPoint: pointer, window: panel)
            waitForViewUpdate()

            XCTAssertEqual(panel.frame.origin.x, start.x + 40, accuracy: 1)
            XCTAssertEqual(panel.frame.origin.y, start.y + 20, accuracy: 1)

            pointer.x += 30
            pointer.y -= 50
            sendMouseEventAtScreenPoint(.leftMouseDragged, screenPoint: pointer, window: panel)
            waitForViewUpdate()
            sendMouseEventAtScreenPoint(.leftMouseUp, screenPoint: pointer, window: panel)
            waitForViewUpdate()

            XCTAssertEqual(panel.frame.origin.x, start.x + 70, accuracy: 1)
            XCTAssertEqual(panel.frame.origin.y, start.y - 30, accuracy: 1)
        }
    }

    /// A window manager (e.g. Wins edge snapping) may grab the panel right
    /// after a drag ends. The post-drag height settle must not fight the
    /// external frame, and the external position must not be persisted.
    func testPostDragSettleYieldsToExternalReposition() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            let previousTopLeft = store.panelTopLeft
            let previousPinned = store.isPinned
            store.panelSize = NSSize(width: PopupWindow.minimumWidth, height: 300)
            store.panelTopLeft = nil
            store.isPinned = true
            defer {
                store.panelSize = previousSize
                store.panelTopLeft = previousTopLeft
                store.isPinned = previousPinned
            }

            let appState = AppState()
            appState.isPinned = true
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let dropOrigin = panel.frame.origin.applying(CGAffineTransform(translationX: 40, y: 20))
            let dropTop = panel.frame.maxY + 20

            appState.popupWindow.moveManually(by: CGSize(width: 40, height: -20))
            appState.popupWindow.endManualMove()
            XCTAssertEqual(store.panelTopLeft?.x ?? 0, dropOrigin.x, accuracy: 1)
            XCTAssertEqual(store.panelTopLeft?.y ?? 0, dropTop, accuracy: 1)

            // The window manager repositions/resizes the panel before the
            // debounced settle (150ms) fires.
            panel.setFrame(NSRect(x: dropOrigin.x, y: dropOrigin.y - 200, width: 700, height: 500), display: false)
            waitForViewUpdate()

            // The settle must not fight the external frame…
            XCTAssertEqual(panel.frame.width, 700, accuracy: 1)
            XCTAssertEqual(panel.frame.height, 500, accuracy: 1)
            // …and the external position must not overwrite the saved one.
            XCTAssertEqual(store.panelTopLeft?.x ?? 0, dropOrigin.x, accuracy: 1)
            XCTAssertEqual(store.panelTopLeft?.y ?? 0, dropTop, accuracy: 1)
        }
    }

    func testModeSwitchPreservesInputAndChangesTaskRoute() {
        MainActor.assumeIsolated {
            let toolPanel = ToolPanelModel()
            toolPanel.activate(mode: .translation, input: "A difficult sentence", clearResults: true)

            toolPanel.selectMode(.deepRead)

            XCTAssertEqual(toolPanel.input, "A difficult sentence")
            XCTAssertEqual(toolPanel.activeTask, .deepRead)

            toolPanel.selectMode(.grammar)
            XCTAssertEqual(toolPanel.input, "A difficult sentence")
            XCTAssertEqual(toolPanel.activeTask, .grammar)
        }
    }

    func testModeSelectorAcceptsClicksOnAllSegments() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let state = ModeSelectorHarnessState()
            let hostingView = NSHostingView(
                rootView: ModeSelectorHarness(state: state)
                    .environmentObject(L10n.shared)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 38),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)

            click(
                at: NSPoint(x: hostingView.bounds.width * 0.83, y: hostingView.bounds.midY),
                in: hostingView,
                window: window
            )
            waitForViewUpdate(hostingView)
            XCTAssertEqual(state.selectedMode, .deepRead)

            click(
                at: NSPoint(x: hostingView.bounds.width * 0.50, y: hostingView.bounds.midY),
                in: hostingView,
                window: window
            )
            waitForViewUpdate(hostingView)
            XCTAssertEqual(state.selectedMode, .translation)

            click(
                at: NSPoint(x: hostingView.bounds.width * 0.17, y: hostingView.bounds.midY),
                in: hostingView,
                window: window
            )
            waitForViewUpdate(hostingView)
            XCTAssertEqual(state.selectedMode, .grammar)
        }
    }

    func testPopupContentAllowsBackgroundWindowDrag() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let appState = AppState()
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()
            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let hostingView = try XCTUnwrap(panel.contentView as? NSHostingView<AnyView>)
            XCTAssertTrue(hostingView.mouseDownCanMoveWindow)
        }
    }

    func testWorkspaceModesExposeEditableInput() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let appState = AppState()
            let source = "Text entered in the workspace"
            defer { appState.dismissPopup(restoreFocus: false) }

            for mode in ToolPanelModel.Mode.allCases {
                appState.toolPanelModel.activate(mode: mode, input: source, clearResults: true)
                appState.popupWindow.show()
                waitForViewUpdate()

                let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
                let contentView = try XCTUnwrap(panel.contentView)
                let textView = try XCTUnwrap(
                    firstDescendant(of: QuickTranslationTextEditor.PasteAwareTextView.self, in: contentView)
                )
                XCTAssertEqual(textView.string, source, "Missing editable input for \(mode.rawValue)")
                appState.dismissPopup(restoreFocus: false)
            }
        }
    }

    func testMenuBarRemovesRedundantEntriesAndAddsDeepRead() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let controller = MenuBarController(appState: AppState())
            let titles = controller.menu.items.map(\.title)

            XCTAssertTrue(titles.contains(L10n.shared.t("menu.deepRead")))
            XCTAssertFalse(titles.contains("Translate Clipboard"))
            XCTAssertFalse(titles.contains("Grammar Check"))
        }
    }

    func testSettingsTabsRenderReIconAssets() {
        MainActor.assumeIsolated {
            for tab in SettingsTab.allCases {
                let hostingView = NSHostingView(
                    rootView: tab.icon
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.black)
                        .frame(width: 24, height: 24)
                        .background(Color.white)
                )
                hostingView.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
                hostingView.layoutSubtreeIfNeeded()

                XCTAssertGreaterThan(
                    renderedDarkPixelCount(in: hostingView),
                    16,
                    "Missing or empty ReIcon asset for \(tab.rawValue)"
                )
            }
        }
    }

    func testProviderPickerReIconAssetsRender() {
        MainActor.assumeIsolated {
            for provider in LLMProviderKind.allCases {
                let image = ReIconAsset.providerIcon(for: provider)
                XCTAssertTrue(image.isTemplate)
                XCTAssertEqual(image.size, NSSize(width: 13, height: 13))

                let hostingView = NSHostingView(
                    rootView: Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.black)
                        .frame(width: 16, height: 16)
                        .background(Color.white)
                )
                hostingView.frame = NSRect(x: 0, y: 0, width: 16, height: 16)
                hostingView.layoutSubtreeIfNeeded()

                XCTAssertGreaterThan(
                    renderedDarkPixelCount(in: hostingView),
                    8,
                    "Missing or empty Provider ReIcon asset for \(provider.rawValue)"
                )
            }
        }
    }

    func testMenuBarReIconAssetRendersAtStatusBarSize() {
        MainActor.assumeIsolated {
            let image = ReIconAsset.menuBarPenSparkle
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 17, height: 17))

            let hostingView = NSHostingView(
                rootView: Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.black)
                    .frame(width: 17, height: 17)
                    .background(Color.white)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 17, height: 17)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertGreaterThan(renderedDarkPixelCount(in: hostingView), 12)
        }
    }

    func testYagrakerMarkPreservesBrandColors() {
        MainActor.assumeIsolated {
            let image = ReIconAsset.yagrakerMark
            XCTAssertFalse(image.isTemplate)

            let hostingView = NSHostingView(
                rootView: Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 88, height: 88)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertGreaterThan(renderedOpaquePixelCount(in: hostingView), 5_000)
        }
    }

    func testSettingsTabBarAnimatesSelection() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let appState = AppState()
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let originalContentView = try XCTUnwrap(panel.contentView)
            let state = SettingsTabBarHarnessState()
            let hostingView = NSHostingView(
                rootView: SettingsTabBarHarness(state: state)
                    .environmentObject(L10n.shared)
            )
            panel.contentView = hostingView
            defer { panel.contentView = originalContentView }
            waitForViewUpdate(hostingView)

            let start = try XCTUnwrap(renderedImage(in: hostingView))
            let startSelection = try XCTUnwrap(settingsSelectionCenterX(in: start))

            state.selectedTab = .provider
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            hostingView.layoutSubtreeIfNeeded()
            let transition = try XCTUnwrap(renderedImage(in: hostingView))
            let transitionSelection = try XCTUnwrap(settingsSelectionCenterX(in: transition))

            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hostingView.layoutSubtreeIfNeeded()
            let end = try XCTUnwrap(renderedImage(in: hostingView))
            let endSelection = try XCTUnwrap(settingsSelectionCenterX(in: end))
            XCTAssertGreaterThan(endSelection - startSelection, 80)
            XCTAssertGreaterThan(transitionSelection, startSelection + 5)
            XCTAssertLessThan(transitionSelection, endSelection - 5)
        }
    }

    func testSettingsTabBarAcceptsClickAcrossSegmentBoundary() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let state = SettingsTabBarHarnessState()
            let hostingView = NSHostingView(
                rootView: SettingsTabBarHarness(state: state)
                    .environmentObject(L10n.shared)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 62),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            waitForViewUpdate(hostingView)

            let startImage = try XCTUnwrap(renderedImage(in: hostingView))
            let startSelection = try XCTUnwrap(settingsSelectionCenterX(in: startImage))

            state.selectedTab = .provider
            waitForAnimation(in: hostingView)
            let endImage = try XCTUnwrap(renderedImage(in: hostingView))
            let endSelection = try XCTUnwrap(settingsSelectionCenterX(in: endImage))

            state.selectedTab = .general
            waitForAnimation(in: hostingView)
            let pixelsPerPoint = CGFloat(startImage.pixelsWide) / hostingView.bounds.width
            click(
                at: NSPoint(x: endSelection / pixelsPerPoint, y: hostingView.bounds.midY),
                in: hostingView,
                window: window
            )
            waitForViewUpdate(hostingView)
            XCTAssertEqual(state.selectedTab, .provider, "The synthetic click must reach a real tab button")

            state.selectedTab = .general
            waitForAnimation(in: hostingView)
            let segmentBoundary = (startSelection + endSelection) / (2 * pixelsPerPoint)
            click(
                at: NSPoint(x: segmentBoundary + 1, y: hostingView.bounds.midY),
                in: hostingView,
                window: window
            )
            waitForViewUpdate(hostingView)

            XCTAssertEqual(state.selectedTab, .provider)
        }
    }

    func testManualResizeChangesPopupWidthAndHeight() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let previousSize = SettingsStore.shared.panelSize
            SettingsStore.shared.panelSize = PopupWindow.defaultSize
            defer { SettingsStore.shared.panelSize = previousSize }

            let appState = AppState()
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            guard let panel = NSApp.windows.first(where: { $0 is PopupPanel && $0.isVisible }) else {
                return XCTFail("PopupPanel not found")
            }
            let initialFrame = panel.frame
            appState.popupWindow.beginManualResize()
            appState.popupWindow.resizeManually(
                to: NSSize(width: initialFrame.width + 80, height: initialFrame.height + 80)
            )
            appState.popupWindow.endManualResize()
            appState.popupWindow.resizePanel(animated: false)

            XCTAssertEqual(panel.frame.width, initialFrame.width + 80, accuracy: 1)
            XCTAssertEqual(panel.frame.height, initialFrame.height + 80, accuracy: 1)
            XCTAssertEqual(panel.frame.minX, initialFrame.minX, accuracy: 1)
            XCTAssertEqual(panel.frame.maxY, initialFrame.maxY, accuracy: 1)
            XCTAssertEqual(SettingsStore.shared.panelSize?.width ?? 0, panel.frame.width, accuracy: 1)
            XCTAssertEqual(SettingsStore.shared.panelSize?.height ?? 0, panel.frame.height, accuracy: 1)
        }
    }

    func testManualResizePersistsAcrossPopupRecreation() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let store = SettingsStore.shared
            let previousSize = store.panelSize
            store.panelSize = nil
            defer { store.panelSize = previousSize }

            let firstState = AppState()
            firstState.popupWindow.show()
            waitForViewUpdate()
            guard NSApp.windows.contains(where: { $0 is PopupPanel && $0.isVisible }) else {
                return XCTFail("First PopupPanel not found")
            }
            let targetSize = NSSize(width: 680, height: 420)
            firstState.popupWindow.beginManualResize()
            firstState.popupWindow.resizeManually(to: targetSize)
            firstState.popupWindow.endManualResize()
            firstState.dismissPopup(restoreFocus: false)

            let secondState = AppState()
            secondState.popupWindow.show()
            defer { secondState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()
            guard let secondPanel = NSApp.windows.first(where: { $0 is PopupPanel && $0.isVisible }) else {
                return XCTFail("Second PopupPanel not found")
            }

            XCTAssertEqual(secondPanel.frame.width, targetSize.width, accuracy: 1)
            XCTAssertEqual(secondPanel.frame.height, targetSize.height, accuracy: 1)
        }
    }

    func testEditorRendersTextAfterBeingReinserted() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let previousAppearance = NSApp.appearance
            NSApp.appearance = NSAppearance(named: .aqua)
            defer { NSApp.appearance = previousAppearance }

            let source = Array(repeating: "Need maybe manually verify drag with code?", count: 12)
                .joined(separator: "\n")
            let state = EditorHarnessState(text: source)

            let hostingView = NSHostingView(
                rootView: EditorHarness(state: state)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 120)
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(renderedDarkPixelCount(in: hostingView), 100)

            let initialTextView = try XCTUnwrap(firstDescendant(of: QuickTranslationTextEditor.PasteAwareTextView.self, in: hostingView))
            let end = NSRange(location: initialTextView.string.utf16.count, length: 0)
            initialTextView.setSelectedRange(end)
            initialTextView.scrollRangeToVisible(end)

            state.showsResult = true
            waitForViewUpdate(hostingView)
            state.showsResult = false
            waitForViewUpdate(hostingView)

            let textView = try XCTUnwrap(firstDescendant(of: QuickTranslationTextEditor.PasteAwareTextView.self, in: hostingView))
            XCTAssertEqual(textView.string, source)
            let scrollView = try XCTUnwrap(textView.enclosingScrollView)
            let visibleRect = scrollView.documentVisibleRect
            let textContainer = try XCTUnwrap(textView.textContainer)
            let layoutManager = try XCTUnwrap(textView.layoutManager)
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let textRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: textView.textContainerInset.width, dy: textView.textContainerInset.height)
            XCTAssertTrue(textView.isVerticallyResizable)
            XCTAssertFalse(textView.isHorizontallyResizable)
            XCTAssertTrue(textView.autoresizingMask.contains(.width))
            XCTAssertTrue(textContainer.widthTracksTextView)
            XCTAssertEqual(textView.frame.width, scrollView.contentSize.width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(textView.frame.height, scrollView.contentSize.height)
            XCTAssertFalse(visibleRect.isEmpty)
            XCTAssertTrue(visibleRect.intersects(textRect), "visible=\(visibleRect), text=\(textRect)")
            XCTAssertGreaterThan(renderedDarkPixelCount(in: scrollView.contentView), 100)
        }
    }

    func testTranslationEditorDrawsExistingGrammarInputInPopupWindow() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let previousAppearance = NSApp.appearance
            NSApp.appearance = NSAppearance(named: .aqua)
            defer { NSApp.appearance = previousAppearance }

            let source = Array(repeating: "Need maybe manually verify drag with code?", count: 12)
                .joined(separator: "\n")
            let appState = AppState()
            let toolPanel = appState.toolPanelModel
            toolPanel.activate(mode: .grammar, input: source, clearResults: true)
            appState.popupWindow.show()
            defer { appState.dismissPopup(restoreFocus: false) }
            waitForViewUpdate()

            let initialPanel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let initialContentView = try XCTUnwrap(initialPanel.contentView)
            let initialTextView = try XCTUnwrap(
                firstDescendant(of: QuickTranslationTextEditor.PasteAwareTextView.self, in: initialContentView)
            )
            let end = NSRange(location: initialTextView.string.utf16.count, length: 0)
            initialTextView.setSelectedRange(end)
            initialTextView.scrollRangeToVisible(end)

            appState.originalText = source
            appState.correctionResult = CorrectionResult(
                corrections: [Correction(original: "Need maybe", corrected: "Maybe I need to")],
                tip: "Keep the explanation focused."
            )
            waitForViewUpdate()

            toolPanel.selectMode(.translation)
            waitForViewUpdate()

            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PopupPanel && $0.isVisible })
            let contentView = try XCTUnwrap(panel.contentView)
            let textView = try XCTUnwrap(
                firstDescendant(of: QuickTranslationTextEditor.PasteAwareTextView.self, in: contentView)
            )
            let scrollView = try XCTUnwrap(textView.enclosingScrollView)
            XCTAssertEqual(textView.string, source)
            XCTAssertEqual(textView.frame.width, scrollView.contentSize.width, accuracy: 1)
            XCTAssertGreaterThan(renderedDarkPixelCount(in: scrollView.contentView), 100)
        }
    }

    func testStreamingMarkdownViewConsumesReplacementStream() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let state = TranslationMarkdownHarnessState()
            let hostingView = NSHostingView(
                rootView: TranslationMarkdownHarness(state: state)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.orderFrontRegardless()
            defer {
                state.source.finish()
                window.orderOut(nil)
            }

            state.source.update(with: "First streamed response")
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertTrue(renderedText(in: hostingView).contains("First streamed response"))

            state.source.finish()
            let replacement = MarkdownStreamSource()
            state.source = replacement
            waitForViewUpdate(hostingView)
            replacement.update(with: "Second streamed response")
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertTrue(
                renderedText(in: hostingView).contains("Second streamed response"),
                "A new translation must consume its own stream instead of retaining the completed stream"
            )
        }
    }

    @MainActor
    func testTranslationStreamPublishesNormalizedFullSnapshots() async {
        let source = MarkdownStreamSource()
        var iterator = source.text.makeAsyncIterator()

        source.update(with: "\n\nFirst draft\n")
        source.update(with: "\n\nFinal translation\n\n")
        source.finish()

        let snapshot = await iterator.next()
        XCTAssertEqual(snapshot, "Final translation")
        let completion = await iterator.next()
        XCTAssertNil(completion)
    }

    func testCompletedTranslationRendersAfterTabRoundTrip() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let state = TranslationMarkdownHarnessState()
            let hostingView = NSHostingView(
                rootView: TranslationMarkdownHarness(state: state)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }

            state.source.update(with: "Persisted translation")
            state.source.finish()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            XCTAssertTrue(renderedText(in: hostingView).contains("Persisted translation"))

            state.showsTranslation = false
            waitForViewUpdate(hostingView)
            state.showsTranslation = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertTrue(
                renderedText(in: hostingView).contains("Persisted translation"),
                "A completed translation must be replayed when returning to the Translate tab"
            )
        }
    }

    func testClearingOrModifyingInputResetsStaleResults() {
        MainActor.assumeIsolated {
            let appState = AppState()

            // 1. Grammar Mode: result is cleared when input is modified
            appState.originalText = "She don't like apples"
            appState.toolPanelModel.input = "She don't like apples"
            appState.correctionResult = CorrectionResult(
                corrections: [Correction(original: "don't", corrected: "doesn't")],
                tip: "Use doesn't for third person singular."
            )
            XCTAssertNotNil(appState.correctionResult)

            // Modifying input clears the stale grammar correction
            appState.toolPanelModel.input = "She don't like oranges"
            XCTAssertNil(appState.correctionResult)

            // 2. ClearAll resets everything to clean state
            appState.originalText = "Some text"
            appState.correctionResult = CorrectionResult(corrections: [], tip: "")
            appState.toolPanelModel.input = "Some text"
            appState.clearAll()
            XCTAssertEqual(appState.toolPanelModel.input, "")
            XCTAssertNil(appState.correctionResult)
            XCTAssertEqual(appState.originalText, "")
        }
    }

    @MainActor
    private func waitForViewUpdate(_ view: NSView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.layoutSubtreeIfNeeded()
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @MainActor
    private func waitForAnimation(in view: NSView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
    }

    @MainActor
    private func waitForViewUpdate() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        NSApp.windows.forEach { $0.contentView?.layoutSubtreeIfNeeded() }
    }

    private func firstDescendant<View: NSView>(of type: View.Type, in root: NSView) -> View? {
        if let match = root as? View { return match }
        for subview in root.subviews {
            if let match = firstDescendant(of: type, in: subview) { return match }
        }
        return nil
    }

    private func allDescendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
        var descendants = (root as? View).map { [$0] } ?? []
        for subview in root.subviews {
            descendants.append(contentsOf: allDescendants(of: type, in: subview))
        }
        return descendants
    }

    private func renderedText(in root: NSView) -> String {
        allDescendants(of: NSTextView.self, in: root)
            .map(\.string)
            .joined(separator: "\n")
    }

    @MainActor
    private func click(at point: NSPoint, in view: NSView, window: NSWindow) {
        sendMouseEvent(.leftMouseDown, at: point, in: view, window: window)
        sendMouseEvent(.leftMouseUp, at: point, in: view, window: window)
    }

    @MainActor
    private func sendMouseEvent(
        _ eventType: NSEvent.EventType,
        at point: NSPoint,
        in view: NSView,
        window: NSWindow
    ) {
        let location = view.convert(point, to: nil)
        let event = NSEvent.mouseEvent(
            with: eventType,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: eventType == .leftMouseDown ? 1 : 0
        )
        if let event {
            window.sendEvent(event)
        }
    }

    /// Sends a mouse event for a pointer at `screenPoint`, mirroring the window
    /// server: `locationInWindow` is recomputed against the window's *current*
    /// origin, so events reflect any window movement since the previous event.
    @MainActor
    private func sendMouseEventAtScreenPoint(
        _ eventType: NSEvent.EventType,
        screenPoint: NSPoint,
        window: NSWindow
    ) {
        let origin = window.frame.origin
        let location = NSPoint(x: screenPoint.x - origin.x, y: screenPoint.y - origin.y)
        let event = NSEvent.mouseEvent(
            with: eventType,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: eventType == .leftMouseDown ? 1 : 0
        )
        if let event {
            window.sendEvent(event)
        }
    }

    @MainActor
    private func renderedDarkPixelCount(in view: NSView) -> Int {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: image)

        var count = 0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                if color.redComponent < 0.45,
                   color.greenComponent < 0.45,
                   color.blueComponent < 0.45 {
                    count += 1
                }
            }
        }
        return count
    }

    @MainActor
    private func renderedOpaquePixelCount(in view: NSView) -> Int {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: image)

        var count = 0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide
            where (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                count += 1
            }
        }
        return count
    }

    private func horizontalHairlineClusterCount(in image: NSBitmapImageRep) -> Int {
        guard let background = image.colorAt(
            x: image.pixelsWide / 2,
            y: image.pixelsHigh / 2
        )?.usingColorSpace(.deviceRGB) else { return 0 }

        let horizontalInset = 12
        let verticalInset = 12
        let requiredPixels = Int(Double(image.pixelsWide - horizontalInset * 2) * 0.72)
        var matchingRows: [Int] = []

        for y in verticalInset..<(image.pixelsHigh - verticalInset) {
            var matchingPixels = 0
            for x in horizontalInset..<(image.pixelsWide - horizontalInset) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                let darkness = (
                    background.redComponent - color.redComponent
                        + background.greenComponent - color.greenComponent
                        + background.blueComponent - color.blueComponent
                ) / 3
                if darkness > 0.035, darkness < 0.16 {
                    matchingPixels += 1
                }
            }
            if matchingPixels >= requiredPixels {
                matchingRows.append(y)
            }
        }

        var clusters = 0
        var previousRow: Int?
        for row in matchingRows {
            if previousRow.map({ row > $0 + 1 }) ?? true {
                clusters += 1
            }
            previousRow = row
        }
        return clusters
    }

    @MainActor
    private func renderedImage(in view: NSView) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: image)
        return image
    }

    private func settingsSelectionCenterX(in image: NSBitmapImageRep) -> CGFloat? {
        var weightedX: CGFloat = 0
        var totalWeight: CGFloat = 0

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                let warmth = color.redComponent - color.blueComponent
                guard warmth > 0.04 else { continue }
                weightedX += CGFloat(x) * warmth
                totalWeight += warmth
            }
        }
        return totalWeight > 0 ? weightedX / totalWeight : nil
    }

}

@MainActor
private final class SettingsTabBarHarnessState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

private struct SettingsTabBarHarness: View {
    @ObservedObject var state: SettingsTabBarHarnessState

    var body: some View {
        SettingsTabBar(selectedTab: $state.selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
    }
}

@MainActor
private final class ModeSelectorHarnessState: ObservableObject {
    @Published var selectedMode: ToolPanelModel.Mode = .grammar
}

private struct ModeSelectorHarness: View {
    @ObservedObject var state: ModeSelectorHarnessState

    var body: some View {
        GlassModeSelector(
            selectedMode: state.selectedMode,
            onSelect: { state.selectedMode = $0 }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

@MainActor
private final class DragHarnessState: ObservableObject {
    @Published var translation: CGSize = .zero
    @Published var didEnd = false
}

@MainActor
private final class EditorHarnessState: ObservableObject {
    @Published var text: String
    @Published var showsResult = false

    init(text: String) {
        self.text = text
    }
}

private struct EditorHarness: View {
    @ObservedObject var state: EditorHarnessState

    var body: some View {
        ScrollView {
            if state.showsResult {
                Text(state.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                QuickTranslationTextEditor(
                    text: $state.text,
                    placeholder: "Input",
                    onSubmit: {},
                    onPasteAndSubmit: {}
                )
                .frame(minHeight: 44, maxHeight: 96)
            }
        }
        .frame(width: 480, height: 96)
        .background(Color.white)
    }
}

@MainActor
private final class TranslationMarkdownHarnessState: ObservableObject {
    @Published var source = MarkdownStreamSource()
    @Published var showsTranslation = true
}

private struct TranslationMarkdownHarness: View {
    @ObservedObject var state: TranslationMarkdownHarnessState

    var body: some View {
        Group {
            if state.showsTranslation {
                StreamingMarkdownView(source: state.source)
            } else {
                Text("Grammar")
            }
        }
        .frame(width: 480, height: 180, alignment: .topLeading)
    }
}

private final class EchoingOpenStreamService: LLMServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    func checkGrammar(
        request: GrammarCheckRequest,
        apiKey: String,
        model: String
    ) async throws -> CorrectionResult {
        throw LLMError.invalidResponse
    }

    func streamText(
        task: LLMTask,
        text: String,
        systemPrompt: String,
        targetLanguage: TranslationTargetLanguage,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            let previousContinuation = self.continuation
            self.continuation = continuation
            lock.unlock()
            previousContinuation?.finish()
            continuation.yield(text)
        }
    }

    func listModels(apiKey: String) async throws -> [LLMModel] { [] }

    func validate(apiKey: String, model: String) async throws -> String { "test" }

    func finish() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}
