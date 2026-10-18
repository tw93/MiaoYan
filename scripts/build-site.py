#!/usr/bin/env python3
"""Build the MiaoYan home pages, one per language: / (English), /zh/, /tw/,
/ja/, /ko/, /de/, /fr/ and /es/.

One template and one copy table per language, so the pages cannot drift
apart. The languages are the README's seven plus Spanish, which the Mac app
ships. The output is committed; Vercel serves it as static files.

    python3 scripts/build-site.py
"""

import html
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_STORE = "https://apps.apple.com/app/id6759252269"
# A desktop browser in China loses the app on the region-less link (it lands
# on the /cn storefront home), so the Chinese page defaults to /cn. The script
# at the end swaps in the right link for iOS and the Mac.
APP_STORE_CN = "https://apps.apple.com/cn/app/id6759252269"
MAC_APP_STORE = "macappstore://apps.apple.com/app/id6759252269"
GITHUB = "https://github.com/tw93/MiaoYan"
SHOTS = ["edit", "preview", "split", "ppt", "dark"]

# key, path, html lang, menu name, short code (narrow nav), screenshot set
LANGS = [
    ("en", "/", "en", "English", "EN", "en"),
    ("zh", "/zh/", "zh-CN", "简体中文", "中", "zh"),
    ("tw", "/tw/", "zh-Hant", "繁體中文", "繁", "zh"),
    ("ja", "/ja/", "ja", "日本語", "日", "en"),
    ("ko", "/ko/", "ko", "한국어", "한", "en"),
    ("de", "/de/", "de", "Deutsch", "DE", "en"),
    ("fr", "/fr/", "fr", "Français", "FR", "en"),
    ("es", "/es/", "es", "Español", "ES", "en"),
]

EN_ALTS = {
    "edit": "MiaoYan editing a Markdown note with folders, a note list and syntax highlighting",
    "preview": "MiaoYan previewing a note with a table and a checklist",
    "split": "MiaoYan in split view with Markdown on the left and a rendered Mermaid diagram on the right",
    "ppt": "A MiaoYan note shown as a slide",
    "dark": "MiaoYan in dark mode editing Swift code",
}

