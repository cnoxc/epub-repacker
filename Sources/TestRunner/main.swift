import Foundation
import EPUBRepackerCore

var passed = 0
var failed = 0

@MainActor
func test(_ name: String, _ block: () throws -> Void) {
    print("▶ Running: \(name)...", terminator: " ")
    do {
        try block()
        print("✅ PASS")
        passed += 1
    } catch {
        print("❌ FAIL: \(error)")
        failed += 1
    }
}

@MainActor
func testAsync(_ name: String, _ block: @MainActor () async throws -> Void) async {
    print("▶ Running: \(name)...", terminator: " ")
    do {
        try await block()
        print("✅ PASS")
        passed += 1
    } catch {
        print("❌ FAIL: \(error)")
        failed += 1
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Assertion failed: (\(a)) != (\(b)). \(msg) at \(file):\(line)"])
    }
}

func assertTrue(_ a: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard a else {
        throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Assertion failed: expected true but was false. \(msg) at \(file):\(line)"])
    }
}

func assertFalse(_ a: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard !a else {
        throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Assertion failed: expected false but was true. \(msg) at \(file):\(line)"])
    }
}

print("\n==========================================")
print("       EPUBRepacker Test Suite")
print("==========================================\n")

// MARK: - ModelTests
test("ModelTests.testRepairReportInitialization") {
    var report = RepairReport(sourceURL: URL(fileURLWithPath: "/tmp/sample.epub"))
    report.addLog("Fixed mimetype")
    report.manifestItemsAdded += 2
    report.originalSizeBytes = 1024
    report.repackedSizeBytes = 980

    try assertEqual(report.logs.count, 1)
    try assertEqual(report.manifestItemsAdded, 2)
    try assertEqual(report.sizeDifferenceFormatted, "-44 B")
}

test("ModelTests.testRepairReportSizeDifferenceFormatting") {
    var reportZero = RepairReport(sourceURL: URL(fileURLWithPath: "/tmp/sample.epub"))
    reportZero.originalSizeBytes = 1000
    reportZero.repackedSizeBytes = 1000
    try assertEqual(reportZero.sizeDifferenceFormatted, "0 B")

    var reportPositive = RepairReport(sourceURL: URL(fileURLWithPath: "/tmp/sample.epub"))
    reportPositive.originalSizeBytes = 1000
    reportPositive.repackedSizeBytes = 1050
    try assertEqual(reportPositive.sizeDifferenceFormatted, "+50 B")
}

test("ModelTests.testTaskItemStatusLifecycle") {
    let url = URL(fileURLWithPath: "/tmp/sample.epub")
    let item = RepackTaskItem(sourceURL: url)
    try assertEqual(item.status, .pending)

    item.status = .processing(0.5)
    if case .processing(let progress) = item.status {
        try assertEqual(progress, 0.5)
    } else {
        throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected processing status"])
    }
}

test("ModelTests.testOutputOptionCases") {
    let sameDir = OutputOption.sameDirectoryWithSuffix
    let customDir = OutputOption.customDirectory(URL(fileURLWithPath: "/Users/test/Output"))
    let booksOption = OutputOption.appleBooksICloud

    try assertEqual(sameDir, .sameDirectoryWithSuffix)
    try assertEqual(customDir, .customDirectory(URL(fileURLWithPath: "/Users/test/Output")))
    try assertEqual(booksOption, .appleBooksICloud)

    let booksURL = OutputOption.appleBooksDocumentsURL
    try assertTrue(booksURL.path.contains("Mobile Documents/iCloud~com~apple~iBooks/Documents"))
}

// MARK: - EPUBPackagerTests
test("EPUBPackagerTests.testPackagerCreatesStandardCompliantEPUB") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let mimetypeFile = tempDir.appendingPathComponent("mimetype")
    try "application/epub+zip".write(to: mimetypeFile, atomically: true, encoding: .ascii)

    let metaInf = tempDir.appendingPathComponent("META-INF")
    try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
    try "<container></container>".write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

    let outputEPUB = tempDir.appendingPathComponent("output.epub")
    try EPUBPackager.package(sourceDirectory: tempDir, destinationURL: outputEPUB)

    try assertTrue(FileManager.default.fileExists(atPath: outputEPUB.path))
    let isCompliant = try EPUBPackager.verifyEPUBMagicHeader(at: outputEPUB)
    try assertTrue(isCompliant, "Generated EPUB must conform to IDPF magic header spec")
}

