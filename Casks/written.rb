cask "written" do
  version "1.1.1"
  sha256 "b10ba35fca0e842cab983d715b0d27fd7f6d3590b04130ec446c00fc464148fc"

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