COPY = {
    "en": {
        "title": "MiaoYan, Markdown notes for Mac, iPhone and iPad",
        "description": "MiaoYan is a native Markdown note app for Mac, iPhone and iPad. Your notes are plain Markdown files in a folder you choose.",
        "nav": ["Features", "iPhone & iPad", "FAQ"],
        "language": "Language",
        "nav_cta": "App Store",
        "h1": "MiaoYan",
        "tagline": "Local Markdown notes on Mac, iPhone and iPad",
        "lede": "MiaoYan is 妙言 in Chinese, words beyond words.",
        "trust": ["One purchase for Mac, iPhone and iPad", "Local Markdown files", "Open source on GitHub", "macOS 12 / iOS 18+"],
        "cta": ("Get it on the App Store", "Source code"),
        "gallery_title": "Write, read and present",
        "gallery_lede": "Edit plain Markdown, switch to a typeset preview, work side by side, or turn a note into slides.",
        "tabs": {"edit": "Edit", "preview": "Preview", "split": "Split", "ppt": "Present", "dark": "Dark"},
        "captions": {
            "edit": "Plain Markdown with syntax highlighting, so headings, links and code stand apart",
            "preview": "Images, tables and code rendered the way they will be read",
            "split": "Write on the left and see it on the right, Mermaid diagrams included",
            "ppt": "Split a note with --- and it becomes a slide deck",
            "dark": "Dark mode follows the system",
        },
        "alts": EN_ALTS,
        "devices_title": "On iPhone and iPad",
        "devices_lede": "The same App Store purchase runs on iPhone and iPad, opening the same iCloud Drive folder as your Mac.",
        "devices_cta": "Get it on the App Store",
        "device_alts": ("MiaoYan on iPhone reading a note", "MiaoYan on iPad showing a note with a diagram"),
        "features_title": "Why MiaoYan",
        "features": [
            ("Local-first", "Your Markdown files stay in a folder you choose. MiaoYan does not collect note data; iCloud Drive, Nutstore, or another file-sync client can handle cross-device sync."),
            ("Focused", "A clear three-column layout keeps folders, notes, and writing together. Dark mode, distraction-free writing, and keyboard shortcuts are built in without a plugin system to maintain."),
            ("Native", "Built natively with Swift 6 instead of Electron. Split mode pairs real-time preview with 60fps bidirectional scroll sync for focused Markdown editing."),
            ("Capable", "Wikilinks and backlinks, LaTeX, Mermaid, version history, auto-formatting, a CLI, and Markdown presentations cover the work around writing."),
        ],
        "compare_title": "Who MiaoYan is for",
        "compare": [
            ("Compared with Typora", "MiaoYan keeps pure Markdown editing and a separate preview instead of WYSIWYG. It fits people who want direct control of source files with immediate visual feedback."),
            ("Compared with Obsidian", "MiaoYan has no Electron runtime and is not centered on a plugin ecosystem. It fits people who prefer a native, lightweight app with local files and focused built-in features."),
        ],
        "faq_title": "Questions",
        "faq": [
            ("Is it a one-time purchase or a subscription?", "A one-time purchase with lifetime access, no subscriptions or in-app purchases. One purchase covers your Mac, iPhone and iPad on the same Apple account."),
            ("Which version should I get?", "The App Store version. One purchase covers Mac, iPhone and iPad, they all open the same iCloud Drive folder, and updates arrive on their own. The Mac app's source code is open on GitHub."),
            ("Where are my notes stored?", "In the folder you choose, as plain .md files. MiaoYan does not collect note data, and if you ever switch tools the folder comes with you."),
            ("How do notes sync across Mac, iPhone and iPad?", "Keep the folder in iCloud Drive and the Mac, iPhone and iPad all open the same notes. On the Mac, Nutstore or another file-sync client works too."),
            ("What Markdown does it support?", "GitHub Flavored Markdown, plus LaTeX, Mermaid, PlantUML and Markmap, wikilinks with backlinks, and slides split with ---."),
            ("What do I need to run it?", "macOS 12 or later on the Mac, and iOS 18 or iPadOS 18 or later on iPhone and iPad."),
        ],
        "about": "Tw93 designs, builds and maintains MiaoYan.",
        "foot": (("Get", "Help", "Connect"), ("FAQ", "Privacy")),
    },
    "zh": {
        "title": "妙言 MiaoYan，Mac、iPhone 和 iPad 上的 Markdown 笔记",
        "description": "妙言是原生的 Markdown 笔记应用，笔记就是你选定文件夹里的 Markdown 文件，Mac、iPhone 和 iPad 都能打开。",
        "nav": ["功能", "多端体验", "常见问题"],
        "language": "语言",
        "nav_cta": "App Store",
        "h1": "妙言",
        "tagline": "轻灵的 Markdown 笔记本，伴你写出妙言",
        "lede": "原生 Markdown 笔记应用，文件保存在本地文件夹，通过 iCloud 云盘即可在 Mac、iPhone 与 iPad 间同步。",
        "trust": ["一次购买覆盖三端", "纯本地 Markdown", "Mac 版开源透明", "macOS 12 / iOS 18+"],
        "cta": ("在 App Store 获取", "查看源码"),
        "gallery_title": "书写、排版与演示",
        "gallery_lede": "纯 Markdown 专注书写，切到预览看排版，分栏一边写一边看，一篇笔记还能直接变成幻灯片。",
        "tabs": {"edit": "编辑", "preview": "预览", "split": "分栏", "ppt": "演示", "dark": "深色"},
        "captions": {
            "edit": "纯 Markdown 编辑，标题、链接与代码各有色彩，层次分明",
            "preview": "排版如书，图片、表格和代码按最终阅读形态呈现",
            "split": "左边写右边实时预览，60fps 双向滚动与 Mermaid 流程图随手即得",
            "ppt": "用 --- 分页，同一篇笔记瞬间化作精美幻灯片",
            "dark": "跟随系统昼夜轮转，专为夜间书写调校的暖调深色",
        },
        "alts": {
            "edit": "妙言编辑一篇 Markdown 笔记，左侧是文件夹和笔记列表",
            "preview": "妙言预览一期周刊，带封面图和链接",
            "split": "妙言分栏模式，左边是 Markdown，右边是渲染好的流程图",
            "ppt": "妙言把一篇笔记展示成幻灯片",
            "dark": "妙言深色模式下编辑 Swift 代码",
        },
        "devices_title": "iPhone 和 iPad",
        "devices_lede": "一次 App Store 购买，Mac、iPhone 与 iPad 通用，直接打开同一个 iCloud 云盘笔记文件夹。",
        "devices_cta": "在 App Store 获取",
        "device_alts": ("妙言在 iPhone 上阅读笔记", "妙言在 iPad 上显示带流程图的笔记"),
        "features_title": "为什么选择妙言",
        "features": [
            ("本地", "Markdown 文件保存在你选择的本地文件夹，不收集笔记数据。跨设备时，可交给 iCloud 云盘、坚果云或你熟悉的文件同步工具。"),
            ("专注", "三栏经典布局将目录、笔记与编辑器融为一体。支持深色模式、无干扰写作和常用快捷键，无需维护复杂插件系统。"),
            ("原生", "使用 Swift 6 原生开发，不依赖 Electron。分栏模式提供实时预览与 60fps 双向滚动同步，丝滑跟手。"),
            ("称手", "内置双向链接与反向链接、LaTeX 公式、Mermaid 图表、版本历史、自动排版与命令行工具，也能一键开启幻灯片演示。"),
        ],
        "compare_title": "妙言适合谁",
        "compare": [
            ("和 Typora 相比", "妙言不做所见即所得编辑，而是保留纯 Markdown 源码编辑与独立预览。更适合希望直接掌控源文件，又需要即时预览的人。"),
            ("和 Obsidian 相比", "妙言没有 Electron 运行时，也不以插件生态为中心。更适合想要原生、轻量、纯本地文件和开箱即用核心功能的人。"),
        ],
        "faq_title": "常见问题",
        "faq": [
            ("是买断制还是订阅制？", "一次性买断，终身使用，没有订阅或内购。同一次购买可在登录同一 Apple 账户的 Mac、iPhone 和 iPad 上完整使用。"),
            ("该装哪个版本？", "推荐 App Store 版：一次购买覆盖 Mac、iPhone 和 iPad，通过 iCloud 云盘无缝同步，且自动更新。Mac 版源码在 GitHub 开源透明。"),
            ("笔记存在哪里？", "就在你选定的文件夹里，每篇都是普通的 .md 文件，妙言不收集笔记数据，以后换工具时整个文件夹带走就行。"),
            ("Mac、iPhone 和 iPad 之间怎么同步？", "把笔记文件夹放在 iCloud 云盘里，Mac、iPhone 和 iPad 打开的就是同一份笔记，Mac 上也可以用坚果云等文件同步工具。"),
            ("支持哪些 Markdown 语法？", "GitHub 风格的 Markdown，加上 LaTeX 公式、Mermaid、PlantUML 和 Markmap 图表、双向链接，以及用 --- 分页的演示模式。"),
            ("需要什么系统？", "Mac 需要 macOS 12 及以上，iPhone 和 iPad 分别需要 iOS 18 与 iPadOS 18 及以上。"),
        ],
        "about": "Tw93，妙言的主理人，负责设计、开发和维护。",
        "foot": (("获取", "帮助", "联系"), ("常见问题", "隐私政策")),
    },
    "tw": {
        "title": "妙言 MiaoYan，Mac、iPhone 和 iPad 上的 Markdown 筆記",
        "description": "妙言是原生的 Markdown 筆記 App，筆記就是你選定檔案夾裡的 Markdown 檔案，Mac、iPhone 和 iPad 都能打開。",
        "nav": ["功能", "多端體驗", "常見問題"],
        "language": "語言",
        "nav_cta": "App Store",
        "h1": "妙言",
        "tagline": "輕靈的 Markdown 筆記本，伴你寫出妙言",
        "lede": "原生 Markdown 筆記 App，檔案儲存在本機檔案夾，透過 iCloud 雲碟即可在 Mac、iPhone 與 iPad 間同步。",
        "trust": ["一次購買覆蓋三端", "純本地 Markdown", "Mac 版開源透明", "macOS 12 / iOS 18+"],
        "cta": ("在 App Store 取得", "查看原始碼"),
        "gallery_title": "書寫、排版與簡報",
        "gallery_lede": "純 Markdown 專注書寫，切到預覽看排版，分欄一邊寫一邊看，一篇筆記還能直接變成投影片。",
        "tabs": {"edit": "編輯", "preview": "預覽", "split": "分欄", "ppt": "簡報", "dark": "深色"},
        "captions": {
            "edit": "純 Markdown 編輯，標題、連結與程式碼各有色彩，層次分明",
            "preview": "排版如書，圖片、表格和程式碼按最終閱讀形態呈現",
            "split": "左邊寫右邊即時預覽，60fps 雙向捲動與 Mermaid 流程圖隨手即得",
            "ppt": "用 --- 分頁，同一篇筆記瞬間化作精美投影片",
            "dark": "跟隨系統晝夜輪轉，專為夜間書寫調校的暖調深色",
        },
        "alts": {
            "edit": "妙言編輯一篇 Markdown 筆記，左側是檔案夾和筆記列表",
            "preview": "妙言預覽一期週刊，帶封面圖和連結",
            "split": "妙言分欄模式，左邊是 Markdown，右邊是繪製好的流程圖",
            "ppt": "妙言把一篇筆記展示成投影片",
            "dark": "妙言深色模式下編輯 Swift 程式碼",
        },
        "devices_title": "iPhone 和 iPad",
        "devices_lede": "一次 App Store 購買，Mac、iPhone 與 iPad 通用，直接打開同一個 iCloud 雲碟筆記檔案夾。",
        "devices_cta": "在 App Store 取得",
        "device_alts": ("妙言在 iPhone 上閱讀筆記", "妙言在 iPad 上顯示帶流程圖的筆記"),
        "features_title": "為什麼選擇妙言",
        "features": [
            ("本地", "Markdown 檔案保存在你選擇的本機檔案夾，不收集筆記資料。跨裝置時，可交給 iCloud 雲碟、堅果雲或你熟悉的檔案同步工具。"),
            ("專注", "三欄經典佈局將目錄、筆記與編輯器融為一體。支援深色模式、無干擾寫作和常用快捷鍵，無需維護複雜外掛系統。"),
            ("原生", "使用 Swift 6 原生開發，不依賴 Electron。分欄模式提供即時預覽與 60fps 雙向捲動同步，絲滑跟手。"),
            ("稱手", "內建雙向連結與反向連結、LaTeX 公式、Mermaid 圖表、版本歷史、自動排版與命令列工具，也能一鍵開啟投影片簡報。"),
        ],
        "compare_title": "妙言適合誰",
        "compare": [
            ("和 Typora 相比", "妙言不做所見即所得編輯，而是保留純 Markdown 原始檔編輯與獨立預覽。更適合希望直接掌控原始檔，又需要即時預覽的人。"),
            ("和 Obsidian 相比", "妙言沒有 Electron 執行環境，也不以外掛生態為中心。更適合想要原生、輕量、純本地檔案和開箱即用核心功能的人。"),
        ],
        "faq_title": "常見問題",
        "faq": [
            ("是買斷制還是訂閱制？", "一次性買斷，終身使用，沒有訂閱或內購。同一次購買可在登入同一 Apple 帳號的 Mac、iPhone 和 iPad 上完整使用。"),
            ("該裝哪個版本？", "推薦 App Store 版：一次購買覆蓋 Mac、iPhone 和 iPad，透過 iCloud 雲碟無縫同步，且自動更新。Mac 版原始碼在 GitHub 開源透明。"),
            ("筆記存在哪裡？", "就在你選定的檔案夾裡，每篇都是普通的 .md 檔案，妙言不收集筆記資料，以後換工具時整個檔案夾帶走就行。"),
            ("Mac、iPhone 和 iPad 之間怎麼同步？", "把筆記檔案夾放在 iCloud 雲碟裡，Mac、iPhone 和 iPad 打開的就是同一份筆記，Mac 上也可以用堅果雲等檔案同步工具。"),
            ("支援哪些 Markdown 語法？", "GitHub 風格的 Markdown，加上 LaTeX 公式、Mermaid、PlantUML 和 Markmap 圖表、雙向連結，以及用 --- 分頁的簡報模式。"),
            ("需要什麼系統？", "Mac 需要 macOS 12 以上，iPhone 和 iPad 分別需要 iOS 18 與 iPadOS 18 以上。"),
        ],
        "about": "Tw93，妙言的主理人，負責設計、開發和維護。",
        "foot": (("取得", "說明", "聯絡"), ("常見問題", "隱私權政策")),
    },
    "ja": {
        "title": "MiaoYan、Mac・iPhone・iPadのためのMarkdownノート",
        "description": "MiaoYanはネイティブのMarkdownノートアプリです。ノートは自分で選んだフォルダにあるMarkdownファイルで、Mac、iPhone、iPadのどれからでも開けます。",
        "nav": ["機能", "iPhoneとiPad", "よくある質問"],
        "language": "言語",
        "nav_cta": "App Store",
        "h1": "MiaoYan",
        "tagline": "Mac、iPhone、iPadで使えるローカルのMarkdownノート",
        "lede": "MiaoYanは中国語の妙言、言葉を超えた言葉という意味です。",
        "trust": ["一度の購入でMac・iPhone・iPad", "ローカルのMarkdown", "GitHubでオープンソース", "macOS 12 / iOS 18以降"],
        "cta": ("App Storeで入手", "ソースコード"),
        "gallery_title": "書く、読む、プレゼンする",
        "gallery_lede": "素のMarkdownで書き、プレビューで組版を確かめ、分割表示で並べて作業し、ノートをそのままスライドにできます。",
        "tabs": {"edit": "編集", "preview": "プレビュー", "split": "分割", "ppt": "プレゼン", "dark": "ダーク"},
        "captions": {
            "edit": "シンタックスハイライト付きの素のMarkdownで、見出し、リンク、コードがひと目で区別できます",
            "preview": "画像、表、コードを読まれるときと同じ姿で表示します",
            "split": "左で書いて右で確認、Mermaidの図もそのまま描画されます",
            "ppt": "---で区切ればノートがスライドになります",
            "dark": "ダークモードはシステムに合わせて切り替わります",
        },
        "alts": {
            "edit": "フォルダ、ノート一覧、シンタックスハイライトとともにMarkdownノートを編集するMiaoYan",
            "preview": "表とチェックリストのあるノートをプレビューするMiaoYan",
            "split": "左にMarkdown、右に描画されたMermaid図を並べたMiaoYanの分割表示",
            "ppt": "スライドとして表示したMiaoYanのノート",
            "dark": "ダークモードでSwiftのコードを編集するMiaoYan",
        },
        "devices_title": "iPhoneとiPad",
        "devices_lede": "同じApp Storeの購入でiPhoneとiPadでも使え、Macと同じiCloud Driveフォルダを開きます。",
        "devices_cta": "App Storeで入手",
        "device_alts": ("iPhoneでノートを読むMiaoYan", "iPadで図入りのノートを表示するMiaoYan"),
        "features_title": "MiaoYanを選ぶ理由",
        "features": [
            ("ローカルファースト", "Markdownファイルは自分で選んだフォルダに保存され、MiaoYanはノートのデータを集めません。デバイス間の同期はiCloud DriveやNutstoreなどのファイル同期ツールに任せられます。"),
            ("集中", "フォルダ、ノート一覧、エディタの3ペイン構成で、書くのに必要なものがひとつの画面に揃います。ダークモード、集中して書ける画面、キーボードショートカットを内蔵し、管理するプラグインはありません。"),
            ("ネイティブ", "ElectronではなくSwift 6でネイティブに開発しています。分割モードはリアルタイムプレビューと60fpsの双方向スクロール同期で、Markdownの編集に集中できます。"),
            ("必要十分", "双方向リンクとバックリンク、LaTeX、Mermaid、バージョン履歴、自動整形、CLI、Markdownプレゼンテーションで、書くまわりの作業もこなせます。"),
        ],
        "compare_title": "MiaoYanが向いている人",
        "compare": [
            ("Typoraと比べると", "MiaoYanはWYSIWYGではなく、素のMarkdown編集と独立したプレビューを保っています。ソースファイルを直接扱いながら、すぐに見た目も確かめたい人に向いています。"),
            ("Obsidianと比べると", "MiaoYanはElectronを使わず、プラグインのエコシステムを中心にもしていません。ローカルファイルと絞り込んだ内蔵機能で、ネイティブで軽いアプリを求める人に向いています。"),
        ],
        "faq_title": "よくある質問",
        "faq": [
            ("買い切りですか、サブスクリプションですか？", "サブスクリプションやアプリ内課金のない、一度の買い切りです。同じAppleアカウントのMac、iPhone、iPadでそのまま使えます。"),
            ("どのバージョンを入れればいいですか？", "App Store版がおすすめです。一度の購入でMac、iPhone、iPadのすべてで使え、どれも同じiCloud Driveフォルダを開き、アップデートも自動です。Mac版のソースコードはGitHubで公開しています。"),
            ("ノートはどこに保存されますか？", "自分で選んだフォルダに、普通の.mdファイルとして保存されます。MiaoYanはノートのデータを集めず、ほかのツールに移るときもフォルダごと持っていけます。"),
            ("Mac、iPhone、iPadの間でどう同期しますか？", "フォルダをiCloud Driveに置けば、Mac、iPhone、iPadが同じノートを開きます。MacではNutstoreなどのファイル同期ツールも使えます。"),
            ("どんなMarkdownに対応していますか？", "GitHub Flavored Markdownに加えて、LaTeX、Mermaid、PlantUML、Markmap、双方向リンクとバックリンク、---で区切るスライドに対応しています。"),
            ("動作環境は？", "MacはmacOS 12以降、iPhoneとiPadはiOS 18またはiPadOS 18以降が必要です。"),
        ],
        "about": "Tw93がMiaoYanのデザイン、開発、メンテナンスをしています。",
        "foot": (("入手", "ヘルプ", "連絡先"), ("よくある質問", "プライバシー")),
    },
    "ko": {
        "title": "MiaoYan, Mac·iPhone·iPad를 위한 마크다운 노트",
        "description": "MiaoYan은 네이티브 마크다운 노트 앱입니다. 노트는 직접 고른 폴더 안의 마크다운 파일이며, Mac, iPhone, iPad 어디서든 열 수 있습니다.",
        "nav": ["기능", "iPhone과 iPad", "자주 묻는 질문"],
        "language": "언어",
        "nav_cta": "App Store",
        "h1": "MiaoYan",
        "tagline": "Mac, iPhone, iPad에서 쓰는 로컬 마크다운 노트",
        "lede": "MiaoYan은 중국어 妙言에서 온 이름으로, 말을 넘어선 말이라는 뜻입니다.",
        "trust": ["한 번 구매로 Mac·iPhone·iPad", "로컬 마크다운 파일", "GitHub 오픈 소스", "macOS 12 / iOS 18 이상"],
        "cta": ("App Store에서 받기", "소스 코드"),
        "gallery_title": "쓰고, 읽고, 발표하기",
        "gallery_lede": "순수 마크다운으로 쓰고, 미리보기로 조판을 확인하고, 분할 화면에서 나란히 작업하거나, 노트를 그대로 슬라이드로 바꿀 수 있습니다.",
        "tabs": {"edit": "편집", "preview": "미리보기", "split": "분할", "ppt": "발표", "dark": "다크"},
        "captions": {
            "edit": "구문 강조가 적용된 순수 마크다운으로 제목, 링크, 코드가 한눈에 구분됩니다",
            "preview": "이미지, 표, 코드를 실제 읽는 모습 그대로 보여 줍니다",
            "split": "왼쪽에서 쓰고 오른쪽에서 확인하며, Mermaid 다이어그램도 바로 그려집니다",
            "ppt": "---로 나누면 노트가 슬라이드가 됩니다",
            "dark": "다크 모드는 시스템 설정을 따릅니다",
        },
        "alts": {
            "edit": "폴더, 노트 목록, 구문 강조와 함께 마크다운 노트를 편집하는 MiaoYan",
            "preview": "표와 체크리스트가 있는 노트를 미리 보는 MiaoYan",
            "split": "왼쪽에 마크다운, 오른쪽에 렌더링된 Mermaid 다이어그램이 있는 MiaoYan 분할 화면",
            "ppt": "슬라이드로 표시된 MiaoYan 노트",
            "dark": "다크 모드에서 Swift 코드를 편집하는 MiaoYan",
        },
        "devices_title": "iPhone과 iPad",
        "devices_lede": "같은 App Store 구매로 iPhone과 iPad에서도 쓸 수 있고, Mac과 같은 iCloud Drive 폴더를 엽니다.",
        "devices_cta": "App Store에서 받기",
        "device_alts": ("iPhone에서 노트를 읽는 MiaoYan", "iPad에서 다이어그램이 있는 노트를 보여 주는 MiaoYan"),
        "features_title": "MiaoYan을 쓰는 이유",
        "features": [
            ("로컬 우선", "마크다운 파일은 직접 고른 폴더에 저장되고, MiaoYan은 노트 데이터를 수집하지 않습니다. 기기 간 동기화는 iCloud Drive나 Nutstore 같은 파일 동기화 도구에 맡기면 됩니다."),
            ("집중", "폴더, 노트 목록, 편집기로 이루어진 3단 구성으로 쓰는 데 필요한 것이 한 화면에 모입니다. 다크 모드, 방해 없는 글쓰기, 키보드 단축키가 들어 있고 관리할 플러그인은 없습니다."),
            ("네이티브", "Electron이 아닌 Swift 6으로 만든 네이티브 앱입니다. 분할 모드는 실시간 미리보기와 60fps 양방향 스크롤 동기화로 마크다운 편집에 집중하게 해 줍니다."),
            ("충분한 기능", "양방향 링크와 백링크, LaTeX, Mermaid, 버전 기록, 자동 서식, CLI, 마크다운 프레젠테이션으로 글쓰기에 필요한 부가 작업까지 두루 뒷받침합니다."),
        ],
        "compare_title": "MiaoYan이 맞는 사람",
        "compare": [
            ("Typora와 비교하면", "MiaoYan은 WYSIWYG 대신 순수 마크다운 편집과 별도의 미리보기를 유지합니다. 원본 파일을 직접 다루면서 결과도 바로 보고 싶은 사람에게 맞습니다."),
            ("Obsidian과 비교하면", "MiaoYan은 Electron을 쓰지 않고, 플러그인 생태계를 중심에 두지도 않습니다. 로컬 파일과 꼭 필요한 내장 기능을 갖춘 가벼운 네이티브 앱을 원하는 사람에게 맞습니다."),
        ],
        "faq_title": "자주 묻는 질문",
        "faq": [
            ("일회성 구매인가요, 구독제인가요?", "구독이나 인앱 결제가 없는 일회성 구매입니다. 동일한 Apple 계정의 Mac, iPhone, iPad에서 모두 사용할 수 있습니다."),
            ("어떤 버전을 설치하면 되나요?", "App Store 버전을 추천합니다. 한 번 구매로 Mac, iPhone, iPad에서 모두 쓸 수 있고, 모두 같은 iCloud Drive 폴더를 열며 업데이트도 자동입니다. Mac 앱의 소스 코드는 GitHub에 공개되어 있습니다."),
            ("노트는 어디에 저장되나요?", "직접 고른 폴더에 일반 .md 파일로 저장됩니다. MiaoYan은 노트 데이터를 수집하지 않으며, 다른 도구로 옮길 때도 폴더째 가져가면 됩니다."),
            ("Mac, iPhone, iPad 사이에서 어떻게 동기화하나요?", "폴더를 iCloud Drive에 두면 Mac, iPhone, iPad가 같은 노트를 엽니다. Mac에서는 Nutstore 같은 파일 동기화 도구도 쓸 수 있습니다."),
            ("어떤 마크다운을 지원하나요?", "GitHub Flavored Markdown과 함께 LaTeX, Mermaid, PlantUML, Markmap, 양방향 링크와 백링크, ---로 나누는 슬라이드를 지원합니다."),
            ("실행 환경은 어떻게 되나요?", "Mac은 macOS 12 이상, iPhone과 iPad는 iOS 18 또는 iPadOS 18 이상이 필요합니다."),
        ],
        "about": "Tw93이 MiaoYan의 디자인, 개발, 유지 관리를 맡고 있습니다.",
        "foot": (("받기", "도움말", "연락"), ("자주 묻는 질문", "개인정보 처리방침")),
    },
    "de": {
        "title": "MiaoYan, Markdown-Notizen für Mac, iPhone und iPad",
        "description": "MiaoYan ist eine native Markdown-Notiz-App für Mac, iPhone und iPad. Deine Notizen sind einfache Markdown-Dateien in einem Ordner deiner Wahl.",
        "nav": ["Funktionen", "iPhone & iPad", "FAQ"],
        "language": "Sprache",
        "nav_cta": "App Store",
        "h1": "MiaoYan",
        "tagline": "Lokale Markdown-Notizen auf Mac, iPhone und iPad",
        "lede": "MiaoYan ist das chinesische 妙言, Worte jenseits der Worte.",
        "trust": ["Ein Kauf für Mac, iPhone und iPad", "Lokale Markdown-Dateien", "Open Source auf GitHub", "macOS 12 / iOS 18+"],
        "cta": ("Im App Store laden", "Quellcode"),
        "gallery_title": "Schreiben, lesen, präsentieren",
        "gallery_lede": "Schreib reines Markdown, wechsle zur gesetzten Vorschau, arbeite Seite an Seite oder mach aus einer Notiz eine Präsentation.",
        "tabs": {"edit": "Bearbeiten", "preview": "Vorschau", "split": "Geteilt", "ppt": "Präsentieren", "dark": "Dunkel"},
        "captions": {
            "edit": "Reines Markdown mit Syntaxhervorhebung, damit sich Überschriften, Links und Code abheben",
            "preview": "Bilder, Tabellen und Code so dargestellt, wie sie gelesen werden",
            "split": "Links schreiben, rechts sehen, Mermaid-Diagramme inklusive",
            "ppt": "Teile eine Notiz mit --- und sie wird zur Präsentation",
            "dark": "Der Dark Mode folgt dem System",
        },
        "alts": {
            "edit": "MiaoYan beim Bearbeiten einer Markdown-Notiz mit Ordnern, Notizliste und Syntaxhervorhebung",
            "preview": "MiaoYan zeigt die Vorschau einer Notiz mit Tabelle und Checkliste",
            "split": "MiaoYan in der geteilten Ansicht mit Markdown links und gerendertem Mermaid-Diagramm rechts",
            "ppt": "Eine MiaoYan-Notiz als Folie",
            "dark": "MiaoYan im Dark Mode beim Bearbeiten von Swift-Code",
        },
        "devices_title": "Auf iPhone und iPad",
        "devices_lede": "Derselbe App-Store-Kauf läuft auf iPhone und iPad und öffnet denselben iCloud-Drive-Ordner wie dein Mac.",
        "devices_cta": "Im App Store laden",
        "device_alts": ("MiaoYan auf dem iPhone beim Lesen einer Notiz", "MiaoYan auf dem iPad mit einer Notiz samt Diagramm"),
        "features_title": "Warum MiaoYan",
        "features": [
            ("Lokal zuerst", "Deine Markdown-Dateien bleiben in einem Ordner deiner Wahl. MiaoYan erfasst keine Notizdaten; iCloud Drive, Nutstore oder ein anderer Sync-Client gleicht sie zwischen Geräten ab."),
            ("Fokussiert", "Ordner, Notizen und Editor in drei klaren Spalten. Dark Mode, ablenkungsfreies Schreiben und Tastaturkürzel sind eingebaut, ohne Plugin-System, das gepflegt werden muss."),
            ("Nativ", "Nativ mit Swift 6 statt Electron gebaut. Der geteilte Modus verbindet Echtzeitvorschau mit synchronem Scrollen in beide Richtungen bei 60 fps."),
            ("Gut ausgestattet", "Wikilinks und Backlinks, LaTeX, Mermaid, Versionsverlauf, automatische Formatierung, eine CLI und Markdown-Präsentationen decken die Arbeit rund ums Schreiben ab."),
        ],
        "compare_title": "Für wen MiaoYan gedacht ist",
        "compare": [
            ("Im Vergleich zu Typora", "MiaoYan setzt auf reines Markdown mit separater Vorschau statt WYSIWYG. Das passt zu allen, die ihre Quelldateien direkt in der Hand behalten und das Ergebnis trotzdem sofort sehen wollen."),
            ("Im Vergleich zu Obsidian", "MiaoYan läuft ohne Electron und dreht sich nicht um ein Plugin-Ökosystem. Das passt zu allen, die eine native, leichte App mit lokalen Dateien und gezielten integrierten Funktionen bevorzugen."),
        ],
        "faq_title": "Fragen",
        "faq": [
            ("Ist es ein Einmalkauf oder ein Abo?", "Ein einmaliger Kauf mit lebenslangem Zugriff, ohne Abo oder In-App-Käufe. Derselbe Kauf gilt für Mac, iPhone und iPad mit demselben Apple-Account."),
            ("Welche Version soll ich nehmen?", "Die App-Store-Version. Ein Kauf gilt für Mac, iPhone und iPad, alle öffnen denselben iCloud-Drive-Ordner, und Updates kommen automatisch. Der Quellcode der Mac-App liegt offen auf GitHub."),
            ("Wo werden meine Notizen gespeichert?", "In dem Ordner, den du wählst, als einfache .md-Dateien. MiaoYan erfasst keine Notizdaten, und wenn du das Werkzeug wechselst, nimmst du den Ordner einfach mit."),
            ("Wie werden Notizen zwischen Mac, iPhone und iPad abgeglichen?", "Leg den Ordner in iCloud Drive, dann öffnen Mac, iPhone und iPad dieselben Notizen. Auf dem Mac funktioniert auch Nutstore oder ein anderer Sync-Client."),
            ("Welches Markdown wird unterstützt?", "GitHub Flavored Markdown, dazu LaTeX, Mermaid, PlantUML und Markmap, Wikilinks mit Backlinks sowie Folien, die mit --- getrennt werden."),
            ("Was brauche ich dafür?", "macOS 12 oder neuer auf dem Mac sowie iOS 18 bzw. iPadOS 18 oder neuer auf iPhone und iPad."),
        ],
        "about": "Tw93 gestaltet, entwickelt und pflegt MiaoYan.",
        "foot": (("Laden", "Hilfe", "Kontakt"), ("FAQ", "Datenschutz")),
    },
    "fr": {
        "title": "MiaoYan, des notes Markdown pour Mac, iPhone et iPad",
        "description": "MiaoYan est une app native de notes Markdown pour Mac, iPhone et iPad. Vos notes sont de simples fichiers Markdown dans le dossier de votre choix.",
        "nav": ["Fonctionnalités", "iPhone et iPad", "FAQ"],
        "language": "Langue",
        "nav_cta": "App Store",
        "h1": "MiaoYan",
        "tagline": "Des notes Markdown locales sur Mac, iPhone et iPad",
        "lede": "MiaoYan vient du chinois 妙言, des mots au-delà des mots.",
        "trust": ["Un achat pour Mac, iPhone et iPad", "Fichiers Markdown locaux", "Open source sur GitHub", "macOS 12 / iOS 18+"],
        "cta": ("Télécharger sur l'App Store", "Code source"),
        "gallery_title": "Écrire, lire, présenter",
        "gallery_lede": "Écrivez en Markdown pur, passez à un aperçu mis en page, travaillez côte à côte ou transformez une note en diaporama.",
        "tabs": {"edit": "Édition", "preview": "Aperçu", "split": "Côte à côte", "ppt": "Présentation", "dark": "Sombre"},
        "captions": {
            "edit": "Du Markdown pur avec coloration syntaxique, pour distinguer titres, liens et code",
            "preview": "Images, tableaux et code rendus tels qu'ils seront lus",
            "split": "Écrivez à gauche, voyez le résultat à droite, diagrammes Mermaid compris",
            "ppt": "Séparez une note avec --- et elle devient un diaporama",
            "dark": "Le mode sombre suit le système",
        },
        "alts": {
            "edit": "MiaoYan éditant une note Markdown avec dossiers, liste de notes et coloration syntaxique",
            "preview": "MiaoYan affichant l'aperçu d'une note avec un tableau et une liste de tâches",
            "split": "MiaoYan en vue partagée, le Markdown à gauche et un diagramme Mermaid rendu à droite",
            "ppt": "Une note MiaoYan affichée en diapositive",
            "dark": "MiaoYan en mode sombre éditant du code Swift",
        },
        "devices_title": "Sur iPhone et iPad",
        "devices_lede": "Le même achat App Store fonctionne sur iPhone et iPad et ouvre le même dossier iCloud Drive que votre Mac.",
        "devices_cta": "Télécharger sur l'App Store",
        "device_alts": ("MiaoYan sur iPhone affichant une note", "MiaoYan sur iPad affichant une note avec un diagramme"),
        "features_title": "Pourquoi MiaoYan",
        "features": [
            ("Local d'abord", "Vos fichiers Markdown restent dans le dossier de votre choix. MiaoYan ne collecte aucune donnée de vos notes ; iCloud Drive, Nutstore ou un autre client de synchronisation s'occupe des autres appareils."),
            ("Épuré", "Dossiers, notes et éditeur sur trois colonnes claires. Mode sombre, écriture sans distraction et raccourcis clavier sont intégrés, sans système d'extensions à entretenir."),
            ("Natif", "Développé nativement en Swift 6 plutôt qu'avec Electron. Le mode partagé associe aperçu en temps réel et défilement synchronisé à 60 fps dans les deux sens."),
            ("Bien équipé", "Wikilinks et rétroliens, LaTeX, Mermaid, historique des versions, mise en forme automatique, une CLI et des présentations Markdown couvrent tout ce qui entoure l'écriture."),
        ],
        "compare_title": "À qui s'adresse MiaoYan",
        "compare": [
            ("Par rapport à Typora", "MiaoYan garde l'édition en Markdown pur et un aperçu séparé plutôt que le WYSIWYG. Il convient à ceux qui veulent garder la main sur leurs fichiers source tout en voyant tout de suite le résultat."),
            ("Par rapport à Obsidian", "MiaoYan n'utilise pas Electron et ne tourne pas autour d'un écosystème d'extensions. Il convient à ceux qui préfèrent une app native et légère, avec des fichiers locaux et des fonctions intégrées bien choisies."),
        ],
        "faq_title": "Questions",
        "faq": [
            ("S'agit-il d'un achat unique ou d'un abonnement ?", "Un achat unique sans abonnement ni achat intégré. Le même achat fonctionne sur Mac, iPhone et iPad avec le même compte Apple."),
            ("Quelle version choisir ?", "La version App Store. Un seul achat couvre le Mac, l'iPhone et l'iPad, qui ouvrent tous le même dossier iCloud Drive, avec des mises à jour automatiques. Le code source de l'app Mac est ouvert sur GitHub."),
            ("Où sont stockées mes notes ?", "Dans le dossier que vous choisissez, sous forme de simples fichiers .md. MiaoYan ne collecte aucune donnée de vos notes, et si vous changez d'outil, le dossier part avec vous."),
            ("Comment les notes se synchronisent-elles entre le Mac, l'iPhone et l'iPad ?", "Placez le dossier dans iCloud Drive et le Mac, l'iPhone et l'iPad ouvrent les mêmes notes. Sur le Mac, Nutstore ou un autre client de synchronisation fonctionne aussi."),
            ("Quel Markdown est pris en charge ?", "Le GitHub Flavored Markdown, plus LaTeX, Mermaid, PlantUML et Markmap, les wikilinks avec rétroliens, et des diapositives séparées par ---."),
            ("De quoi ai-je besoin ?", "macOS 12 ou version ultérieure sur le Mac, et iOS 18 et iPadOS 18 ou version ultérieure sur iPhone et iPad."),
        ],
        "about": "Tw93 conçoit, développe et maintient MiaoYan.",
        "foot": (("Obtenir", "Aide", "Contact"), ("FAQ", "Confidentialité")),
    },
    "es": {
        "title": "MiaoYan, notas Markdown para Mac, iPhone y iPad",
        "description": "MiaoYan es una app nativa de notas Markdown para Mac, iPhone y iPad. Tus notas son archivos Markdown normales en la carpeta que elijas.",
        "nav": ["Funciones", "iPhone y iPad", "Preguntas"],
        "language": "Idioma",
        "nav_cta": "App Store",
        "h1": "MiaoYan",
        "tagline": "Notas Markdown locales en Mac, iPhone y iPad",
        "lede": "MiaoYan es 妙言 en chino, palabras más allá de las palabras.",
        "trust": ["Una compra para Mac, iPhone y iPad", "Archivos Markdown locales", "Código abierto en GitHub", "macOS 12 / iOS 18+"],
        "cta": ("Descargar en el App Store", "Código fuente"),
        "gallery_title": "Escribe, lee y presenta",
        "gallery_lede": "Escribe Markdown puro, cambia a una vista previa maquetada, trabaja en paralelo o convierte una nota en diapositivas.",
        "tabs": {"edit": "Editar", "preview": "Vista previa", "split": "Dividido", "ppt": "Presentar", "dark": "Oscuro"},
        "captions": {
            "edit": "Markdown puro con resaltado de sintaxis, para que títulos, enlaces y código se distingan",
            "preview": "Imágenes, tablas y código tal como se van a leer",
            "split": "Escribe a la izquierda y míralo a la derecha, con diagramas Mermaid incluidos",
            "ppt": "Divide una nota con --- y se convierte en una presentación",
            "dark": "El modo oscuro sigue al sistema",
        },
        "alts": {
            "edit": "MiaoYan editando una nota Markdown con carpetas, lista de notas y resaltado de sintaxis",
            "preview": "MiaoYan mostrando la vista previa de una nota con una tabla y una lista de tareas",
            "split": "MiaoYan en vista dividida con Markdown a la izquierda y un diagrama Mermaid renderizado a la derecha",
            "ppt": "Una nota de MiaoYan mostrada como diapositiva",
            "dark": "MiaoYan en modo oscuro editando código Swift",
        },
        "devices_title": "En iPhone y iPad",
        "devices_lede": "La misma compra en el App Store funciona en iPhone y iPad y abre la misma carpeta de iCloud Drive que tu Mac.",
        "devices_cta": "Descargar en el App Store",
        "device_alts": ("MiaoYan en iPhone leyendo una nota", "MiaoYan en iPad mostrando una nota con un diagrama"),
        "features_title": "Por qué MiaoYan",
        "features": [
            ("Local primero", "Tus archivos Markdown se quedan en la carpeta que elijas. MiaoYan no recopila datos de tus notas; iCloud Drive, Nutstore u otro cliente de sincronización se encarga del resto de dispositivos."),
            ("Enfocado", "Carpetas, notas y editor en tres columnas claras. Modo oscuro, escritura sin distracciones y atajos de teclado integrados, sin un sistema de plugins que mantener."),
            ("Nativo", "Hecho de forma nativa con Swift 6 en lugar de Electron. El modo dividido combina vista previa en tiempo real con desplazamiento sincronizado a 60 fps en ambos sentidos."),
            ("Completo", "Wikilinks y backlinks, LaTeX, Mermaid, historial de versiones, formato automático, una CLI y presentaciones en Markdown cubren el trabajo alrededor de la escritura."),
        ],
        "compare_title": "Para quién es MiaoYan",
        "compare": [
            ("Frente a Typora", "MiaoYan mantiene la edición en Markdown puro y una vista previa aparte en lugar de WYSIWYG. Encaja con quien quiere controlar directamente sus archivos fuente y ver el resultado al momento."),
            ("Frente a Obsidian", "MiaoYan no usa Electron ni gira en torno a un ecosistema de plugins. Encaja con quien prefiere una app nativa y ligera, con archivos locales y funciones integradas bien elegidas."),
        ],
        "faq_title": "Preguntas",
        "faq": [
            ("¿Es compra única o suscripción?", "Una compra única para siempre, sin suscripciones ni compras dentro de la app. La misma compra sirve para Mac, iPhone y iPad con la misma cuenta de Apple."),
            ("¿Qué versión debo instalar?", "La del App Store. Una sola compra sirve para Mac, iPhone y iPad, todos abren la misma carpeta de iCloud Drive y las actualizaciones llegan solas. El código fuente de la app de Mac está abierto en GitHub."),
            ("¿Dónde se guardan mis notas?", "En la carpeta que elijas, como archivos .md normales. MiaoYan no recopila datos de tus notas y, si algún día cambias de herramienta, la carpeta se va contigo."),
            ("¿Cómo se sincronizan las notas entre el Mac, el iPhone y el iPad?", "Guarda la carpeta en iCloud Drive y el Mac, el iPhone y el iPad abrirán las mismas notas. En el Mac también sirven Nutstore u otro cliente de sincronización."),
            ("¿Qué Markdown admite?", "GitHub Flavored Markdown, además de LaTeX, Mermaid, PlantUML y Markmap, wikilinks con backlinks y diapositivas separadas con ---."),
            ("¿Qué necesito para usarlo?", "macOS 12 o posterior en el Mac, e iOS 18 o iPadOS 18 o posterior en iPhone y iPad."),
        ],
        "about": "Tw93 diseña, desarrolla y mantiene MiaoYan.",
        "foot": (("Obtener", "Ayuda", "Contacto"), ("Preguntas", "Privacidad")),
    },
}

