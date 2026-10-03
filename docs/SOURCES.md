# 实现来源

核对日期：2026-10-03。

- [Hammerspoon AX 接口](https://www.hammerspoon.org/docs/hs.axuielement.html)：选区读取、父元素与查询超时。
- [Hammerspoon 全局快捷键](https://www.hammerspoon.org/docs/hs.hotkey.html)：快捷键可注册检查及注册结果。
- [Hammerspoon 语音](https://www.hammerspoon.org/docs/hs.speech.html)：系统语音、首字和结束回调。
- [Hammerspoon 原生 canvas](https://www.hammerspoon.org/docs/hs.canvas.html)：原生浮窗与点击行为。
- [Hammerspoon 后台任务](https://www.hammerspoon.org/docs/hs.task.html)：不通过 shell 传入选文。
- [Apple Dictionary Services](https://developer.apple.com/documentation/coreservices/dictionary_services)：公开词典接口。本机 SDK 的 `DCSGetTermRangeInString` 和 `DCSCopyTextDefinition` 已编译运行。
- [Apple TranslationSession](https://developer.apple.com/documentation/translation/translationsession)：本地离线翻译；构造器 availability 以本机 SDK 声明为准。
- [Apple prepareTranslation](https://developer.apple.com/documentation/translation/translationsession/preparetranslation())：官方语言资源准备；本机已成功完成并验证整句译文。
- [Apple NaturalLanguage](https://developer.apple.com/documentation/naturallanguage/nltagger)：词典未标注时的设备端词性识别，界面单独标记来源。
- [Easydict 2.23.0](https://github.com/tisfeng/Easydict/releases/tag/2.23.0)：原附件建议的对照路线。本项目未复制该项目源码。

个人库字段和只读边界以本机英语系统的 `schema/schema.md` 与 `wiki/workflows/query.md` 为准。本仓库只包含连接代码，个人正式库没有打包上传。
