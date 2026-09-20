import Foundation
import Combine

public enum TaskStatus: Equatable, Sendable {
    case pending
    case processing(Double)
    case success(RepairReport)
    case failed(String)
}

@MainActor
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
