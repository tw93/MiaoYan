<h4 align="right">English | <strong><a href="https://github.com/tw93/MiaoYan/blob/main/README_ES.md">Español</a></strong> | <strong><a href="https://github.com/tw93/MiaoYan/blob/main/README_CN.md">简体中文</a></strong></h4>

<p align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://gw.alipayobjects.com/zos/k/t0/43.png" width="138" /></a>
  <h1 align="center">MiaoYan</h1>
  <div align="center">
    <a href="https://twitter.com/HiTw93" target="_blank">
      <img alt="Twitter 关注" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
    <a href="https://t.me/+GclQS9ZnxyI2ODQ1" target="_blank">
      <img alt="Telegram 群组" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
    <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">
      <img alt="GitHub 下载量" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/commits" target="_blank">
      <img alt="GitHub 提交活跃度" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank">
      <img alt="GitHub 已关闭议题" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
    <img alt="macOS 11.5+" src="https://img.shields.io/badge/macOS-11.5%2B-orange?style=flat-square">
  </div>
  <div align="center">Un cuaderno Markdown ligero que te acompaña a escribir palabras hermosas</div>
</p>

<img src="https://raw.githubusercontent.com/tw93/static/master/miaoyan/newmiaoyan.gif" width="900px" />

## Características

- **Fantástico**: Uso puramente local, no recopila ningún dato, resaltado de sintaxis, vista previa y edición en columnas, presentaciones PPT, LaTeX, diagramas Mermaid.
- **Hermoso**: Estilo de diseño minimalista, modo de tres columnas, modo oscuro, enfoque en la escritura.
- **Rápido**: Desarrollo nativo en Swift 6, proporciona una mejor experiencia de rendimiento en comparación con las aplicaciones basadas en Web.
- **Simple**: Ligero y puro, numerosos atajos de teclado, formato automático.

## Instalación y Uso

1. Instalación mediante Homebrew:
```bash
brew install --cask miaoyan
```
2. O instalación manual: Descarga el último paquete DMG desde [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) (requiere macOS 11.5+).
3. Abre el DMG y arrastra MiaoYan.app a la carpeta de Aplicaciones.
4. **Primera apertura**: Haz doble clic en MiaoYan.app para iniciar directamente, la aplicación ha sido notariada por Apple ✓.
5. Crea una carpeta llamada `MiaoYan` en tu iCloud Drive o en otra ubicación.
6. Abre las preferencias de MiaoYan y establece la ubicación de almacenamiento predeterminada en esa carpeta.
7. Haz clic en el ícono de "Nueva Carpeta" en la esquina superior izquierda, crea una categoría para tus documentos y comienza a escribir.

Después de la instalación, te sugerimos abrir la configuración (⌘,) para echar un vistazo. MiaoYan ofrece abundantes opciones de personalización, incluyendo modos de edición, estilos de temas, configuración de fuentes, etc., permitiéndote crear tu entorno de escritura exclusivo.

## Herramienta de Línea de Comandos

MiaoYan proporciona una herramienta de línea de comandos para facilitar la operación rápida de notas en la terminal.

```bash
# Instalación
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# Uso
miao open <título|ruta>    # Abre una nota
miao new <título> [texto]  # Crea una nueva nota
miao search <palabra>      # Busca notas en la terminal
miao list [carpeta]        # Lista el directorio principal, o el Markdown en el directorio especificado
miao cat <título|ruta>     # Imprime el contenido de la nota
miao update                # Actualiza el CLI
```

## Modo de Vista Previa y Edición en Columnas

El área de edición y el área de vista previa se muestran lado a lado, soportando sincronización de desplazamiento bidireccional a 60fps para previsualizar los efectos de edición en tiempo real.

**Cambio rápido**: Presiona `⌘\` para cambiar rápidamente al modo de columnas divididas, o actívalo en Configuración → Interfaz → Modo de Editor → Modo Dividido.

¿Por qué no usar una vista previa instantánea al estilo Typora? Buscamos una experiencia de edición Markdown pura, y la implementación nativa en Swift de la vista previa instantánea es demasiado compleja, lo que dificulta garantizar su estabilidad. El modo de columnas divididas proporciona retroalimentación visual en tiempo real mientras mantiene una experiencia de edición limpia.

<img src="https://gw.alipayobjects.com/zos/k/eg/jV8Gra.png" width="100%" alt="Modo de vista previa y edición en columnas divididas" />

## Guías de Uso

- [Introducción a MiaoYan](Resources/Initial/Introducción%20a%20MiaoYan.md) - Guía completa de uso, incluyendo atajos de teclado, etc.
- [Guía de Sintaxis Markdown](Resources/Initial/MiaoYan%20Guía%20de%20Sintaxis%20Markdown.md) - Demostración completa de sintaxis, fórmulas matemáticas, gráficos, etc.
- [Modo de Presentación PPT](Resources/Initial/MiaoYan%20PPT.md) - Guía de presentación utilizando `---` para separar diapositivas.

## Soporte

<a href="https://miaoyan.app/cats.html"><img src="https://rawcdn.githack.com/tw93/MiaoYan/vercel/assets/sponsors.svg" width="1000px" /></a>

1. Tengo dos gatos: Tangyuan y Cola. Si MiaoYan te hace feliz, <a href="https://miaoyan.app/cats.html" target="_blank">invítales una lata de comida 🥩</a>.
2. Si te gusta MiaoYan, eres bienvenido a darle una Estrella (Star), y te invitamos a recomendarlo a amigos con intereses similares.
3. Puedes seguir mi [Twitter](https://twitter.com/HiTw93) para recibir las últimas noticias de actualización, y también eres bienvenido a unirte al grupo de chat en [Telegram](https://t.me/+GclQS9ZnxyI2ODQ1).

## Agradecimientos

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - Referencia de la estructura inicial del proyecto
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Analizador Markdown en Swift
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Herramienta de formato Markdown
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - Soporte para el resaltado de sintaxis
- [Cang'er Fonts](https://tsanger.cn/product) - Fuente Cang'er Jinkai (fuente predeterminada)
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - Marco de trabajo para presentaciones PPT
- [Vercel](https://vercel.com?utm_source=tw93&utm_campaign=oss) - Soporte de alojamiento estático para [miaoyan.app](https://miaoyan.app/)

## Licencia

Licencia MIT - Siéntete libre de usar y contribuir
