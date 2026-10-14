import AppKit
import SwiftUI

struct SelectionFollowingScrollView<ID: Hashable, Content: View>: View {
    let selection: ID?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content() }
                .onAppear { revealSelection(using: proxy) }
                .onChange(of: selection) { _, _ in revealSelection(using: proxy) }
        }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard let selection else { return }
        // Wait for the selected row's layout, including filtering/reordering.
        // No animation: repeated arrow presses should follow immediately.
        DispatchQueue.main.async { proxy.scrollTo(selection) }
    }
}

enum NoteScrollCommand: Equatable {
    case line(Int), page(Int), top, bottom

    func targetOffset(current: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let maximum = max(0, contentHeight - viewportHeight)
        let proposed: CGFloat
        switch self {
        case .line(let direction): proposed = current + CGFloat(direction) * 48
        case .page(let direction): proposed = current + CGFloat(direction) * max(48, viewportHeight * 0.9)
        case .top: proposed = 0
        case .bottom: proposed = maximum
        }
        return min(maximum, max(0, proposed))
    }
}

enum NoteKeyboardAction: Equatable {
    case enter, leave, scroll(NoteScrollCommand)

    static func resolve(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags,
                        reading: Bool, searchEmpty: Bool) -> Self? {
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        if !reading {
            if modifiers.isEmpty && (keyCode == 36 || keyCode == 76) && searchEmpty { return .enter }
            if modifiers.isEmpty && keyCode == 48 { return .enter }
            return nil
        }
        if modifiers == .command {
            if keyCode == 126 { return .scroll(.top) }
            if keyCode == 125 { return .scroll(.bottom) }
            return nil
        }
        if keyCode == 48 && modifiers == .shift { return .leave }
        guard modifiers.isEmpty else { return nil }
        switch keyCode {
        case 53: return .leave
        case 125: return .scroll(.line(1))
        case 126: return .scroll(.line(-1))
        case 121: return .scroll(.page(1))
        case 116: return .scroll(.page(-1))
        case 115: return .scroll(.top)
        case 119: return .scroll(.bottom)
        default:
            if characters == "j" { return .scroll(.line(1)) }
            if characters == "k" { return .scroll(.line(-1)) }
            return nil
        }
    }
}

// A probe inside the document finds the detail scroll view, never the sidebar.
final class NoteScrollController: ObservableObject {
    weak var scrollView: NSScrollView?

    @discardableResult
    func scroll(_ command: NoteScrollCommand) -> Bool {
        guard let scrollView, let document = scrollView.documentView else { return false }
        let clip = scrollView.contentView
        let maximum = max(0, document.bounds.height - clip.bounds.height)
        let rawOffset = clip.bounds.minY - document.bounds.minY
        let current = document.isFlipped ? rawOffset : maximum - rawOffset
        let offset = command.targetOffset(current: current, contentHeight: document.bounds.height,
                                          viewportHeight: clip.bounds.height)
        let y = document.bounds.minY + (document.isFlipped ? offset : maximum - offset)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
        return true
    }
}

struct NoteScrollProbe: NSViewRepresentable {
    let controller: NoteScrollController

    final class Probe: NSView {
        var controller: NoteScrollController?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); connect() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); connect() }

        func connect() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView else { return }
                self.controller?.scrollView = scrollView
            }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.controller = controller
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.controller = controller
        probe.connect()
    }
}
