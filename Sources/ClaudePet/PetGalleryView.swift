import SwiftUI
import AppKit

/// Browse and apply any installed pet (from ~/.claude/pets or ~/.codex/pets)
/// with a live preview, instead of cycling blind through "Next Pet" in the
/// menu bar one at a time.
struct PetGalleryView: View {
    @ObservedObject var library: PetLibrary

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pet Gallery").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Reveal Folder") {
                    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pets")
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                Button("Reload") { library.reload() }
            }

            if library.availableDirs.isEmpty {
                Text("No custom pets installed yet. Drop a Codex-format pet.json + spritesheet into ~/.claude/pets/<name>/, or Reload to pick up ~/.codex/pets.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    tile(name: "Emoji", thumbnail: nil, isSelected: library.selectedIndex == nil) {
                        library.useEmoji()
                    }
                    ForEach(Array(library.availableDirs.enumerated()), id: \.offset) { index, dir in
                        tile(
                            name: dir.lastPathComponent.capitalized,
                            thumbnail: thumbnail(for: dir),
                            isSelected: library.selectedIndex == index
                        ) {
                            library.select(index: index)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(18)
        .frame(width: 360)
    }

    private func thumbnail(for dir: URL) -> NSImage? {
        PetAssetLoader.load(from: dir)?.frames(row: "idle")?.first
    }

    private func tile(name: String, thumbnail: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.06))
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Text("😴").font(.system(size: 36))
                    }
                }
                .frame(width: 84, height: 84)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
                Text(name).font(.system(size: 10, weight: isSelected ? .semibold : .regular)).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
