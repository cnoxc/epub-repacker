import Foundation

public enum OutputOption: Equatable, Sendable {
    case sameDirectoryWithSuffix
    case appleBooksICloud
    case customDirectory(URL)

    public static var appleBooksDocumentsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Mobile Documents")
            .appendingPathComponent("iCloud~com~apple~iBooks")
            .appendingPathComponent("Documents")
    }

    public static func openAppleBooksDocumentsInFinder() -> Bool {
        let url = appleBooksDocumentsURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = [url.path]
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}
