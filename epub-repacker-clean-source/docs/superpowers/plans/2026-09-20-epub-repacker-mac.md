# EPUB Repacker for macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, zero-dependency macOS desktop application to validate, repair, clean, and repackage EPUB files into standard-compliant EPUB containers with batch processing support.

**Architecture:** Pure Swift/SwiftUI application separated into a clean core library (`EPUBRepackerCore`) and presentation layer (`EPUBRepackerApp`). The core engine handles extraction, manifest & container XML repair, spec-compliant ZIP generation (mimetype stored uncompressed at offset 0), and async batch queue orchestration.

**Tech Stack:** Swift 6.4, SwiftUI, AppKit, Foundation XML & Process utilities, macOS arm64.

## Global Constraints
- Target platform: macOS 13.0+ (Apple Silicon arm64).
- Zero third-party package dependencies (uses only Apple standard frameworks and built-in system tools).
- Mimetype specification: Entry 0 in ZIP archive MUST be `mimetype` with Compression Method 0 (STORED) without extra field, body strictly `application/epub+zip`.
- Error isolation: Any corrupted file in a batch must report failure without halting other files in the queue.

---

### Task 1: Project Scaffolding & Core Models

**Files:**
- Create: `Package.swift`
- Create: `Sources/EPUBRepackerCore/Models/RepairReport.swift`
- Create: `Sources/EPUBRepackerCore/Models/RepackTaskItem.swift`
- Create: `Sources/EPUBRepackerCore/Models/OutputOption.swift`
- Test: `Tests/EPUBRepackerCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: Foundation
- Produces:
  - `struct RepairReport: Equatable, Sendable`: records log items, items added/removed, mimetype fixed flag, original and repacked sizes.
  - `enum TaskStatus: Equatable, Sendable`: `.pending`, `.processing(Double)`, `.success(RepairReport)`, `.failed(String)`
  - `final class RepackTaskItem: Identifiable, ObservableObject`: manages single-file repack lifecycle.
  - `enum OutputOption: Equatable, Sendable`: `.sameDirectoryWithSuffix`, `.customDirectory(URL)`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/EPUBRepackerCoreTests/ModelTests.swift
import XCTest
@testable import EPUBRepackerCore

final class ModelTests: XCTestCase {
    func testRepairReportInitialization() {
        var report = RepairReport(sourceURL: URL(fileURLWithPath: "/tmp/sample.epub"))
        report.addLog("Fixed mimetype")
        report.manifestItemsAdded += 2
        report.originalSizeBytes = 1024
        report.repackedSizeBytes = 980

        XCTAssertEqual(report.logs.count, 1)
        XCTAssertEqual(report.manifestItemsAdded, 2)
        XCTAssertEqual(report.sizeDifferenceFormatted, "-44 B")
    }

    func testTaskItemStatusLifecycle() {
        let url = URL(fileURLWithPath: "/tmp/sample.epub")
        let item = RepackTaskItem(sourceURL: url)
        XCTAssertEqual(item.status, .pending)

        item.status = .processing(0.5)
        if case .processing(let progress) = item.status {
            XCTAssertEqual(progress, 0.5)
        } else {
            XCTFail("Expected processing status")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelTests`
Expected: FAIL with "error: no such module 'EPUBRepackerCore'"

- [ ] **Step 3: Write minimal implementation**

Create `Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EPUBRepacker",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EPUBRepackerCore", targets: ["EPUBRepackerCore"]),
        .executable(name: "EPUBRepackerApp", targets: ["EPUBRepackerApp"])
    ],
    targets: [
        .target(
            name: "EPUBRepackerCore",
            dependencies: []
        ),
        .executableTarget(
            name: "EPUBRepackerApp",
            dependencies: ["EPUBRepackerCore"]
        ),
        .testTarget(
            name: "EPUBRepackerCoreTests",
            dependencies: ["EPUBRepackerCore"]
        )
    ]
)
```

Create `Sources/EPUBRepackerCore/Models/RepairReport.swift`:
```swift
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
        let formatted = formatter.string(fromByteCount: abs(diff))
        if diff < 0 {
            return "-\(formatted)"
        } else if diff > 0 {
            return "+\(formatted)"
        } else {
            return "0 B"
        }
    }
}
```

