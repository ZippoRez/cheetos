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

    func testSidebarKeepsSelectedRowVisibleAtBothEnds() {
        _ = NSApplication.shared
        let model = SidebarSelection()
        let controller = NoteScrollController()
        let host = NSHostingView(rootView: SidebarFixture(model: model, controller: controller))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        defer { window.close() }

        for selected in [39, 0, 25, 3] {
            model.selection = selected
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            guard let scroll = controller.scrollView, let document = scroll.documentView,
                  let marker = findMarker("row-\(selected)", in: document) else {
                XCTFail("Missing sidebar scroll view or selected row")
                return
            }
            let row = document.convert(marker.bounds, from: marker)
            XCTAssertTrue(scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(row),
                          "Selected row \(selected) is outside the visible sidebar")
        }
    }

    private func findMarker(_ id: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == id { return view }
        return view.subviews.lazy.compactMap { self.findMarker(id, in: $0) }.first
    }

    private final class SidebarSelection: ObservableObject {
        @Published var selection: Int? = 0
    }

    private struct SidebarFixture: View {
        @ObservedObject var model: SidebarSelection
        let controller: NoteScrollController
        var body: some View {
            SelectionFollowingScrollView(selection: model.selection) {
                VStack(spacing: 0) {
                    ForEach(0..<40) { index in
                        Text("Sheet \(index)").frame(width: 250, height: 32)
                            .background(RowMarker(id: "row-\(index)"))
                            .id(index)
                    }
                }
                .background(NoteScrollProbe(controller: controller).frame(width: 0, height: 0))
            }
        }
    }

    private struct RowMarker: NSViewRepresentable {
        let id: String
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.identifier = NSUserInterfaceItemIdentifier(id)
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }

    func testLongCommandsStayInsideWindowAfterResizing() {
        _ = NSApplication.shared
        let command = "ycp --syntax 2 --profile internal ydb database get-by-path --location-id location --path "
            + String(repeating: "/very-long-database-path", count: 12)
        let root = HStack(spacing: 0) {
            Text("Sidebar").frame(width: 200)
                .background(RowMarker(id: "sidebar"))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownBlock.quote("Замени параметры своими значениями").view(highlight: "")
                        .background(RowMarker(id: "quote"))
                    MarkdownBlock.section("Команды").view(highlight: "")
                        .background(RowMarker(id: "section"))
                    MarkdownBlock.keyRow(key: command, desc: "Найти базу по пути").view(highlight: "")
                        .background(RowMarker(id: "command"))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        defer { window.close() }
        for width in [900, 1300, 900] {
            window.setContentSize(NSSize(width: width, height: 680))
            host.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            for id in ["sidebar", "quote", "section", "command"] {
                guard let marker = findMarker(id, in: host.view) else { XCTFail("Missing \(id)"); return }
                let rect = host.view.convert(marker.bounds, from: marker)
                XCTAssertTrue(rect.minX >= -1 && rect.maxX <= host.view.bounds.maxX + 1,
                              "\(id) overflows at width \(width): \(rect)")
                if id == "quote" || id == "section" {
                    XCTAssertTrue(rect.height < 80, "\(id) stretches vertically: \(rect.height)")
                }
            }
        }
    }
}
