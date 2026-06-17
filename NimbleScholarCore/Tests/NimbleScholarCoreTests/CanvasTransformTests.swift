import XCTest
import CoreGraphics
@testable import NimbleScholarCore

final class CanvasTransformTests: XCTestCase {
    func testRoundTripAtVariousZoomPan() {
        let cases: [CanvasTransform] = [
            CanvasTransform(zoom: 1, pan: .zero),
            CanvasTransform(zoom: 2, pan: CGSize(width: 30, height: -40)),
            CanvasTransform(zoom: 0.5, pan: CGSize(width: -100, height: 100)),
        ]
        for t in cases {
            let p = CGPoint(x: 12.5, y: -7.25)
            let back = t.canvas(from: t.screen(from: p))
            XCTAssertEqual(back.x, p.x, accuracy: 0.0001)
            XCTAssertEqual(back.y, p.y, accuracy: 0.0001)
        }
    }

    func testScreenMapping() {
        let t = CanvasTransform(zoom: 2, pan: CGSize(width: 10, height: 20))
        let s = t.screen(from: CGPoint(x: 5, y: 5))   // 5*2+10, 5*2+20
        XCTAssertEqual(s.x, 20, accuracy: 0.0001)
        XCTAssertEqual(s.y, 30, accuracy: 0.0001)
    }

    func testClampZoom() {
        XCTAssertEqual(CanvasTransform.clampZoom(10), CanvasTransform.maxZoom)
        XCTAssertEqual(CanvasTransform.clampZoom(0.01), CanvasTransform.minZoom)
        XCTAssertEqual(CanvasTransform.clampZoom(1), 1)
    }

    func testVisibilityCulling() {
        let t = CanvasTransform(zoom: 1, pan: .zero)
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(t.isVisible(canvasRect: CGRect(x: 100, y: 100, width: 50, height: 50), in: viewport))
        XCTAssertFalse(t.isVisible(canvasRect: CGRect(x: 5000, y: 5000, width: 50, height: 50), in: viewport))
    }
}
