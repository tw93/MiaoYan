# V4.6.0 Lagiacrus ⚡

1. 侧栏、列表、编辑器和预览统一成一种暖白纸色，编辑器换上更安静的配色，Markdown 符号淡下去，格式、演示和置顶图标也重新画过
2. 默认字体改成系统字体，英文用 SF，中文用苹方，之前选过仓耳今楷或其他字体的保持不变
3. 文件夹右键新增「移动到」，整个文件夹连同子文件夹和笔记都能挪到别处，重命名文件夹也会带上子文件夹、排序设置和版本历史
4. 读不出来的笔记不会再被空内容覆盖，清理未使用附件不会再删掉没打开过的笔记还在用的图片，GBK、Big5 和 UTF-16 这类旧编码的笔记能正确打开，没改过就不会被改写
5. 别处改过的笔记再打开时读到的是最新内容，后缀是 .MD 的笔记在外部修改后也会及时刷新，版本历史跟着改名、移动和废纸篓走
6. 分栏预览不再闪出破图，也不会停在别的笔记上，预览模式里点任务框能正确保存，导出 HTML 不用先打开预览并会带上图片，以 --- 开头的幻灯片不再丢掉第一页
7. 列表快捷键不再触发两次，在列表里按回车不会把换行打进笔记，格式和查找菜单恢复可用，主窗口改为 ⌥⌘0，标题里用中文输入法回车确认英文不会跳到正文
8. 打字时不再每次按键都复制整篇笔记，大笔记输入更顺，粘贴图片上传到 PicGo 后撤销不再错位，菜单和提示补齐了日文、繁体中文和西班牙语
9. 命令行 miao 能找到 App 实际用的笔记目录，标题带引号也能正常新建，网络不通时安装脚本不再中途报错

---

1. The sidebar, note list, editor and preview share one warm paper tone, the editor uses a calmer palette with quieter Markdown symbols, and the format, presentation and pin icons are redrawn
2. The default font is now the system pairing, SF for Latin and PingFang for Chinese, and fonts you already chose, TsangerJinKai02 included, stay as they are
3. Folders gain Move to… in their context menu, carrying every subfolder and note along, and renaming a folder now keeps its subfolders, sort settings and version history
4. Notes that cannot be read are never saved over with empty text, Clean Unused Attachments no longer trashes images used by notes you have not opened, and GBK, Big5 and UTF-16 notes open correctly and are not rewritten unless you edit them
5. A note changed elsewhere shows its latest text when you open it again, notes ending in .MD refresh after outside edits, and version history follows renames, moves and the Trash
6. Split preview no longer flashes broken images or stays on another note, ticking a task in preview mode is saved, HTML export works without opening the preview and carries its images, and a deck that opens with --- keeps its first slide
7. List shortcuts no longer fire twice, Return in the list no longer types into the note, the Format and Find menus work again, Main Window moves to ⌥⌘0, and confirming English with Return in a Chinese input method keeps focus in the title
8. Typing no longer copies the whole note on every key, so large notes stay smooth, Undo after a PicGo image upload lands in the right place, and menus and messages are fully translated into Japanese, Traditional Chinese and Spanish
9. The miao command line finds the notes folder the app actually uses, creates notes whose titles contain quotes, and its installer no longer stops when the network is down
