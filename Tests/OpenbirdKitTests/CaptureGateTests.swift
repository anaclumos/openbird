import Foundation
import Testing
@testable import OpenbirdKit

struct CaptureGateTests {
    @Test func dropsOverlappingWork() async throws {
        let gate = CaptureGate()
        let recorder = ConcurrencyRecorder()

        let first = Task {
            await gate.runIfIdle {
                await recorder.started()
                try? await Task.sleep(for: .milliseconds(100))
                await recorder.finished()
            }
        }

        try await Task.sleep(for: .milliseconds(20))

        let second = Task {
            await gate.runIfIdle {
                await recorder.started()
                await recorder.finished()
            }
        }

        await first.value
        await second.value

        let snapshot = await recorder.snapshot()
        #expect(snapshot.completed == 1)
        #expect(snapshot.maxConcurrent == 1)
    }

    @Test func acceptsNewWorkAfterCompletion() async {
        let gate = CaptureGate()
        let recorder = ConcurrencyRecorder()

        await gate.runIfIdle {
            await recorder.started()
            await recorder.finished()
        }

        await gate.runIfIdle {
            await recorder.started()
            await recorder.finished()
        }

        let snapshot = await recorder.snapshot()
        #expect(snapshot.completed == 2)
    }
}

private actor ConcurrencyRecorder {
    private var concurrentCount = 0
    private var maxConcurrentCount = 0
    private var completedCount = 0

    func started() {
        concurrentCount += 1
        maxConcurrentCount = max(maxConcurrentCount, concurrentCount)
    }

    func finished() {
        concurrentCount -= 1
        completedCount += 1
    }

    func snapshot() -> (completed: Int, maxConcurrent: Int) {
        (completedCount, maxConcurrentCount)
    }
}
