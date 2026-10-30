# 产品演示示意图

`demo-en.png` 是双语 README 共用的英文演示图（1440 × 920）。
参考用户提供的 Alfred 截图，使用可编辑的 `demo-en.svg` 绘制并导出 PNG。

此图不是实机截图：网页、进程和设备信息使用示例数据，
应用图标为简化图形；去掉了系统设置和文件搜索等与工作流无关的结果。
图内及两份 README 均注明 English UI mockup。
v1.2.0 工作流支持中英文界面，但示意图并非实机截图，文案不与当前界面逐字对应。

重新导出：

```sh
rsvg-convert --output docs/images/demo-en.png docs/images/demo-en.svg
```

普通构建直接打包已提交的 PNG，无需安装 SVG 渲染工具。
