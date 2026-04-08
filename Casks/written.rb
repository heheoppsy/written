cask "written" do
  version "1.1.4"
  sha256 "705f15a8ece62919bff6e416aa49c57c831a4a207c5084d1f75e05a14a8cbe8d"

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
