cask "miaoyan" do
  version :latest
  sha256 :no_check

  url "https://miaoyan.app/Release/MiaoYan.dmg"
  name "MiaoYan"
  desc "Markdown editor"
  homepage "https://miaoyan.app/"

  auto_updates true
  depends_on macos: ">= 11.5"

  app "MiaoYan.app"
end
