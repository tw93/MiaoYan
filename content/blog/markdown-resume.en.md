Write the resume as one `.md` file, keep it in git, and turn it into a PDF with Pandoc and a small CSS file, or with MiaoYan's File > Export > PDF if you want no setup. Use only headings, bullet lists, bold and italic, links and, at most, one small table. The trade-off is control: MiaoYan prints a fixed A4 page in its own style with no custom CSS, while Pandoc lets you set paper, margins and fonts but needs a command-line install.

## A complete sample resume

This one is fictional. The structure is the part to copy: name as the only `#` heading, one contact line, then `##` sections.

```markdown
# Maya Okafor

Backend engineer · Rotterdam, NL · maya@example.com · [github.com/mayaokafor](https://github.com/mayaokafor)

## Summary

Backend engineer with seven years of experience building payment and invoicing services in Go and PostgreSQL. I like small services, boring deploys and clear runbooks.

## Experience

### Senior Backend Engineer, Brightwave Payments

*Rotterdam, NL · Mar 2022 to present*

- Rebuilt the invoice export service in Go, cutting the nightly run from 4 hours to 35 minutes.
- Led a team of four through a move from a monolith to six services, with no customer-facing downtime.

### Backend Engineer, Tulip Logistics

*Amsterdam, NL · Aug 2018 to Feb 2022*

- Built the shipment tracking API used by 40 partner carriers.
- Moved nightly jobs from cron to a queue, so a failed job retries on its own.

## Skills

| Area      | Tools                             |
| --------- | --------------------------------- |
| Languages | Go, Python, SQL, TypeScript       |
| Data      | PostgreSQL, Redis, Kafka          |
| Tools     | Docker, Terraform, GitHub Actions |

## Education

**BSc Computer Science**, Delft University of Technology, 2014 to 2018
```

The dates sit in an italic line under each job title, so the `###` heading stays short and a date change is a one-line diff.

## Which Markdown elements suit a resume

A resume is a short document with a repeating shape, which is what Markdown is good at.

**Headings.** One `#` for your name, `##` for sections, `###` for each job or degree.

**Bullet lists.** The body of each job, one achievement per bullet.

**Bold and italic.** Bold for a degree, italic for the place and dates line.

**Links.** Write the visible address as the link text, as in the sample. MiaoYan's PDF styles remove the link underline and color, so a link prints like ordinary text and a paper reader still sees the address.

**A small table.** A skills grid works, but a table needs a header row in GitHub Flavored Markdown, so the grid above carries "Area" and "Tools" labels you may not want. In MiaoYan's PDF a table also gets borders, a shaded header and equal-width columns. A bullet such as `- Languages: Go, Python, SQL` prints cleaner. The rules for header rows and alignment are in [Markdown tables](/blog/markdown-tables/).

**What to leave out.** Images, deeply nested lists and code blocks. Columns and sidebars are not possible in plain Markdown, so a two-column layout means HTML or a design tool.

## Getting to PDF with Pandoc

Pandoc converts the `.md` to HTML or LaTeX and hands it to a PDF engine. Its manual lists `weasyprint`, `xelatex`, `pdflatex` and others for `--pdf-engine`, and says `--css` only affects HTML and EPUB output. That gives two routes.

**HTML engine and CSS.** This is the one to start with, because styling is ordinary CSS. Save the file below as `resume.css`:

```css
@page { size: A4; margin: 16mm 18mm; }
body { font-family: "Helvetica Neue", Arial, sans-serif; font-size: 10pt; line-height: 1.45; }
h1 { font-size: 22pt; margin: 0 0 4pt; }
h2 { font-size: 11pt; text-transform: uppercase; border-bottom: 1px solid #999; margin: 14pt 0 6pt; }
h3 { font-size: 10.5pt; margin: 8pt 0 0; }
h3 + p { margin: 0 0 3pt; color: #555; }
ul { margin: 3pt 0; padding-left: 14pt; }
a { color: inherit; }
```

Then run it with WeasyPrint installed:

```bash
pandoc resume.md -o resume.pdf --pdf-engine=weasyprint --css=resume.css -M pagetitle="Maya Okafor, Resume"
```

