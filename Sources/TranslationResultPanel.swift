import AppKit
import SwiftUI

/// 从翻译流程传递给悬浮窗口的不可变结果。
struct TranslationDisplayResult {
    let source: String
    let translation: String
}

/// 复用单个置顶窗口展示最新译文，避免每次翻译都创建一个新窗口。
final class TranslationResultPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func show(_ result: TranslationDisplayResult) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: FloatingTranslationView(result: result))
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "翻译结果"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // 在所有桌面空间及全屏应用上都允许显示结果。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 360, height: 180)
        panel.delegate = self
        return panel
    }

    private func position(_ panel: NSPanel) {
        // 优先显示在鼠标所在屏幕，方便多显示器场景下直接查看。
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}

private struct FloatingTranslationView: View {
    let result: TranslationDisplayResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("译文")
                .font(.headline)

            ScrollView {
                Text(result.translation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            Divider()

            HStack {
                Text("原文：\(result.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("复制译文") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.translation, forType: .string)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 180)
    }
}
