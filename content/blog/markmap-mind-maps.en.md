To get a mind map from a Markdown outline, put the outline in a fenced code block tagged `markmap`: headings and nested list items become branches, and the preview draws them as an SVG tree. In MiaoYan the Markmap library is bundled inside the app, so a plain outline renders offline and its text does not leave your Mac. The trade-off is control. In V4.5.0 the colors, spacing and starting expansion are fixed by the app, the map in the normal preview does not respond to clicks or the scroll wheel, and the options you may know from Markmap's own documentation do not change anything here.

## What Markmap does

Markmap's own documentation describes it as a combination of Markdown and mind map: it parses Markdown, extracts the hierarchy, and renders an interactive map. A heading level or list indent decides which node is the parent of which. Because the input is an ordinary outline, you can write the structure as notes first and see it as a map second, and the note still reads as text in any editor.

## Syntax

````markdown
```markmap
# Release plan
## Design
- Wireframes
- Icon set
## Build
- Editor
  - Tabs
  - Search
- Preview
## Ship
- Notarize
- Update the appcast
```
````

The first `#` heading becomes the root, `##` headings are its branches, and list items hang below the nearest heading. Lists nest by indentation, two spaces per level is the convention used here. You can mix levels: a list under a `##` heading is one level deeper than the heading.

You do not have to type the fence. In MiaoYan, type `/markmap` and press `Tab`, or open the Tab Quick Input submenu in the Format menu and pick "/markmap - Mind Map". It inserts a small template with a root, two branches and three items, with the root title selected; the placeholder text is in Chinese.

## How it works in MiaoYan

A fenced block with a language tag reaches the page as a code element with the class `language-markmap`. After the preview loads, a script (`diagram-handler.js`) finds those elements and hands each one to the bundled Markmap loader (`markmap.min.js`, with `markmap-view.min.js` and `d3.min.js` beside it). The loader reads the text of the block, strips the common indentation, converts the outline into a tree and draws it into an SVG that replaces the code. All of those files are packaged in the preview bundle (markmap-lib 0.14.1 and markmap-view 0.14.0) and referenced by relative path, so a plain outline sends no request. Math is the exception: a node with `$x^2$` makes the Markmap library fetch KaTeX styles and fonts from jsDelivr, so keep formulas out of maps that must stay offline.

Reading the V4.5.0 loader, a few behaviors are fixed:

- The box height is computed from the block: roughly 30 pixels per non-empty line plus a depth allowance, with a minimum of 300 pixels. A long outline gets a taller box, not a smaller font.
- Node colors come from a built-in palette of twelve colors cycled by depth. The diagram background follows the light or dark appearance through the app's CSS, but a branch palette you choose is not read.
- Everything starts expanded, and in the normal preview it stays that way. The app's handler sets `pointer-events: none` on the block, so clicks never reach the nodes and nothing folds.
- The map is created with wheel zoom on and drag panning off, but with pointer events off the wheel does nothing either. The map is fitted to the box when it first renders.

## Options: what to expect

Upstream Markmap lets a document set options in front matter under a `markmap` key. Its options page lists `color`, `colorFreezeLevel`, `maxWidth` and `initialExpandLevel`, for example `initialExpandLevel: 2` to collapse deeper levels on first render:

````markdown
---
markmap:
  initialExpandLevel: 2
  colorFreezeLevel: 2
---
````

The Markmap library bundled with MiaoYan V4.5.0 recognises this block inside a fence and strips it from the outline. But the app's own loader creates the map with fixed options and does not feed the parsed ones back. Loading the V4.5.0 preview files with `initialExpandLevel: 1` still drew every level. If you need collapsed levels or custom colors, use the Markmap web tools or a full Markmap-enabled editor for that map, then bring a screenshot into the note.

One option does exist in MiaoYan, but only in presentation mode: a comment `<!--markmap-height=400-->` inside the block sets the pixel height when you present the note as slides. In the normal preview the height is computed.

## Markmap or Mermaid mindmap

Mermaid has its own `mindmap` diagram type, started with the keyword `mindmap` and built from indentation, with one root and several node shapes. The Mermaid documentation calls it experimental. The Mermaid bundled with MiaoYan V4.5.0 is version 11.14.0 and draws a `mindmap` block, but since the syntax may still change, keep a small example to check after updates.

The two solve different problems. Markmap reads the headings and lists you already have, so it suits an outline that doubles as a note. Mermaid mindmap is a separate syntax, useful when the map should live in the same document language as your flowcharts and sequence diagrams. The [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/) post covers that side, and the [Markdown cheat sheet](/blog/markdown-cheat-sheet/) shows the fence form for all three diagram languages.

## Export and what goes wrong

- **The block shows as a normal code block.** The language word must be exactly `markmap` and the fence must be closed. Check the backtick count first.
- **The map is a single node.** The block needs headings or list items. A paragraph of prose on its own becomes one node with the whole sentence in it.
- **A very large outline.** Each node is drawn as an HTML label inside the SVG, and a few hundred nodes is hard to read even when it fits. Split the outline into several blocks, one per branch.
- **Links and formatting inside nodes.** Bold, inline code and links render inside nodes. A link cannot be clicked in the normal preview, because the map ignores pointer events, so do not use a map as navigation.
- **Export.** For PDF export, MiaoYan waits until every Markmap block has rendered before printing. Still open an exported file once: a diagram is a drawn snapshot, and large maps are the likeliest to be scaled.

To check it works, insert the template, switch to preview (`⌘3`) or split mode (`⌘\`), and confirm the tree appears with colored branches.

## FAQ

### Does Markmap need an internet connection in MiaoYan?

Not for a plain outline. The library files ship inside the app, unlike PlantUML, which sends the diagram to a public server. A node with math is the exception, since it loads KaTeX from a CDN.

### Can I make the map start collapsed?

No. In V4.5.0 the front matter options are ignored and the preview map does not respond to clicks, so every level shows. Split a large outline into several blocks instead.

### Can I edit the map directly?

No. The map is drawn from the text, so you edit the outline and the preview updates.
