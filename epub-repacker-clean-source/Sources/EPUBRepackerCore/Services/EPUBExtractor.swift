import Foundation

public enum ExtractorError: LocalizedError, Equatable, Sendable {
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg):
            return "解压失败: \(msg)"
        }
    }
}

public struct EPUBExtractor: Sendable {
    public static func extract(from sourceURL: URL, to destinationDir: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue {
            // Source is already a directory, copy its content
            if let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    let subPath = fileURL.path.replacingOccurrences(of: sourceURL.path, with: "")
                    let targetURL = destinationDir.appendingPathComponent(subPath)
                    var fileIsDir: ObjCBool = false
                    if fm.fileExists(atPath: fileURL.path, isDirectory: &fileIsDir) {
                        if fileIsDir.boolValue {
                            try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                        } else {
                            try? fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try fm.copyItem(at: fileURL, to: targetURL)
                        }
                    }
                }
            }
            return
        }

        // Unzip file using /usr/bin/unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", sourceURL.path, "-d", destinationDir.path]

        let pipeErr = Pipe()
        process.standardError = pipeErr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipeErr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: data, encoding: .utf8) ?? "未知错误"
            throw ExtractorError.extractionFailed(errStr)
        }
    }
}
