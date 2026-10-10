<div align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/Resources/app.icon/Assets/43.png" width="138" /></a>
  <h1>MiaoYan</h1>
  <p><b>Eine native Mac-App für lokale Markdown-Notizen</b></p>
  <p><a href="README.md">English</a> · <a href="README_CN.md">中文</a> · <a href="README_TW.md">繁體</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · Deutsch · <a href="README_FR.md">Français</a></p>
  <a href="https://twitter.com/HiTw93" target="_blank"><img alt="Twitter Follow" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
  <a href="https://t.me/+9f9gf4ZrFSQ2OWVl" target="_blank"><img alt="Telegram" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
  <a href="https://github.com/tw93/MiaoYan/releases" target="_blank"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/commits" target="_blank"><img alt="GitHub Commit Activity" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank"><img alt="GitHub Closed Issues" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
  <img alt="macOS 12.0+" src="https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square">
</div>

<img src="https://raw.githubusercontent.com/tw93/static/main/miaoyan/miaoyan.gif" width="900px" />

## Funktionen

- **Lokal zuerst**: Notizen sind Markdown-Dateien in einem Ordner deiner Wahl, ohne Datenerfassung; den Abgleich zwischen Geräten übernimmt iCloud Drive oder Nutstore
- **Fokussiert**: Ordner, Notizen und Editor in drei Spalten, mit Dark Mode und ohne Plugin-System, das gepflegt werden muss
- **Nativ**: Mit Swift 6 gebaut, leichter als Web-Wrapper, geteilte Vorschau mit 60fps-Bildlaufsynchronisation
- **Gut ausgestattet**: Wikilinks, LaTeX, Mermaid, Versionsverlauf, automatische Formatierung und PPT-Präsentationen integriert

## Installation

1. **Mac App Store** (kostenpflichtig, automatische Updates, inklusive iPhone- und iPad-App):

   <a href="https://apps.apple.com/cn/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Laden im Mac App Store" /></a>

2. **Homebrew**:
   ```bash
   brew install --cask miaoyan
   ```

3. **GitHub Releases**: Neueste DMG von [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) herunterladen (macOS 12.0+)

Homebrew und GitHub Releases installieren die Open-Source-Version, die ausschließlich Fehlerbehebungen erhält. Die Mac-App-Store-Version wird separat entwickelt und bekommt die neuen Funktionen.

## Synchronisation mit Nutstore oder anderen Cloud-Diensten

MiaoYan meldet sich nicht bei WebDAV oder Cloud-Diensten an; es liest und schreibt ausschließlich im ausgewählten Markdown-Ordner. Erstelle nach der Installation einen `MiaoYan`-Ordner in iCloud Drive, im vom Nutstore-Desktop-Client synchronisierten Verzeichnis oder an einem beliebigen Ort und lege ihn in den Einstellungen (⌘,) als Speicherpfad fest. Die Synchronisation zwischen Geräten übernehmen iCloud Drive, Nutstore, Dropbox oder andere Clients.

- **iPhone**: Wähle denselben Ordner in der Dateien-App aus, und falls ein Anbieter dort keinen beschreibbaren Ordner bereitstellt, nutze iCloud Drive oder lade den Ordner vorher für den Offline-Zugriff herunter
- **Ordnerprüfung**: MiaoYan prüft vor dem Wechsel die Lese- und Schreibberechtigung und behält den bestehenden Pfad, wenn der Ordner nicht verfügbar ist, ohne das Problem als Synchronisationsfehler von MiaoYan zu melden

## Befehlszeilenwerkzeug (CLI)

```bash
# Installation
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# Verwendung
miao open <Titel|Pfad>    # Notiz oder Ordner öffnen
miao new <Titel> [Text]   # Neue Notiz erstellen
miao search <Suchbegriff> # Notizen im Terminal durchsuchen
miao list [Ordner]        # Ordner der obersten Ebene oder Markdown-Dateien eines Ordners auflisten
miao cat <Titel|Pfad>     # Notizinhalt ausgeben
miao update               # CLI aktualisieren
```

## Geteilte Ansicht (Editor & Vorschau)

Editor und Vorschau stehen nebeneinander. Drücke `⌘\`, um die geteilte Ansicht umzuschalten, oder stelle in den Einstellungen unter General den Editor Mode auf Split Mode. Warum kein Typora-ähnliches WYSIWYG? Reines Markdown-Schreiben ist das Kernprinzip. Ein natives Swift-WYSIWYG wäre schwerfällig und instabil. Die geteilte Ansicht ermöglicht ablenkungsfreies Schreiben bei sofortigem visuellem Feedback.

<img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/assets/split-preview.png" width="100%" alt="Geteilte Ansicht (Editor & Vorschau)" />

## Dokumentation

- [Einführung in MiaoYan](Resources/Initial/Introduction%20to%20MiaoYan.md) - Bedienungsanleitung und Tastenkürzel
- [Markdown-Syntaxanleitung](Resources/Initial/MiaoYan%20Markdown%20Syntax%20Guide.md) - Syntaxübersicht mit Formeln und Diagrammen
- [PPT-Präsentationsmodus](Resources/Initial/MiaoYan%20PPT.md) - Anleitung zur Folienerstellung mit `---`-Trennlinien
- [MiaoYan Agent Skill](skills/miaoyan) - Bringt KI-Agenten MiaoYan-Syntax, Anhänge, PPT-Strukturen und CLI-Abläufe bei

Installiere den offiziellen Skill mit `npx skills add tw93/MiaoYan/skills/miaoyan -g`.

## Unterstützung

- Die direkteste Unterstützung ist der Kauf von [Mole for Mac](https://mole.fit), meiner Bereinigungs-App für macOS
- Wenn dir MiaoYan gefällt, vergib einen Stern, [teile es](https://twitter.com/intent/tweet?url=https://github.com/tw93/MiaoYan&text=MiaoYan%20-%20Eine%20native%20Mac-App%20f%C3%BCr%20lokale%20Markdown-Notizen) oder eröffne ein Issue oder einen PR
- Ich habe zwei Katzen, TangYuan und Coke. Wenn dir MiaoYan Freude bereitet, kannst du ihnen etwas <a href="https://cats.tw93.fun?name=MiaoYan" target="_blank">Dosenfutter 🥩</a> spendieren

<details>
<summary>Unterstützer 🐱</summary>
<br/>
<a href="https://cats.tw93.fun?name=MiaoYan"><img src="https://cdn.jsdelivr.net/gh/tw93/sponsors@main/assets/sponsors.svg" width="1000" loading="lazy" /></a>
</details>

## Danksagung

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - Ursprüngliche Projektstruktur
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift Markdown-Parser
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Markdown-Formatierung
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - Syntax-Highlighting
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT-Präsentations-Framework

## Lizenz

MIT License
