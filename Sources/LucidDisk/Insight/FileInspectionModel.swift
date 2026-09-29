import Combine
import Foundation

/// Selection prepares safety information only. AI requires an explicit request.
@MainActor
final class FileInspectionModel: ObservableObject {
    @Published private(set) var assessment: DeletionAssessment?
    @Published private(set) var insight: FileInsight?
    @Published private(set) var isLoadingInsight = false
    private var selectedID: UUID?
    private var assessmentTask: Task<Void, Never>?
    private var insightTask: Task<Void, Never>?

    func select(_ node: FileNode) {
        cancelInsight()
        assessmentTask?.cancel()
        selectedID = node.id
        assessment = nil
        insight = nil
        assessmentTask = Task {
            let value = await Task.detached(priority: .userInitiated) {
                DeletionSafety.assess(node: node)
            }.value
            guard !Task.isCancelled, selectedID == node.id else { return }
            assessment = value
        }
    }

    func ask(about node: FileNode, service: LocalFileInsightService = .init()) {
        guard selectedID == node.id, let assessment, !isLoadingInsight else { return }
        isLoadingInsight = true
        let worker = Task.detached(priority: .userInitiated) {
            await service.insight(for: node, assessment: assessment)
        }
        insightTask = Task {
            let value = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, selectedID == node.id else { return }
            insight = value
            isLoadingInsight = false
        }
    }

    func cancelInsight() {
        insightTask?.cancel()
        insightTask = nil
        isLoadingInsight = false
    }

    func clear() {
        cancelInsight()
        assessmentTask?.cancel()
        selectedID = nil
        assessment = nil
        insight = nil
    }
}

