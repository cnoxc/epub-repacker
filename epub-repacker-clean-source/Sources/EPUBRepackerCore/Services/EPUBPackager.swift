// Sources/EPUBRepackerCore/Services/EPUBPackager.swift
import Foundation

public enum PackagerError: LocalizedError, Equatable, Sendable {
    case missingMimetype
    case packagingFailed(String)
    case invalidArchive(String)

    public var errorDescription: String? {
        switch self {
        case .missingMimetype:
            return "mimetype 文件不存在，无法符合 EPUB 规范打包"
        case .packagingFailed(let msg):
            return "EPUB 打包失败: \(msg)"
        case .invalidArchive(let msg):
            return "校验失败: \(msg)"
        }
    }
}

public struct EPUBPackager: Sendable {
    public static func package(sourceDirectory: URL, destinationURL: URL) throws {
        let fm = FileManager.default
        let mimetypeURL = sourceDirectory.appendingPathComponent("mimetype")
        guard fm.fileExists(atPath: mimetypeURL.path) else {
            throw PackagerError.missingMimetype
        }

        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        // Step 1: Add mimetype uncompressed (method 0, no extra fields)
        let processMimetype = Process()
        processMimetype.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        processMimetype.currentDirectoryURL = sourceDirectory
        processMimetype.arguments = ["-q", "-X", "-0", destinationURL.path, "mimetype"]

        let pipeErr = Pipe()
        processMimetype.standardError = pipeErr
        try processMimetype.run()
        processMimetype.waitUntilExit()

        if processMimetype.terminationStatus != 0 {
            let data = pipeErr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: data, encoding: .utf8) ?? "未知错误"
            throw PackagerError.packagingFailed("写入 mimetype 失败: \(errStr)")
        }

        // Step 2: Add all other files deflated (-9, recursive) if any exist
        let destinationFilename = destinationURL.lastPathComponent
        let contents = (try? fm.contentsOfDirectory(atPath: sourceDirectory.path)) ?? []
        let hasOtherFiles = contents.contains { name in
            name != "mimetype" && name != destinationFilename && name != ".DS_Store" && !name.hasPrefix("__MACOSX")
        }

        if hasOtherFiles {
            let processRest = Process()
            processRest.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            processRest.currentDirectoryURL = sourceDirectory
            processRest.arguments = ["-q", "-X", "-9", "-r", destinationURL.path, ".", "-x", "mimetype", "-x", destinationFilename, "-x", "*.DS_Store", "-x", "__MACOSX*"]

            let pipeErr2 = Pipe()
            processRest.standardError = pipeErr2
            try processRest.run()
            processRest.waitUntilExit()

            // Info-ZIP exit code 12 is ZE_NONE (nothing to do)
            if processRest.terminationStatus != 0 && processRest.terminationStatus != 12 {
                let data = pipeErr2.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: data, encoding: .utf8) ?? "未知错误"
                throw PackagerError.packagingFailed("追加内容文件失败: \(errStr)")
            }
        }
    }

    public static func verifyEPUBMagicHeader(at fileURL: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        guard let headerData = try handle.read(upToCount: 58) else {
            return false
        }

        // Standard ZIP local file header begins with PK\x03\x04
        guard headerData.count >= 30,
              headerData[0] == 0x50, headerData[1] == 0x4B,
              headerData[2] == 0x03, headerData[3] == 0x04 else {
            return false
        }

        // Compression method at offset 8 (2 bytes): must be 0 (Stored)
        let compressionMethod = UInt16(headerData[8]) | (UInt16(headerData[9]) << 8)
        guard compressionMethod == 0 else { return false }

        // Filename length at offset 26 (2 bytes): must be 8 ("mimetype")
        let filenameLen = Int(headerData[26]) | (Int(headerData[27]) << 8)
        guard filenameLen == 8 else { return false }

        let extraLen = Int(headerData[28]) | (Int(headerData[29]) << 8)
        let nameStart = 30
        guard headerData.count >= nameStart + filenameLen else {
            return false
        }

        let nameData = headerData.subdata(in: nameStart..<(nameStart + filenameLen))
        guard String(data: nameData, encoding: .ascii) == "mimetype" else {
            return false
        }

        let contentStart = nameStart + filenameLen + extraLen
        if headerData.count >= contentStart + 20 {
            let bodyData = headerData.subdata(in: contentStart..<(contentStart + 20))
            return String(data: bodyData, encoding: .ascii) == "application/epub+zip"
        }

        return true
    }
}
