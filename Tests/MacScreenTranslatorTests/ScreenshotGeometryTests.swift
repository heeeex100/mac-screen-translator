import XCTest
@testable import MacScreenTranslator

final class ScreenshotGeometryTests: XCTestCase {
    private let screen = CGSize(width: 1000, height: 800)

    func testRetinaSelectionScalesAndFlipsVerticalAxis() {
        let rect = ScreenshotGeometry.cropRect(selection: CGRect(x: 100, y: 200, width: 300, height: 100),
                                               screenSize: screen, imageSize: CGSize(width: 2000, height: 1600))
        XCTAssertEqual(rect, CGRect(x: 200, y: 1000, width: 600, height: 200))
    }

    func testLocalCoordinatesWorkWithoutSecondaryScreenOrigin() {
        // 副屏也传入屏幕本地选区；不应再减去主屏或副屏的全局 origin。
        let rect = ScreenshotGeometry.cropRect(selection: CGRect(x: 20, y: 650, width: 100, height: 50),
                                               screenSize: screen, imageSize: screen)
        XCTAssertEqual(rect, CGRect(x: 20, y: 100, width: 100, height: 50))
    }

    func testSelectionCrossingScreenEdgesIsClipped() {
        let rect = ScreenshotGeometry.cropRect(selection: CGRect(x: -20, y: 750, width: 80, height: 100),
                                               screenSize: screen, imageSize: screen)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 60, height: 50))
    }

    func testSelectionEntirelyOutsideScreenIsRejected() {
        XCTAssertNil(ScreenshotGeometry.cropRect(selection: CGRect(x: 1200, y: 50, width: 20, height: 20),
                                                screenSize: screen, imageSize: screen))
    }

    func testZeroSizeSelectionIsRejected() {
        XCTAssertNil(ScreenshotGeometry.cropRect(selection: .zero, screenSize: screen, imageSize: screen))
    }

    func testOnePixelCropIsRejected() {
        XCTAssertNil(ScreenshotGeometry.cropRect(selection: CGRect(x: 10, y: 10, width: 1, height: 10),
                                                screenSize: screen, imageSize: screen))
    }

    func testFractionalSelectionExpandsToWholePixelBounds() {
        let rect = ScreenshotGeometry.cropRect(selection: CGRect(x: 10.25, y: 20.25, width: 10.5, height: 5.5),
                                               screenSize: screen, imageSize: screen)
        XCTAssertEqual(rect, CGRect(x: 10, y: 774, width: 11, height: 6))
    }

    func testInvalidScreenOrImageSizeIsRejected() {
        let selection = CGRect(x: 10, y: 10, width: 20, height: 20)
        for size in [CGSize.zero, CGSize(width: 0, height: 800), CGSize(width: 1000, height: -1)] {
            XCTAssertNil(ScreenshotGeometry.cropRect(selection: selection, screenSize: size, imageSize: screen))
            XCTAssertNil(ScreenshotGeometry.cropRect(selection: selection, screenSize: screen, imageSize: size))
        }
    }
}
