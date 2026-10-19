A Zettelkasten is a collection of small notes that each hold one idea, carry a permanent address, and point to related notes, so that you find ideas by following links instead of looking them up in a folder tree. You can run one with nothing but Markdown files in a folder: one file per note, a unique name, `[[wikilinks]]` between them, and a search box. MiaoYan V4.5.0 covers that core with wikilinks, a backlinks list and full-text search. It has no graph view, so if you want to see the network drawn, Obsidian fits better. The system works or fails on habits, not on the app.

## What Luhmann actually built

The method is named after the slip-box of the sociologist Niklas Luhmann, who taught at Bielefeld University. The university acquired his estate, and its Luhmann archive project has published work on how the box was organized. This section follows Johannes Schmidt's article "Der Zettelkasten Niklas Luhmanns als Überraschungsgenerator", from that project.

The box is two collections of paper slips: an earlier one from roughly the 1950s and early 1960s with about 23,000 slips, and a later one with about 67,000. Each slip was given a number, and that number is its fixed place, which is not changed afterwards. A slip that continues the thought on slip 1,1 gets the number 1,1a and is filed between 1,1 and 1,2, and a slip that continues that one becomes 1,1a1, so the collection branches inwards instead of being sorted by topic. Schmidt also describes slips that carry the numbers of other slips as references, and a keyword register, with about 3,200 entries in the later collection. zettelkasten.de points out that the register is a list of entry points, not a tag system: next to each term there are very few note numbers, sometimes just one. Luhmann said in interviews that his productivity is largely explained by the system, and Schmidt's title calls the box a generator of surprises, quoting Luhmann that without the slips, by thinking alone, he would not have come up with such ideas.

Three ideas carry over to files: every note has an address that never changes, notes link to each other explicitly, and the entry points are few and chosen by hand.

## The same ideas in plain Markdown

zettelkasten.de, a site run by practitioners of the method, puts it as two principles: a note needs a unique address so others can refer to it, and it should be atomic, meaning one knowledge building block per note, as a guide and not a rigid law. It also says the point is connecting notes more than collecting them, and that the body should be written in your own words, with sources listed in a footer.

In a folder of Markdown files that becomes:

- **One idea per file.** If a note needs two headings that could stand alone, split it.
- **The file name is the address.** Pick one naming scheme and keep it. zettelkasten.de's examples use a timestamp such as `202005191402`, and notes that the title can also serve as the ID if it is unique.
- **Links are plain text in the note body.** In MiaoYan that is `[[Another note title]]`.
- **Entry points are notes too.** A note called `Index` or `Writing` that only lists links to the best notes on a topic plays the role of Luhmann's register.
- **Sources go at the bottom** of each note as a short line with the book or URL.

## File naming in MiaoYan

MiaoYan uses the file name without its extension as the note title, and a wikilink must match that title exactly, so the name you choose is also the link you type. That leaves two workable choices.

A descriptive title as the name, such as `Spaced repetition needs retrieval.md`, makes links readable in the body: `[[Spaced repetition needs retrieval]]`. This follows the zettelkasten.de remark that a unique title can be the ID, and a claim written as a sentence is easy to recognize in a backlinks list. The cost is that renaming a note later breaks links that point to it.

An ID plus title, such as `202610191402 Spaced repetition needs retrieval.md`, sorts by creation time in any file browser, but you type the ID in every link. If you pick this, let the app help: type part of the title in the search field to find the exact name before you write the link.

[[figure:zettelkasten-markdown-notes|A reading or idea becomes a single note in your own words, saved under a unique file name in a Markdown folder, linked with a wikilink to related notes, with the best notes listed in an index note and backlinks pointing back.|Each idea becomes one file with its own name, links make the connections, and the backlinks list shows what points back.]]

## Wikilinks and backlinks in MiaoYan V4.5.0

Write the title between double brackets, without the extension. The match is exact, so case and spacing count. MiaoYan treats everything between the brackets as the title, so the Obsidian forms `[[Note|alias]]` and `[[Note#Heading]]` are not supported: there is no alias and no jump to a heading, and the backlinks list records the whole text as the title. The [wikilinks and backlinks](/blog/wikilinks-and-backlinks/) post lists the rules and the error messages.

