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
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() { panel?.orderOut(nil) }

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
        panel.minSize = NSSize(width: 480, height: 320)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCurrentResult: Bool {
        !store.isTranslating && result.source == store.source && result.translation == store.translation
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    HStack(spacing: 9) {
                        BrandIcon(size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("多多翻译").font(.headline)
                            Text("译文已送达").font(.caption).foregroundStyle(AppTheme.secondary)
                        }
                    }
                    Spacer()
                    CopyTextButton(text: result.translation)
                    if isCurrentResult && store.canLearnCurrentText {
                        Button {
                            learningExpanded.toggle()
                            if learningExpanded && store.learningNote == nil { store.loadLearningNote() }
                        } label: {
                            Label(learningExpanded ? "收起" : "学习", systemImage: "lightbulb.fill")
                        }
                        .buttonStyle(WarmButtonStyle(prominent: true))
                        .tint(AppTheme.accent)
                    }
                }

                Text(result.translation)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
                    .warmCard(radius: 16)

                if learningExpanded && isCurrentResult {
                    learningContent.transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("原文", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondary)
                    Text(result.source)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.secondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(14)
                .warmCard(fill: AppTheme.peach.opacity(0.35), radius: 16)
            }
            .padding(18)
        }
        .frame(minWidth: 440, idealWidth: 520, minHeight: 280, idealHeight: 420)
        .foregroundStyle(AppTheme.cocoa)
        .tint(AppTheme.accent)
        .background(AppTheme.background)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: learningExpanded)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isLoadingLearningNote)
    }

    @ViewBuilder private var learningContent: some View {
        if store.isLoadingLearningNote {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在整理这句话…").foregroundStyle(AppTheme.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.peach.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let note = store.learningNote {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(AppTheme.accent)
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
            VStack(alignment: .leading, spacing: 10) {
                Text(store.learningError ?? "点击学习，理解这句话。")
                    .font(.callout).foregroundStyle(AppTheme.secondary)
                if store.learningError != nil {
                    Button("重试学习") { store.loadLearningNote() }.buttonStyle(WarmButtonStyle())
                }
            }
        }
    }

    private func learningBlock(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.callout)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppTheme.peach.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
