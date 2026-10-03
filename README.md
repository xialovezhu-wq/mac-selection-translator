# Mac 划词翻译与朗读

用两个全局快捷键，在当前阅读应用里查看选词的词性与中文意思、翻译完整句子，或朗读原文。界面由已安装的 Hammerspoon 提供；本地 Swift 程序使用苹果英汉词典和设备端翻译。无需翻译 API Key。

| 功能 | 快捷键 |
|---|---|
| 查询选中文字 | Control + Option + Command + T（⌃⌥⌘T） |
| 朗读选中文字 | Control + Option + Command + R（⌃⌥⌘R） |

先用鼠标选中词，再按快捷键。按 Esc、点击浮窗外部或点击 × 收起浮窗。长记录可在浮窗中滚动。朗读同一个词时再按一次朗读键可停止；选中另一个词则改读新词。

![复数选词显示词性和中文释义](docs/screenshots/idealists.png)

![完整的两句选区翻译](docs/screenshots/whole-sentence.png)

## 查询顺序

1. 单词查询显示词性，释义优先读取本地英语正式库 `bank/master_bank.csv`，显示当前词条的语境释义、用法、库内原句和复习备注。
2. 同词的多条记录分语境展示，附正式词条 ID。最多展示最近的四条，不把不同语境合并为一个通用释义。
3. 个人库未命中时，查询苹果本地英汉词典，只显示中文释义，不附系统词典的英文解释、音标和例句。
4. 词典未收录的选文由苹果英中离线翻译处理。整句和连续多句选区将完整原文交给翻译引擎，不截取首词。已明确标记为词组的个人库条目保持个人库优先。

个人库先查完整选词，再使用系统词典确认的词形匹配，例如 `responses → response`。复数、部分时态和词典的屈折词形引用都可解析；不使用盲目删除 `s` 的规则，也不做子串匹配。保留真实原句，不生成新的学习例句。句型条目不进入划词词典。

词性优先采用词典标注，多种词性并列显示；词典不可用时采用系统词性识别并明确标记。仍无法确认的词会显示“词性：暂未确认”，不把猜测当成词典结论。

## 本地安装

需要 macOS 15 或更新版本、Hammerspoon、Python 3，以及包含 Translation 新版 API 的 macOS SDK 26 或更新版本。整句翻译的直接离线入口需要 macOS 26 或更新版本。

```bash
bash scripts/build.sh
bash scripts/test.sh
python3 scripts/install.py --apply
```

首次使用整句翻译时准备语言包：

```bash
bash scripts/prepare_languages.sh
```

准备窗口使用苹果官方 `prepareTranslation()` 下载或确认英语、简体中文离线资源，并实际翻译一个合成句子。显示“英中离线翻译已就绪”后即可使用同一个翻译热键。本机已完成准备和整句验证。

安装器会保留其他 Hammerspoon 模块，在 `init.lua` 末尾加入独立模块块，并在本机创建备份。随后在 Hammerspoon 菜单选择“Reload Config”。如系统要求，在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Hammerspoon。

默认自动接入 `~/Documents/kaoyan-english/bank/master_bank.csv`，文件不存在时正常使用本地词典。词库位于其他目录时：

```bash
python3 scripts/install.py --apply --english-root /path/to/kaoyan-english
```

安装前预览改动：

```bash
python3 scripts/install.py
```

文件监视器只观察被配置的英语库文件所在目录，遇到正式 CSV 更新时重建私有查词索引。个人索引保存在 `~/.hammerspoon/mac-selection-translator/english-index.json`，权限为 `0600`。英语原库保持只读，查询不更新学习记录、计数或掌握度。

## 响应与兼容性

中文词典查询使用编译后的 Swift 小程序，个人词库在内存中查询，重复的离线词典查询使用有界内存缓存。测量结果与范围见 [本机验收记录](docs/LOCAL_VERIFICATION.md)。语音的首字回调延迟与实际扬声器声波出现时间不同，报告中会明确区分。

采用辅助功能接口读取当前选区；不读取整篇正文，不模拟复制，不改写剪贴板。能否读取选区取决于目标应用。没有可读取的选区时提示，不沿用旧词。终端、密码管理器和安全输入区域拒绝取词。

浮窗显示在鼠标附近，限制在该显示器的可用范围内。浮窗不主动激活 Hammerspoon，实际焦点行为以验收结果为准。

## 隐私和运行方式

查询在本机执行，不使用云端翻译或浏览器登录。首次语言准备可以下载苹果离线资源。不保存查词历史。短期内存缓存最多 128 条、有效期五分钟；模块停止时清空。诊断接口只返回状态和耗时，不返回原文、译文或个人释义。

GitHub 项目包含连接器、源码、合成测试和说明文档。个人 CSV、私有索引、Hammerspoon 配置备份不属于仓库内容。

Hammerspoon 已有的启动设置负责启动本模块；本项目不新增 LaunchAgent。英语库路径和 Python 路径保存在本机私有配置中。

## 卸载

先在 Hammerspoon 控制台停止模块：

```lua
selectionTranslator.stop()
```

再执行：

```bash
python3 scripts/uninstall.py --apply
```

只移除本项目的模块、派生索引及托管配置块；保留英语正式库、其他快捷键和本次配置备份。

## 项目结构

- `src/DictionaryHelper.swift`：苹果英汉词典及已安装的苹果离线翻译。
- `src/LanguagePreparation.swift`：官方离线语言准备窗口。
- `hammerspoon/selection_translator.lua`：全局热键、选区读取、浮窗与语音。
- `hammerspoon/english_lookup.lua`：个人库查询及变更刷新。
- `scripts/build_english_index.py`：只读正式 CSV，原子生成私有索引。
- `scripts/`：构建、安装、卸载和测试入口。
- `tests/`：合成数据测试。
- `docs/`：设计、来源和本机验收。
