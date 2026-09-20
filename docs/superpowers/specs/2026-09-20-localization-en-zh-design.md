# EPUB Repacker 国际化与语言动态切换设计规约 (Localization Design Spec)

## 1. 目标与背景 (Goals & Background)

为 **EPUB Repacker** macOS 原生应用增加多语言国际化支持，满足用户在中英文环境下的使用需求：
- **默认语言**：英文（English）。
- **支持语言**：英文（English, `en`）与 简体中文（Simplified Chinese, `zh-Hans`）。
- **双入口切换**：
  1. 主窗口右上角常驻切换控件（分段选择器 `[English | 中文]`）。
  2. macOS 系统顶部菜单栏（Menu Bar）增加 `Language` 菜单项，带有选中勾选状态（Checkmark）。
- **即时热刷新**：切换语言后毫秒级就地更新全部界面组件文字，无需退出或重启 App。
- **持久化配置**：通过 `UserDefaults` 保存用户的语言偏好，下次启动自动还原。

---

## 2. 架构设计 (Architecture Design)

### 2.1 模块职责划分

```
Sources/EPUBRepackerCore/
  └── Localization/
      ├── AppLanguage.swift         // 语言枚举与元数据
      ├── LocalizationKey.swift     // 强类型翻译 Key 定义与双语字典映射
      └── LocalizationManager.swift // 状态持有者、持久化及发布通知

Sources/EPUBRepackerApp/
  ├── AppDelegate.swift             // 响应通知重构/刷新系统菜单栏及窗口标题
  └── MainViewController.swift      // 响应通知刷新窗口全部 Label、Button、表头与弹窗
```

### 2.2 核心数据结构

#### `AppLanguage`
```swift
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}
```

#### `LocalizationManager`
- 单例模式：`LocalizationManager.shared`。
- 默认语言：读取 `UserDefaults.standard.string(forKey: "selected_app_language")`，若无记录则强制回退为 `.english`。
- 切换方法：`setLanguage(_ lang: AppLanguage)`，写入 `UserDefaults` 并向 `NotificationCenter.default` 发送 `Notification.Name.appLanguageDidChange`。
- 便捷获取方法：`L10n.get(_ key: LocalizationKey) -> String`。

#### `LocalizationKey` 映射范围
涵盖整个应用的所有文本：
1. **窗口与全局**：
   - 窗口标题：`"EPUB Repacker (EPUB Standards Compliant Repackager)"` vs `"EPUB Repacker (EPUB 规范重构与批量封装器)"`
2. **菜单栏**：
   - App Menu：`About EPUB Repacker`, `Hide EPUB Repacker`, `Hide Others`, `Show All`, `Quit EPUB Repacker`
   - File Menu：`File`, `Open Apple Books (iCloud) Folder`
   - Window Menu：`Window`, `Minimize`, `Zoom`
   - Language Menu：`Language`, `English`, `简体中文`
3. **拖拽区域**：
   - 标题：`"📦 Drag & drop EPUB files or folders here"` vs `"📦 拖拽一个或多个 EPUB 文件或目录至此处"`
   - 副标题：`"Automatically repairs mimetype, container.xml, manifest and standardizes repacking"` vs `"自动修复 mimetype、container.xml、manifest 清单并标准化重封装"`
   - 浏览按钮：`"Select Files / Folders..."` vs `"选择文件 / 目录..."`
4. **导出设置栏**：
   - 导出标题：`"Export Destination:"` vs `"导出目标位置:"`
   - 模式 0：`"Original Folder"` vs `"原文件同级目录"`
   - 模式 1：`"📚 Apple Books (iCloud)"`
   - 模式 2：`"📁 Custom Folder..."` vs `"📁 自定义目录..."`
   - 更改按钮：`"Change..."` vs `"更改目录..."`
   - Books 捷径按钮：`"📚 Open Books Folder"` vs `"📚 开启 Books 捷径目录"`
   - 路径提示模版（支持参数化插值）
5. **表格列表**：
   - 表头：`File Name`, `Status / Changes`, `Action` vs `文件名称`, `状态 / 变动`, `操作`
   - 状态：`⏳ Pending`, `🔄 Repacking...`, `✅ Done (%@)`, `❌ Failed: %@`
   - 操作按钮：`View Report`, `Finder` vs `查看报告`, `Finder`
6. **底部操作栏**：
   - 清空列表按钮：`"Clear List"` vs `"清空列表"`
   - 开始按钮：`"Repack All"` vs `"全部开始重新封装"`
   - 取消按钮：`"Cancel"` vs `"取消"`
   - 状态提示：`"Ready"`, `"Added %d item(s)"`, `"List cleared"`, `"Processing..."`, `"Progress: %d/%d"`, `"Completed!"`
7. **弹窗与报告**：
   - 队列为空提示框（标题、内容、确定按钮）
   - 重新封装报告详情（各项指标的本地化描述）

---

## 3. UI 布局与交互体验 (UI Layout & UX)

1. **主窗口顶部控制条**：
   - 在主窗口右上角添加 `NSSegmentedControl`（2 segments: `English` / `中文`）。
   - 用户点击任一语言，立即触发 `LocalizationManager.shared.setLanguage(...)`。
2. **菜单栏 `Language` 菜单**：
   - 在主菜单栏中插入 `Language`（或 `语言`）菜单项。
   - 子项中分别展示 `English` 与 `简体中文`，当前选中的项显示勾选标记（`state = .on`）。
3. **状态双向同步**：
   - 无论是通过窗口控件还是菜单栏点击切换，另一方均自动同步选中状态。
   - 调用 `updateLocalizedStrings()` 立即重设所有控件的 `title` / `stringValue` / `toolTip`，完全不需要重新绘制或闪烁。

---

## 4. 验证策略 (Verification Strategy)

1. **单元测试 (`TestRunner`)**：
   - 验证 `LocalizationManager` 默认语言为 `.english`。
   - 验证 `LocalizationManager.setLanguage` 的持久化与读取正确性。
   - 验证 `LocalizationKey` 在 English 和 Chinese 字典中均有完整翻译，不存在缺失项或空字符串。
2. **构建与运行验证 (`build_app.sh`)**：
   - 重新编译 Release 并打包签名 `EPUBRepacker.app`。
   - 启动测试，验证界面初始默认展示英文。
   - 切换至中文，验证所有控件即刻变为中文。
   - 切换回英文，验证所有控件即刻变为英文。
   - 重启 App，验证自动记住上一次选择的语言。