Create `Sources/EPUBRepackerCore/Models/RepackTaskItem.swift`:
```swift
import Foundation
import Combine

public enum TaskStatus: Equatable, Sendable {
    case pending
    case processing(Double)
    case success(RepairReport)
    case failed(String)
}

public final class RepackTaskItem: Identifiable, ObservableObject {
    public let id: UUID
    public let sourceURL: URL
    public let fileName: String

    @Published public var status: TaskStatus
    @Published public var report: RepairReport?

    public init(sourceURL: URL, id: UUID = UUID()) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = sourceURL.lastPathComponent
        self.status = .pending
        self.report = nil
    }
}
```

Create `Sources/EPUBRepackerCore/Models/OutputOption.swift`:
```swift
import Foundation

public enum OutputOption: Equatable, Sendable {
    case sameDirectoryWithSuffix
    case customDirectory(URL)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/EPUBRepackerCore/Models Tests/EPUBRepackerCoreTests/ModelTests.swift
git commit -m "feat: add project package and core data models"
```

---

### Task 2: Spec-Compliant EPUBPackager (TDD)

**Files:**
- Create: `Sources/EPUBRepackerCore/Services/EPUBPackager.swift`
- Test: `Tests/EPUBRepackerCoreTests/EPUBPackagerTests.swift`

**Interfaces:**
- Consumes: Foundation
- Produces:
  - `struct EPUBPackager`:
    - `static func package(sourceDirectory: URL, destinationURL: URL) throws`
    - `static func verifyEPUBMagicHeader(at fileURL: URL) throws -> Bool`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/EPUBRepackerCoreTests/EPUBPackagerTests.swift
import XCTest
@testable import EPUBRepackerCore

final class EPUBPackagerTests: XCTestCase {
    func testPackagerCreatesStandardCompliantEPUB() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup test structure
        let mimetypeFile = tempDir.appendingPathComponent("mimetype")
        try "application/epub+zip".write(to: mimetypeFile, atomically: true, encoding: .ascii)

        let metaInf = tempDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try "<container></container>".write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        let outputEPUB = tempDir.appendingPathComponent("output.epub")
        try EPUBPackager.package(sourceDirectory: tempDir, destinationURL: outputEPUB)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputEPUB.path))

        // Verify magic bytes: first entry must be uncompressed mimetype
        let isCompliant = try EPUBPackager.verifyEPUBMagicHeader(at: outputEPUB)
        XCTAssertTrue(isCompliant, "The generated EPUB must conform to IDPF uncompressed mimetype header specification")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EPUBPackagerTests`
Expected: FAIL with "cannot find 'EPUBPackager' in scope"

- [ ] **Step 3: Write minimal implementation**

Create `Sources/EPUBRepackerCore/Services/EPUBPackager.swift`:
```swift
import Foundation

public enum PackagerError: LocalizedError {
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

public struct EPUBPackager {
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

        // Step 2: Add all other files deflated (-9, recursive)
        let processRest = Process()
        processRest.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        processRest.currentDirectoryURL = sourceDirectory
        processRest.arguments = ["-q", "-X", "-9", "-r", destinationURL.path, ".", "-x", "mimetype", "-x", "*.DS_Store", "-x", "__MACOSX*"]

        let pipeErr2 = Pipe()
        processRest.standardError = pipeErr2
        try processRest.run()
        processRest.waitUntilExit()

