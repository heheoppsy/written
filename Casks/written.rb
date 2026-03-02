cask "written" do
  version "1.1.2"
  sha256 "08cbc073449cb76845bc4ef0141f38422c06adb2109ac725ba049494974c8891"

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
