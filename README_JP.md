<h4 align="right"><strong><a href="https://github.com/tw93/MiaoYan">English</a></strong> | <strong><a href="https://github.com/tw93/MiaoYan/blob/main/README_CN.md">简体中文</a></strong> | 日本語</h4>

<p align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://gw.alipayobjects.com/zos/k/t0/43.png" width="138" /></a>
  <h1 align="center">MiaoYan</h1>
  <div align="center">
    <a href="https://twitter.com/HiTw93" target="_blank">
      <img alt="Twitter フォロー" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
    <a href="https://t.me/+GclQS9ZnxyI2ODQ1" target="_blank">
      <img alt="Telegram グループ" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
    <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">
      <img alt="GitHub ダウンロード数" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/commits" target="_blank">
      <img alt="GitHub コミット活動" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank">
      <img alt="GitHub クローズ済み Issue" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
    <img alt="macOS 11.5+" src="https://img.shields.io/badge/macOS-11.5%2B-orange?style=flat-square">
  </div>
  <div align="center">軽量な macOS 向け Markdown ノートアプリ</div>
</p>

<img src="https://raw.githubusercontent.com/tw93/static/master/miaoyan/newmiaoyan.gif" width="900px" />

## 特徴

- **素晴らしい**: ローカルファースト、プライバシー重視、シンタックスハイライト、分割編集プレビュー、PPT モード、LaTeX、Mermaid 図表
- **美しい**: ミニマルデザイン、3カラムレイアウト、ダークモード、集中できる環境
- **高速**: Swift 6 ネイティブ、Electron アプリより高パフォーマンス
- **シンプル**: 軽量、キーボードショートカット、自動フォーマット

## インストール & セットアップ

1. [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) から最新の DMG パッケージをダウンロード(macOS 11.5+ 必要)
2. ダブルクリックして MiaoYan.app をアプリケーションフォルダにインストール
3. iCloud Drive またはお好みの場所に `MiaoYan` フォルダを作成
4. MiaoYan の環境設定を開き、保存場所をこのフォルダに設定
5. 左上の「新規フォルダ」アイコンをクリックして文書カテゴリを作成し、執筆を開始

## 分割編集プレビューモード

編集とプレビューを並べて表示し、リアルタイムプレビューと双方向スクロール同期を実現。環境設定 (⌘,) → エディタタブで有効化。

なぜ Typora のような WYSIWYG ではないのか？純粋な Markdown 編集体験を重視し、ネイティブ Swift での WYSIWYG 実装は過度に複雑で信頼性の懸念があります。分割モードは、クリーンな編集を維持しながら即時の視覚フィードバックを提供します。

<img src="https://cdn.tw93.fun/pic/1jZnC4.png" width="100%" alt="分割編集プレビューモード" />

## ドキュメント

- [Markdown 構文ガイド](Resources/Initial/MiaoYan%20Markdown%20Syntax%20Guide.md) - 高度な機能を含む完全な構文リファレンス
- [PPT プレゼンテーションモード](Resources/Initial/MiaoYan%20PPT.md) - `---` スライド区切りでプレゼンテーションを作成するガイド

## サポート

- MiaoYan がワークフローを改善した場合は、[プロジェクトのサポート](https://miaoyan.app/cats.html)をご検討ください
- GitHub でこのリポジトリにスターを付ける
- 他の人と [MiaoYan をシェア](https://twitter.com/intent/tweet?text=%23MiaoYan%20-%20macOS%20向けの軽量%20Markdown%20エディタ、ネイティブ%20Swift%20で構築、シンタックスハイライト、ダークモード、プレゼンテーションモードを搭載。&url=https://github.com/tw93/MiaoYan)
- [@HiTw93](https://twitter.com/HiTw93) をフォローして更新情報を入手、または [Telegram グループ](https://t.me/+GclQS9ZnxyI2ODQ1)に参加

## 謝辞

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - プロジェクト初期構造の参考
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift Markdown パーサー
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Markdown フォーマットユーティリティ
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - シンタックスハイライト
- [仓耳字库](https://tsanger.cn/product) - TsangerJinKai フォント(デフォルトフォント)
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT プレゼンテーションフレームワーク
- [Vercel](https://vercel.com?utm_source=tw93&utm_campaign=oss) - [miaoyan.app](https://miaoyan.app/) の静的ホスティング

## ライセンス

MIT License - 自由に使用・貢献してください
