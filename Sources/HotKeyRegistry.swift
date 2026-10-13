import Foundation

enum HotKeyAction: CaseIterable {
    case capture, clipboard
    var title: String { self == .capture ? "截图" : "剪贴板" }
    var id: UInt32 { self == .capture ? 1 : 2 }
}

struct HotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// 每项快捷键独立注册。新配置经过注册验证后，调用方才可持久化。
@MainActor
final class HotKeyRegistry<Handle> {
    private(set) var shortcuts: [HotKeyAction: HotKeyShortcut]
    private var handles: [HotKeyAction: Handle] = [:]
    private(set) var enabled = false
    private let register: (HotKeyAction, HotKeyShortcut) -> Handle?
    private let unregister: (Handle) -> Void

    init(shortcuts: [HotKeyAction: HotKeyShortcut],
         register: @escaping (HotKeyAction, HotKeyShortcut) -> Handle?,
         unregister: @escaping (Handle) -> Void) {
        self.shortcuts = shortcuts
        self.register = register
        self.unregister = unregister
    }

    func setEnabled(_ enabled: Bool) -> [String] {
        self.enabled = enabled
        if !enabled {
            handles.values.forEach(unregister)
            handles.removeAll()
            return []
        }
        var errors: [String] = []
        for action in HotKeyAction.allCases where handles[action] == nil {
            guard let shortcut = shortcuts[action] else { continue }
            if let handle = register(action, shortcut) { handles[action] = handle }
            else { errors.append("\(action.title)快捷键注册失败，可能已被其他应用占用。") }
        }
        return errors
    }

    func update(_ action: HotKeyAction, to shortcut: HotKeyShortcut) -> String? {
        guard !shortcuts.contains(where: { $0.key != action && $0.value == shortcut }) else {
            return "两个快捷键不能设置为同一组合键，已保留原配置。"
        }
        let previous = shortcuts[action]
        if previous == shortcut && enabled && handles[action] != nil { return nil }
        let previousHandle = handles.removeValue(forKey: action)
        if let previousHandle { unregister(previousHandle) }
        guard let newHandle = register(action, shortcut) else {
            if enabled, previousHandle != nil, let previous {
                if let restored = register(action, previous) { handles[action] = restored }
                else { return "\(action.title)快捷键注册失败，旧快捷键恢复失败；已保留原配置，请重试。" }
            }
            return "\(action.title)快捷键注册失败，可能已被其他应用占用；已保留原配置。"
        }
        shortcuts[action] = shortcut
        if enabled { handles[action] = newHandle }
        else { unregister(newHandle) }
        return nil
    }
}