APPLE = '<svg viewBox="0 0 16 16" aria-hidden="true" fill="currentColor"><path d="M11.18 8.5c-.02-1.6 1.31-2.37 1.37-2.41-.75-1.09-1.91-1.24-2.32-1.26-.99-.1-1.93.58-2.43.58-.5 0-1.27-.57-2.09-.55-1.08.02-2.07.62-2.62 1.58-1.12 1.94-.29 4.81.8 6.38.53.77 1.17 1.63 2 1.6.8-.03 1.11-.52 2.08-.52.97 0 1.25.52 2.1.5.87-.01 1.42-.78 1.95-1.55.61-.89.86-1.75.88-1.8-.02-.01-1.69-.65-1.72-2.55zM9.6 3.81c.44-.54.74-1.29.66-2.03-.64.03-1.41.43-1.87.96-.41.47-.77 1.23-.67 1.96.71.05 1.44-.36 1.88-.89z"/></svg>'

GITHUB_MARK = '<svg viewBox="0 0 16 16" aria-hidden="true" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>'

GLOBE = '<svg class="lang-globe" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z"/></svg>'


def esc(s):
    return html.escape(s, quote=True)


def french_spacing(s):
    # French sets a no-break space before ? ! : ; so the mark never starts a line.
    for mark in "?!:;":
        s = s.replace(" " + mark, " " + mark)
    return s