        if processRest.terminationStatus != 0 {
            let data = pipeErr2.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: data, encoding: .utf8) ?? "未知错误"
            throw PackagerError.packagingFailed("追加内容文件失败: \(errStr)")
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EPUBPackagerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/EPUBRepackerCore/Services/EPUBPackager.swift Tests/EPUBRepackerCoreTests/EPUBPackagerTests.swift
git commit -m "feat: implement spec-compliant EPUBPackager with uncompressed mimetype validation"
```

---

### Task 3: EPUBExtractor & EPUBRepairer (TDD)

**Files:**
- Create: `Sources/EPUBRepackerCore/Services/EPUBExtractor.swift`
- Create: `Sources/EPUBRepackerCore/Services/EPUBRepairer.swift`
- Test: `Tests/EPUBRepackerCoreTests/EPUBRepairerTests.swift`

**Interfaces:**
- Consumes: `RepairReport`, `EPUBPackager`
- Produces:
  - `struct EPUBExtractor`:
    - `static func extract(from sourceURL: URL, to destinationDir: URL) throws`
  - `struct EPUBRepairer`:
    - `static func repairAndRepack(sourceURL: URL, outputDir: URL?, option: OutputOption) throws -> RepairReport`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/EPUBRepackerCoreTests/EPUBRepairerTests.swift
import XCTest
@testable import EPUBRepackerCore

final class EPUBRepairerTests: XCTestCase {
    func testRepairBrokenEPUB() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a broken folder missing mimetype, missing container.xml, with OPF missing an image in manifest
        let contentDir = tempDir.appendingPathComponent("OEBPS")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)

        let testImage = contentDir.appendingPathComponent("cover.jpg")
        try "fake_image_data".write(to: testImage, atomically: true, encoding: .utf8)

        let opfContent = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test Book</dc:title>
          </metadata>
          <manifest>
            <item id="missing" href="dead_link.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="missing"/>
          </spine>
        </package>
        """
        try opfContent.write(to: contentDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        // Run repair directly on folder
        let report = try EPUBRepairer.repairStagingDirectory(tempDir, sourceURL: tempDir)

        XCTAssertTrue(report.mimetypeCorrected, "Should create missing mimetype")
        XCTAssertTrue(report.containerCreated, "Should recreate container.xml")
        XCTAssertGreaterThanOrEqual(report.manifestItemsAdded, 1, "Should add unmanifested cover.jpg")
        XCTAssertGreaterThanOrEqual(report.manifestItemsRemoved, 1, "Should remove dead link from manifest")

        // Verify container.xml exists
        let containerFile = tempDir.appendingPathComponent("META-INF/container.xml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: containerFile.path))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EPUBRepairerTests`
Expected: FAIL with "cannot find 'EPUBRepairer' in scope"

- [ ] **Step 3: Write minimal implementation**

Create `Sources/EPUBRepackerCore/Services/EPUBExtractor.swift`:
```swift
import Foundation

public enum ExtractorError: LocalizedError {
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg):
            return "解压失败: \(msg)"
        }
    }
}

public struct EPUBExtractor {
    public static func extract(from sourceURL: URL, to destinationDir: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue {
            // Source is already a directory
            let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: nil)!
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
            return
        }

        // Unzip file
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
```

Create `Sources/EPUBRepackerCore/Services/EPUBRepairer.swift`:
```swift
import Foundation

public struct EPUBRepairer {
    public static func mimeTypeFor(extension ext: String) -> String {
        switch ext.lowercased() {
        case "xhtml", "html", "htm": return "application/xhtml+xml"
        case "css": return "text/css"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ncx": return "application/x-dtbncx+xml"
        case "otf": return "font/otf"
        case "ttf": return "font/ttf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "smil": return "application/smil+xml"
        case "js": return "application/javascript"
        default: return "application/octet-stream"
        }
    }

    public static func repairStagingDirectory(_ stagingDir: URL, sourceURL: URL) throws -> RepairReport {
        let fm = FileManager.default
        var report = RepairReport(sourceURL: sourceURL)

        // 1. Sanitize junk files (.DS_Store, __MACOSX, Thumbs.db)
        if let enumerator = fm.enumerator(at: stagingDir, includingPropertiesForKeys: nil) {
            var filesToDelete: [URL] = []
            for case let itemURL as URL in enumerator {
                let name = itemURL.lastPathComponent
                if name == ".DS_Store" || name == "Thumbs.db" || name.hasPrefix("._") || name == "__MACOSX" {
                    filesToDelete.append(itemURL)
                }
            }
            for url in filesToDelete {
                try? fm.removeItem(at: url)
                report.junkFilesRemoved += 1
            }
        }

        // 2. Mimetype normalization
        let mimetypeFile = stagingDir.appendingPathComponent("mimetype")
        let standardMimetype = "application/epub+zip"
        if !fm.fileExists(atPath: mimetypeFile.path) {
            try standardMimetype.write(to: mimetypeFile, atomically: true, encoding: .ascii)
            report.mimetypeCorrected = true
            report.addLog("补齐了缺失的根目录 mimetype 文件")
        } else {
            let current = (try? String(contentsOf: mimetypeFile, encoding: .ascii)) ?? ""
            if current.trimmingCharacters(in: .whitespacesAndNewlines) != standardMimetype {
                try standardMimetype.write(to: mimetypeFile, atomically: true, encoding: .ascii)
                report.mimetypeCorrected = true
                report.addLog("校准了 mimetype 内容为标准的 application/epub+zip")
            }
        }

        // 3. Container & OPF detection
        var opfRelativePath: String? = nil
        let containerFile = stagingDir.appendingPathComponent("META-INF/container.xml")

        // Find OPF file recursively
        if let enumerator = fm.enumerator(at: stagingDir, includingPropertiesForKeys: nil) {
            for case let itemURL as URL in enumerator {
                if itemURL.pathExtension.lowercased() == "opf" {
                    var rel = itemURL.path.replacingOccurrences(of: stagingDir.path, with: "")
                    if rel.hasPrefix("/") { rel.removeFirst() }
                    opfRelativePath = rel
                    break
                }
            }
        }

        if !fm.fileExists(atPath: containerFile.path) {
            if let opfPath = opfRelativePath {
                let metaInfDir = stagingDir.appendingPathComponent("META-INF")
                try fm.createDirectory(at: metaInfDir, withIntermediateDirectories: true)
                let containerXML = """
                <?xml version="1.0" encoding="UTF-8"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles>
                    <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
                  </rootfiles>
                </container>
                """
                try containerXML.write(to: containerFile, atomically: true, encoding: .utf8)
                report.containerCreated = true
                report.addLog("自动创建了缺失的 META-INF/container.xml 并关联到 \(opfPath)")
            }
        }

        // 4. Manifest & Spine Synchronization
        if let opfRel = opfRelativePath {
            let opfURL = stagingDir.appendingPathComponent(opfRel)
            let opfDir = opfURL.deletingLastPathComponent()

            if var opfString = try? String(contentsOf: opfURL, encoding: .utf8) {
                // Collect existing manifest hrefs
                var existingHrefs: Set<String> = []
                let manifestRegex = try NSRegularExpression(pattern: "<item\\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>", options: .caseInsensitive)
                let matches = manifestRegex.matches(in: opfString, range: NSRange(opfString.startIndex..., in: opfString))
                for m in matches {
                    if let range = Range(m.range(at: 1), in: opfString) {
                        existingHrefs.insert(String(opfString[range]))
                    }
                }

                // Remove dead links from manifest
                for href in existingHrefs {
                    let fileTarget = opfDir.appendingPathComponent(href)
                    if !fm.fileExists(atPath: fileTarget.path) {
                        // Dead link
                        let deadItemRegex = try NSRegularExpression(pattern: "<item\\s+[^>]*href=[\"']\(NSRegularExpression.escapedPattern(for: href))[\"'][^>]*/>\\s*", options: .caseInsensitive)
                        opfString = deadItemRegex.stringByReplacingMatches(in: opfString, range: NSRange(opfString.startIndex..., in: opfString), withTemplate: "")
                        report.manifestItemsRemoved += 1
                        report.addLog("从 manifest 清单中清除了失效文件引用: \(href)")
                    }
                }

                // Scan disk for unmanifested files
                if let enumerator = fm.enumerator(at: opfDir, includingPropertiesForKeys: nil) {
                    var newManifestItems: [String] = []
                    var index = 1
                    for case let fileURL as URL in enumerator {
                        var isDirectory: ObjCBool = false
                        if fm.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                            if fileURL.pathExtension.lowercased() == "opf" { continue }
                            var rel = fileURL.path.replacingOccurrences(of: opfDir.path, with: "")
                            if rel.hasPrefix("/") { rel.removeFirst() }

                            if !existingHrefs.contains(rel) && !rel.contains(".DS_Store") {
                                let mime = mimeTypeFor(extension: fileURL.pathExtension)
                                let cleanId = "auto_item_\(fileURL.pathExtension)_\(index)"
                                index += 1
                                let itemTag = "    <item id=\"\(cleanId)\" href=\"\(rel)\" media-type=\"\(mime)\"/>"
                                newManifestItems.append(itemTag)
                                report.manifestItemsAdded += 1
                                report.addLog("自动为未登记的资源补充了清单条目: \(rel) [\(mime)]")
                            }
                        }
                    }

                    if !newManifestItems.isEmpty {
                        if let manifestCloseRange = opfString.range(of: "</manifest>") {
                            let insertion = "\n" + newManifestItems.joined(separator: "\n") + "\n"
                            opfString.insert(contentsOf: insertion, at: manifestCloseRange.lowerBound)
                        }
                    }
                }

                try? opfString.write(to: opfURL, atomically: true, encoding: .utf8)
            }
        }

        return report
    }

    public static func repairAndRepack(sourceURL: URL, outputDir: URL?, option: OutputOption) throws -> RepairReport {
        let fm = FileManager.default
        let stagingUUID = UUID().uuidString
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("EPUBRepacker_\(stagingUUID)")
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stagingDir) }

        // 1. Extract
        try EPUBExtractor.extract(from: sourceURL, to: stagingDir)

        // 2. Repair
        var report = try repairStagingDirectory(stagingDir, sourceURL: sourceURL)

        // Original size
        let attr = try? fm.attributesOfItem(atPath: sourceURL.path)
        report.originalSizeBytes = (attr?[.size] as? NSNumber)?.int64Value ?? 0

        // 3. Determine destination
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let targetFolder: URL
        switch option {
        case .sameDirectoryWithSuffix:
            targetFolder = outputDir ?? sourceURL.deletingLastPathComponent()
        case .customDirectory(let custom):
            targetFolder = custom
        }

        let destinationURL = targetFolder.appendingPathComponent("\(baseName)_repacked.epub")
        try EPUBPackager.package(sourceDirectory: stagingDir, destinationURL: destinationURL)

        let outAttr = try? fm.attributesOfItem(atPath: destinationURL.path)
        report.repackedSizeBytes = (outAttr?[.size] as? NSNumber)?.int64Value ?? 0
        report.destinationURL = destinationURL

        return report
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EPUBRepairerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/EPUBRepackerCore/Services/ Tests/EPUBRepackerCoreTests/EPUBRepairerTests.swift
git commit -m "feat: implement EPUBExtractor and EPUBRepairer with manifest auto-sync"
```

---

### Task 4: Batch Processing Queue & RepackViewModel (TDD)

**Files:**
- Create: `Sources/EPUBRepackerCore/ViewModel/RepackViewModel.swift`
- Test: `Tests/EPUBRepackerCoreTests/BatchRepackTests.swift`

**Interfaces:**
- Consumes: `RepackTaskItem`, `EPUBRepairer`, `OutputOption`
- Produces:
  - `final class RepackViewModel: ObservableObject`:
    - `addItems(urls: [URL])`
    - `processAll()` async
    - `clearList()`
    - `cancelAll()`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/EPUBRepackerCoreTests/BatchRepackTests.swift
import XCTest
@testable import EPUBRepackerCore

@MainActor
final class BatchRepackTests: XCTestCase {
    func testBatchQueueProcessing() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create 2 test folder sources
        var testURLs: [URL] = []
        for i in 1...2 {
            let bookDir = tempDir.appendingPathComponent("book_\(i)")
            try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
            try "application/epub+zip".write(to: bookDir.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)
            testURLs.append(bookDir)
        }

