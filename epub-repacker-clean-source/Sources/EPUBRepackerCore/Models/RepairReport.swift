import Foundation

public struct RepairReport: Equatable, Sendable {
    public let sourceURL: URL
    public var destinationURL: URL?
    public var logs: [String] = []
    public var mimetypeCorrected: Bool = false
    public var containerCreated: Bool = false
    public var manifestItemsAdded: Int = 0
    public var manifestItemsRemoved: Int = 0
    public var junkFilesRemoved: Int = 0
    public var originalSizeBytes: Int64 = 0
    public var repackedSizeBytes: Int64 = 0

    public init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    public mutating func addLog(_ message: String) {
        logs.append(message)
    }

    public var sizeDifferenceFormatted: String {
        let diff = repackedSizeBytes - originalSizeBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        let rawFormatted = formatter.string(fromByteCount: abs(diff))
        let formatted = rawFormatted
            .replacingOccurrences(of: " bytes", with: " B")
            .replacingOccurrences(of: " byte", with: " B")
        if diff < 0 {
            return "-\(formatted)"
        } else if diff > 0 {
            return "+\(formatted)"
        } else {
            return "0 B"
        }
    }
}
