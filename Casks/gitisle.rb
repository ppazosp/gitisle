# Homebrew cask. New installs use the tap at github.com/ppazosp/homebrew-gitisle:
#   brew install --cask ppazosp/gitisle/gitisle
# This copy stays for anyone who tapped this repository; keep the two the same.
cask "gitisle" do
  version :latest
  sha256 :no_check

  url "https://github.com/ppazosp/gitisle/releases/latest/download/GitIsle.zip"
  name "GitIsle"
  desc "GitHub pull requests in your Mac's notch"
  homepage "https://github.com/ppazosp/gitisle"

  depends_on macos: ">= :sonoma"
  depends_on formula: "gh"

  app "GitIsle.app"

  # Releases are signed ad hoc and not notarized yet.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/GitIsle.app"]
  end

  uninstall quit: "dev.ppazosp.gitisle"

  zap trash: "~/Library/Application Support/GitIsle"
end
