# SoundFinder 图标

`icon.svg` 是可编辑的矢量源图，仓库根目录的 `icon.png` 是供 Alfred 使用的 512 × 512 RGBA 导出。

设计使用“放大镜内的声波”表达寻找声音来源：高对比白色镜框、青绿色声波、
深色圆角底板，外部区域透明。没有文字，便于在小尺寸下辨识。
这是本项目绘制的矢量图形，不是外部平台或 AI 图片服务产物。

使用 `rsvg-convert` 重新导出：

```sh
rsvg-convert --width 512 --height 512 --output icon.png assets/icon.svg
```

普通构建直接使用已提交的 PNG，不需要安装 SVG 渲染工具。
修改图标后请检查 32px、64px 和原图，再运行 `bash scripts/build.sh`，
安装包测试会核对 PNG 尺寸、格式及与源码图标的一致性。
