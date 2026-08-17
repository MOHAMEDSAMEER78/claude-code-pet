import AppKit
import ClaudePetCore

/// Opt-in audible cues for states that need attention. Off by default -
/// see AppSettings.soundEnabled - since not everyone wants a chime from a
/// menu-bar pet, but it's a real gap for anyone working with headphones or a
/// second monitor where the pet panel isn't in view.
enum SoundPlayer {
    static func play(for state: PetState) {
        guard AppSettings.shared.soundEnabled else { return }
        switch state {
        case .waitingPermission: NSSound(named: "Ping")?.play()
        case .review: NSSound(named: "Glass")?.play()
        case .failed: NSSound(named: "Basso")?.play()
        case .idle, .running: break
        }
    }
}
