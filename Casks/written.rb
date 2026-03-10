cask "written" do
  version "1.1.2"
  sha256 "08cbc073449cb76845bc4ef0141f38422c06adb2109ac725ba049494974c8891"

  url "https://github.com/heheoppsy/written/releases/download/v#{version}/Written-#{version}.dmg"
  name "Written"
  desc "Distraction-free plaintext writing app for macOS"
  homepage "https://github.com/heheoppsy/written"

  depends_on macos: ">= :sequoia"

  app "Written.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Written.app"]
  end

  caveats <<~EOS
    Written is not notarized. The quarantine attribute is removed
    during installation to prevent macOS from blocking the app.
  EOS

  binary "#{appdir}/Written.app/Contents/MacOS/WrittenCLI", target: "written"

  zap trash: [
    "~/Library/Preferences/com.written.app.plist",
  ]
end
