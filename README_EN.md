<p align="right"><a href="https://github.com/tw93/MiaoYan">中文</a> | <strong>English</strong></p>
<p align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src=https://gw.alipayobjects.com/zos/k/t0/43.png width=138 /></a>
  <h1 align="center">MiaoYan</h1>
  <div align="center">
    <a href="https://twitter.com/intent/follow?&original_referer=https://github.com/tw93/MiaoYan&screen_name=HiTw93" target="_blank">
       <img alt="twitter" src="https://img.shields.io/twitter/follow/Hitw93?color=%231D9BF0&label=MiaoYan%20%F0%9F%93%A2%20&logo=Twitter&style=flat-square"></a>
    <a href="https://t.me/miaoyan" target="_blank">
      <img alt="Telegram" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
     <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">
      <img alt="GitHub downloads" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/commits" target="_blank">
      <img alt="GitHub commit" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank">
      <img alt="GitHub closed issues" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
  </div>
  <div align="center">Lightweight Markdown app to help you write great sentences.</div>
</p>

<kbd>
<img src=https://gw.alipayobjects.com/zos/k/8m/en.gif width="100%">
</kbd>

## Features

- 🪂 **Fantastic**: Local use, security, syntax highlighting, dark mode, source file saving, international, presentation mode, [PPT Mode](#miaoYan-ppt), single edit mode, export file, internal jump, document auto typesetting, picture upload, LaTeX, Mermaid, PlantUML.
- 🐶 **Beauty**: Minimalist design style, folder + file list + editor 3 column mode.
- 🏌🏽‍♂️ **Fast**: Using Swift5 native development, the performance experience is much better compared to the Web.
- 🩴 **Simple**: Very light, pure editor input experience, many shortcut keys to help you fast.

## Why do this

- I have tried many note-taking applications before, such as WizNote, Ulysses, Quiver, MWeb, Bear, Typora, for various reasons, I did not find a conventional Markdown application, so I had the idea of doing MiaoYan.
- My job is front-end development, but also can develop iOS App, love to toss new things, so develop MiaoYan as a fun leisure.

## Install

- Way1: Download the latest `MiaoYan.dmg` installation package from <a href="https://github.com/tw93/MiaoYan/releases/latest" target="_blank">GitHub Releases</a> and double-click to install it.
- Way2: Install with brew ```brew install miaoyan --cask```.

## First Use

1. You can create a `MiaoYan` folder in iCloud or the root directory, open MiaoYan's Settings, and change the default storage address to this.
2. Click icon of the new folder in the upper left corner of MiaoYan, create your own document category folder, and you can start using it.
3. Similarly, if you are not used to the default font, you can change it to other normal fonts in the settings.

## Shortcut Keys

#### Window Operations

- `command + 1`: Collapse expand folder list
- `command + 2`: Expand the list of documents
- `command + 3`: Switching between edit and preview states
- `command + 4`: Switching between edit and presentation states
- `command + option + m`: Global active/hide MiaoYan

#### File Operations

- `command + n`：New document
- `command + r`：Rename document
- `command + d`：Copy document
- `command + o`：Single open document separately
- `command + delete`：Delete document
- `command + shift + n`：New folder
- `command + shift + l`：Auto typesetting
- `command + option + r`：Displaying document in Finder
- `command + option + i`：Display document attributes such as word count
- `command + option + p`：Launch MiaoYan PPT preview.

🏂 There are also many other shortcuts 👆🏻 👇🏻 👈🏻 👉🏻 waiting for you to find if you like to toss and turn~

## MiaoYan PPT

<a href=https://gw.alipayobjects.com/zos/k/app3/ScreenFlow1.gif target="_blank"><img src="https://user-images.githubusercontent.com/8736212/180579489-a8ac6f0f-1d47-44fa-a8bb-0be998f7895f.gif" width="100%"></a>

1. The default initialization of new friends will generate templates. If you are an old friend, You need to upgrade to 1.0 then try copy [this file](https://raw.githubusercontent.com/tw93/MiaoYan/master/Resources/Initial/MiaoYan%20PPT.md) to MiaoYan.
2. Execute `command + option + p` to start MiaoYan PPT preview. At the same time, you can also select the document, right-click and select 'MiaoYan PPT' to open it.
3. PPT mode can be enabled only in documents marked with `---` separator. During the presentation, You can preview the outline of the speech with `Enter` Key and exit ppt mode with `ESC` Key.
4. You can use HTML to customize the effect. For more complex usage, Please refer to [reveal](https://revealjs.com/markdown/) Documentation.

## Support

- I have two cats, one is called TangYuan, and one is called Coke, If you think MiaoYan makes your life better, you can give my cats <a href="https://miaoyan.app/cats.html" target="_blank">feed canned food 🥩🍤</a>.
- If you like MiaoYan, you can star it in Github. We are more welcome to [recommend MiaoYan](https://twitter.com/intent/tweet?text=MiaoYan%20-%20a%20simple%20and%20good-looking%20open-source%20mac%20markdown%20editor,%20without%20any%20redundant%20functions,%20is%20developed%20using%20native%20swift,%20pure%20local%20use,%20has%20functions%20such%20as%20syntax%20highlighting,%20automatic%20formatting,%20presentation%20mode%20etc.&url=https://github.com/tw93/MiaoYan&via=HiTw93) to your like-minded friends.

## Thanks

- Thanks to <a href="https://vercel.com?utm_source=miaoyan&utm_campaign=oss"><a href="https://vercel.com?utm_source=tw93&utm_campaign=oss"><img src="https://gw.alipayobjects.com/zos/k/app/vercel-logotype-dark.jpg" height="13px"></a>  for providing static rendering capability to [MiaoYan](https://miaoyan.app/). <a href="https://vercel.com?utm_source=tw93&utm_campaign=oss">
- <a href="https://github.com/KristopherGBaker/libcmark_gfm" target="_blank">KristopherGBaker/libcmark_gfm</a>: Swift Compatible framework for cmark-gfm.
- <a href="https://github.com/raspu/Highlightr" target="_blank">raspu/Highlightr</a>: Syntax highlighting capability.
- <a href="https://github.com/glushchenko/fsnotes" target="_blank">glushchenko/fsnotes</a>: MiaoYan has part of the framework code from this project.
- <a href="https://github.com/lxgw/LxgwWenKai" target="_blank">lxgw/LxgwWenKai</a>: A beautiful open source chinese font, MiaoYan has made it the default font.
- <a href="https://github.com/sivan/heti" target="_blank">sivan/heti</a>：Enhanced typography for Chinese content presentation.
- <a href="https://github.com/hakimel/reveal.js" target="_blank">hakimel/reveal.js</a>：An open source HTML presentation framework.

# License

- Follow the MIT License.
- Please feel free to enjoy and participate in open source.
