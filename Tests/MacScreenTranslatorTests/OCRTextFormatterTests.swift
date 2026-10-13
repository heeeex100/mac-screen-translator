import XCTest
@testable import MacScreenTranslator

final class OCRTextFormatterTests: XCTestCase {
    private func item(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 0.35) -> OCRTextFormatter.Item {
        .init(text: text, box: CGRect(x: x, y: y, width: width, height: 0.05))
    }

    func testAlignedColumnsReadLeftThenRight() {
        let items = [item("L1", 0.05, 0.8), item("R1", 0.6, 0.8),
                     item("L2", 0.05, 0.7), item("R2", 0.6, 0.7)]
        XCTAssertEqual(OCRTextFormatter.format(items), "L1\nL2\nR1\nR2")
        XCTAssertEqual(OCRTextFormatter.format(items.reversed()), "L1\nL2\nR1\nR2")
    }

    func testStaggeredColumnsStillReadByColumn() {
        XCTAssertEqual(OCRTextFormatter.format([item("R1", 0.6, 0.83), item("L2", 0.05, 0.70),
                                               item("L1", 0.05, 0.80), item("R2", 0.6, 0.73)]),
                       "L1\nL2\nR1\nR2")
    }

    func testAdjacentFragmentsStayOnSameLine() {
        XCTAssertEqual(OCRTextFormatter.format([item("world", 0.22, 0.8, 0.15),
                                               item("Hello", 0.05, 0.8, 0.15), item("Next", 0.05, 0.7)]),
                       "Hello world\nNext")
    }

    func testHeadingAboveColumnsDoesNotMergeColumns() {
        XCTAssertEqual(OCRTextFormatter.format([item("Heading", 0.05, 0.9, 0.9),
                                               item("L1", 0.05, 0.8), item("R1", 0.6, 0.8),
                                               item("L2", 0.05, 0.7), item("R2", 0.6, 0.7)]),
                       "Heading\nL1\nL2\nR1\nR2")
    }

    func testSingleColumnParagraphGapIsPreserved() {
        XCTAssertEqual(OCRTextFormatter.format([item("Bottom", 0.05, 0.5), item("Top", 0.05, 0.8)]),
                       "Top\n\nBottom")
    }

    func testEmptyAndSingleItem() {
        XCTAssertEqual(OCRTextFormatter.format([]), "")
        XCTAssertEqual(OCRTextFormatter.format([item("Only", 0.05, 0.8)]), "Only")
    }

    func testActualVisionBoxesFromWideImageReadByColumn() {
        // 1600×400 图片的真实 Vision 文字框；归一化高度不代表横向距离。
        let boxes: [(String, CGRect)] = [
            ("L1", CGRect(x: 0.02456, y: 0.71929, width: 0.29684, height: 0.09268)),
            ("L2", CGRect(x: 0.02451, y: 0.53412, width: 0.26646, height: 0.09669)),
            ("L3", CGRect(x: 0.02462, y: 0.35445, width: 0.27637, height: 0.08688)),
            ("R1", CGRect(x: 0.53198, y: 0.72674, width: 0.28779, height: 0.08826)),
            ("R2", CGRect(x: 0.53189, y: 0.53424, width: 0.28939, height: 0.09780)),
            ("R3", CGRect(x: 0.53198, y: 0.34884, width: 0.30523, height: 0.08721))
        ]
        XCTAssertEqual(OCRTextFormatter.format(boxes.map { .init(text: $0.0, box: $0.1) }),
                       "L1\nL2\nL3\nR1\nR2\nR3")
    }

}
