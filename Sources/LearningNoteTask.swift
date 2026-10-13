import Foundation

/// 即使底层请求忽略取消，也只允许当前任务回写结果。
@MainActor
final class LearningNoteTask {
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    @discardableResult
    func start(operation: @escaping () async throws -> LearningNote,
               completion: @escaping (Result<LearningNote, Error>) -> Void) -> Task<Void, Never> {
        cancel()
        let id = requestID
        let task = Task { [weak self] in
            let result: Result<LearningNote, Error>
            do { result = .success(try await operation()) }
            catch { result = .failure(error) }
            guard let self, self.requestID == id, !Task.isCancelled else { return }
            self.task = nil
            completion(result)
        }
        self.task = task
        return task
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
    }
}
