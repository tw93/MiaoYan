<div align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/Resources/app.icon/Assets/43.png" width="138" /></a>
  <h1>MiaoYan</h1>
  <p><b>Une app Mac native pour vos notes Markdown locales</b></p>
  <p><a href="README.md">English</a> · <a href="README_CN.md">中文</a> · <a href="README_TW.md">繁體</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_DE.md">Deutsch</a> · Français</p>
  <a href="https://twitter.com/HiTw93" target="_blank"><img alt="Twitter Follow" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
  <a href="https://t.me/+9f9gf4ZrFSQ2OWVl" target="_blank"><img alt="Telegram" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
  <a href="https://github.com/tw93/MiaoYan/releases" target="_blank"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/commits" target="_blank"><img alt="GitHub Commit Activity" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank"><img alt="GitHub Closed Issues" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
  <img alt="macOS 12.0+" src="https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square">
</div>

<img src="https://raw.githubusercontent.com/tw93/static/main/miaoyan/miaoyan.gif" width="900px" />

## Fonctionnalités

- **Local d'abord** : les notes sont des fichiers Markdown dans le dossier de votre choix, sans collecte de données, et iCloud Drive ou Nutstore assure la synchronisation entre appareils
- **Épuré** : dossiers, notes et éditeur sur trois colonnes, avec mode sombre et sans système d'extensions à maintenir
- **Natif** : écrit en Swift 6, plus léger qu'un wrapper web, avec un défilement synchronisé à 60 fps dans l'aperçu divisé
- **Bien équipé** : wikilinks, LaTeX, Mermaid, historique des versions, mise en forme automatique et présentations PPT intégrés

## Installation

1. **Mac App Store** (payant, mises à jour automatiques, inclut l'application iPhone et iPad) :

   <a href="https://apps.apple.com/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Télécharger sur le Mac App Store" /></a>

2. **Homebrew** :
   ```bash
   brew install --cask miaoyan
   ```

3. **GitHub Releases** : téléchargez le dernier DMG depuis [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) (macOS 12.0+)

Homebrew et GitHub Releases installent la version open source, qui ne reçoit désormais que des correctifs. L'édition Mac App Store est développée séparément et accueille les nouvelles fonctionnalités.

## Synchronisation avec Nutstore ou d'autres services cloud

MiaoYan ne se connecte pas à WebDAV ni à des comptes cloud ; il lit et écrit uniquement dans le dossier Markdown choisi. Après l'installation, créez un dossier `MiaoYan` dans iCloud Drive, dans le répertoire synchronisé par le client de bureau Nutstore ou à l'emplacement de votre choix, puis ouvrez les Préférences (⌘,) et définissez-le comme emplacement de stockage. La synchronisation entre appareils est assurée par iCloud Drive, Nutstore, Dropbox ou un autre client.

- **iPhone** : sélectionnez le même dossier dans l'application Fichiers, et si un fournisseur n'y propose pas de dossier modifiable, utilisez iCloud Drive ou rendez le dossier disponible hors ligne au préalable
- **Vérification du dossier** : MiaoYan vérifie les accès en lecture et écriture avant de changer d'emplacement et conserve le chemin actuel si le dossier est inaccessible, sans signaler le problème comme une erreur de synchronisation de MiaoYan

## Interface en ligne de commande (CLI)

```bash
# Installation
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# Utilisation
miao open <titre|chemin>   # Ouvrir une note ou un dossier
miao new <titre> [texte]   # Créer une nouvelle note
miao search <terme>        # Rechercher des notes dans le terminal
miao list [dossier]        # Lister les dossiers de premier niveau ou les fichiers Markdown d'un dossier
miao cat <titre|chemin>    # Afficher le contenu d'une note
miao update                # Mettre à jour le CLI
```

## Mode Éditeur et Aperçu divisé

Édition et aperçu s'affichent côte à côte. Appuyez sur `⌘\` pour basculer en mode divisé, ou ouvrez les Préférences, section General, et réglez Editor Mode sur Split Mode. Pourquoi pas de WYSIWYG comme Typora ? L'écriture en Markdown pur est au cœur du projet. Un WYSIWYG natif en Swift est lourd et fragile ; le mode divisé garantit une écriture concentrée tout en offrant un retour visuel instantané et fluide.

<img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/assets/split-preview.png" width="100%" alt="Mode Éditeur et Aperçu divisé" />

## Documentation

- [Présentation de MiaoYan](Resources/Initial/Introduction%20to%20MiaoYan.md) - Guide d'utilisation et raccourcis clavier
- [Guide de syntaxe Markdown](Resources/Initial/MiaoYan%20Markdown%20Syntax%20Guide.md) - Référence de syntaxe avec formules et diagrammes
- [Mode présentation PPT](Resources/Initial/MiaoYan%20PPT.md) - Guide de création de présentations avec séparateurs `---`
- [MiaoYan Agent Skill](skills/miaoyan) - Enseigne aux agents la syntaxe MiaoYan, la gestion des pièces jointes, les présentations et le CLI

Installez le skill officiel avec `npx skills add tw93/MiaoYan/skills/miaoyan -g`.

## Soutien

- La façon la plus directe de me soutenir est d'acheter [Mole for Mac](https://mole.fit), mon application de nettoyage pour Mac
- Si MiaoYan vous est utile, laissez une étoile, [partagez-le](https://twitter.com/intent/tweet?url=https://github.com/tw93/MiaoYan&text=MiaoYan%20-%20Une%20app%20Mac%20native%20pour%20vos%20notes%20Markdown%20locales) ou ouvrez une issue ou une PR
- J'ai deux chats, TangYuan et Coke. Si MiaoYan vous apporte satisfaction, vous pouvez leur offrir de la <a href="https://cats.tw93.fun?name=MiaoYan" target="_blank">pâtée 🥩</a>

<details>
<summary>Ces personnes l'ont déjà fait 🐱</summary>
<br/>
<a href="https://cats.tw93.fun?name=MiaoYan"><img src="https://cdn.jsdelivr.net/gh/tw93/sponsors@main/assets/sponsors.svg" width="1000" loading="lazy" /></a>
</details>

## Remerciements

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - Référence initiale pour la structure du projet
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Analyseur Markdown en Swift
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Outils de formatage Markdown
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - Coloration syntaxique
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - Moteur de présentation PPT

## Licence

MIT License
