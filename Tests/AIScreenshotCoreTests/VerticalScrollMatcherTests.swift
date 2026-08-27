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

    func testAutomaticDownwardMatchNeverAcceptsAnUpwardFrame() {
        let world = makeWorld(width: 32, height: 320)
        let previous = crop(world, y: 100, height: 140)
        let current = crop(world, y: 63, height: 140)

        let match = VerticalScrollMatcher().match(
            previous: previous,
            current: current,
            constraint: .downwardOnly,
            preferredSignedShift: 40
        )

        XCTAssertNil(match)
    }

    func testAutomaticDownwardMatchRejectsFarRepeatedContentTie() {
        let previous = makeRepeatingFrame(offset: 0)
        let current = makeRepeatingFrame(offset: 36)

        let match = VerticalScrollMatcher().match(
            previous: previous,
            current: current,
            constraint: .downwardOnly,
            preferredSignedShift: 36
        )

        XCTAssertNil(match)
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

    func testFindsScrollInsideContentWhenSidebarAndComposerStayFixed() throws {
        let previous = makeAppFrame(offset: 0)
        let current = makeAppFrame(offset: 41)

        let match = try XCTUnwrap(VerticalScrollMatcher().match(previous: previous, current: current))

        XCTAssertEqual(match.signedShift, 41, accuracy: 1)
        XCTAssertFalse(match.isDuplicate)
    }

    func testBrowserLikeStickyHeaderAndAnimatedBandCannotOverrideContentVote() throws {
        let previous = makeBrowserFrame(offset: 0, animationSeed: 7)
        let current = makeBrowserFrame(offset: 52, animationSeed: 91)

        let match = try XCTUnwrap(
            VerticalScrollMatcher().match(
                previous: previous,
                current: current,
                constraint: .downwardOnly,
                preferredSignedShift: 52
            )
        )

        XCTAssertEqual(match.signedShift, 52, accuracy: 1)
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

    private func makeAppFrame(offset: Int) -> GrayscaleFrame {
        let width = 96
        let height = 160
        let sidebarWidth = 24
        let composerHeight = 28
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if x < sidebarWidth {
                    pixels[index] = UInt8((x * 11 + y / 9 * 7 + 31) % 256)
                } else if y >= height - composerHeight {
                    pixels[index] = UInt8((x * 5 + y * 3 + 17) % 256)
                } else {
                    let documentY = y + offset
                    pixels[index] = UInt8((x * 17 + documentY * 31 + (documentY / 3) * 47 + x * documentY % 83) % 256)
                }
            }
        }
        return GrayscaleFrame(width: width, height: height, pixels: pixels)
    }

    private func makeRepeatingFrame(offset: Int) -> GrayscaleFrame {
        let width = 48
        let height = 144
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let documentY = y + offset
                pixels[y * width + x] = UInt8((x * 13 + (documentY % 36) * 17) % 256)
            }
        }
        return GrayscaleFrame(width: width, height: height, pixels: pixels)
    }

    private func makeBrowserFrame(offset: Int, animationSeed: Int) -> GrayscaleFrame {
        let width = 120
        let height = 180
        let stickyHeaderHeight = 20
        var pixels = [UInt8](repeating: 248, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if y < stickyHeaderHeight {
                    pixels[index] = UInt8((x * 7 + y * 5 + 43) % 256)
                } else if x >= 50, x < 70 {
                    pixels[index] = UInt8((x * 31 + y * 19 + animationSeed * 23) % 256)
                } else {
                    let documentY = y + offset
                    let textStripe = (documentY / 5) % 11 == 0 ? 35 : 235
                    pixels[index] = UInt8((textStripe + x * 3 + documentY * 7) % 256)
                }
            }
        }
        return GrayscaleFrame(width: width, height: height, pixels: pixels)
    }
}
