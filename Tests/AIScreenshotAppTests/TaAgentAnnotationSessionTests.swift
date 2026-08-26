import Testing
import TaAgentContracts
@testable import AIScreenshotApp

@Suite("Ta Agent annotation session")
struct TaAgentAnnotationSessionTests {
    @Test("eraser, undo, and redo restore vector snapshots")
    func eraserUndoRedo() throws {
        let source = try fixtureImage(width: 60, height: 40)
        let baseDigest = pixelDigest(source)
        var session = TaAgentAnnotationSession(sourceImage: source)

        let marked = try session.apply(AnnotationRecipe(version: 1, operations: [
            .rectangle(.init(id: "focus", rect: .init(x: 5, y: 5, width: 30, height: 20)))
        ]))
        #expect(pixelDigest(marked.image) != baseDigest)
        #expect(marked.canUndo)
        #expect(!marked.canRedo)

        let erased = try session.apply(AnnotationRecipe(version: 1, operations: [
            .eraser(.init(targetIDs: ["focus"]))
        ]))
        #expect(pixelDigest(erased.image) == baseDigest)

        let undone = try session.undo()
        #expect(pixelDigest(undone.image) == pixelDigest(marked.image))
        #expect(undone.canRedo)

        let redone = try session.redo()
        #expect(pixelDigest(redone.image) == baseDigest)
    }

    @Test("a failed recipe is atomic and does not change history")
    func invalidRecipeIsAtomic() throws {
        var session = TaAgentAnnotationSession(sourceImage: try fixtureImage(width: 60, height: 40))
        let marked = try session.apply(AnnotationRecipe(version: 1, operations: [
            .rectangle(.init(id: "focus", rect: .init(x: 5, y: 5, width: 30, height: 20)))
        ]))

        #expect(throws: AnnotationRecipeValidationError.self) {
            _ = try session.apply(AnnotationRecipe(version: 1, operations: [
                .ellipse(.init(id: "new", rect: .init(x: 10, y: 10, width: 20, height: 10))),
                .eraser(.init(targetIDs: ["missing"]))
            ]))
        }

        let current = try session.renderCurrent()
        #expect(pixelDigest(current.image) == pixelDigest(marked.image))
        #expect(current.elementCount == 1)
        #expect(!current.canRedo)
    }

    @Test("new edits invalidate redo and history keeps at most 100 snapshots")
    func historyLimitAndRedoInvalidation() throws {
        var session = TaAgentAnnotationSession(sourceImage: try fixtureImage(width: 30, height: 30))
        for index in 0..<105 {
            _ = try session.apply(AnnotationRecipe(version: 1, operations: [
                .rectangle(.init(
                    id: "rect-\(index)",
                    rect: .init(x: Double(index % 20), y: Double(index % 20), width: 5, height: 5),
                    lineWidth: 1
                ))
            ]))
        }

        for _ in 0..<100 { _ = try session.undo() }
        #expect(throws: TaAgentAnnotationSessionError.self) { _ = try session.undo() }

        _ = try session.redo()
        _ = try session.apply(AnnotationRecipe(version: 1, operations: [
            .number(.init(id: "replacement", center: .init(x: 10, y: 10), number: 9))
        ]))
        #expect(throws: TaAgentAnnotationSessionError.self) { _ = try session.redo() }
    }
}
