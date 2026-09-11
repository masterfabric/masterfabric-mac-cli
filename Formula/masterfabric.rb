class MasterFabric < Formula
  desc "Open-source MacBook monitor — CLI, menu bar, and MCP for AI agents"
  homepage "https://github.com/gurkanfikretgunak/masterfabric-mac-cli"
  url "https://github.com/gurkanfikretgunak/masterfabric-mac-cli/archive/refs/tags/v0.4.14.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"
  depends_on xcode: ["14.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/mf"
    bin.install ".build/release/MasterFabricMenuBar"
  end

  def caveats
    <<~EOS
      MCP (Cursor ~/.cursor/mcp.json):

        "masterfabric": {
          "command": "#{opt_bin}/mf",
          "args": ["mcp"]
        }

      Menu bar: mf menubar
      Docs: https://github.com/gurkanfikretgunak/masterfabric-mac-cli
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mf --version")
    assert_match "Model", shell_output("#{bin}/mf info")
  end
end
