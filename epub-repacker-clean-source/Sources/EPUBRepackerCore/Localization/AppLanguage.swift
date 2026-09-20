import Foundation

/// Supported application languages in EPUB Repacker.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh"

    /// User-facing display name for the language.
    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "简体中文"
        }
    }

    /// Initializes an `AppLanguage` from a language code or prefix (e.g. "en", "zh", "zh-Hans").
    public init?(code: String) {
        if code.hasPrefix("zh") {
            self = .chinese
        } else if code.hasPrefix("en") {
            self = .english
        } else {
            self.init(rawValue: code)
        }
    }
}
