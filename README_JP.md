<h4 align="right"><strong><a href="https://github.com/tw93/MiaoYan/blob/master/README_EN.md">English</a></strong> | <strong><a href="https://github.com/tw93/MiaoYan">中文</a></strong> | 日本語</h4>
<p align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src=https://gw.alipayobjects.com/zos/k/t0/43.png width=138 /></a>
  <h1 align="center">MiaoYan</h1>
  <div align="center">
    <a href="https://twitter.com/HiTw93" target="_blank">
       <img alt="twitter" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
    <a href="https://t.me/+GclQS9ZnxyI2ODQ1" target="_blank">
      <img alt="Telegram" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
     <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">
      <img alt="GitHub downloads" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/commits" target="_blank">
      <img alt="GitHub commit" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank">
      <img alt="GitHub closed issues" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
    <img alt="Minimum supported version" src="https://img.shields.io/badge/macOS-10.15%2B-orange?style=flat-square">
  </div>
  <div align="center">軽量のMarkdownアプリで、素晴らしい文章を生み出せます</div>
</p>

<img src="https://gw.alipayobjects.com/zos/k/xg/miaoyan.gif" width="900px">

## 機能

- 🏂 **素晴らしい**: ローカル利用、セキュリティ、シンタックスハイライト、ダークモード、ソースファイルの保存、国際化、プレゼンテーションモード、[スライド モード](#miaoYan-ppt)、単一編集モード、ファイルのエクスポート、内部ジャンプ、文書の自動タイプセット、画像のアップロード、LaTeX、Mermaid、PlantUML、Markmap。
- 🎊 **美しさ**: ミニマリストのデザインスタイル、フォルダ+ファイルリスト+エディタの 3 カラムモード。
- 🚄‍ **高速**: Swift5 ネイティブ開発を使用しており、Web と比較してパフォーマンス体験がはるかに良い。
- 🥛 **シンプル**: とても軽量で、純粋なエディタ入力体験、多くのショートカットキーで高速化が実現。

## 最初の使用

1. 最新の dmg インストールパッケージを<a href="https://github.com/tw93/MiaoYan/releases/latest" target="_blank">GitHub Releases</a>から**ダウンロード**し、ダブルクリックしてインストールします。macOS Big Sur 以上でより良い体験が得られます。また、`brew install miaoyan -- cask`でのインストールもサポートしています。
2. iCloud またはルートディレクトリに`MiaoYan`フォルダを作成し、MiaoYan の設定を開き、デフォルトの保存先をこれに変更します。
3. MiaoYan の左上隅にある新しいフォルダのアイコンをクリックして、独自のドキュメントカテゴリフォルダを作成し、使用を開始できます。
4. 同様に、デフォルトのフォントに慣れていない場合は、設定で他の通常のフォントに変更できます。

## ショートカットキー

#### ウィンドウ操作

- `command + 1`: フォルダリストの折りたたみを隠す
- `command + 2`: ドキュメントのリストを隠す
- `command + 3`: 編集状態とプレビュー状態の切り替え
- `command + 4`: 編集状態とプレゼンテーション状態の切り替え
- `command + option + m`: MiaoYanを表示/非表示

#### ファイル操作

- `command + n`：新規ドキュメント
- `command + r`：ドキュメントの名前変更
- `command + d`：ドキュメントのコピー
- `command + o`：ドキュメントを単体で開く
- `command + delete`：ドキュメントの削除
- `command + shift + n`：新規フォルダ
- `command + shift + l`：自動タイプセット
- `command + option + r`：Finder でドキュメントを表示
- `command + option + i`：単語数などのドキュメント属性を表示
- `command + option + p`：MiaoYan スライド プレビューを起動。

🏂 他にも多くのショートカットがあります 👆🏻 👇🏻 👈🏻 👉🏻 隠れているショートカットを見つけることに楽しんでください~

## MiaoYan スライド

<a href=https://gw.alipayobjects.com/zos/k/app3/ScreenFlow1.gif target="_blank"><img src="https://user-images.githubusercontent.com/8736212/180579489-a8ac6f0f-1d47-44fa-a8bb-0be998f7895f.gif" width="100%"></a>

1. 新しいユーザーさんのデフォルトの初期化はテンプレートを生成します。古いユーザーさんの場合は、1.0 にアップグレードしてから[このファイル](https://raw.githubusercontent.com/tw93/MiaoYan/master/Resources/Initial/MiaoYan%20PPT.md)を MiaoYan にコピーしてみてください。
2. `command + option + p`を実行して MiaoYan PPT プレビューを開始します。同時に、ドキュメントを選択し、右クリックして'MiaoYan PPT'を選択して開くこともできます。
3. PPT モードは`---`セパレータでマークされたドキュメントでのみ有効にできます。プレゼンテーション中には、`Enter`キーでスピーチのアウトラインをプレビューし、`ESC`キーで スライド モードを終了できます。
4. HTML を使用して効果をカスタマイズできます。より複雑な使用法については、[reveal](https://revealjs.com/markdown/)のドキュメンテーションを参照してください。

## なぜこれを作ったのか

- 私は以前に多くのノートアプリを試しました、例えば WizNote、Ulysses、Quiver、MWeb、Bear、Typora、様々な理由で、私は従来の Markdown アプリを見つけられませんでした、そこで MiaoYan を作るアイデアが生まれました。
- 私の仕事はフロントエンド開発ですが、iOS App も開発でき、新しいものをいじることも好きなので、MiaoYan を楽しみながら開発しました。

## サポート

- 私は2匹の猫を飼っています。一つは TangYuan という名前で、もう一つは Coke という名前です。もし MiaoYan があなたの生活をより良くできたと思ったら、私の猫に<a href="https://miaoyan.app/cats.html" target="_blank">缶詰のエサを 🥩🍤</a>あげてください。
- もしあなたが MiaoYan を気に入っていたら、Github でそれをスターしてくれたら嬉しいで。我々はあなたが同じ趣味の友人に[MiaoYan を推薦する](https://twitter.com/intent/tweet?text=%23%E5%A6%99%E8%A8%80%20MiaoYan%20-%20a%20simple%20and%20good-looking%20open-source%20mac%20markdown%20editor,%20without%20any%20redundant%20functions,%20is%20developed%20using%20swift,%20pure%20local%20use,%20has%20functions%20such%20as%20syntax%20highlighting,%20automatic%20formatting,%20presentation%20mode%20etc.&url=https://github.com/tw93/MiaoYan)ことをより歓迎します。
- あなたは私の[Twitter](https://twitter.com/HiTw93)をフォローして MiaoYan の最新ニュースを得るか、または[Telegram](https://t.me/+GclQS9ZnxyI2ODQ1)のチャットグループに参加することができます。

## 感謝

- <a href="https://github.com/KristopherGBaker/libcmark_gfm" target="_blank">KristopherGBaker/libcmark_gfm</a>: cmark-gfm 用の Swift 互換フレームワーク。
- <a href="https://github.com/raspu/Highlightr" target="_blank">raspu/Highlightr</a>: シンタックスハイライト機能。
- <a href="https://github.com/glushchenko/fsnotes" target="_blank">glushchenko/fsnotes</a>: MiaoYan はこのプロジェクトからフレームワークの一部のコードを持っています。
- <a href="https://github.com/lxgw/LxgwWenKai" target="_blank">lxgw/LxgwWenKai</a>: 美しいオープンソースの中国語フォント、MiaoYan はこれをデフォルトのフォントにしました。
- <a href="https://github.com/michaelhenry/Prettier.swift" target="_blank">michaelhenry/Prettier.swift</a>：MiaoYan のドキュメント自動タイプセットは Prettier から来ています。
- <a href="https://github.com/hakimel/reveal.js" target="_blank">hakimel/reveal.js</a>：オープンソースの HTML プレゼンテーションフレームワーク。
- Vercel に感謝します、[MiaoYan](https://miaoyan.app/)に静的レンダリング能力を提供してくれたため。  
   <a href="https://vercel.com?utm_source=tw93&utm_campaign=oss"><img
      src=https://gw.alipayobjects.com/zos/k/wr/powered-by-vercel.svg
      width="118px"/></a>

# ライセンス

- MIT ライセンスを遵守してください。
- オープンソースを楽しみ、参加することをお気軽にどうぞ。
