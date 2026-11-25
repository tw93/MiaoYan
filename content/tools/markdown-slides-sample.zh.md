<!--
slideNumber: c/t
-->

# 妙言 PPT

用 Markdown 写幻灯片

---

## 一行三个短横就是一页

- 左边写，右边跟着变
- 光标停在哪一页，右边就翻到哪一页
- 点演示全屏放映，方向键翻页，Esc 退出
- 存成 PDF 时一张幻灯片占一页纸

---

## 开头的注释是配置

```txt
<!--
transition: fade
slideNumber: c/t
controls: false
-->
```

- 键名和 [reveal.js 的配置](https://revealjs.com/config/) 一样
- 嵌套的键用点号，比如 `highlight.lineNumbers`
- 注释本身不会出现在幻灯片上

---

<!-- .slide: data-background="#F8CB9E" -->
## 自定义背景

颜色、渐变和图片都能当背景

---

## 分步出现

- 第一个出现 <!-- .element: class="fragment" data-fragment-index="1" -->
- 第二个出现 <!-- .element: class="fragment" data-fragment-index="2" -->
- 最后出现 <!-- .element: class="fragment" data-fragment-index="3" -->

适合一步步讲

---

## 代码高亮

按行号一步步高亮：

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

## 数学公式

$$E = mc^2$$

行内公式也行：$\pi \approx 3.14159$

$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$

---

## 双栏布局

<div style="display: flex; gap: 2rem;">
<div style="flex: 1;">

**左栏**

- 功能 1
- 功能 2
- 功能 3

</div>
<div style="flex: 1;">

**右栏**

- 优势 A
- 优势 B
- 优势 C

</div>
</div>

---

## 表格

| 功能 | 状态 |
|------|------|
| Markdown | 完整支持 |
| LaTeX 公式 | 完整支持 |
| 代码高亮 | 完整支持 |

---

## 谢谢观看
