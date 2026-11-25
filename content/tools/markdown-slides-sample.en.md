<!--
slideNumber: c/t
-->

# MiaoYan PPT

Slides written in Markdown

---

## Three hyphens make a new slide

- Write on the left, the deck follows
- The deck turns to the slide the cursor is on
- Present plays it full screen, arrow keys turn the page, Esc leaves
- Save as PDF puts one slide on each page

---

## The comment at the top is the setup

```txt
<!--
transition: fade
slideNumber: c/t
controls: false
-->
```

- Keys are [reveal.js config](https://revealjs.com/config/) options
- Nested keys take a dot, as in `highlight.lineNumbers`
- The comment itself never shows on a slide

---

<!-- .slide: data-background="#F8CB9E" -->
## Custom backgrounds

Colours, gradients and pictures can all be a background

---

## Step by step

- First to appear <!-- .element: class="fragment" data-fragment-index="1" -->
- Second to appear <!-- .element: class="fragment" data-fragment-index="2" -->
- Last to appear <!-- .element: class="fragment" data-fragment-index="3" -->

Good for walking through a point

---

## Code highlighting

Lines light up a step at a time:

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

## Math

$$E = mc^2$$

Inline math too: $\pi \approx 3.14159$

$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$

---

## Two columns

<div style="display: flex; gap: 2rem;">
<div style="flex: 1;">

**Left**

- Feature 1
- Feature 2
- Feature 3

</div>
<div style="flex: 1;">

**Right**

- Benefit A
- Benefit B
- Benefit C

</div>
</div>

---

## Tables

| Feature | Status |
|------|------|
| Markdown | Supported |
| LaTeX math | Supported |
| Code highlighting | Supported |

---

## Thank you
