import Foundation

public struct EPUBRepairer: Sendable {
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

        let canonicalStagingDir = stagingDir.resolvingSymlinksInPath()

        // 1. Sanitize junk files (.DS_Store, __MACOSX, Thumbs.db, ._* files)
        if let enumerator = fm.enumerator(at: canonicalStagingDir, includingPropertiesForKeys: nil) {
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
        let mimetypeFile = canonicalStagingDir.appendingPathComponent("mimetype")
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
        let containerFile = canonicalStagingDir.appendingPathComponent("META-INF/container.xml")

        // Find OPF file recursively
        if let enumerator = fm.enumerator(at: canonicalStagingDir, includingPropertiesForKeys: nil) {
            for case let itemURL as URL in enumerator {
                if itemURL.pathExtension.lowercased() == "opf" {
                    let canonicalItem = itemURL.resolvingSymlinksInPath()
                    var rel = canonicalItem.path.replacingOccurrences(of: canonicalStagingDir.path, with: "")
                    if rel.hasPrefix("/") { rel.removeFirst() }
                    opfRelativePath = rel
                    break
                }
            }
        }

        if !fm.fileExists(atPath: containerFile.path) {
            if let opfPath = opfRelativePath {
                let metaInfDir = canonicalStagingDir.appendingPathComponent("META-INF")
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
            let opfURL = canonicalStagingDir.appendingPathComponent(opfRel).resolvingSymlinksInPath()
            let opfDir = opfURL.deletingLastPathComponent().resolvingSymlinksInPath()

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
                    let fileTarget = opfDir.appendingPathComponent(href).resolvingSymlinksInPath()
                    if !fm.fileExists(atPath: fileTarget.path) {
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
                        let canonicalFile = fileURL.resolvingSymlinksInPath()
                        var isDirectory: ObjCBool = false
                        if fm.fileExists(atPath: canonicalFile.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                            if canonicalFile.pathExtension.lowercased() == "opf" { continue }
                            var rel = canonicalFile.path.replacingOccurrences(of: opfDir.path, with: "")
                            if rel.hasPrefix("/") { rel.removeFirst() }

                            if !existingHrefs.contains(rel) && !rel.contains(".DS_Store") {
                                let mime = mimeTypeFor(extension: canonicalFile.pathExtension)
                                let cleanId = "auto_item_\(canonicalFile.pathExtension)_\(index)"
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
        case .appleBooksICloud:
            targetFolder = OutputOption.appleBooksDocumentsURL
            try? fm.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        case .customDirectory(let custom):
            targetFolder = custom
            try? fm.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        }

        let destinationURL = targetFolder.appendingPathComponent("\(baseName)_repacked.epub")
        try EPUBPackager.package(sourceDirectory: stagingDir, destinationURL: destinationURL)

        let outAttr = try? fm.attributesOfItem(atPath: destinationURL.path)
        report.repackedSizeBytes = (outAttr?[.size] as? NSNumber)?.int64Value ?? 0
        report.destinationURL = destinationURL

        return report
    }
}