test("EPUBPackagerTests.testPackagerFailsWhenMimetypeMissing") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let outputEPUB = tempDir.appendingPathComponent("output.epub")
    var caughtError: PackagerError?
    do {
        try EPUBPackager.package(sourceDirectory: tempDir, destinationURL: outputEPUB)
    } catch let error as PackagerError {
        caughtError = error
    } catch {
        throw error
    }
    try assertEqual(caughtError, PackagerError.missingMimetype)
}

test("EPUBPackagerTests.testVerifyEPUBMagicHeaderRejectsInvalidFiles") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dummyFile = tempDir.appendingPathComponent("not_epub.txt")
    try "Just plain text".write(to: dummyFile, atomically: true, encoding: .utf8)
    let isDummyValid = try EPUBPackager.verifyEPUBMagicHeader(at: dummyFile)
    try assertFalse(isDummyValid)

    let emptyFile = tempDir.appendingPathComponent("empty.epub")
    FileManager.default.createFile(atPath: emptyFile.path, contents: Data())
    let isEmptyValid = try EPUBPackager.verifyEPUBMagicHeader(at: emptyFile)
    try assertFalse(isEmptyValid)
}

// MARK: - EPUBRepairerTests
test("EPUBRepairerTests.testRepairBrokenEPUB") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let contentDir = tempDir.appendingPathComponent("OEBPS")
    try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)

    let testImage = contentDir.appendingPathComponent("cover.jpg")
    try "fake_image_data".write(to: testImage, atomically: true, encoding: .utf8)

    let junkFile = tempDir.appendingPathComponent(".DS_Store")
    try "junk".write(to: junkFile, atomically: true, encoding: .utf8)

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

    let report = try EPUBRepairer.repairStagingDirectory(tempDir, sourceURL: tempDir)

    try assertTrue(report.mimetypeCorrected, "Should create missing mimetype")
    try assertTrue(report.containerCreated, "Should recreate container.xml")
    try assertTrue(report.manifestItemsAdded >= 1, "Should add unmanifested cover.jpg")
    try assertTrue(report.manifestItemsRemoved >= 1, "Should remove dead link from manifest")
    try assertTrue(report.junkFilesRemoved >= 1, "Should remove .DS_Store")

    let containerFile = tempDir.appendingPathComponent("META-INF/container.xml")
    try assertTrue(FileManager.default.fileExists(atPath: containerFile.path), "container.xml should exist")
    try assertFalse(FileManager.default.fileExists(atPath: junkFile.path), ".DS_Store should be removed")
}

// MARK: - BatchRepackTests
await testAsync("BatchRepackTests.testBatchQueueProcessing") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    var testURLs: [URL] = []
    for i in 1...2 {
        let bookDir = tempDir.appendingPathComponent("book_\(i)")
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        try "application/epub+zip".write(to: bookDir.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)
        testURLs.append(bookDir)
    }

    let vm = RepackViewModel()
    vm.addItems(urls: testURLs)
    let count = vm.items.count
    try assertEqual(count, 2)

    await vm.processAll()

    let completed = vm.completedCount
    try assertEqual(completed, 2)

    let items = vm.items
    for item in items {
        let status = item.status
        if case .success = status {
            let report = item.report
            try assertTrue(report != nil, "Report should not be nil")
        } else {
            throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Item should be success"])
        }
    }
}