The backlinks list is in the panel opened by Show Info (`⌘⌥I`), next to the word count and the created and modified dates. It shows the titles of notes that link to the current one, or "None". The titles are text, not links, so you jump to one with the search field. The index reads the text of notes MiaoYan has loaded in the current list, so a link written in a note you have not opened since launch may not show up until you open or save that note.

For finding things, the search field matches the words you type against titles and note bodies, and a folder structure still works alongside links. A common compromise is a few broad folders such as `Inbox`, `Notes` and `Sources`, with the links doing the real organizing inside them. MiaoYan's [local-first](/blog/local-first-markdown-notes/) setup keeps all of it as ordinary files you can open in another app.

## What MiaoYan does not have

There is no graph view and no plugin system. Link aliases, heading links and embeds are not supported either. If seeing the shape of your notes matters to you, or you want plugins for daily notes or spaced review, Obsidian is the better fit, and [an Obsidian alternative for Mac](/blog/obsidian-alternative-mac/) lists what moves across and what does not. Plain `[[Title]]` links and ordinary notes do move between the two, since both read a folder of Markdown files.

If you only want to write notes, link them and find them again, the smaller tool means fewer settings to maintain.

## A weekly routine

This part is advice drawn from the principles above, not from Luhmann's archive:

1. **Capture while reading.** Keep a single `Inbox` note or folder for quick fragments. Do not tidy it yet.
2. **Once a week, turn fragments into notes.** For each fragment worth keeping, write a note in your own words, one idea long, with the source at the bottom. Delete the rest of the fragments.
3. **Add at least two links to every new note.** Search for related words, link to older notes, and write a short reason in the sentence around the link.
4. **Open the backlinks list of one old note.** Look at what has attached to it and decide whether it needs its own entry-point note.
5. **Update the index notes.** Add the best new notes to the relevant `Index` note.

Half an hour is enough once the habit sticks, and the order matters: write first, link second, index last.

## What goes wrong

- **Collecting without writing.** The folder fills with clipped quotes and no notes in your own words. The fix is the weekly step 2, where nothing stays unless you rewrite it.
- **Notes that are too big.** A note that covers a whole chapter has no single place to link to. Split it.
- **Links with no reason.** `See also [[X]]` is weaker than a sentence that says how X relates.
- **Index notes that grow into lists of everything.** Luhmann's register had few entries per term. Keep entry points short and chosen.
- **Renaming notes.** In MiaoYan, links in other notes keep the old title, and the missing target shows a message that the title does not exist. Search for the old title and fix the links.
- **Two notes with the same title in different folders.** MiaoYan then starts a search instead of opening one, so keep titles unique.

To list every link whose target no longer exists, run this from the notes folder:

```bash
grep -rhoE '\[\[[^]]+\]\]' --include='*.md' --include='*.markdown' --include='*.txt' . |
  sed -E 's/^\[\[//; s/\]\]$//; s/#.*$//' | sort -u |
  while IFS= read -r t; do
    [ -n "$(find . \( -name "$t.md" -o -name "$t.markdown" -o -name "$t.txt" \) -print -quit)" ] || echo "missing: $t"
  done
```

It uses the same `[[...]]` pattern as MiaoYan's backlinks index drops a `#heading` part, and compares names with exact case, and each `missing:` line is a title to search for and fix. Links inside code blocks are counted too.

## FAQ

### Do I need an app for Zettelkasten?

No. Luhmann used paper slips. Markdown files in a folder with links by file name are enough, and an app only speeds up linking and search.

### Should I use IDs or titles in file names?

Either works with MiaoYan's exact-title links. Titles read better in the body and in backlinks, and IDs sort by time but have to be typed in each link.

### Can I move my notes to Obsidian later?

Yes for the files and plain `[[Title]]` links, since both apps read Markdown folders. Aliases and heading links written in Obsidian will not work in MiaoYan.
