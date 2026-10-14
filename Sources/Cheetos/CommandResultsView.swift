import SwiftUI
import AppKit

enum CommandResultAction: Equatable {
    case move(Int), copy, open

    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
        guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch keyCode {
        case 125: return .move(1)
        case 126: return .move(-1)
        case 36, 76: return .copy
        case 48: return .open
        default: return nil
        }
    }
}

enum CommandSelection {
    static func moved(in ids: [String], current: String?, by delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let index = ids.firstIndex(where: { $0 == current }) else { return ids.first }
        return ids[max(0, min(ids.count - 1, index + delta))]
    }
}

struct CommandResultsView: View {
    let commands: [IndexedCommand]
    let selection: String?
    let favorites: Set<String>
    let favoritesOnly: Bool
    let onSelect: (IndexedCommand) -> Void
    let onCopy: (IndexedCommand) -> Void
    let onFavorite: (IndexedCommand) -> Void
    let onOpen: (IndexedCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(favoritesOnly ? "Избранное" : "Все вкладки").font(.headline)
                Spacer()
                Text("⌘D — звезда · ⌘E — редактор").font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if commands.isEmpty {
                VStack(spacing: 8) {
                    Text(favoritesOnly ? "Нет избранных команд" : "Нет подходящих команд")
                    Text(favoritesOnly ? "⌘F — найти · ⌘D — добавить" : "Измените запрос или нажмите Esc")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SelectionFollowingScrollView(selection: selection) {
                    VStack(spacing: 4) {
                        ForEach(commands) { command in
                            row(command).id(command.id)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func row(_ command: IndexedCommand) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(command.key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                Text(command.desc).font(.system(size: 12))
                Button(command.sheetTitle) { onOpen(command) }
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Tab — открыть заметку")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { onFavorite(command) } label: {
                Image(systemName: favorites.contains(command.id) ? "star.fill" : "star")
                    .foregroundStyle(favorites.contains(command.id) ? Color.yellow : .secondary)
            }
            .help("⌘D — добавить / убрать")
            Button { onCopy(command) } label: { Image(systemName: "doc.on.doc") }
                .help("Enter — копировать")
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 7).fill(selection == command.id ? Color.accentColor.opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(command) }
    }
}
