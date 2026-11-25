## Writing the outline

The first `#` heading is the centre, `##` headings are its branches, and list items hang under the nearest heading, nesting one level per indent; two spaces a level is the habit, and `Tab` and `Shift + Tab` in the editor add or remove one. Nodes can hold **bold**, *italic*, `code`, links and math in `$...$`. Click the dot on a node to fold or unfold its branch, drag to move the map, and pinch or hold `Ctrl` while scrolling to zoom.

When the map is ready, Copy Markdown gives you a markmap code block. Paste it into a MiaoYan note and the preview draws it with the same Markmap. More syntax, and how it compares with Mermaid's mind maps, is in [Markmap: turn a Markdown outline into a mind map](/blog/markmap-mind-maps/).

## FAQ

### How is it different from a Mermaid mind map?

Markmap reads the headings and lists of plain Markdown, so an outline you already have draws as it is and its branches fold on click. A Mermaid mindmap has its own indented syntax with brackets for node shapes, which pays off when it lives beside flowcharts and sequence diagrams. With an outline in hand, use Markmap; to keep it with other diagrams, use the [Mermaid Editor](/tools/mermaid-editor/).

### Does the exported image match what I see?

It has the same layout and colours, as the map is currently unfolded: folded branches stay out of the image. PNG is exported at twice the size, and node labels in the SVG are plain SVG text, so other apps show them and can edit the words.

### How is it different from the map in MiaoYan?

It uses the same Markmap version and colours as MiaoYan. In MiaoYan's preview the map has a fixed size and does not fold on click; here you can fold, zoom and drag, which helps with a long outline.

### Is my outline saved?

Your last outline stays in this browser for the next visit, until you switch browsers or clear the site's data. The map is drawn in your browser and the outline never reaches a server.