        let vm = RepackViewModel()
        vm.addItems(urls: testURLs)
        XCTAssertEqual(vm.items.count, 2)

        await vm.processAll()

        XCTAssertEqual(vm.completedCount, 2)
        for item in vm.items {
            if case .success = item.status {
                XCTAssertNotNil(item.report)
            } else {
                XCTFail("Item should be success")
            }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BatchRepackTests`
Expected: FAIL with "cannot find 'RepackViewModel' in scope"

- [ ] **Step 3: Write minimal implementation**

Create `Sources/EPUBRepackerCore/ViewModel/RepackViewModel.swift`:
```swift
import Foundation
import Combine

@MainActor
public final class RepackViewModel: ObservableObject {
    @Published public var items: [RepackTaskItem] = []
    @Published public var isProcessing: Bool = false
    @Published public var completedCount: Int = 0
    @Published public var totalCount: Int = 0
    @Published public var outputOption: OutputOption = .sameDirectoryWithSuffix
    @Published public var customOutputFolder: URL? = nil

    private var cancelRequested: Bool = false

    public init() {}

    public func addItems(urls: [URL]) {
        for url in urls {
            // Avoid exact duplicates
            if !items.contains(where: { $0.sourceURL == url }) {
                items.append(RepackTaskItem(sourceURL: url))
            }
        }
        totalCount = items.count
    }

    public func clearList() {
        guard !isProcessing else { return }
        items.removeAll()
        completedCount = 0
        totalCount = 0
    }

    public func removeItems(at offsets: IndexSet) {
        guard !isProcessing else { return }
        items.remove(atOffsets: offsets)
        totalCount = items.count
    }

    public func cancelAll() {
        cancelRequested = true
        isProcessing = false
    }

    public func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        cancelRequested = false
        completedCount = 0
        totalCount = items.count

        for item in items {
            if cancelRequested { break }
            if case .success = item.status {
                completedCount += 1
                continue
            }

            item.status = .processing(0.1)

            let opt = customOutputFolder != nil ? OutputOption.customDirectory(customOutputFolder!) : outputOption

            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try EPUBRepairer.repairAndRepack(sourceURL: item.sourceURL, outputDir: nil, option: opt)
                }.value

                item.report = report
                item.status = .success(report)
            } catch {
                item.status = .failed(error.localizedDescription)
            }

            completedCount += 1
        }