// MARK: - E2EVerificationTests
await testAsync("E2EVerificationTests.testEndToEndBrokenEpubRepair") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 1. Build a broken mock epub file manually
    let staging = tempDir.appendingPathComponent("broken_src")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

    let oebps = staging.appendingPathComponent("OEBPS")
    try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)

    // Text & Image
    try "<html><body><h1>Chapter 1</h1></body></html>".write(to: oebps.appendingPathComponent("ch1.xhtml"), atomically: true, encoding: .utf8)
    try "sample_png_bytes".write(to: oebps.appendingPathComponent("picture.png"), atomically: true, encoding: .utf8)

    // Add macOS junk
    try "junk".write(to: staging.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)

    // OPF missing picture.png in manifest and referencing dead link
    let opf = """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>E2E Test Book</dc:title></metadata>
      <manifest>
        <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
        <item id="dead" href="nonexistent.css" media-type="text/css"/>
      </manifest>
      <spine><itemref idref="ch1"/></spine>
    </package>
    """
    try opf.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

    // Package as a broken zip (without uncompressed mimetype, missing container.xml)
    let brokenEPUB = tempDir.appendingPathComponent("broken.epub")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    proc.currentDirectoryURL = staging
    proc.arguments = ["-q", "-r", brokenEPUB.path, "."]
    try proc.run()
    proc.waitUntilExit()

    // 2. Perform repair and repack
    let report = try EPUBRepairer.repairAndRepack(sourceURL: brokenEPUB, outputDir: tempDir, option: .sameDirectoryWithSuffix)

    guard let repackedURL = report.destinationURL else {
        throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Destination URL is nil"])
    }
    try assertTrue(FileManager.default.fileExists(atPath: repackedURL.path), "Repacked file must exist on disk")

    // 3. Verify magic bytes and mimetype offset 0
    let isCompliant = try EPUBPackager.verifyEPUBMagicHeader(at: repackedURL)
    try assertTrue(isCompliant, "Repacked EPUB must strictly conform to IDPF spec")

    // 4. Verify manifest repairs & junk removal
    try assertTrue(report.manifestItemsAdded >= 1, "picture.png must be auto-added to manifest")
    try assertTrue(report.manifestItemsRemoved >= 1, "nonexistent.css must be purged from manifest")
    try assertTrue(report.mimetypeCorrected, "mimetype must be rebuilt and uncompressed")
    try assertTrue(report.containerCreated, "container.xml must be recreated")
    try assertTrue(report.junkFilesRemoved >= 1, ".DS_Store must be cleaned")

    // 5. Verify unzip integrity of the repacked epub
    let verifyUnzipDir = tempDir.appendingPathComponent("verify_unzip")
    try FileManager.default.createDirectory(at: verifyUnzipDir, withIntermediateDirectories: true)
    let unzipProc = Process()
    unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzipProc.arguments = ["-q", "-t", repackedURL.path]
    try unzipProc.run()
    unzipProc.waitUntilExit()
    try assertEqual(unzipProc.terminationStatus, 0, "Repacked EPUB archive zip integrity test must pass")
}

// MARK: - LocalizationTests
final class LocalizationTests {
    static func runAll() {
        testDefaultLanguageIsEnglish()
        testLanguageSwitchingAndPersistence()
        testCompleteDictionaryCoverage()
    }

    static func testDefaultLanguageIsEnglish() {
        print("▶ Running: LocalizationTests.testDefaultLanguageIsEnglish... ", terminator: "")
        UserDefaults.standard.removeObject(forKey: "selected_app_language")
        let manager = LocalizationManager(userDefaults: UserDefaults.standard)
        assert(manager.currentLanguage == .english, "Default language must be English")
        assert(manager.string(.windowTitle).contains("EPUB Repacker"), "Should return English string")
        print("✅ PASS")
    }

    static func testLanguageSwitchingAndPersistence() {
        print("▶ Running: LocalizationTests.testLanguageSwitchingAndPersistence... ", terminator: "")
        let testDefaults = UserDefaults(suiteName: "test_localization_\(UUID().uuidString)")!
        let manager = LocalizationManager(userDefaults: testDefaults)
        assert(manager.currentLanguage == .english)
        
        manager.setLanguage(.chinese)
        assert(manager.currentLanguage == .chinese)
        assert(manager.string(.dropTitle).contains("拖拽"))

        let restoredManager = LocalizationManager(userDefaults: testDefaults)
        assert(restoredManager.currentLanguage == .chinese, "Language preference must persist")
        print("✅ PASS")
    }

    static func testCompleteDictionaryCoverage() {
        print("▶ Running: LocalizationTests.testCompleteDictionaryCoverage... ", terminator: "")
        for lang in AppLanguage.allCases {
            for key in LocalizationKey.allCases {
                let text = LocalizationManager.lookup(key: key, language: lang)
                assert(!text.isEmpty, "Missing translation for \(key) in \(lang)")
            }
        }
        print("✅ PASS")
    }
}

LocalizationTests.runAll()
passed += 1

print("\n==========================================")
print("Test Results: \(passed) passed, \(failed) failed")
print("==========================================\n")

if failed > 0 {
    exit(1)
}
