import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PetGalleryView: View {
    @ObservedObject var library: PetLibrary
    var projectKeys: [String] = []

    @State private var shareError: String?
    @State private var scope: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pet Gallery").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Import Pet…") { importPet() }
                Button("Export Pet…") { exportSelectedPet() }
                    .disabled(library.selectedIndex == nil)
                Button("Reveal Folder") {
                    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pets")
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                Button("Reload") { library.reload() }
            }

            if !projectKeys.isEmpty {
                HStack {
                    Picker("Applies to", selection: $scope) {
                        Text("Global default").tag(String?.none)
                        ForEach(projectKeys, id: \.self) { key in
                            Text(key.capitalized).tag(String?.some(key))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240)
                    if let scope, library.perProjectSelection[scope] != nil {
                        Button("Use Global Default") {
                            library.setSelection(forKey: scope, dirName: nil)
                        }
                        .font(.system(size: 10))
                    }
                }
            }

            if let shareError {
                Text(shareError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
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
                    tile(name: "Emoji", thumbnail: nil, isSelected: isSelected(dirName: nil)) {
                        select(dirName: nil)
                    }
                    ForEach(Array(library.availableDirs.enumerated()), id: \.offset) { index, dir in
                        tile(
                            name: dir.lastPathComponent.capitalized,
                            thumbnail: thumbnail(for: dir),
                            isSelected: isSelected(dirName: dir.lastPathComponent)
                        ) {
                            select(dirName: dir.lastPathComponent, index: index)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(18)
        .frame(width: 360)
    }

    private func isSelected(dirName: String?) -> Bool {
        guard let scope else {
            guard let selectedIndex = library.selectedIndex, library.availableDirs.indices.contains(selectedIndex) else {
                return dirName == nil
            }
            return library.availableDirs[selectedIndex].lastPathComponent == dirName
        }
        guard let dirName else { return library.isEmojiOverride(forKey: scope) }
        return library.perProjectSelection[scope] == dirName
    }

    private func select(dirName: String?, index: Int? = nil) {
        guard let scope else {
            if let index { library.select(index: index) } else { library.useEmoji() }
            return
        }
        if let dirName {
            library.setSelection(forKey: scope, dirName: dirName)
        } else {
            library.useEmoji(forKey: scope)
        }
    }

    private func thumbnail(for dir: URL) -> NSImage? {
        PetAssetLoader.load(from: dir)?.frames(row: "idle")?.first
    }

    private func exportSelectedPet() {
        guard let index = library.selectedIndex, library.availableDirs.indices.contains(index) else { return }
        let petDir = library.availableDirs[index]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(petDir.lastPathComponent).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try PetSharing.export(petDir: petDir, to: destination)
            shareError = nil
        } catch {
            shareError = "Couldn't export \(petDir.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func importPet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            _ = try PetSharing.importPet(fromZip: source)
            shareError = nil
            library.reload()
        } catch {
            shareError = "Couldn't import that pet: \(error.localizedDescription)"
        }
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
        .accessibilityLabel(isSelected ? "\(name), selected" : name)
    }
}