        isProcessing = false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BatchRepackTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/EPUBRepackerCore/ViewModel/ Tests/EPUBRepackerCoreTests/BatchRepackTests.swift
git commit -m "feat: implement RepackViewModel and async batch queue processing"
```

---

### Task 5: Native macOS SwiftUI User Interface & App Packaging

**Files:**
- Create: `Sources/EPUBRepackerApp/App.swift`
- Create: `Sources/EPUBRepackerApp/Views/ContentView.swift`
- Create: `Sources/EPUBRepackerApp/Views/DropZoneView.swift`
- Create: `Sources/EPUBRepackerApp/Views/TaskListView.swift`
- Create: `Sources/EPUBRepackerApp/Views/ReportDetailSheet.swift`
- Create: `scripts/build_app.sh`

**Interfaces:**
- Consumes: `RepackViewModel`, `RepackTaskItem`, `RepairReport`
- Produces: Executable `EPUBRepackerApp` and standalone `dist/EPUBRepacker.app` bundle

- [ ] **Step 1: Write SwiftUI views and app entry**

Create `Sources/EPUBRepackerApp/Views/ReportDetailSheet.swift`:
```swift
import SwiftUI
import EPUBRepackerCore

struct ReportDetailSheet: View {
    let report: RepairReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("修复与封装报告")
                        .font(.headline)
                    Text(report.sourceURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
            }

