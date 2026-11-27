// 辅助功能（VoiceOver 等）标签的纯函数：只拼字符串，不碰任何视图，便于单测。
// 类型词全部取自已有的本地化 key（Folder / Image / Video / Other / Tag），不新增文案。

import Foundation

enum AccessibilityLabels {
    enum Kind: Equatable {
        case folder, image, video, other
    }

    /// 名称与类型词之间的分隔。VoiceOver 在逗号处停顿，各语言都按停顿读，不引入需要翻译的格式串。
    private static let separator = ", "

    /// FileModel 的 isDir / type 归到四类：目录优先；图像、视频之外（含 .notSet / .all）都算「其它」。
    static func kind(isDirectory: Bool, type: FileType) -> Kind {
        if isDirectory { return .folder }
        switch type {
        case .folder: return .folder
        case .image: return .image
        case .video: return .video
        case .other, .notSet, .all: return .other
        }
    }

    /// 与 ViewController.setWindowTitle 的统计文案使用同一批 key，17 种语言已齐全。
    static func typeWord(_ kind: Kind) -> String {
        switch kind {
        case .folder: return NSLocalizedString("Folder", comment: "目录")
        case .image: return NSLocalizedString("Image", comment: "图像")
        case .video: return NSLocalizedString("Video", comment: "视频")
        case .other: return NSLocalizedString("Other", comment: "其它")
        }
    }

    /// 缩略图（文件与文件夹）：「文件名, 类型词」。
    /// 文件名原样保留（不截断、不转义，VoiceOver 要读完整）；名称为空或全是空白时只返回类型词。
    static func thumbnail(name: String, kind: Kind) -> String {
        join(name: name, word: typeWord(kind))
    }

    /// 大图视图：与缩略图同一格式，保证同一个文件在两种视图里读出来一样。
    static func largeImage(name: String, kind: Kind) -> String {
        thumbnail(name: name, kind: kind)
    }

    /// 侧栏条目。返回 nil 表示没有可暴露的标签：分隔线、根节点，以及名称为空的条目。
    /// - 分组标题、目录、卷、文件、特殊入口（如 iCloud 云盘）：只用名称。它们在侧栏里本来就靠位置和图标区分，
    ///   每行都追加「文件夹」只会让朗读变啰嗦；卷没有合适的已有类型词（已有的 "Volume" key 在中文等语言里是「音量」）。
    /// - 标签：名称 + 「标签」。标签名（如「工作」「红色」）与目录名同形，没有类型词听不出是标签。
    static func sidebar(name: String, role: SidebarNodeRole, isAllTagsEntry: Bool = false) -> String? {
        switch role {
        case .separator, .root:
            return nil
        case .tag:
            // 「所有标签…」入口的角色也是 .tag：名称本身已经说明是标签，再追加类型词会读成「所有标签…, 标签」。
            // 注意不能靠 entryID 区分：颜色标签是从它展开出来的，同样带 entryID == "tags"。调用方按 fullPath 恰为 `file:///VirtualFinderTagsFolder/` 判断（见 CustomOutlineViewManager；fileURL 对标签节点恒为 nil，也不能用）。
            if isAllTagsEntry { return isBlank(name) ? nil : name }
            return join(name: name, word: NSLocalizedString("Tag", comment: "标签"))
        case .group, .directory, .volume, .file, .special:
            return isBlank(name) ? nil : name
        }
    }

    private static func join(name: String, word: String) -> String {
        isBlank(name) ? word : name + separator + word
    }

    private static func isBlank(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
