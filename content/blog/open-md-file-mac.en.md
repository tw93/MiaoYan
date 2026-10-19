A `.md` file is a plain text file written in Markdown, so any text editor on a Mac can open it. To read the raw text, right-click the file in Finder, choose Open With, then TextEdit. To read it with headings and lists rendered, open it in a Markdown app or in VS Code's preview. If you do this often, set the default app once through Get Info so a double-click does the right thing. The one trap with TextEdit is saving: a file in rich text mode saves as `.rtf`, not as the `.md` you started with.

## What is inside a .md file

A Markdown file is ordinary text with a few punctuation marks standing in for formatting: `#` for a heading, `-` for a list item, `**` around bold words. Nothing is hidden in it, no images are embedded, and there is no binary container like a `.docx`. That is why every editor can open it, and why the same file looks different in different apps. The [what is Markdown](/blog/what-is-markdown/) post covers the marks, and the [cheat sheet](/blog/markdown-cheat-sheet/) lists them with examples.

`.md` and `.markdown` are the same format with different extensions. The shorter one is far more common, and apps that handle one normally handle the other.

## Open it once with a specific app

Apple's Mac User Guide lists four ways to open a file with a chosen app, and any of them works for a `.md` file:

1. Drag the file onto the app's icon in the Finder or the Dock.
2. Select the file in the Finder, then choose File > Open With and pick an app.
3. Control-click the file, choose Open With, then pick an app.
4. Open the app first, then choose File > Open.

## Read the raw text with TextEdit

TextEdit ships with every Mac and shows the file exactly as written, `#` and `**` included. Two settings decide whether that stays safe.

The first is rich text. Apple's TextEdit guide says plain text documents have no formatting options, and that choosing Format > Make Plain Text removes all formatting and saves the document as a `.txt` file; Format > Make Rich Text allows formatting and saves as `.rtf`. Apple's formatting guide adds that if you don't see the toolbar, you choose Format > Make Rich Text to get it, so a toolbar on your `.md` file means rich text mode, which is how Markdown files end up converted. Switch with Format > Make Plain Text before you edit.

The second is the extension. Under TextEdit > Settings > Open and Save there is an option, Add ".txt" extension to plain text files, which Apple describes as always using the `.txt` extension when saving a plain text file. Under New Document in the same window you can set the default format to Plain text. Check both before you use TextEdit for Markdown, because a notes folder full of `.md.txt` files is annoying to clean up.

## Quick Look from the Finder

Select the file and press the Space bar. Apple's guide describes Quick Look as a way to see what a file contains without opening it, and it works for items in Finder windows, on the desktop, in Mail and in Messages. It is a preview, not an editor, so use it to find the right file and then open that file in a real app.

## Make one app the default

To make every `.md` file open in the same app, which Apple calls permanently changing the app used for a type of file:

1. Select a `.md` file in the Finder and choose File > Get Info, or Control-click it and choose Get Info.
2. In the Info window, expand Open with.
3. Pick the app from the pop-up menu, then click Change All.

Apple's warning is worth repeating: do not click Change All if you only want that one file to open in the app. The change applies to every file of the same type, so it also affects other Markdown files in other folders.

## See it rendered

Two options cover most cases.

- **VS Code.** Visual Studio Code supports Markdown out of the box. Its documentation describes a command to toggle between the code and the preview, and Markdown: Open Preview to the Side, which shows both next to each other and updates as you type. It is the right pick if you already work in a code editor.
- **A Markdown app.** An app built for notes shows the rendered result alongside the source. MiaoYan is one, and [Choosing a Markdown editor for Mac](/blog/markdown-editor-for-mac/) compares it with Typora, Obsidian and VS Code.

## How MiaoYan opens .md files

MiaoYan, in its V4.5.0 release, declares itself in its Info.plist as an editor for Markdown files with the extensions `md` and `markdown`, under the type `net.daringfireball.markdown`. That is what lets it appear in Open With and in the Open with pop-up of Get Info. It does not list `mdown`, `mkd` or other rarer extensions itself, so whether macOS offers it for those files depends on what other installed apps declare.

Terminal shows the same thing. `mdls -name kMDItemContentType note.md` prints the type macOS gave the file, `net.daringfireball.markdown` for a `.md` file, while an extension that no installed app declares comes back as a value starting with `dyn.`, as `.mdown` and `.mkd` did on a Mac with MiaoYan installed. `open -a MiaoYan note.md` opens one file in MiaoYan without changing any default, and `open -e note.md` opens it in TextEdit.

Double-clicking a file starts what the app calls Single Mode, whose menu item is File > Single Mode (`⌘O`), in Chinese 「单独模式」. The same mode starts when you choose that menu item and pick a file or folder. The note list shows the files that sit next to the one you opened. The app's own prompt says to leave this mode with `Command+Shift+W`.

Which neighbors appear depends on the extension. In V4.5.0 the list is built from files ending in `md`, `markdown` or `txt`, and the code compares that text exactly, with the case you typed. A file named `README.MD` is therefore not matched by that scan, so if a file with an uppercase extension does not show up next to its neighbors, rename it to lowercase `.md`. When it reads a folder, MiaoYan also skips files that macOS does not identify as text and files of 100 MB or more.

To bring files into your own notes folder instead of browsing them in place, use File > Import (「导入」), which accepts files and folders and copies Markdown files in.

## Garbled text and encoding

A `.md` file is text, but text still has an encoding, and a file saved in an older encoding, such as GBK for Chinese text, can look garbled in an app that assumes UTF-8. MiaoYan tries UTF-8 first and, if that fails, asks the system to detect the encoding and reads the file with that. TextEdit lets you choose: under TextEdit > Settings > Open and Save, the Plain Text File Encoding pop-up menus set the default encoding for opening and saving plain text files. If a file looks wrong in one app, try another that detects the encoding before you edit and save it, because saving rewrites the file in the encoding the app chooses.

## Which one to use

Quick Look or TextEdit is enough for a file someone sent you. A README inside a code project belongs in VS Code. For a folder of notes you use every day, set a Markdown app as the default for `.md`.

## FAQ

### Why does my .md file open in Xcode or another app?

Another app has registered for the type. Use Get Info, Open with, pick your app and click Change All.

### Can Windows or Linux open the same file?

Yes. It is plain text, so any editor opens it. Renderers differ on extras such as tables and task lists, as [CommonMark vs GFM](/blog/commonmark-vs-gfm/) explains.

### Is a .md file the same as a .txt file?

The contents are both plain text. The extension tells apps whether to treat the marks as Markdown, and MiaoYan lists both along with `.markdown`.