            Divider()

            GroupBox(label: Label("统计概览", systemImage: "chart.bar.fill")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Mimetype 校准:")
                        Spacer()
                        Text(report.mimetypeCorrected ? "已校准 (Method 0 Stored)" : "原有符合标准")
                            .foregroundColor(report.mimetypeCorrected ? .orange : .secondary)
                    }
                    HStack {
                        Text("Container 容器:")
                        Spacer()
                        Text(report.containerCreated ? "重新生成 container.xml" : "正常")
                            .foregroundColor(report.containerCreated ? .orange : .secondary)
                    }
                    HStack {
                        Text("Manifest 清单补齐:")
                        Spacer()
                        Text("+\(report.manifestItemsAdded) 项")
                    }
                    HStack {
                        Text("Manifest 清除死链:")
                        Spacer()
                        Text("-\(report.manifestItemsRemoved) 项")
                    }
                    HStack {
                        Text("移除系统冗余垃圾:")
                        Spacer()
                        Text("\(report.junkFilesRemoved) 项 (.DS_Store 等)")
                    }
                    HStack {
                        Text("体积变化:")
                        Spacer()
                        Text(report.sizeDifferenceFormatted)
                            .bold()
                    }
                }
                .padding(8)
            }

            Text("详细执行日志:")
                .font(.subheadline)
                .bold()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if report.logs.isEmpty {
                        Text("无特殊异常，直接完成了标准重封装。")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(report.logs, id: \.self) { log in
                            Text("• \(log)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)

            if let dest = report.destinationURL {
                HStack {
                    Text("输出文件: \(dest.lastPathComponent)")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 450)
    }
}
```

Create `Sources/EPUBRepackerApp/Views/DropZoneView.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers
import EPUBRepackerCore

struct DropZoneView: View {
    @ObservedObject var viewModel: RepackViewModel
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 44))
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            Text("拖入一个或多个 EPUB 文件到此处")
                .font(.headline)

            Text("支持 .epub 电子书或已解压的书籍文件夹，自动批量加入队列")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("选择文件...") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseDirectories = true
                panel.canChooseFiles = true
                panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data, .folder]
                if panel.runModal() == .OK {
                    viewModel.addItems(urls: panel.urls)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            viewModel.addItems(urls: [url])
                        }
                    }
                }
            }
            return true
        }
    }
}
```

Create `Sources/EPUBRepackerApp/Views/TaskListView.swift`:
```swift
import SwiftUI
import EPUBRepackerCore

