import XCTest
@testable import MacScreenTranslator

@MainActor
final class HotKeyRegistryTests: XCTestCase {
    private let capture = HotKeyShortcut(keyCode: 17, modifiers: 1)
    private let clipboard = HotKeyShortcut(keyCode: 9, modifiers: 1)

    private final class Backend {
        var active: [HotKeyAction: HotKeyShortcut] = [:]
        var blocked: Set<UInt32> = []
        var attempts = 0
        func register(_ action: HotKeyAction, _ shortcut: HotKeyShortcut) -> HotKeyAction? {
            attempts += 1
            guard !blocked.contains(shortcut.keyCode) else { return nil }
            active[action] = shortcut
            return action
        }
        func unregister(_ handle: HotKeyAction) { active.removeValue(forKey: handle) }
    }

    private func registry(_ backend: Backend) -> HotKeyRegistry<HotKeyAction> {
        HotKeyRegistry(shortcuts: [.capture: capture, .clipboard: clipboard],
                       register: backend.register, unregister: backend.unregister)
    }

    func testDuplicateDoesNotUnregisterExistingShortcuts() {
        let backend = Backend(), registry = registry(backend)
        XCTAssertTrue(registry.setEnabled(true).isEmpty)
        XCTAssertNotNil(registry.update(.clipboard, to: capture))
        XCTAssertEqual(backend.active, [.capture: capture, .clipboard: clipboard])
        XCTAssertEqual(registry.shortcuts[.clipboard], clipboard)
        XCTAssertEqual(backend.attempts, 2)
    }

    func testFailedUpdateRestoresOnlyChangedShortcut() {
        let backend = Backend(), registry = registry(backend)
        _ = registry.setEnabled(true)
        backend.blocked = [10]
        XCTAssertNotNil(registry.update(.clipboard, to: .init(keyCode: 10, modifiers: 1)))
        XCTAssertEqual(backend.active, [.capture: capture, .clipboard: clipboard])
        XCTAssertEqual(registry.shortcuts[.clipboard], clipboard)
        _ = registry.setEnabled(false)
        let restarted = HotKeyRegistry(shortcuts: registry.shortcuts,
                                      register: backend.register, unregister: backend.unregister)
        XCTAssertTrue(restarted.setEnabled(true).isEmpty)
        XCTAssertEqual(backend.active[.clipboard], clipboard)
    }

    func testStartupFailureDoesNotDisableOtherShortcut() {
        for blocked in [capture.keyCode, clipboard.keyCode] {
            let backend = Backend(), registry = registry(backend)
            backend.blocked = [blocked]
            XCTAssertEqual(registry.setEnabled(true).count, 1)
            XCTAssertEqual(backend.active.count, 1)
            XCTAssertFalse(backend.active.values.contains { $0.keyCode == blocked })
        }
    }

    func testUpdatesAreValidatedWhileSettingsPauseHotkeys() {
        let backend = Backend(), registry = registry(backend)
        _ = registry.setEnabled(true)
        _ = registry.setEnabled(false)
        backend.blocked = [10]
        XCTAssertNotNil(registry.update(.clipboard, to: .init(keyCode: 10, modifiers: 1)))
        XCTAssertEqual(registry.shortcuts[.clipboard], clipboard)
        XCTAssertTrue(backend.active.isEmpty)
        let next = HotKeyShortcut(keyCode: 11, modifiers: 1)
        XCTAssertNil(registry.update(.clipboard, to: next))
        XCTAssertTrue(backend.active.isEmpty)
        XCTAssertEqual(registry.shortcuts[.clipboard], next)
        XCTAssertTrue(registry.setEnabled(true).isEmpty)
        XCTAssertEqual(backend.active, [.capture: capture, .clipboard: next])
    }

    func testSuccessfulChangeLeavesOtherShortcutRegistered() {
        let backend = Backend(), registry = registry(backend)
        _ = registry.setEnabled(true)
        let next = HotKeyShortcut(keyCode: 11, modifiers: 1)
        XCTAssertNil(registry.update(.capture, to: next))
        XCTAssertEqual(backend.active, [.capture: next, .clipboard: clipboard])
    }

    func testRestoreFailureIsReportedWithoutLosingOtherShortcut() {
        let backend = Backend(), registry = registry(backend)
        _ = registry.setEnabled(true)
        backend.blocked = [10, clipboard.keyCode]
        let error = registry.update(.clipboard, to: .init(keyCode: 10, modifiers: 1))
        XCTAssertTrue(error?.contains("恢复失败") == true)
        XCTAssertEqual(registry.shortcuts[.clipboard], clipboard)
        XCTAssertEqual(backend.active, [.capture: capture])
    }

    func testStoreRejectsConflictAndRegistrationFailureWithoutSaving() {
        let store = TranslationStore(apiKey: "")
        let old = store.clipboardShortcut
        let other = store.captureShortcut
        var called = false
        store.registerShortcut = { _, _ in called = true; return "注册失败" }
        store.setClipboardShortcut(keyCode: other.keyCode, modifiers: other.modifiers)
        XCTAssertFalse(called)
        XCTAssertEqual(store.clipboardShortcut.keyCode, old.keyCode)
        XCTAssertEqual(store.clipboardShortcut.modifiers, old.modifiers)
        let candidate = old.keyCode == 123 || other.keyCode == 123 ? UInt32(124) : UInt32(123)
        store.setClipboardShortcut(keyCode: candidate, modifiers: old.modifiers)
        XCTAssertTrue(called)
        XCTAssertEqual(store.shortcutError, "注册失败")
        XCTAssertEqual(store.clipboardShortcut.keyCode, old.keyCode)
        XCTAssertEqual(store.clipboardShortcut.modifiers, old.modifiers)
    }

}
