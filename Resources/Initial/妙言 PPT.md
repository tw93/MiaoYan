# command + option + p  试试
---
# 妙言支持快速写 PPT 啦 🎉
---
# 怎么样，喜欢不？
- 也可以选择文档右键点击「妙言 PPT」启动
- 妙言会识别带 `---` 标志的文档方可打开
- 你可以按下「回车」试试，将看到预览大纲
- 底层使用 [Reveal](https://revealjs.com/markdown/)，更复杂使用可参考
---
<!-- .slide: data-background="#F8CB9E" -->
# 让我们改一个颜色看看
---
# 控制顺序也很简单
- Item 1：最后一个出现 <!-- .element: class="fragment" data-fragment-index="3" -->
- Item 2：第二个出现 <!-- .element: class="fragment" data-fragment-index="2" -->
- Item 3：第一个出现 <!-- .element: class="fragment" data-fragment-index="1" -->
---
# 展示代码也好弄
```js [1|2-4|5]
import {withTable，useTable} from 'table-render';
const Page = () => {const { refresh} = useTable();}
export default withTable(Page)
```
---
# 来一个牛逼的效果
<p class="fragment">Fade in</p>
<p class="fragment fade-out">Fade out</p>
<p class="fragment highlight-red">Highlight red</p>
<p class="fragment fade-in-then-out">Fade in, then out</p>
<p class="fragment fade-up">Slide up while fading in</p>

---
<!-- .slide: data-background-iframe="https://miaoyan.app/" -->
<!-- .slide: data-background-interactive -->
---
<!-- .slide: data-background-gradient="radial-gradient(#36563C, #4A674F)" -->
<h1 style="color:#fff">希望可以伴你写出妙言❤️</h1>