struct TaskListView: View {
    @ObservedObject var viewModel: RepackViewModel
    @State private var selectedReport: RepairReport? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("处理队列 (\(viewModel.items.count))")
                    .font(.headline)
                Spacer()
                if viewModel.isProcessing {
                    ProgressView(value: Double(viewModel.completedCount), total: Double(max(1, viewModel.totalCount)))
                        .frame(width: 150)
                    Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                        .font(.caption)
                }
            }

            List {
                ForEach(viewModel.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.zipper")
                            .font(.title2)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                                .font(.body)
                                .lineLimit(1)
                            if let report = item.report {
                                Text("重封装完成 (\(report.sizeDifferenceFormatted))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        switch item.status {
                        case .pending:
                            Text("等待中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        case .processing:
                            ProgressView()
                                .scaleEffect(0.6)
                        case .success(let report):
                            Button("查看报告") {
                                selectedReport = report
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundColor(.accentColor)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)

                            if let dest = report.destinationURL {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.borderless)
                                .help("在 Finder 中显示")
                            }
                        case .failed(let reason):
                            Text("失败: \(reason)")
                                .font(.caption)
                                .foregroundColor(.red)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: viewModel.removeItems)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .sheet(item: Binding(
                get: { selectedReport.map { IdentifiableReport(report: $0) } },
                set: { selectedReport = $0?.report }
            )) { wrapper in
                ReportDetailSheet(report: wrapper.report)
            }
        }
    }
}

struct IdentifiableReport: Identifiable {
    let id = UUID()
    let report: RepairReport
}
```

Create `Sources/EPUBRepackerApp/Views/ContentView.swift`:
```swift
import SwiftUI
import EPUBRepackerCore

struct ContentView: View {
    @StateObject private var viewModel = RepackViewModel()

