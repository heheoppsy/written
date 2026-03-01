cask "written" do
  version "1.0.0"
  sha256 "<sha256 of DMG>"

  url "https://github.com/heheoppsy/written/releases/download/v#{version}/Written-#{version}.dmg"
  name "Written"
  desc "Distraction-free plaintext writing app for macOS"
  homepage "https://github.com/heheoppsy/written"

  depends_on macos: ">= :sequoia"

  app "Written.app"

  binary "#{appdir}/Written.app/Contents/MacOS/WrittenCLI", target: "written"

  zap trash: [
    "~/Library/Preferences/com.written.app.plist",
  ]
end
