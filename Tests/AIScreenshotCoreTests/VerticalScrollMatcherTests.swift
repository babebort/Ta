import XCTest
@testable import AIScreenshotCore

final class VerticalScrollMatcherTests: XCTestCase {
    func testFindsDownwardScrollShift() throws {
        let world = makeWorld(width: 32, height: 260)
        let previous = crop(world, y: 0, height: 140)
        let current = crop(world, y: 37, height: 140)

        let match = try XCTUnwrap(VerticalScrollMatcher().match(previous: previous, current: current))
        XCTAssertEqual(match.shift, 37, accuracy: 1)
        XCTAssertLessThan(match.meanAbsoluteDifference, 0.1)
    }

    func testDuplicateFrameIsReported() throws {
        let frame = crop(makeWorld(width: 28, height: 180), y: 10, height: 120)
        let match = try XCTUnwrap(VerticalScrollMatcher().match(previous: frame, current: frame))

        XCTAssertTrue(match.isDuplicate)
        XCTAssertEqual(match.shift, 0)
    }

    func testIgnoresStickyHeaderWhenMatching() throws {
        let world = makeWorld(width: 34, height: 300)
        let previous = crop(world, y: 0, height: 150)
        var current = crop(world, y: 29, height: 150)
        let stickyHeader = Array(previous.pixels.prefix(previous.width * 12))
        var pixels = current.pixels
        pixels.replaceSubrange(0..<(current.width * 12), with: stickyHeader)
        current = GrayscaleFrame(width: current.width, height: current.height, pixels: pixels)

        let matcher = VerticalScrollMatcher(ignoredTopFraction: 0.10)
        let match = try XCTUnwrap(matcher.match(previous: previous, current: current))
        XCTAssertEqual(match.shift, 29, accuracy: 1)
    }

    func testRejectsUnrelatedFrames() {
        let previous = crop(makeWorld(width: 30, height: 200, seed: 3), y: 0, height: 120)
        let current = crop(makeWorld(width: 30, height: 200, seed: 97), y: 0, height: 120)

        XCTAssertNil(VerticalScrollMatcher().match(previous: previous, current: current))
    }

    func testFindsUpwardScrollShift() throws {
        let world = makeWorld(width: 32, height: 320)
        let previous = crop(world, y: 100, height: 140)
        let current = crop(world, y: 63, height: 140)

        let match = try XCTUnwrap(VerticalScrollMatcher().match(previous: previous, current: current))
        XCTAssertEqual(match.signedShift, -37, accuracy: 1)
        XCTAssertEqual(match.direction, .up)
        XCTAssertEqual(match.shift, 37, accuracy: 1)
    }

    func testDetectsStableTopAndBottomRegions() {
        let world = makeWorld(width: 34, height: 320)
        let previous = crop(world, y: 40, height: 160)
        var current = crop(world, y: 77, height: 160)
        var pixels = current.pixels
        pixels.replaceSubrange(0..<(current.width * 16), with: previous.pixels[0..<(previous.width * 16)])
        let footerStart = current.width * 146
        pixels.replaceSubrange(footerStart..<pixels.count, with: previous.pixels[footerStart..<previous.pixels.count])
        current = GrayscaleFrame(width: current.width, height: current.height, pixels: pixels)

        let edges = VerticalScrollMatcher().stableEdges(previous: previous, current: current)

        XCTAssertGreaterThanOrEqual(edges.topRows, 14)
        XCTAssertGreaterThanOrEqual(edges.bottomRows, 12)
    }

    private func makeWorld(width: Int, height: Int, seed: Int = 11) -> GrayscaleFrame {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            let x = index % width
            let y = index / width
            let columnTerm = x * 17
            let rowTerm = y * 31
            let bandTerm = (y / 3) * 47
            let textureTerm = (x * y) % 83
            pixels.append(UInt8((columnTerm + rowTerm + bandTerm + textureTerm + seed) % 256))
        }
        return GrayscaleFrame(width: width, height: height, pixels: pixels)
    }

    private func crop(_ frame: GrayscaleFrame, y: Int, height: Int) -> GrayscaleFrame {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(frame.width * height)
        for row in y..<(y + height) {
            let start = row * frame.width
            pixels.append(contentsOf: frame.pixels[start..<(start + frame.width)])
        }
        return GrayscaleFrame(width: frame.width, height: height, pixels: pixels)
    }
}