With Pandoc 3.13 and WeasyPrint 68.1 the sample comes out as one A4 page of selectable text. `-M pagetitle=...` sets the PDF title without printing a title block.

**LaTeX.** Without `--pdf-engine`, Pandoc goes through LaTeX, so a TeX distribution must be installed. Pandoc's LaTeX output defaults to US Letter, so set the paper:

```bash
pandoc resume.md -o resume.pdf --pdf-engine=xelatex -V papersize=a4 -V geometry:margin=18mm -V mainfont="Helvetica Neue"
```

`papersize`, `geometry` and `mainfont` are variables in the Pandoc manual's LaTeX section. You get Pandoc's default LaTeX look, not the compact layout above. For a Chinese resume the manual says `CJKmainfont` needs `xeCJK` with `xelatex`; the HTML route avoids that, since a CSS line like `font-family: "PingFang SC"` is enough.

## Getting to PDF with MiaoYan

Select the note and choose File > Export > PDF. MiaoYan prints the rendered preview onto an A4 page (595.2 by 841.8 points) with margins of 40 points at the top, 48 at the bottom and 45 at the sides, and saves a file named after the note title in Downloads. The steps and shortcuts are in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/).

What you can and cannot change in version 4.9.0:

- The text and headings use the Preview Font from settings.
- Paper size, margins and headers are fixed.
- There is no custom CSS for the PDF.
- A note that starts with a `#` heading keeps it as the title, so your name is not printed twice. The PDF also gets a gray `1 / N` footer.
- Links lose their underline and color, tables get borders and a shaded header, and the page background is white even in a dark preview.

The result is a clean page, but you cannot restyle it. If the look matters, run Pandoc on the same `.md` file.

## Controlling the page break

To start a section on a new page, put a line of raw HTML between blocks:

```markdown
<div style="page-break-after: always"></div>
```

Pandoc with WeasyPrint honours it. The LaTeX route drops raw HTML, so the break is ignored there; write `\newpage` for LaTeX instead. MiaoYan keeps raw HTML in the preview and its PDF is printed by WebKit, which honours `page-break-after: always` (and the newer `break-after: page`) when it paginates, so the break carries into the export. The `1 / N` footer shows whether it landed.

## One source, several roles

Keep the longest version on `main`, then make a branch per role:

```bash
git switch -c resume/platform-engineer
```

Cut bullets and reorder sections on that branch. A typo fix or a new job goes on `main` and is merged into each role branch. Each branch exports its own PDF with the same command.

Front matter is useful for the build, not for the content. Put `pagetitle: Maya Okafor, Resume` at the top of the file and Pandoc uses it as the PDF title, so the command needs no `-M`. MiaoYan hides a leading front matter block in the preview and in exports, so it does not appear on the page. A key Pandoc does not use, like `role: backend`, stays out of the PDF too, which makes it a note for yourself, not a switch. Choosing content by role still means a branch or a second file. [Markdown front matter](/blog/markdown-front-matter/) covers the exact rules for when MiaoYan treats a block as front matter.

## What goes wrong

- **The table prints with borders and equal columns.** That is the MiaoYan print style. Use a bullet list for skills.
- **The page break does nothing.** In the LaTeX route raw HTML is dropped; use `\newpage`.
- **The LaTeX build fails on Chinese.** It needs `CJKmainfont` and `xeCJK`. Use the HTML route with a CSS `font-family`.
- **The PDF is Letter, not A4.** That is Pandoc's LaTeX default. Add `-V papersize=a4`.
- **A link prints as plain text.** That is intended in MiaoYan. Keep the address visible in the link text.

## FAQ

### Will a Markdown resume pass applicant tracking systems?

That depends on the system, and it only ever sees the PDF, not the Markdown. What you control is that the PDF holds real text in reading order: both Pandoc routes above produce selectable text that `pdftotext resume.pdf -` reads top to bottom, so run that on your file before you send it.

### Should I send the `.md` file instead of a PDF?

Send the PDF. Most application forms expect a PDF or Word file, and a PDF keeps your layout. Keep the `.md` as the source.
