import Carbon.HIToolbox
import XCTest
@testable import MacScreenTranslator

final class ShortcutFormatterTests: XCTestCase {
    func testDefaultCaptureShortcut() {
        XCTAssertEqual(ShortcutFormatter.title(keyCode: UInt32(kVK_ANSI_T),
                                              modifiers: UInt32(controlKey | shiftKey)), "⌃⇧T")
    }

    func testModifierSymbolsHaveStableDisplayOrder() {
        XCTAssertEqual(ShortcutFormatter.title(keyCode: UInt32(kVK_ANSI_V),
                                              modifiers: UInt32(shiftKey | cmdKey | controlKey | optionKey)), "⌘⌥⌃⇧V")
    }

    func testUnrelatedModifierBitsDoNotAppear() {
        XCTAssertEqual(ShortcutFormatter.title(keyCode: UInt32(kVK_ANSI_A),
                                              modifiers: UInt32(cmdKey | alphaLock)), "⌘A")
    }

    func testDigitWithoutModifiers() {
        XCTAssertEqual(ShortcutFormatter.title(keyCode: UInt32(kVK_ANSI_9), modifiers: 0), "9")
    }

    func testUnknownKeyCodeHasReadableFallback() {
        XCTAssertEqual(ShortcutFormatter.title(keyCode: 999, modifiers: UInt32(optionKey)), "⌥键码 999")
    }
}
