import Foundation
import CoreGraphics

/// 使用归一化文字框分析阅读顺序，不依赖 Vision 的 observation 顺序。
enum OCRTextFormatter {
    struct Item {
        let text: String
        let box: CGRect
    }

    static func format(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "" }
        let height = items.map(\.box.height).sorted()[items.count / 2]
        return blocks(items, height: height).joined(separator: "\n")
    }

    private static func blocks(_ items: [Item], height: CGFloat) -> [String] {
        // 先找贯穿当前区域的栏间空白；避免先合并同高度的左右栏。
        let horizontal = items.sorted { $0.box.minX < $1.box.minX }
        var right = horizontal[0].box.maxX
        for index in 1..<horizontal.count {
            let item = horizontal[index]
            // x、y 各自归一化，不能用文字框高度衡量横向空白。
            if item.box.minX - right > 0.06 {
                return blocks(Array(horizontal[..<index]), height: height)
                    + blocks(Array(horizontal[index...]), height: height)
            }
            right = max(right, item.box.maxX)
        }

        // 跨栏标题会挡住纵向空白。先按完整横向空白分区，再分别尝试分栏。
        let vertical = items.sorted { $0.box.maxY > $1.box.maxY }
        var bottom = vertical[0].box.minY
        for index in 1..<vertical.count {
            let item = vertical[index]
            let gap = bottom - item.box.maxY
            if gap > height * 0.45 {
                let separator = gap > height * 1.8 ? [""] : []
                return blocks(Array(vertical[..<index]), height: height) + separator
                    + blocks(Array(vertical[index...]), height: height)
            }
            bottom = min(bottom, item.box.minY)
        }

        // 没有明显分区时按行排版，保留同一行内相邻文字片段。
        var lines: [[Item]] = []
        for item in items.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let index = lines.firstIndex(where: { line in
                let minY = line.map { $0.box.minY }.min()!
                let maxY = line.map { $0.box.maxY }.max()!
                let overlap = min(maxY, item.box.maxY) - max(minY, item.box.minY)
                return overlap > min(item.box.height, maxY - minY) * 0.35
                    || abs(item.box.midY - (minY + maxY) / 2) < max(item.box.height, maxY - minY) * 0.45
            }) {
                lines[index].append(item)
            } else { lines.append([item]) }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }
}
