cask "written" do
  version "1.1.3"
  sha256 "50b0cccdad5ea3ad4be7553a5986623d22d9a5be8c9052a73d4014596c1ce254"

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
