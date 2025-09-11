# Try command + option + p 🎬

---

# MiaoYan PPT Mode 🎉

*Beautiful presentations made simple*

---

# Getting Started 🚀

- **Method 1:** Press `Command + Option + P` in any document
- **Method 2:** Right-click document → "MiaoYan PPT"
- **Method 3:** Select presentation mode from menu bar
- Documents with `---` separators are automatically recognized
- Press "Enter" to preview slide outline

Built with [Reveal.js](https://revealjs.com/markdown/) for advanced features

---

<!-- .slide: data-background="#F8CB9E" -->
# Custom Backgrounds ✨

You can customize slide backgrounds with colors, gradients, images, or even websites!

---

# Animation Control 🎭

Watch these items appear in sequence:

- Item 3: First to appear <!-- .element: class="fragment" data-fragment-index="1" -->
- Item 2: Second to appear <!-- .element: class="fragment" data-fragment-index="2" -->  
- Item 1: Last to appear <!-- .element: class="fragment" data-fragment-index="3" -->

Perfect for step-by-step explanations!

---

# Code Highlighting 💻

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

Line-by-line highlighting:

```python [1-2|3|4|5-6]
def process_data(items):
    """Process a list of items with validation"""
    results = []
    for item in items:
        if validate_item(item):
            results.append(transform(item))
    return results
```

Fragment-based code reveal:

```javascript [|1|2-3|4-6|7-8]
// Modern JavaScript ES6+ features
const fetchUserData = async (userId) => {
  try {
    const response = await fetch(`/api/users/${userId}`);
    const userData = await response.json();
    return { success: true, data: userData };
  } catch (error) {
    return { success: false, error: error.message };
  }
};
```

---

# Mathematical Formulas 📊

MiaoYan supports LaTeX math in presentations:

$$E = mc^2$$

Inline math works too: $\pi \approx 3.14159$

Complex equations:
$$\sum_{i=1}^{n} x_i = \frac{n(n+1)}{2}$$

Quadratic formula:
$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

---

# Advanced Layout 🎯

## Two Column Layout

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

# Visual Effects Gallery 🎨

<p class="fragment">✨ Fade in</p>
<p class="fragment fade-out">👻 Fade out</p>
<p class="fragment highlight-red">🔴 Highlight red</p>
<p class="fragment highlight-green">🟢 Highlight green</p>
<p class="fragment fade-in-then-out">💫 Fade in, then out</p>
<p class="fragment fade-up">⬆️ Slide up while fading in</p>
<p class="fragment grow">📈 Grow effect</p>
<p class="fragment shrink">📉 Shrink effect</p>
---

# Table Support 📋

| Feature | Status | Rating |
|---------|--------|--------|
| **Markdown** | ✅ Complete | ⭐⭐⭐⭐⭐ |
| **LaTeX Math** | ✅ Complete | ⭐⭐⭐⭐⭐ |
| **Code Syntax** | ✅ Complete | ⭐⭐⭐⭐⭐ |
| **Diagrams** | ✅ Complete | ⭐⭐⭐⭐⭐ |

---

# Lists and Nested Content 📝

## Ordered Lists

1. First important point
   - Sub-point A
   - Sub-point B
2. Second important point
3. Third important point

---

<!-- .slide: data-background-iframe="https://miaoyan.app/" -->
<!-- .slide: data-background-interactive -->

---

# Thank You! 🙏
