//
//  LKHierarchyLocationTreeFormatter.swift
//  LookInside
//
//  同事原为 Objective-C 实现（依赖 2.x 的 LookinDisplayItem.h），3.x 中 DisplayItem 已是 Swift 类，
//  这里改写为 Swift，类型名与方法签名保持不变，调用方无需改动。
//

import Foundation

/// 把节点从根到自身的路径格式化为缩进树，每行附带标题、副标题和 frame，便于复制给他人或 AI 定位。
enum LKHierarchyLocationTreeFormatter {
    static func locationTree(
        forDisplayItem displayItem: DisplayItem,
        titleProvider: (DisplayItem) -> String?,
        subtitleProvider: (DisplayItem) -> String?
    ) -> String {
        // 从当前节点向上收集到根，再按根在前的顺序输出
        var items: [DisplayItem] = []
        var cursor: DisplayItem? = displayItem
        while let item = cursor {
            items.insert(item, at: 0)
            cursor = item.super
        }

        var lines: [String] = []
        for (index, item) in items.enumerated() {
            let indent = String(repeating: " ", count: index * 3)
            var title = titleProvider(item) ?? ""
            if title.isEmpty {
                if let customDisplayTitle = item.customDisplayTitle, !customDisplayTitle.isEmpty {
                    title = customDisplayTitle
                } else {
                    title = "<Unknown>"
                }
            }
            var components = [title]
            if let subtitle = subtitleProvider(item), !subtitle.isEmpty {
                components.append(subtitle)
            }
            components.append("frame=\(string(from: item.frame))")
            lines.append("\(indent)└─ \(components.joined(separator: " "))")
        }
        return lines.joined(separator: "\n")
    }

    private static func string(from frame: CGRect) -> String {
        let values = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height].map(string(from:))
        return "(\(values.joined(separator: ", ")))"
    }

    /// 最多保留三位小数，并去掉末尾多余的 0 和小数点。
    private static func string(from value: CGFloat) -> String {
        var string = String(format: "%.3f", Double(value))
        while string.contains("."), string.hasSuffix("0") {
            string.removeLast()
        }
        if string.hasSuffix(".") {
            string.removeLast()
        }
        return string
    }
}
