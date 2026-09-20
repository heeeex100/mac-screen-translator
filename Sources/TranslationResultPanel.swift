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

    func show(_ result: TranslationDisplayResult, store: TranslationStore) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: FloatingTranslationView(result: result, store: store))
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
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
        panel.minSize = NSSize(width: 400, height: 280)
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
    @ObservedObject var store: TranslationStore
    @State private var learningExpanded = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Label("译文", systemImage: "character.bubble")
                        .font(.headline)
                    Spacer()
                    if store.canLearnCurrentText {
                        Button {
                            learningExpanded.toggle()
                            if learningExpanded && store.learningNote == nil { store.loadLearningNote() }
                        } label: {
                            Label(learningExpanded ? "收起" : "学习", systemImage: "lightbulb.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }

                Text(result.translation)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))

                if learningExpanded {
                    learningContent
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("原文", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(result.source)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(18)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 380, idealHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var learningContent: some View {
        if store.isLoadingLearningNote {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在整理这句话…").foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let note = store.learningNote {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                    Text("理解这句话").font(.subheadline.weight(.semibold))
                }
                if !note.summary.isEmpty {
                    learningBlock(title: "句意", icon: "text.alignleft", text: note.summary)
                }
                if !note.keyPoints.isEmpty {
                    learningBlock(title: "表达", icon: "text.book.closed", text: note.keyPoints)
                }
                if !note.words.isEmpty {
                    learningBlock(title: "词汇", icon: "character.book.closed", text: note.words)
                }
            }
            .textSelection(.enabled)
        } else {
            Text("正在准备学习内容…").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func learningBlock(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