    var body: some View {
        VStack(spacing: 16) {
            DropZoneView(viewModel: viewModel)

            if !viewModel.items.isEmpty {
                TaskListView(viewModel: viewModel)

                HStack {
                    Button("清空列表") {
                        viewModel.clearList()
                    }
                    .disabled(viewModel.isProcessing)

                    Spacer()

                    if viewModel.isProcessing {
                        Button("取消") {
                            viewModel.cancelAll()
                        }
                    } else {
                        Button("全部开始重新封装") {
                            Task {
                                await viewModel.processAll()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: 520)
    }
}
```

Create `Sources/EPUBRepackerApp/App.swift`:
```swift
import SwiftUI

@main
struct EPUBRepackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
```

Create `scripts/build_app.sh`:
```bash
#!/bin/bash
set -e
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Building EPUBRepacker executable in release mode..."
swift build -c release

APP_NAME="EPUBRepacker.app"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> Copying binary..."
cp "$ROOT_DIR/.build/release/EPUBRepackerApp" "$MACOS_DIR/EPUBRepacker"

echo "==> Generating Info.plist..."
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>EPUBRepacker</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.EPUBRepacker</string>
    <key>CFBundleName</key>
    <string>EPUB Repacker</string>
    <key>CFBundleDisplayName</key>
    <string>EPUB Repacker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Successfully created: $APP_BUNDLE"
```

- [ ] **Step 2: Build project and verify compilation**

Run: `swift build`
Expected: Build complete!

- [ ] **Step 3: Run build_app.sh to generate .app bundle**

Run: `chmod +x scripts/build_app.sh && ./scripts/build_app.sh`
Expected: Successfully created `dist/EPUBRepacker.app`

- [ ] **Step 4: Commit**

```bash
git add Sources/EPUBRepackerApp/ scripts/build_app.sh
git commit -m "feat: implement native macOS SwiftUI application and .app bundle packager"
```

---

### Task 6: End-to-End Verification with Synthetic Corrupt EPUBs

**Files:**
- Create: `Tests/EPUBRepackerCoreTests/E2EVerificationTests.swift`

- [ ] **Step 1: Write E2E test verifying broken EPUB repair and container compliance**

```swift
// Tests/EPUBRepackerCoreTests/E2EVerificationTests.swift
import XCTest
@testable import EPUBRepackerCore

final class E2EVerificationTests: XCTestCase {
    func testEndToEndBrokenEpubRepair() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Build a broken mock epub file manually
        let staging = tempDir.appendingPathComponent("broken_src")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let oebps = staging.appendingPathComponent("OEBPS")
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)

        // Text & Image
        try "<html><body><h1>Chapter 1</h1></body></html>".write(to: oebps.appendingPathComponent("ch1.xhtml"), atomically: true, encoding: .utf8)
        try "sample_png".write(to: oebps.appendingPathComponent("picture.png"), atomically: true, encoding: .utf8)

        // OPF missing picture.png in manifest
        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>E2E Test</dc:title></metadata>
          <manifest>
            <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="dead" href="nonexistent.css" media-type="text/css"/>
          </manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """
        try opf.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        // Package as a broken zip (without uncompressed mimetype)
        let brokenEPUB = tempDir.appendingPathComponent("broken.epub")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = staging
        proc.arguments = ["-q", "-r", brokenEPUB.path, "."]
        try proc.run()
        proc.waitUntilExit()

        // 2. Perform repair and repack
        let report = try EPUBRepairer.repairAndRepack(sourceURL: brokenEPUB, outputDir: tempDir, option: .sameDirectoryWithSuffix)

        XCTAssertNotNil(report.destinationURL)
        let repackedURL = report.destinationURL!
        XCTAssertTrue(FileManager.default.fileExists(atPath: repackedURL.path))

        // 3. Verify magic bytes and mimetype offset 0
        let isCompliant = try EPUBPackager.verifyEPUBMagicHeader(at: repackedURL)
        XCTAssertTrue(isCompliant, "Repacked EPUB must strictly conform to IDPF spec")

        // 4. Verify manifest repairs
        XCTAssertEqual(report.manifestItemsAdded, 1, "picture.png must be auto-added to manifest")
        XCTAssertEqual(report.manifestItemsRemoved, 1, "nonexistent.css must be purged from manifest")
        XCTAssertTrue(report.mimetypeCorrected, "mimetype must be rebuilt and uncompressed")
    }
}
```

- [ ] **Step 2: Run all unit and integration tests**

Run: `swift test`
Expected: All tests pass (100% green).

- [ ] **Step 3: Commit and tag release**

```bash
git add Tests/EPUBRepackerCoreTests/E2EVerificationTests.swift
git commit -m "test: add comprehensive end-to-end verification for broken EPUB repair"
```
