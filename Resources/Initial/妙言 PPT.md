# 试试 command + option + p 🎬

---

## 妙言 PPT 模式 🎉

*让演示文稿制作变得简单优雅*

---

# 快速开始 🚀

- **方法一：** 在任意文档中按 `Command + Option + P`
- **方法二：** 右键点击文档选择「妙言 PPT」
- **方法三：** 从菜单栏选择演示模式
- 带有 `---` 分隔符的文档会自动识别
- 按「回车」键预览幻灯片大纲

基于 [Reveal.js](https://revealjs.com/markdown/) 构建，支持高级功能

---

<!-- .slide: data-background="#F8CB9E" -->
# 自定义背景 ✨

你可以使用颜色、渐变、图片甚至网页作为幻灯片背景！

---

## 动画控制 🎭

观察这些项目按顺序出现：

- 项目 3：第一个出现 <!-- .element: class="fragment" data-fragment-index="1" -->
- 项目 2：第二个出现 <!-- .element: class="fragment" data-fragment-index="2" -->
- 项目 1：最后出现 <!-- .element: class="fragment" data-fragment-index="3" -->

非常适合分步骤讲解！

---

# 代码高亮 💻

渐进式代码展示：

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

## 数学公式 📊

妙言在演示文稿中完美支持 LaTeX 数学公式：

$$E = mc^2$$

行内数学公式也支持：$\pi \approx 3.14159$

复杂方程式：
$$\sum_{i=1}^{n} x_i = \frac{n(n+1)}{2}$$

---

# 视觉效果画廊 🎨

<p class="fragment">✨ 淡入效果</p>
<p class="fragment fade-out">👻 淡出效果</p>
<p class="fragment highlight-red">🔴 红色高亮</p>
<p class="fragment highlight-green">🟢 绿色高亮</p>
<p class="fragment fade-in-then-out">💫 淡入后淡出</p>
<p class="fragment fade-up">⬆️ 向上滑动淡入</p>
<p class="fragment grow">📈 放大效果</p>
<p class="fragment shrink">📉 缩小效果</p>

---

<!-- .slide: data-background="linear-gradient(45deg, #12c2e9, #c471ed, #f64f59)" -->
# 渐变魔法 🌈

<div style="color: white; text-align: center;">
<h2>美丽的渐变背景</h2>
<p>现代演示文稿的完美选择</p>
</div>

---

## 表格支持 📋

| 功能 | 状态 | 评分 |
|------|------|------|
| **Markdown** | ✅ 完整支持 | ⭐⭐⭐⭐⭐ |
| **LaTeX 数学** | ✅ 完整支持 | ⭐⭐⭐⭐⭐ |
| **代码语法** | ✅ 完整支持 | ⭐⭐⭐⭐⭐ |
| **图表绘制** | ✅ 完整支持 | ⭐⭐⭐⭐⭐ |

---

<!-- .slide: data-background-iframe="https://miaoyan.app/" -->
<!-- .slide: data-background-interactive -->
<div style="background: rgba(0,0,0,0.8); padding: 20px; border-radius: 10px; margin: 20px;">
<h2 style="color: white;">交互式背景</h2>
<p style="color: white;">甚至可以嵌入网页！</p>
</div>
