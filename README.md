# MarkdownEditor

一个面向 macOS、iPadOS 和 iOS 的原生 Markdown 编辑器工程。

## 当前进度

- 使用 SwiftUI 构建三端共享界面
- 创建、打开、编辑并自动保存 Markdown 文档
- UTF-8 文本读写
- Markdown 标题、代码、链接、引用、列表等语法着色
- 粗体、斜体、删除线、链接、代码、引用和列表格式工具栏
- `⌘B`、`⌘I`、`⌘K` 编辑快捷键
- 源码、分栏和预览三种布局
- 标题、段落、列表、任务、引用和代码块实时预览
- 文档大纲及标题跳转
- 基础字数、字符数和行数统计
- 系统浅色/深色模式

## 开发环境

需要安装完整的 Xcode。用 Xcode 打开 `MarkdownEditor.xcodeproj`，选择
`MarkdownEditor` scheme 和对应的 Mac、iPad 或 iPhone 运行目标即可。

当前工程的最低系统版本为：

- macOS 14.0
- iOS / iPadOS 17.0

## 目录结构

```text
Sources/
├── App/        应用入口
├── Document/   Markdown 文档读写
└── Editor/     编辑器界面
Config/         应用配置
```
