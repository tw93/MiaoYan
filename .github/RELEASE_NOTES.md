# V4.6.0 Lagiacrus ⚡

1. 侧栏、列表、编辑器和预览统一成一种暖白纸色，列表行之间用缩进细线分开，编辑器换上更安静的配色，Markdown 符号淡下去，代码、行内代码和 HTML 标签统一成淡金色，预览里的代码块也是同一套颜色，格式、演示和置顶图标也重新画过
2. 默认字体改成系统字体，英文用 SF，中文用苹方，之前选过仓耳今楷或其他字体的保持不变
3. 设置窗口重新排成通用、编辑器、字体三页，每行左边是说明右边是控件，需要重启的设置在行内就能重启，侧栏 Logo 下面多了一行「全部笔记」，升级后也会回到上次打开的文件夹
4. 确认弹框改成纸色底，图标只留小鸟，移入废纸篓的说法前后一致，预览里的引用左边多了一条细竖条，图片滚到顶部被遮住时也保留圆角
5. 文件夹右键新增「移动到」，整个文件夹连同子文件夹和笔记都能挪到别处，重命名文件夹也会带上子文件夹、排序设置和版本历史，超过 100 个文件夹、名叫 assets 的笔记文件夹和通过符号链接打开的笔记库都能完整列出
6. 读不出来的笔记不会再被空内容覆盖，保存成功后不再误报保存失败，清理未使用附件不会再删掉没打开过的笔记和废纸篓里的笔记还在用的图片，GBK、Big5 和 UTF-16 这类旧编码的笔记能正确打开，英文占多数的也一样，没改过就不会被改写
7. 别处改过的笔记再打开时读到的是最新内容，后缀是 .MD 的笔记在外部修改后也会及时刷新，版本历史跟着改名、移动和废纸篓走，删除后撤销也会带回来，反向链接覆盖各层文件夹里的笔记并跟着改名和删除更新，在 App 外放进文件夹的笔记也会列出来
8. 分栏预览不再闪出破图，也不会停在别的笔记上，预览模式里点任务框能正确保存，导出 HTML 不用先打开预览并会带上图片，以 --- 开头的幻灯片不再丢掉第一页，没写内容的任务项也显示成复选框，取消保存面板后导出不再卡住，从预览复制整个标题不会再带上 # 号
9. 列表快捷键不再触发两次，在列表里按回车不会把换行打进笔记，格式和查找菜单恢复可用，主窗口改为 ⌥⌘0，标题里用中文输入法回车确认英文不会跳到正文，标题只填空格不会把笔记移出文件夹，排版时继续打字也不会被覆盖
10. 打字时不再每次按键都复制整篇笔记，大笔记输入更顺，粘贴图片上传到 PicGo 后撤销不再错位，菜单和提示补齐了日文、繁体中文和西班牙语
11. 命令行 miao 能找到 App 实际用的笔记目录，标题带引号也能正常新建，网络不通时安装脚本不再中途报错，miao update 查不到版本时不再装上开发中的代码

---

1. The sidebar, note list, editor and preview share one warm paper tone, list rows are parted by an inset hairline, the editor uses a calmer palette with quieter Markdown symbols, code, inline code and HTML tags share a soft gold that preview code blocks use too, and the format, presentation and pin icons are redrawn
2. The default font is now the system pairing, SF for Latin and PingFang for Chinese, and fonts you already chose, TsangerJinKai02 included, stay as they are
3. Settings is laid out as General, Editor and Fonts, each row a description on the left and its control on the right, with a Restart button in the row for settings that need one, the sidebar gains an All Notes row under the logo, and an upgrade reopens the folder you left
4. Confirmations sit on the app's paper with the bird alone as their icon and name the Trash the same way everywhere, quotes in the preview gain a thin bar on the left, and images keep their rounded corners as they scroll under the top edge
5. Folders gain Move to… in their context menu, carrying every subfolder and note along, and renaming a folder now keeps its subfolders, sort settings and version history, and libraries with over 100 folders, note folders named assets and libraries reached through a symlink are listed in full
6. Notes that cannot be read are never saved over with empty text, a save that worked no longer reports Save Failed, Clean Unused Attachments no longer trashes images used by notes you have not opened or notes in the Trash, and GBK, Big5 and UTF-16 notes open correctly, mostly English ones included, and are not rewritten unless you edit them
7. A note changed elsewhere shows its latest text when you open it again, notes ending in .MD refresh after outside edits, and version history follows renames, moves and the Trash and comes back when a delete is undone, and backlinks cover notes in every folder and follow renames and deletes, and notes added to a folder outside the app are listed
8. Split preview no longer flashes broken images or stays on another note, ticking a task in preview mode is saved, HTML export works without opening the preview and carries its images, a deck that opens with --- keeps its first slide, a task item with no text shows as a checkbox, exports no longer stick after a cancelled save panel, and copying a whole heading from the preview no longer brings its # marks
9. List shortcuts no longer fire twice, Return in the list no longer types into the note, the Format and Find menus work again, Main Window moves to ⌥⌘0, and confirming English with Return in a Chinese input method keeps focus in the title, a title of only spaces no longer moves the note out of its folder, and typing while Format runs is kept
10. Typing no longer copies the whole note on every key, so large notes stay smooth, Undo after a PicGo image upload lands in the right place, and menus and messages are fully translated into Japanese, Traditional Chinese and Spanish
11. The miao command line finds the notes folder the app actually uses, creates notes whose titles contain quotes, its installer no longer stops when the network is down, and miao update no longer installs unreleased code when the release lookup fails
