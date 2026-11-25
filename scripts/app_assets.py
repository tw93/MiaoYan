#!/usr/bin/env python3
"""Third-party files the tool pages load, other than Mermaid (mermaid_assets.py).

Most are copied byte for byte from MiaoYan's preview bundle on the app's
branch (Resources/DownView.bundle), so the Markdown viewer and the Markmap
editor draw with the files a note's preview uses: the preview stylesheets,
highlight.js 11.5.1, d3 6.7.0 and markmap-lib 0.14.1 with markmap-view 0.14.0
(one combined file), and for the slides page reveal.js 4.3.1 with MiaoYan's
white and night themes, its Markdown and highlight plugins, and KaTeX's
auto-render and mhchem. Two come from npm instead, each checked against the
registry's sha512: markdown-it 14.1.0, since the app parses Markdown natively
with cmark-gfm, and KaTeX 0.16.47 with its woff2 fonts, taken from npm while
the app's 0.16.0 let an edef expand past maxExpand (CVE-2024-28243, fixed in
0.16.10) and a pasted formula could freeze the page; the app moved to the same
0.16.47 on 2026-11-25. mammoth 1.13.0 (the browser build, its sha512 checked
against the registry, with its BSD-2-Clause LICENSE put in front as a comment
since the minified file carries none) reads a .docx for the HTML to Markdown
page, which loads it only when a Word file is opened. docx 9.15.3 (its
dist/index, math and html browser builds joined unchanged into one file behind
its MIT LICENSE, the package's sha512 checked against the registry) writes the
.docx of the Markdown viewer and Markdown to Word pages, loaded only when one
is saved.

    python3 -I scripts/app_assets.py --check   fail on a changed copy, note when
                                               the app's copy moved ahead
"""

import hashlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# site path: (app path or None, sha256)
FILES = {
    "assets/vendor/markdown-it-14.1.0.min.js": (None, "38c70a1e7ca91ab40e2d9e6e60129851a717ed1c7d4acbbdd41bf9503791cf68"),
    "assets/vendor/highlight-11.5.1.min.js": ('Resources/DownView.bundle/js/highlight.min.js', "7d31127fbc6c7cdfef1eb59800f9ec50cedb15efa81ff571dcfa5d13a0ad90f4"),
    "assets/vendor/preview/typography.css": ('Resources/DownView.bundle/css/typography.css', "7eca8db5f31fdcb50783cb51624c0c946508d082743a1d316a55d9491a362a81"),
    "assets/vendor/preview/theme-light.css": ('Resources/DownView.bundle/css/theme-light.css', "c929441d212b4e3b9256bb09a512fba9ea85a9c68f05ce29bc5901466c530059"),
    "assets/vendor/preview/base.css": ('Resources/DownView.bundle/css/base.css', "51fd8b37a4f5f45cb1843114d7bf81f9c7e4d8434323d04bca11704a12083133"),
    "assets/vendor/preview/diagrams.css": ('Resources/DownView.bundle/css/diagrams.css', "e004b542c098fa2e884422f6277edfbe78072de968cb185bb507755a42e55dee"),
    "assets/vendor/d3-6.7.0.min.js": ('Resources/DownView.bundle/js/d3.min.js', "fbb8da602a76f4ed49bac3561da62d8149fa121b8fd15685bacc21355d3a3322"),
    "assets/vendor/markmap-0.14.min.js": ('Resources/DownView.bundle/js/markmap-view.min.js', "40ba3d1e3c2c5f0b82a51a8c76767a6a8838f2b2fcdcc79e72cb7292a7585963"),
    "assets/vendor/reveal-4.3.1/reveal.js": ('Resources/DownView.bundle/ppt/dist/reveal.js', "028fe6706c37e4c010e7be04cd93d00662851ff8460a2f5c651adbd02d586a4b"),
    "assets/vendor/reveal-4.3.1/reveal.css": ('Resources/DownView.bundle/ppt/dist/reveal.css', "7c5950d6cd1a9d4ec3bc67a33863014ca1803967c7c3e84dc1734b13949de7b5"),
    "assets/vendor/reveal-4.3.1/theme/white.css": ('Resources/DownView.bundle/ppt/dist/theme/white.css', "cfef32fd1beec2454a41794ba2b69e1ff3180f3da75a80edeac40be85bef4cff"),
    "assets/vendor/reveal-4.3.1/theme/white_var.css": ('Resources/DownView.bundle/ppt/dist/theme/white_var.css', "70d9dc4d8e1c6738e0dc036777f5923a770e4a37eac680a33b8b5ba27541c783"),
    "assets/vendor/reveal-4.3.1/theme/night.css": ('Resources/DownView.bundle/ppt/dist/theme/night.css', "1859d7a27b615523491a71b893d78772f1ad67deb4b0b9e26f49a797b34db018"),
    "assets/vendor/reveal-4.3.1/theme/night_var.css": ('Resources/DownView.bundle/ppt/dist/theme/night_var.css', "44d122916c5f6552d3c979cd7626157330d27ff560861bc3f9f0737da174d7ec"),
    "assets/vendor/reveal-4.3.1/theme/common.css": ('Resources/DownView.bundle/ppt/dist/theme/common.css', "b7257d486ed86581b9f79ca942a0a218cca8969c64566e4109dbe379d94a66da"),
    "assets/vendor/reveal-4.3.1/plugin/markdown.js": ('Resources/DownView.bundle/ppt/plugin/markdown/markdown.js', "5b023d6665ef91cb2a1e80c91af092014495ce8f1d11892566eadbc8c20a6d86"),
    "assets/vendor/reveal-4.3.1/plugin/highlight.js": ('Resources/DownView.bundle/ppt/plugin/highlight/highlight.js', "47bcfa195929fc2c30309eb02ef2022f1e6acaec4e7d6aa2d5a32227d0a6567c"),
    "assets/vendor/katex/auto-render.min.js": ('Resources/DownView.bundle/js/auto-render.min.js', "e5372d199bcdae8b4de71d0f7ceba72a4ba12774a27c60a6f1f77d03b3228ee4"),
    "assets/vendor/katex/mhchem.min.js": ('Resources/DownView.bundle/js/mhchem.min.js', "aaf20145c0b8ecd450ccf6eb0cebece2f77d8e6a02c30d291f28c1167b57b2df"),
    "assets/vendor/mammoth-1.13.0.browser.min.js": (None, "a175021900f7b85e69684564cdcf2e7f15ba08d968255cc59d6677998d3b9fbb"),
    "assets/vendor/docx-9.15.3.js": (None, "32706f12e03acf0a0b89fa24ec82ab93b62f26f763e957c64d0c3bd739bc0996"),
    "assets/vendor/katex-0.16.47.min.js": (None, "a29d2961d3146de5949d78ac7c1a9d93ae54955bad22a6db4fbe836e88e8bf48"),
    "assets/vendor/katex/katex.min.css": (None, "0289a02cf451a44dd73add683a09644252363871ac11713a647b732cee8b1ee3"),
    "assets/vendor/katex/fonts/KaTeX_AMS-Regular.woff2": (None, "0cdd387c9590a1a9f9794560022dbb59654a7d86f187aa0c81495ad42d3a7308"),
    "assets/vendor/katex/fonts/KaTeX_Caligraphic-Bold.woff2": (None, "de7701e42cf1f4cf0b766c03fb27977207eee2f4fd5d76fa82188406da43ea4c"),
    "assets/vendor/katex/fonts/KaTeX_Caligraphic-Regular.woff2": (None, "5d53e70ad607c2352162dec9e0923fb54ecdafaccbf604cd8dcf7d00facb989b"),
    "assets/vendor/katex/fonts/KaTeX_Fraktur-Bold.woff2": (None, "74444efd593c005e3f4573b44524704c0af0a937fe911cca9e94068d0d140d3f"),
    "assets/vendor/katex/fonts/KaTeX_Fraktur-Regular.woff2": (None, "51814d270d06ff0255dba0799994fa4d8c84d11f09951d47595f4abb1f3602dc"),
    "assets/vendor/katex/fonts/KaTeX_Main-Bold.woff2": (None, "0f60d1b897938ec918c8ce073092411baf9438f6739465693ff18b0f9d20b021"),
    "assets/vendor/katex/fonts/KaTeX_Main-BoldItalic.woff2": (None, "99cd42a3c072d918f2f44984a807cf7aa16e13545fd0875fc07c6c65f99e715b"),
    "assets/vendor/katex/fonts/KaTeX_Main-Italic.woff2": (None, "97479ca6cce906abc961ecac96faa5f9ca2e61b8e7670d475826bcdee9a7c267"),
    "assets/vendor/katex/fonts/KaTeX_Main-Regular.woff2": (None, "c2342cd8b869e01752a9321dc17213fc40d4d04c79688c1d43f2cf316abd7866"),
    "assets/vendor/katex/fonts/KaTeX_Math-BoldItalic.woff2": (None, "dc47344dbb6cb5b655c8460d561f4df5f501b90c804ad3c6cec65fe322351ab1"),
    "assets/vendor/katex/fonts/KaTeX_Math-Italic.woff2": (None, "7af58c5ec8f132a2ddde9027c6d7814decce4d3b822a11192a42a20e2e973264"),
    "assets/vendor/katex/fonts/KaTeX_SansSerif-Bold.woff2": (None, "e99ae51144bf1232efcc1bfe5add36262c6866b0faab24fa75740e1b98577a62"),
    "assets/vendor/katex/fonts/KaTeX_SansSerif-Italic.woff2": (None, "00b26ac825e2095056396e0553b8ac26d3f8ad158c3826e28b4c45b385c4714a"),
    "assets/vendor/katex/fonts/KaTeX_SansSerif-Regular.woff2": (None, "68e8c73ef42afd3ccec58bf0fba302cce448938e7fc020a5e31f8a952eee1342"),
    "assets/vendor/katex/fonts/KaTeX_Script-Regular.woff2": (None, "036d4e95149b69ff9bcc0cd55771efeb25ffa3947293e69acd78d5ac328c684b"),
    "assets/vendor/katex/fonts/KaTeX_Size1-Regular.woff2": (None, "6b47c40166b6dbe21a5dfca7718413f2147fd2399be1ba605d8ad39cedf25dfe"),
    "assets/vendor/katex/fonts/KaTeX_Size2-Regular.woff2": (None, "d04c54219f9eaec6d4d4fd42dfb28785975a4794d6b2fc71e566b9cd6db842dd"),
    "assets/vendor/katex/fonts/KaTeX_Size3-Regular.woff2": (None, "73d591271b1604960cb10bb90fee021670af7297017e0e98480b332d11f51995"),
    "assets/vendor/katex/fonts/KaTeX_Size4-Regular.woff2": (None, "a4af7d414440a1c1790825cfb700cf9cf43b0f2c4b04f0ebc523011ad9853ec0"),
    "assets/vendor/katex/fonts/KaTeX_Typewriter-Regular.woff2": (None, "71d517d67827787cfabdf186914cc3358eda539e37931941f2b2fd4a21f68c0b"),
}


def problems():
    found = []
    for path, (_, pinned) in FILES.items():
        p = ROOT / path
        if not p.is_file():
            found.append(f"{path} is missing")
        elif hashlib.sha256(p.read_bytes()).hexdigest() != pinned:
            found.append(f"{path} changed: copy it again and update FILES")
    return found


def app_drift():
    notes = []
    for path, (app_path, pinned) in FILES.items():
        if not app_path:
            continue
        try:
            data = subprocess.run(["git", "show", f"origin/main:{app_path}"], cwd=ROOT, capture_output=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            continue
        if hashlib.sha256(data).hexdigest() != pinned:
            notes.append(f"note: origin/main {app_path} differs from {path}; copy it to follow the app")
    return notes


def main():
    for note in app_drift():
        print(note, file=sys.stderr)
    found = problems()
    for line in found:
        print(line, file=sys.stderr)
    if found:
        return 1
    print(f"app-assets-ok ({len(FILES)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
