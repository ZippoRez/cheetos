import AppKit
import SwiftUI
import XCTest
@testable import Cheetos

final class NoteNavigationTests: XCTestCase {
    private func action(_ code: UInt16, _ chars: String = "", _ modifiers: NSEvent.ModifierFlags = [],
                        reading: Bool = true, searchEmpty: Bool = true) -> NoteKeyboardAction? {
        .resolve(keyCode: code, characters: chars, modifiers: modifiers,
                 reading: reading, searchEmpty: searchEmpty)
    }

    func testEnteringNotePreservesSearchSubmissionAndTextInput() {
        XCTAssertEqual(action(36, reading: false), .enter)
        XCTAssertEqual(action(48, reading: false, searchEmpty: false), .enter)
        XCTAssertNil(action(36, reading: false, searchEmpty: false))
        XCTAssertNil(action(38, "j", reading: false))
        XCTAssertNil(action(40, "k", reading: false))
        XCTAssertNil(action(125, reading: false))
        XCTAssertNil(action(48, "", .shift, reading: false))
    }

    func testReadingKeysAndExit() {
        XCTAssertEqual(action(125), .scroll(.line(1)))
        XCTAssertEqual(action(126), .scroll(.line(-1)))
        XCTAssertEqual(action(38, "j"), .scroll(.line(1)))
        XCTAssertEqual(action(40, "k"), .scroll(.line(-1)))
        XCTAssertEqual(action(121, "", .function), .scroll(.page(1)))
        XCTAssertEqual(action(116, "", .function), .scroll(.page(-1)))
        XCTAssertEqual(action(125, "", .command), .scroll(.bottom))
        XCTAssertEqual(action(126, "", .command), .scroll(.top))
        XCTAssertEqual(action(115), .scroll(.top))
        XCTAssertEqual(action(119), .scroll(.bottom))
        XCTAssertEqual(action(53), .leave)
        XCTAssertEqual(action(48, "", .shift), .leave)
    }

    func testReadingDoesNotCaptureModifiedKeys() {
        XCTAssertNil(action(38, "j", .command))
        XCTAssertNil(action(125, "", .option))
        XCTAssertNil(action(126, "", [.command, .shift]))
        XCTAssertNil(action(3, "f", .command))
    }

    func testOffsetsClampAndUseViewportForPages() {
        XCTAssertEqual(NoteScrollCommand.line(-1).targetOffset(current: 0, contentHeight: 1000, viewportHeight: 200), 0)
        XCTAssertEqual(NoteScrollCommand.page(1).targetOffset(current: 20, contentHeight: 1000, viewportHeight: 200), 200)
        XCTAssertEqual(NoteScrollCommand.bottom.targetOffset(current: 0, contentHeight: 1000, viewportHeight: 200), 800)
        XCTAssertEqual(NoteScrollCommand.line(1).targetOffset(current: 790, contentHeight: 1000, viewportHeight: 200), 800)
        XCTAssertEqual(NoteScrollCommand.bottom.targetOffset(current: 0, contentHeight: 100, viewportHeight: 200), 0)
    }

    // Exercise the actual AppKit scrolling, including both document orientations.
    func testNativeScrollMovesOnlyDetailAndReachesBothEnds() {
        for flipped in [true, false] {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            let document = Document(frame: NSRect(x: 0, y: 0, width: 300, height: 1000), flipped: flipped)
            scrollView.documentView = document
            let controller = NoteScrollController()
            controller.scrollView = scrollView
            let maximum = document.bounds.height - scrollView.contentView.bounds.height
            XCTAssertTrue(controller.scroll(.top))
            XCTAssertEqual(scrollView.contentView.bounds.minY, flipped ? 0 : maximum, accuracy: 0.01)
            XCTAssertTrue(controller.scroll(.line(1)))
            XCTAssertEqual(scrollView.contentView.bounds.minY, flipped ? 48 : maximum - 48, accuracy: 0.01)
            XCTAssertTrue(controller.scroll(.bottom))
            XCTAssertEqual(scrollView.contentView.bounds.minY, flipped ? maximum : 0, accuracy: 0.01)
        }
        XCTAssertFalse(NoteScrollController().scroll(.line(1)))
    }

    func testProbeFindsTheSwiftUIDetailScrollView() {
        _ = NSApplication.shared
        let controller = NoteScrollController()
        let host = NSHostingView(rootView: ScrollView {
            Text("Long note").frame(width: 250, height: 1200)
                .background(NoteScrollProbe(controller: controller).frame(width: 0, height: 0))
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNotNil(controller.scrollView)
        XCTAssertTrue(controller.scroll(.bottom))
        XCTAssertGreaterThan(controller.scrollView?.contentView.bounds.minY ?? 0, 0)
        window.close()
    }

    private final class Document: NSView {
        let documentFlipped: Bool
        override var isFlipped: Bool { documentFlipped }
        init(frame: NSRect, flipped: Bool) { self.documentFlipped = flipped; super.init(frame: frame) }
        required init?(coder: NSCoder) { fatalError("Not used") }
    }
}
