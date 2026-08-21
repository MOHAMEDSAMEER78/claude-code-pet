cask "claudepet" do
  version "1.1.5"
  sha256 "dfab1f4916c1db99c720cd6f99ace804ca675530ff4f8ef647d040c71b8ef1bb"

  url "https://github.com/MOHAMEDSAMEER78/claudepet/releases/download/v#{version}/ClaudePet-#{version}.zip"
  name "ClaudePet"
  desc "Menu-bar pet that shows live Claude Code session state"
  homepage "https://mohamedsameer78.github.io/claudepet/"

  # Not code-signed/notarized - install requires bypassing Gatekeeper's
  # "unidentified developer" warning once (System Settings > Privacy &
  # Security > Open Anyway), same as a manually downloaded build.
  depends_on macos: ">= :ventura"

  app "ClaudePet.app"

  zap trash: [
    "~/.claude/pet",
    "~/Library/Preferences/ai.armada.claudepet.plist",
  ]
end
