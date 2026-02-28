# MiaoYan Release Best Practices

> 每次发布新版本的标准流程，基于实际踩坑经验整理。

---

## 前置准备

- 确认 `~/.config/miaoyan/build.sh` 存在（含 Apple ID、Team ID、app-specific password、Sparkle 私钥路径）
- 确认 `~/.config/miaoyan/sparkle_private.key` 存在（EdDSA 私钥）
- 私钥对应的公钥必须与 `Info.plist` 中的 `SUPublicEDKey` 一致，可用以下命令验证：

```bash
GENERATE_KEYS=$(ls -t ~/Library/Developer/Xcode/DerivedData/MiaoYan-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys | head -1)
base64 < ~/.config/miaoyan/sparkle_private.key | "$GENERATE_KEYS"
# 输出的公钥应与 Info.plist 中 SUPublicEDKey 值一致
```

---

## Step 1：更新版本号

在 Xcode 中修改 `MARKETING_VERSION`，或直接改 `project.pbxproj`，提交到 main。

---

## Step 2：打包公证

运行外部构建脚本（含签名、公证、Sparkle 签名一体化）：

```bash
~/.config/miaoyan/build.sh
```

**产物**（输出到 `~/Downloads/`）：
- `MiaoYan_v{VERSION}.dmg` — 发布用，App 内已 staple 公证票据
- `MiaoYan_V{VERSION}.zip` — Sparkle 自动更新用

**注意事项**：
- DMG staple 会报 Error 65（DMG 未单独公证），属正常现象，已加 `|| true` 跳过
- `hdiutil` 使用 `LC_ALL=C` 前缀避免 locale 导致的静默失败
- DMG 背景图位于 `Resources/dmg-background.png`，构建脚本自动读取

**脚本完成后记录输出的 Sparkle 信息**：
```
sparkle:edSignature="..."
length="..."
```

> ⚠️ **重要**：签名必须在打包完成后立即记录，若后续重新构建会生成新的 ZIP，签名和 length 都会变化，必须重新签名并同步。

---

## Step 3：更新 README

修改 `README.md` 和 `README_CN.md` 的安装说明、功能描述等，提交到 main 分支。

---

## Step 4：创建 GitHub Release

```bash
# 打 tag
git tag V{VERSION}
git push origin V{VERSION}

# 创建 release（只上传 MiaoYan.dmg，不含版本号，不上传 ZIP）
gh release create V{VERSION} \
  --title "V{VERSION} {MonsterName} {emoji}" \
  --notes "..." \
  ~/Downloads/MiaoYan_v{VERSION}.dmg
```

**命名规范**：
- DMG 文件名：`MiaoYan.dmg`（不带版本号）
- release 标题格式：`V{VERSION} {怪物猎人物语怪物名} {emoji}`，例如 `V2.7.0 Zinogre 🍝`
- ZIP 不上传到 GitHub release，只放 Vercel

---

## Step 5：更新 Vercel 分支

```bash
git checkout vercel
git pull
```

**1. 更新 `appcast.xml`**，在顶部新增 item（参考已有格式）：

```xml
<item>
  <title>{VERSION}</title>
  <link>https://github.com/tw93/MiaoYan/releases</link>
  <description><![CDATA[
  <h3>{MonsterName} {emoji}</h3>
  <ol>
    <li><strong>功能点</strong>：说明</li>
    ...
  </ol>
  <h3>{MonsterName} {emoji}</h3>
  <ol>
    <li><strong>Feature</strong>: Description</li>
    ...
  </ol>
      ]]>      </description>
  <pubDate>{RFC2822 日期}</pubDate>
  <enclosure url="https://miaoyan.app/Release/MiaoYan_V{VERSION}.zip"
             sparkle:shortVersionString="{VERSION}"
             sparkle:version="{VERSION}"
             sparkle:edSignature="{签名}"
             length="{文件大小}"
             type="application/octet-stream"/>
  <sparkle:minimumSystemVersion>11.5</sparkle:minimumSystemVersion>
</item>
```

**2. 复制文件到 `Release/` 文件夹**：

```bash
cp ~/Downloads/MiaoYan_v{VERSION}.dmg Release/MiaoYan.dmg
cp ~/Downloads/MiaoYan_V{VERSION}.zip  Release/MiaoYan_V{VERSION}.zip
```

**3. 提交推送**：

```bash
git add appcast.xml Release/MiaoYan.dmg Release/MiaoYan_V{VERSION}.zip
git commit -m "chore: release v{VERSION}"
git push origin vercel
```

---

## 常见问题

### Sparkle 报 "improperly signed"
原因：ZIP 文件被重新构建覆盖，与 appcast.xml 中签名不一致。

修复步骤：
1. 重新对当前 ZIP 签名：
```bash
SIGN_UPDATE=$(ls -t ~/Library/Developer/Xcode/DerivedData/MiaoYan-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update | head -1)
base64 < ~/.config/miaoyan/sparkle_private.key | "$SIGN_UPDATE" --ed-key-file - ~/Downloads/MiaoYan_V{VERSION}.zip
```
2. 用新的 `edSignature` 和 `length` 更新 appcast.xml
3. 用同一个 ZIP 覆盖 `Release/MiaoYan_V{VERSION}.zip`
4. 提交推送

### hdiutil create 失败
- 检查是否有残留挂载卷：`hdiutil info | grep MiaoYan`
- 脚本已内置 retry 和 `LC_ALL=C` 修复，重跑即可

### Archive FAILED
- 通常是 DerivedData 状态异常，重跑脚本会自动 clean 后重建
- 查看详细错误：`cat build/archive.log | grep error:`
