import SwiftUI
import AppKit

/// Cycles a custom pet's sprite-sheet frames for the current PetState, or an
/// explicit override row (e.g. a one-shot "jumping"/"waving" gesture, or an
/// autonomous "running-left"/"running-right" wander). Falls back to nothing
/// (caller should show the emoji instead) if no asset is loaded.
struct PetSpriteView: View {
    let asset: PetAsset
    let state: PetState
    var overrideRow: String? = nil

    @State private var frameIndex = 0
    @State private var timer: Timer?

    private var activeRow: String {
        overrideRow ?? PetAsset.rowName(for: state)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        let frames = asset.frames(row: activeRow) ?? asset.frames(for: state) ?? []
        Group {
            if !frames.isEmpty {
                Image(nsImage: frames[frameIndex % frames.count])
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 116, height: 126)
            }
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: activeRow) { _ in
            frameIndex = 0
            startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        guard !reduceMotion else { return } // freeze on frame 0
        let interval = 1.0 / max(asset.fps, 1)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            frameIndex += 1
        }
    }
}
