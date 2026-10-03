# Mac 划词翻译与朗读

用两个全局快捷键，在当前阅读应用里查看选中词的中文意思或朗读原词。界面由已安装的 Hammerspoon 提供；本地 Swift 程序查询苹果英汉词典。无需翻译 API Key。

| 功能 | 快捷键 |
|---|---|
| 查询选中文字 | Control + Option + Command + T（⌃⌥⌘T） |
| 朗读选中文字 | Control + Option + Command + R（⌃⌥⌘R） |

先用鼠标选中词，再按快捷键。按 Esc、点击浮窗外部或点击 × 收起浮窗。长记录可在浮窗中滚动。朗读同一个词时再按一次朗读键可停止；选中另一个词则改读新词。

![未命中个人库时只显示中文释义](docs/screenshots/chinese-fallback.png)

## 查询顺序

1. 优先读取本地英语正式库 `bank/master_bank.csv`，显示当前词条的语境释义、用法、库内原句和复习备注。
2. 同词的多条记录分语境展示，附正式词条 ID。最多展示最近的四条，不把不同语境合并为一个通用释义。
3. 个人库未命中时，查询苹果本地英汉词典，只显示中文释义，不附系统词典的英文解释、音标和例句。
4. 词典也未收录时，可使用已经安装的苹果英中离线翻译包。未下载语言包时明确提示；当前本机的单词功能不依赖这个包。

个人库按词条或完整表达精确匹配，英文不区分大小写并规范空白。不做子串匹配，不把 `responses` 自动判成 `response`。保留真实原句，不生成新的学习例句。句型条目不进入划词词典。

## 本地安装

需要 macOS 15 或更新版本、Hammerspoon、Python 3，以及包含 Translation 新版 API 的 macOS SDK 26 或更新版本。整句翻译的直接离线入口需要 macOS 26 或更新版本。

```bash
bash scripts/build.sh
bash scripts/test.sh
python3 scripts/install.py --apply
```

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

查询不使用云端翻译、模型服务或浏览器登录。不保存查词历史。短期内存缓存最多 128 条、有效期五分钟；模块停止时清空。诊断接口只返回状态和耗时，不返回原文、译文或个人释义。

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
- `hammerspoon/selection_translator.lua`：全局热键、选区读取、浮窗与语音。
- `hammerspoon/english_lookup.lua`：个人库查询及变更刷新。
- `scripts/build_english_index.py`：只读正式 CSV，原子生成私有索引。
- `scripts/`：构建、安装、卸载和测试入口。
- `tests/`：合成数据测试。
- `docs/`：设计、来源和本机验收。
