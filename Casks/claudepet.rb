cask "claudepet" do
  version "1.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/MOHAMEDSAMEER78/claude-code-pet/releases/download/v#{version}/ClaudePet-#{version}.zip"
  name "ClaudePet"
  desc "Menu-bar pet that shows live Claude Code session state"
  homepage "https://mohamedsameer78.github.io/claude-code-pet/"

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
