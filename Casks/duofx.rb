cask "duofx" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/amjadjibon/DuoFX/releases/download/v#{version}/DuoFX-v#{version}-arm64.dmg",
      verified: "github.com/amjadjibon/DuoFX/"
  name "DuoFX"
  desc "Menu-bar app that animates the desktop as the MacBook lid closes"
  homepage "https://duofx.amjadjibon.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "DuoFX.app"

  uninstall quit: "com.amjadjibon.duofx"

  zap trash: [
    "~/Library/Preferences/com.amjadjibon.duofx.plist",
    "~/Library/Saved Application State/com.amjadjibon.duofx.savedState",
  ]
end
