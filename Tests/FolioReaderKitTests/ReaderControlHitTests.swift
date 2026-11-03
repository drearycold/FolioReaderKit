import XCTest
import WebKit
@testable import FolioReaderKit

@MainActor
final class ReaderControlHitTests: XCTestCase {
    private func cycle(count: Int = 2) -> String {
        let rules = (1...count).map {
            ".cg-cycle input:nth-of-type(\($0)):checked ~ label:nth-of-type(\($0))"
        }.joined(separator: ",")
        let inputs = (1...count).map {
            "<input type='radio' name='cycle' id='slide\($0)' \($0 == 1 ? "checked='checked'" : "")/>"
        }.joined()
        let labels = (1...count).map {
            "<label for='slide\($0 % count + 1)'><img id='image\($0)' width='180' height='\($0 == 1 ? 160 : 40)' alt='Slide \($0)'/></label>"
        }.joined()
        return """
            <style>
            .cg-cycle { margin: 1.2em 0; text-align: center; }
            .cg-cycle input { position:absolute; opacity:0; width:1px; height:1px; overflow:hidden; pointer-events:none; }
            .cg-cycle label { display:none; margin:0; cursor:pointer; }
            \(rules) { display:block; }
            .cg-cycle img { display:block; margin:0 auto; }
            </style>
            <div class='cg-cycle'>\(inputs)\(labels)</div>
            <div id='text' style='height:400px'>Ordinary text below the changing image</div>
            """
    }

    func testRadioCyclesKeepTheirTapAfterImageShrinks() {
        for xhtml in [false, true] {
            for count in [2, 24] {
                let view = readerChapter(cycle(count: count), paged: false, xhtml: xhtml)
                XCTAssertEqual(evaluate("var image = document.getElementById('image1'); var r = image.getBoundingClientRect(); var x = r.left + 20; var y = r.bottom - 8; folioReaderControlAtPoint(x, y)", in: view) as? Bool, true)
                // A real label activation switches the radio and makes the image shorter.
                evaluate("image.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, clientX:x, clientY:y})); image.click(); true", in: view)
                XCTAssertEqual(evaluate("document.getElementById('slide2').checked", in: view) as? Bool, true)
                XCTAssertEqual(evaluate("var target = document.elementFromPoint(x, y); !!(target && target.closest('label'))", in: view) as? Bool, false)
                XCTAssertEqual(evaluate("folioReaderControlAtPoint(x, y)", in: view) as? Bool, true, "The original image tap must remain excluded after its label disappears")
                // The next tap in that same location is now an ordinary text tap.
                evaluate("target.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, clientX:x, clientY:y})); true", in: view)
                XCTAssertEqual(evaluate("folioReaderControlAtPoint(x, y)", in: view) as? Bool, false)
            }
        }
    }

    func testTouchOnCheckboxLabelIsExcludedWithoutDependingOnClassName() {
        for xhtml in [false, true] {
            let view = readerChapter("<label><input type='checkbox'/><span id='caption'>Switch image</span></label>", paged: false, xhtml: xhtml)
            evaluate("var label = document.querySelector('label'); var r = label.getBoundingClientRect(); var x = r.left + 10; var y = r.top + 5; var touch = new Event('touchstart', {bubbles:true}); Object.defineProperty(touch, 'touches', {value:[{clientX:x, clientY:y}]}); label.dispatchEvent(touch); label.click(); true", in: view)
            XCTAssertEqual(evaluate("document.querySelector('input').checked", in: view) as? Bool, true)
            XCTAssertEqual(evaluate("folioReaderControlAtPoint(x, y)", in: view) as? Bool, true)
        }
    }

    func testOrdinaryImagesAndInactiveLabelsRemainReaderTaps() {
        let view = readerChapter("""
            <img id='ordinary' width='100' height='40' alt='Ordinary image'/>
            <label id='caption'>Caption without a control</label>
            <input id='disabled' type='radio' disabled='disabled'/><label id='disabledLabel' for='disabled'>Disabled switch</label>
            <label id='missing' for='absent'>Missing control</label>
            <video id='video' width='100' height='50'></video>
            <audio id='audio' controls='controls'></audio>
            """, paged: false)
        for id in ["ordinary", "caption", "disabledLabel", "missing", "video", "audio"] {
            XCTAssertEqual(evaluate("var r = document.getElementById('\(id)').getBoundingClientRect(); folioReaderControlAtPoint(r.left + 4, r.top + 4)", in: view) as? Bool, id == "video" || id == "audio", id)
        }
    }
}
