<!--
transition: slide
backgroundTransition: none
slideNumber: c/t
hash: true
controls: true
progress: true
-->

# Try command + option + p

---

## MiaoYan PPT Mode

Beautiful presentations made simple

---

## Inline Configuration

Need to adjust animations or pagination? Add a leading HTML comment with `key: value` pairs:

```
<!--
transition: none
backgroundTransition: none
transitionSpeed: fast
controls: false
progress: false
slideNumber: c/t
-->
```
- Keys map directly to the [Reveal.js config](https://revealjs.com/config/) options
- Use dot notation for nested properties (e.g. `highlight.lineNumbers`)
- Values auto-detect booleans, numbers, `null`, bracketed lists `[a, b]`, or strings
- The comment is stripped before rendering, keeping slides clean

---

## Getting Started

- Method 1: Press `Command + Option + P` in any document
- Method 2: Right-click document and select "MiaoYan PPT"
- Method 3: Select presentation mode from menu bar
- Documents with `---` separators are automatically recognized
- Press Enter to preview slide outline

Built with [Reveal.js](https://revealjs.com/markdown/) for advanced features

---

<!-- .slide: data-background="#F8CB9E" -->
## Custom Backgrounds

You can customize slide backgrounds with colors, gradients, images, or even websites

---

## Animation Control

Watch these items appear in sequence:

- Item 3: First to appear <!-- .element: class="fragment" data-fragment-index="1" -->
- Item 2: Second to appear <!-- .element: class="fragment" data-fragment-index="2" -->
- Item 1: Last to appear <!-- .element: class="fragment" data-fragment-index="3" -->

Perfect for step-by-step explanations

---

## Code Highlighting

Progressive code revelation:

```swift [1|2-4|5-7|8]
import SwiftUI
struct MiaoYanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 600)
        }
    }
}
```

---

## Mathematical Formulas

MiaoYan supports LaTeX math in presentations:

$$E = mc^2$$

Inline math works too: $\pi \approx 3.14159$

Complex equations:
$$\sum_{i=1}^{n} x_i = \frac{n(n+1)}{2}$$

---

## Advanced Layout

### Two Column Layout

<div style="display: flex; gap: 2rem;">
<div style="flex: 1;">

**Left Column**

- Feature 1
- Feature 2
- Feature 3

</div>
<div style="flex: 1;">

**Right Column**

- Benefit A
- Benefit B
- Benefit C

</div>
</div>

---

## Visual Effects

<p class="fragment">Fade in</p>
<p class="fragment fade-out">Fade out</p>
<p class="fragment highlight-red">Highlight red</p>
<p class="fragment highlight-green">Highlight green</p>
<p class="fragment fade-in-then-out">Fade in, then out</p>
<p class="fragment fade-up">Slide up while fading in</p>
<p class="fragment grow">Grow effect</p>
<p class="fragment shrink">Shrink effect</p>

---

## Table Support

| Feature | Status | Rating |
|---------|--------|--------|
| Markdown | Complete | 5/5 |
| LaTeX Math | Complete | 5/5 |
| Code Syntax | Complete | 5/5 |
| Diagrams | Complete | 5/5 |

---

## Lists and Nested Content

### Ordered Lists

1. First important point
   - Sub-point A
   - Sub-point B
2. Second important point
3. Third important point

---

<!-- .slide: data-background-iframe="https://miaoyan.app/" -->
<!-- .slide: data-background-interactive -->

---

## Thank You