def page(key):
    c = COPY[key]
    current = next(l for l in LANGS if l[0] == key)
    _, path, lang_attr, _, _, shot = current
    t = french_spacing if key == "fr" else (lambda s: s)
    url = "https://miaoyan.app" + path
    store = APP_STORE_CN if key == "zh" else APP_STORE
    og = "zh" if shot == "zh" else "en"
    hrefs = [("#features", c["nav"][0]), ("#devices", c["nav"][1]), ("#faq", c["nav"][2]), (GITHUB, "GitHub")]
    nav = "".join(
        f'<a href="{esc(h)}"{" target=\"_blank\" rel=\"noopener\"" if h.startswith("http") else ""}>{esc(label)}</a>'
        for h, label in hrefs
    )
    menu = "".join(
        f'<a href="{p}" hreflang="{la}" lang="{la}" data-lang="{k}"{" class=\"active\" aria-current=\"page\"" if k == key else ""}>{esc(name)}</a>'
        for k, p, la, name, _, _ in LANGS
    )
    alternates = "\n".join(
        f'<link rel="alternate" hreflang="{la}" href="https://miaoyan.app{p}">' for _, p, la, _, _, _ in LANGS
    )
    trust = "".join(f"<li>{esc(t(x))}</li>" for x in c["trust"])
    tabs = "".join(
        f'<button type="button" data-shot="{s}" aria-pressed="{"true" if i == 0 else "false"}">{esc(c["tabs"][s])}</button>'
        for i, s in enumerate(SHOTS)
    )
    shots = "".join(
        f'<img src="/assets/shots/{shot}-{s}-1400.webp" srcset="/assets/shots/{shot}-{s}-1400.webp 1400w, /assets/shots/{shot}-{s}-2400.webp 2400w" '
        f'sizes="(max-width: 1248px) 100vw, 1120px" width="2400" height="{1506 if s == "ppt" else 1660}" alt="{esc(c["alts"][s])}" data-shot="{s}"'
        f'{" fetchpriority=\"high\"" if i == 0 else " loading=\"lazy\" hidden"}>'
        for i, s in enumerate(SHOTS)
    )
    captions = json.dumps({k: t(v) for k, v in c["captions"].items()}, ensure_ascii=False)
    cards = "".join(f'<div class="card"><h3>{esc(a)}</h3><p>{esc(t(d))}</p></div>' for a, d in c["features"])
    compare = "".join(f'<div class="card"><h3>{esc(a)}</h3><p>{esc(t(d))}</p></div>' for a, d in c["compare"])
    faq = "".join(f"<details><summary>{esc(t(q))}</summary><p>{esc(t(a))}</p></details>" for q, a in c["faq"])
    (col_get, col_help, col_connect), (faq_label, privacy_label) = c["foot"]
    ext = ' target="_blank" rel="noopener"'
    foot = (
        f'<div class="foot-col"><p class="foot-col-title">{esc(col_get)}</p>'
        f'<a href="{store}"{ext} data-store>App Store</a><a href="{GITHUB}"{ext}>GitHub</a></div>'
        f'<div class="foot-col"><p class="foot-col-title">{esc(col_help)}</p>'
        f'<a href="#faq">{esc(faq_label)}</a><a href="/privacy.html">{esc(privacy_label)}</a></div>'
        f'<div class="foot-col"><p class="foot-col-title">{esc(col_connect)}</p>'
        f'<a href="https://x.com/HiTw93"{ext}>X</a><a href="https://t.me/+9f9gf4ZrFSQ2OWVl"{ext}>Telegram</a></div>'
    )
    ld = json.dumps(
        {
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            "name": "MiaoYan",
            "alternateName": "妙言",
            "url": url,
            "inLanguage": lang_attr,
            "downloadUrl": APP_STORE,
            "applicationCategory": "ProductivityApplication",
            "operatingSystem": "macOS 12.0 or later, iOS 18.0 or later, iPadOS 18.0 or later",
            "description": c["description"],
            "author": {"@type": "Person", "name": "Tw93", "url": "https://tw93.fun/"},
            "sameAs": [GITHUB, APP_STORE],
        },
        ensure_ascii=False,
    )
    # A first visit to / goes to the page for the browser's language; picking
    # a language in the menu is remembered and wins from then on. zh-CN is the
    # value the two-language site stored for Chinese.
    redirect = (
        "<script>try{var s=localStorage.getItem('miaoyanLang');if(s==='zh-CN')s='zh';"
        "var p={zh:'/zh/',tw:'/tw/',ja:'/ja/',ko:'/ko/',de:'/de/',fr:'/fr/',es:'/es/'};"
        "if(!s){var l=((navigator.languages&&navigator.languages[0])||navigator.language||'').toLowerCase();"
        "s=/^zh-(tw|hk|mo|hant)/.test(l)?'tw':l.slice(0,2)}"
        "if(p[s])location.replace(p[s]+location.search+location.hash)}catch(e){}</script>"
        if key == "en"
        else ""
    )
    script = {"zh": "sc", "tw": "tc"}.get(key)
    font_preload = (
        "".join(
            f'<link rel="preload" as="font" type="font/woff2" href="/fonts/miaoyan-serif-{script}-{w}.woff2" crossorigin>\n'
            # Only the regular cut: a preload downloads even when the visitor has
            # the face installed, and the semibold one serves headings alone.
            for w in ("regular",)
        )
        if script
        else ""
    )
    return f"""<!DOCTYPE html>
<html lang="{lang_attr}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#f5f4ed">
<script>document.documentElement.classList.add('js')</script>
{redirect}
<title>{esc(c['title'])}</title>
<meta name="description" content="{esc(c['description'])}">
<link rel="canonical" href="{url}">
{alternates}
<link rel="alternate" hreflang="x-default" href="https://miaoyan.app/">
<link rel="alternate" type="text/plain" href="https://miaoyan.app/llms.txt" title="MiaoYan product facts">
<meta property="og:type" content="website">
<meta property="og:url" content="{url}">
<meta property="og:title" content="{esc(c['title'])}">
<meta property="og:description" content="{esc(c['description'])}">
<meta property="og:image" content="https://miaoyan.app/assets/shots/og-{og}.jpg">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:creator" content="@HiTw93">
<meta name="twitter:image" content="https://miaoyan.app/assets/shots/og-{og}.jpg">
<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" href="/assets/icon-64.png" type="image/png" sizes="64x64">
<link rel="apple-touch-icon" href="/assets/icon-180.png">
{font_preload}<link rel="preload" as="image" href="/assets/shots/{shot}-edit-1400.webp" imagesrcset="/assets/shots/{shot}-edit-1400.webp 1400w, /assets/shots/{shot}-edit-2400.webp 2400w" imagesizes="(max-width: 1248px) 100vw, 1120px">
<link rel="stylesheet" href="/site.css">
<script type="application/ld+json">{ld}</script>
</head>
<body>
<div class="wrap">
<header class="nav">
  <nav class="nav-bar hide-cta" aria-label="Main">
    <a class="brand" href="{path}"><img src="/assets/bird.svg" alt="" width="24" height="24"><b>MiaoYan</b></a>
    <div class="nav-links">{nav}</div>
    <div class="nav-end">
      <div class="lang-switch">
        <button class="lang-trigger" type="button" aria-expanded="false" aria-haspopup="true" aria-controls="language-menu" aria-label="{esc(c['language'])}">{GLOBE}<span class="lang-name">{esc(current[3])}</span><span class="lang-code">{esc(current[4])}</span></button>
        <div class="lang-menu" id="language-menu">{menu}</div>
      </div>
      <a class="nav-cta" href="{store}" target="_blank" rel="noopener" data-store>{APPLE}{esc(c['nav_cta'])}</a>
    </div>
  </nav>
</header>
<main>
  <div class="hero">
    <h1>{esc(c['h1'])}</h1>
    <p class="tagline">{esc(t(c['tagline']))}</p>
    <p class="lede">{esc(t(c['lede']))}</p>
    <ul class="trust">{trust}</ul>
    <div class="cta hero-cta">
      <a class="btn btn-primary" href="{store}" target="_blank" rel="noopener" data-store>{APPLE}{esc(c['cta'][0])}</a>
      <a class="btn btn-ghost" href="{GITHUB}" target="_blank" rel="noopener">{GITHUB_MARK}{esc(c['cta'][1])}</a>
    </div>
  </div>

  <section id="features" aria-labelledby="gallery-title">
    <h2 class="section-title" id="gallery-title">{esc(c['gallery_title'])}</h2>
    <p class="section-lede">{esc(t(c['gallery_lede']))}</p>
    <div class="gallery-frame">{shots}</div>
    <div class="gallery-bar">
      <p class="gallery-caption" aria-live="polite">{esc(t(c['captions']['edit']))}</p>
      <div class="tabs">{tabs}</div>
    </div>
  </section>

  <section id="devices" aria-labelledby="devices-title">
    <h2 class="section-title" id="devices-title">{esc(c['devices_title'])}</h2>
    <p class="section-lede">{esc(t(c['devices_lede']))}</p>
    <div class="devices">
      <figure class="device phone"><img src="/assets/shots/{shot}-iphone.webp" width="700" height="1431" loading="lazy" alt="{esc(c['device_alts'][0])}"><figcaption>iPhone</figcaption></figure>
      <figure class="device pad"><img src="/assets/shots/{shot}-ipad.webp" width="1400" height="1826" loading="lazy" alt="{esc(c['device_alts'][1])}"><figcaption>iPad</figcaption></figure>
    </div>
    <div class="cta devices-cta"><a class="btn btn-primary" href="{store}" target="_blank" rel="noopener" data-store>{APPLE}{esc(c['devices_cta'])}</a></div>
  </section>

  <section aria-labelledby="why-title">
    <h2 class="section-title" id="why-title">{esc(c['features_title'])}</h2>
    <div class="cards">{cards}</div>
  </section>

  <section aria-labelledby="who-title">
    <h2 class="section-title" id="who-title">{esc(c['compare_title'])}</h2>
    <div class="cards">{compare}</div>
  </section>

  <section id="faq" class="faq" aria-labelledby="faq-title">
    <h2 class="section-title" id="faq-title">{esc(c['faq_title'])}</h2>
    {faq}
  </section>
</main>
</div>
<footer>
  <div class="wrap">
    <div class="foot">
      <div class="foot-mark">
        <a class="brand" href="{path}"><img src="/assets/bird-night.svg" alt="" width="24" height="24"><b>MiaoYan</b></a>
        <p>{esc(c['about'])}</p>
      </div>
      <nav class="foot-cols" aria-label="Footer">{foot}</nav>
    </div>
    <div class="copy">© 2026 Tw93</div>
  </div>
</footer>
<script>
(function () {{
  var captions = {captions};
  var frame = document.querySelector('.gallery-frame');
  var caption = document.querySelector('.gallery-caption');
  document.querySelectorAll('.tabs button').forEach(function (tab) {{
    tab.addEventListener('click', function () {{
      var shot = tab.dataset.shot;
      document.querySelectorAll('.tabs button').forEach(function (t) {{ t.setAttribute('aria-pressed', t === tab ? 'true' : 'false'); }});
      frame.querySelectorAll('img').forEach(function (img) {{ img.hidden = img.dataset.shot !== shot; }});
      caption.textContent = captions[shot];
    }});
  }});
  // iPhone and iPad open the App Store app from the region-less link, and the
  // Mac opens the Mac App Store directly; iPadOS reports itself as a Mac.
  var ua = navigator.userAgent;
  var ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  var storeLink = ios ? '{APP_STORE}' : /Macintosh/.test(ua) ? '{MAC_APP_STORE}' : '';
  if (storeLink) document.querySelectorAll('[data-store]').forEach(function (a) {{
    a.href = storeLink;
    a.removeAttribute('target');
  }});
  // The nav's App Store button stays hidden while the hero's own is on screen.
  var bar = document.querySelector('.nav-bar');
  var heroCta = document.querySelector('.hero-cta');
  if ('IntersectionObserver' in window) {{
    new IntersectionObserver(function (entries) {{
      bar.classList.toggle('hide-cta', entries[0].isIntersecting);
    }}, {{ rootMargin: '-72px 0px 0px 0px' }}).observe(heroCta);
  }} else {{
    bar.classList.remove('hide-cta');
  }}
  var sw = document.querySelector('.lang-switch');
  var trigger = sw.querySelector('.lang-trigger');
  function setOpen(open) {{
    sw.classList.toggle('is-open', open);
    trigger.setAttribute('aria-expanded', open ? 'true' : 'false');
  }}
  trigger.addEventListener('click', function (e) {{ e.stopPropagation(); setOpen(!sw.classList.contains('is-open')); }});
  document.addEventListener('click', function (e) {{ if (!sw.contains(e.target)) setOpen(false); }});
  document.addEventListener('keydown', function (e) {{ if (e.key === 'Escape') setOpen(false); }});
  sw.querySelectorAll('[data-lang]').forEach(function (a) {{
    a.addEventListener('click', function () {{ try {{ localStorage.setItem('miaoyanLang', a.dataset.lang); }} catch (e) {{}} }});
  }});
}})();
</script>
<script async src="https://www.googletagmanager.com/gtag/js?id=G-5M47BM3L9Y"></script>
<script>window.dataLayer=window.dataLayer||[];function gtag(){{dataLayer.push(arguments)}}gtag('consent','default',{{analytics_storage:'denied',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'}});gtag('js',new Date());gtag('config','G-5M47BM3L9Y');</script>
</body>
</html>
"""


def main():
    for key, path, *_ in LANGS:
        out = ROOT / "index.html" if path == "/" else ROOT / path.strip("/") / "index.html"
        out.parent.mkdir(exist_ok=True)
        out.write_text(page(key))
    print("wrote", ", ".join(p for _, p, *_ in LANGS))
    # A Chinese character missing from the font subset would fall back to the
    # system face; fail loudly so the subsets get regenerated with the copy.
    import subprocess, sys
    checked = subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "build-fonts.py"), "--check"])
    if checked.returncode:
        sys.exit("font subsets are out of date: run python3 scripts/build-fonts.py")


if __name__ == "__main__":
    main()
