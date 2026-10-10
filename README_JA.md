<div align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/Resources/app.icon/Assets/43.png" width="138" /></a>
  <h1>MiaoYan</h1>
  <p><b>ローカルの Markdown ノートのためのネイティブ Mac アプリ</b></p>
  <p><a href="README.md">English</a> · <a href="README_CN.md">中文</a> · <a href="README_TW.md">繁體</a> · 日本語 · <a href="README_KR.md">한국어</a> · <a href="README_DE.md">Deutsch</a> · <a href="README_FR.md">Français</a></p>
  <a href="https://twitter.com/HiTw93" target="_blank"><img alt="Twitter Follow" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
  <a href="https://t.me/+9f9gf4ZrFSQ2OWVl" target="_blank"><img alt="Telegram" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
  <a href="https://github.com/tw93/MiaoYan/releases" target="_blank"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/commits" target="_blank"><img alt="GitHub Commit Activity" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank"><img alt="GitHub Closed Issues" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
  <img alt="macOS 12.0+" src="https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square">
</div>

<img src="https://raw.githubusercontent.com/tw93/static/main/miaoyan/miaoyan.gif" width="900px" />

## 特徴

- **ローカルファースト**: ノートは選んだフォルダ内の Markdown ファイル、データ収集なし、デバイス間の同期は iCloud Drive や Nutstore で
- **集中**: フォルダ、ノート一覧、エディタの3ペイン構成、ダークモード対応、プラグイン管理は不要
- **ネイティブ**: Swift 6 製で Web ラッパーより軽量、2ペインプレビューは 60fps の双方向スクロール同期
- **必要十分**: 双方向リンク、LaTeX 数式、Mermaid 図、バージョン履歴、自動整形、PPT プレゼンテーションを内蔵

## インストール

1. **Mac App Store**（有料、自動アップデート、iPhone / iPad 版を含む）:

   <a href="https://apps.apple.com/cn/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Download on the Mac App Store" /></a>

2. **Homebrew**:
   ```bash
   brew install --cask miaoyan
   ```

3. **GitHub Releases**: [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) から最新 DMG をダウンロード（macOS 12.0+）

Homebrew と GitHub Releases でインストールされるオープンソース版は、現在バグ修正のみ行っています。新機能や iPhone / iPad 版を含むバージョンは Mac App Store 版として別途開発されています。インストール後、iCloud Drive やローカル同期フォルダに `MiaoYan` フォルダを作成し、設定（⌘,）で保存先を指定してください。

## Nutstore や他のクラウドストレージとの同期

MiaoYan はローカルファーストであり、WebDAV やクラウドストレージのアカウントに直接ログインしません。指定された Markdown フォルダの読み書きのみを行い、デバイス間の同期は iCloud Drive、Nutstore、Dropbox などのクライアントに任せます。

- **Mac**: クラウド同期ディレクトリ内に `MiaoYan` フォルダを作成し、MiaoYan の設定で保存先を指定。
- **iPhone**: システムの「ファイル」アプリで同じフォルダを選択。クラウドアプリが書き込み可能なフォルダを提供していない場合は、iCloud Drive を使用するか、そのアプリ内でオフライン利用可能にしてから選択。
- **フォルダ検証**: MiaoYan は切り替え前に読み書き権限を確認します。利用できない場合は保存先を変更せず、アプリ側の同期エラーとして誤認させません。

## CLI ツール

ターミナルから素早くノートを操作できるコマンドラインツールを提供しています。

```bash
# インストール
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# 使い方
miao open <タイトル|パス>    # ノートまたはフォルダを開く
miao new <タイトル> [内容]   # 新規ノート作成
miao search <キーワード>     # ターミナルでノート検索
miao list [folder]          # 最上位フォルダ、または指定フォルダの Markdown を一覧表示
miao cat <タイトル|パス>     # ノート内容を表示
miao update                 # CLI をアップデート
```

## 2ペイン編集・プレビューモード

編集ペインとプレビューペインを並べて表示し、60fps の双方向スクロール同期によるリアルタイムプレビューに対応しています。

**クイック切り替え**: `⌘\` を押して瞬時に切り替えるか、設定の「一般」でエディタモードを「分割モード」にすると有効になります。

Typora のようなインライン WYSIWYG にしない理由: 純粋な Markdown 編集こそが本質です。Swift によるネイティブ WYSIWYG は肥大化し壊れやすくなります。2ペイン分割により、集中した執筆と滑らかなリアルタイム視覚フィードバックの両立を実現しています。

<img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/assets/split-preview.png" width="100%" alt="2ペイン編集・プレビューモード" />

## ドキュメント

- [Markdown 構文ガイド](Resources/Initial/MiaoYan%20Markdown%20Syntax%20Guide.md) - 高度な機能を含む構文リファレンス
- [PPT プレゼンテーションモード](Resources/Initial/MiaoYan%20PPT.md) - `---` スライド区切りを使ったプレゼンテーションガイド
- [MiaoYan Agent Skill](skills/miaoyan) - MiaoYan の構文、添付ファイル、PPT、CLI ワークフローをエージェントに学習させる

`npx skills add tw93/MiaoYan/skills/miaoyan -g` で公式 Skill をインストールできます。

## サポート

- 開発者を直接支援する方法として、Mac クリーナーアプリ [Mole for Mac](https://mole.fit) の購入をご検討ください。
- MiaoYan が役に立ったら、Star を付けたり、[共有](https://twitter.com/intent/tweet?url=https://github.com/tw93/MiaoYan&text=MiaoYan%20-%20%E3%83%AD%E3%83%BC%E3%82%AB%E3%83%AB%E3%81%AE%20Markdown%20%E3%83%8E%E3%83%BC%E3%83%88%E3%81%AE%E3%81%9F%E3%82%81%E3%81%AE%E3%83%8D%E3%82%A4%E3%83%86%E3%82%A3%E3%83%96%20Mac%20%E3%82%A2%E3%83%97%E3%83%AA)したり、Issue や PR をお寄せください。
- 私にはタンユエン（湯円）とコーラ（可楽）という2匹の猫がいます。もし MiaoYan を気に入っていただけたら、<a href="https://cats.tw93.fun?name=MiaoYan" target="_blank">缶詰 🥩</a> をプレゼントしていただけると嬉しいです。

<details>
<summary>支援してくださった方々 🐱</summary>
<br/>
<a href="https://cats.tw93.fun?name=MiaoYan"><img src="https://cdn.jsdelivr.net/gh/tw93/sponsors@main/assets/sponsors.svg" width="1000" loading="lazy" /></a>
</details>

## 謝辞

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - 初期のプロジェクト構造リファレンス
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift Markdown パーサー
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Markdown フォーマットユーティリティ
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - シンタックスハイライト
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT プレゼンテーションフレームワーク

## ライセンス

MIT License - 自由にご利用・貢献してください
