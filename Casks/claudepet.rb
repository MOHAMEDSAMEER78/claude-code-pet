cask "claudepet" do
  version "1.2.2"
  sha256 "111d23468356171a05f01b8ef08191ad76fd9ae5b2f5abaeccc45adee46510b1"

  url "https://github.com/MOHAMEDSAMEER78/claudepet/releases/download/v#{version}/ClaudePet-#{version}.zip"
  name "ClaudePet"
  desc "Menu-bar pet that shows live Claude Code session state"
  homepage "https://mohamedsameer78.github.io/claudepet/"

  depends_on macos: ">= :ventura"

  app "ClaudePet.app"

  zap trash: [
    "~/.claude/pet",
    "~/Library/Preferences/ai.armada.claudepet.plist",
  ]
end
