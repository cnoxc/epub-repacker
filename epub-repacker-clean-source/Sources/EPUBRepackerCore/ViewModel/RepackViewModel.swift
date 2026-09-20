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
        for index in offsets.sorted(by: >) {
            if index < items.count {
                items.remove(at: index)
            }
        }
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

            let opt: OutputOption
            switch outputOption {
            case .sameDirectoryWithSuffix:
                opt = .sameDirectoryWithSuffix
            case .appleBooksICloud:
                opt = .appleBooksICloud
            case .customDirectory(let url):
                opt = .customDirectory(customOutputFolder ?? url)
            }

            do {
                let source = item.sourceURL
                let report = try await Task.detached(priority: .userInitiated) {
                    try EPUBRepairer.repairAndRepack(sourceURL: source, outputDir: nil, option: opt)
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
