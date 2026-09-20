import Foundation

extension Notification.Name {
    /// Broadcast when the application language has been changed.
    public static let appLanguageDidChange = Notification.Name("EPUBRepackerAppLanguageDidChange")
}

/// Central localization manager providing thread-safe string lookup, formatting, and language persistence.
public final class LocalizationManager: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = LocalizationManager()

    /// User defaults storage key for persisted language preference.
    public static let storageKey = "selected_app_language"

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private var _currentLanguage: AppLanguage

    /// The currently active application language.
    public var currentLanguage: AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        return _currentLanguage
    }

    /// Initializes a LocalizationManager instance with the specified UserDefaults storage.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let savedCode = userDefaults.string(forKey: Self.storageKey),
           let lang = AppLanguage(code: savedCode) ?? AppLanguage(rawValue: savedCode) {
            self._currentLanguage = lang
        } else {
            self._currentLanguage = .english
        }
    }

    /// Updates the active language, persists the preference, and notifies observers.
    public func setLanguage(_ lang: AppLanguage) {
        lock.lock()
        _currentLanguage = lang
        userDefaults.set(lang.rawValue, forKey: Self.storageKey)
        lock.unlock()

        NotificationCenter.default.post(name: .appLanguageDidChange, object: self)
    }

    /// Returns the localized string for the specified key in the active language.
    public func string(_ key: LocalizationKey) -> String {
        return Self.lookup(key: key, language: currentLanguage)
    }

    /// Returns a formatted localized string for the specified key in the active language.
    public func format(_ key: LocalizationKey, _ args: CVarArg...) -> String {
        let template = string(key)
        return String(format: template, arguments: args)
    }

    /// Returns a formatted localized string for the specified key with an array of arguments.
    public func format(_ key: LocalizationKey, args: [CVarArg]) -> String {
        let template = string(key)
        return String(format: template, arguments: args)
    }

    /// Looks up a localized string for a key in the given language.
    public static func lookup(key: LocalizationKey, language: AppLanguage) -> String {
        switch language {
        case .english:
            return englishDictionary[key] ?? key.rawValue
        case .chinese:
            return chineseDictionary[key] ?? englishDictionary[key] ?? key.rawValue
        }
    }

    // MARK: - Dictionaries

    private static let englishDictionary: [LocalizationKey: String] = [
        // Window & App Information
        .windowTitle: "EPUB Repacker (EPUB Standards Normalizer & Repacker)",

        // Menu Bar
        .menuAbout: "About EPUB Repacker",
        .menuHide: "Hide EPUB Repacker",
        .menuHideOthers: "Hide Others",
        .menuShowAll: "Show All",
        .menuQuit: "Quit EPUB Repacker",
        .menuFile: "File",
        .menuOpenBooksSync: "Open Apple Books (iCloud) Directory",
        .menuWindow: "Window",
        .menuMinimize: "Minimize",
        .menuZoom: "Zoom",
        .menuLanguage: "Language",
        .menuLanguageEnglish: "English",
        .menuLanguageChinese: "Simplified Chinese (简体中文)",

        // Drop Zone
        .dropTitle: "📦 Drag & Drop EPUB files or folders here",
        .dropSubtitle: "Auto-repair mimetype, container.xml, manifest, and repack standard EPUB",
        .browseButton: "Select Files / Folders...",

        // Export Destination Settings
        .exportTitle: "Export Destination:",
        .exportSameDir: "Same directory as source",
        .exportAppleBooks: "📚 Apple Books (iCloud)",
        .exportCustomDir: "📁 Custom Folder...",
        .changeFolderButton: "Change Folder...",
        .openBooksButton: "📚 Open Books Shortcut",
        .openBooksTooltip: "Open Apple Books iCloud directory in Finder (~/Library/Mobile Documents/iCloud~com~apple~iBooks/Documents/)",
        .destCurrentSameDir: "Current: Save next to original files (suffix _repacked.epub)",
        .destCurrentAppleBooks: "Current: Auto-export to Apple Books sync directory (%@)",
        .destCurrentCustom: "Current: Export all to %@",

        // File Dialogs & System Actions
        .chooseFolderPrompt: "Select Export Folder",
        .booksOpenedInFinder: "Opened Apple Books directory in Finder",
        .booksOpenFailed: "Attempted to open Books directory in Finder",

        // Queue Table View
        .colFileName: "File Name",
        .colStatus: "Status / Changes",
        .colAction: "Action",

        // Status Updates
        .statusReady: "Ready",
        .statusItemsAdded: "Added %d item(s) to queue",
        .statusListCleared: "Queue cleared",
        .statusProcessing: "Processing...",
        .statusProgress: "Progress: %d/%d",
        .statusCompleted: "Processing completed!",

        // Item Status & Table Actions
        .itemStatusPending: "⏳ Pending",
        .itemStatusProcessing: "🔄 Repacking...",
        .itemStatusSuccess: "✅ Done (%@)",
        .itemStatusFailed: "❌ Failed: %@",
        .btnViewReport: "View Report",
        .btnFinder: "Finder",

        // Control Buttons
        .btnClearQueue: "Clear Queue",
        .btnStartRepack: "Start Repacking All",
        .btnCancel: "Cancel",

        // Alerts
        .alertEmptyTitle: "Queue Empty",
        .alertEmptyMessage: "Please drag and drop or select EPUB files or folders to repack.",
        .alertBtnOK: "OK",

        // Repair & Repack Report Dialog
        .reportTitle: "EPUB Repack & Repair Report",
        .reportFile: "Book/File: %@",
        .reportDivider: "--------------------------------------",
        .reportMimetype: "• Mimetype: %@",
        .reportMimetypeFixed: "Fixed & uncompressed (Method 0)",
        .reportMimetypeOK: "Standard compliant",
        .reportContainer: "• Container: %@",
        .reportContainerCreated: "Recreated valid container.xml",
        .reportContainerOK: "OK",
        .reportManifestAdded: "• Manifest items added: +%d",
        .reportManifestRemoved: "• Manifest dead links removed: -%d",
        .reportJunkRemoved: "• Redundant system files removed: %d (.DS_Store, etc.)",
        .reportSizeDifference: "• Size difference: %@",
        .reportOutputPath: "• Output destination: %@",
        .reportDetailedLogs: "Detailed Execution Logs:"
    ]

    private static let chineseDictionary: [LocalizationKey: String] = [
        // Window & App Information
        .windowTitle: "EPUB Repacker (EPUB 规范重构与批量封装器)",

        // Menu Bar
        .menuAbout: "关于 EPUB Repacker",
        .menuHide: "隐藏 EPUB Repacker",
        .menuHideOthers: "隐藏其他",
        .menuShowAll: "全部显示",
        .menuQuit: "退出 EPUB Repacker",
        .menuFile: "文件",
        .menuOpenBooksSync: "打开 Apple Books (iCloud) 同步目录",
        .menuWindow: "窗口",
        .menuMinimize: "最小化",
        .menuZoom: "缩放",
        .menuLanguage: "语言",
        .menuLanguageEnglish: "English (英文)",
        .menuLanguageChinese: "简体中文",

        // Drop Zone
        .dropTitle: "📦 拖拽一个或多个 EPUB 文件或目录至此处",
        .dropSubtitle: "自动修复 mimetype、container.xml、manifest 清单并标准化重封装",
        .browseButton: "选择文件 / 目录...",

        // Export Destination Settings
        .exportTitle: "导出目标位置:",
        .exportSameDir: "原文件同级目录",
        .exportAppleBooks: "📚 Apple Books (iCloud)",
        .exportCustomDir: "📁 自定义目录...",
        .changeFolderButton: "更改目录...",
        .openBooksButton: "📚 开启 Books 捷径目录",
        .openBooksTooltip: "在 Finder 中打开 Apple Books iCloud 同步目录 (~/Library/Mobile Documents/iCloud~com~apple~iBooks/Documents/)",
        .destCurrentSameDir: "当前设置: 保存在各文件原本所在目录下 (命名自动追加 _repacked.epub)",
        .destCurrentAppleBooks: "当前设置: 自动导出至 Apple Books 同步目录 (%@)",
        .destCurrentCustom: "当前设置: 统一导出至 %@",

        // File Dialogs & System Actions
        .chooseFolderPrompt: "选择导出目录",
        .booksOpenedInFinder: "已在 Finder 中打开 Apple Books 目录",
        .booksOpenFailed: "已尝试在 Finder 中开启 Books 目录",

        // Queue Table View
        .colFileName: "文件名称",
        .colStatus: "状态 / 变动",
        .colAction: "操作",

        // Status Updates
        .statusReady: "准备就绪",
        .statusItemsAdded: "已添加 %d 个待处理项目",
        .statusListCleared: "列表已清空",
        .statusProcessing: "正在处理中...",
        .statusProgress: "进度: %d/%d",
        .statusCompleted: "处理完毕！",

        // Item Status & Table Actions
        .itemStatusPending: "⏳ 等待处理",
        .itemStatusProcessing: "🔄 正在重新封装...",
        .itemStatusSuccess: "✅ 完成 (%@)",
        .itemStatusFailed: "❌ 失败: %@",
        .btnViewReport: "查看报告",
        .btnFinder: "Finder",

        // Control Buttons
        .btnClearQueue: "清空列表",
        .btnStartRepack: "全部开始重新封装",
        .btnCancel: "取消",

        // Alerts
        .alertEmptyTitle: "队列为空",
        .alertEmptyMessage: "请先拖入或选择需要重新封装的 EPUB 文件或目录。",
        .alertBtnOK: "确定",

        // Repair & Repack Report Dialog
        .reportTitle: "EPUB 重新封装与修复报告",
        .reportFile: "书名/文件: %@",
        .reportDivider: "--------------------------------------",
        .reportMimetype: "• Mimetype: %@",
        .reportMimetypeFixed: "已补齐并修正为 Method 0 无压缩",
        .reportMimetypeOK: "规范正常",
        .reportContainer: "• Container: %@",
        .reportContainerCreated: "重新生成规范 container.xml",
        .reportContainerOK: "正常",
        .reportManifestAdded: "• Manifest 清单补齐: +%d 项",
        .reportManifestRemoved: "• Manifest 清除死链: -%d 项",
        .reportJunkRemoved: "• 移除系统冗余垃圾: %d 项 (.DS_Store 等)",
        .reportSizeDifference: "• 体积变动: %@",
        .reportOutputPath: "• 输出位置: %@",
        .reportDetailedLogs: "详细执行日志:"
    ]
}
