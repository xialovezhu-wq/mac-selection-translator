# 朗读设置、验证与回滚

## 使用

- `⌃⌥⌘R`：朗读当前选区。相同选区再次按键会取消等待或停止播放。
- `⌃⌥⌘T`：原有翻译功能。
- `⌃⌥⌘S`：打开中文朗读设置。若该键已被其他功能占用，本模块不抢占；可在 Hammerspoon 控制台调用 `selectionTranslator.openSpeechSettings()`。

设置可选择美音 `en-US`、英音 `en-GB`、具体声音和语速。先试听，再点击“保存为日常朗读设置”。正常预设使用 AVSpeech 原生参数 `0.50`，适度慢读使用 `0.43`；这些数值不是 NSSpeech 的每分钟词数。

2026-10-27 的本机用户试听后选择了 Daniel、英音、正常语速。具体声音 ID 为 `com.apple.voice.compact.en-GB.Daniel`，系统质量属性为基础级。用户随后确认在 Obsidian 中能够听到 Daniel。这表明选择与播放可用，不等同于人工发音评分或宣称所有长句都已达到理想听感。

设置窗口在创建时选择最左侧实体显示器，排除 iPad/Sidecar/OpenDisplay 等虚拟屏，显式设置最终位置后才显示。窗口使用不激活应用的面板；不会为展示设置切换学习应用或桌面。

## 实际问题与技术选择

原版 Hammerspoon 1.1.1 的 `hs.speech` 包装层会给非旧式 ID 自动添加 `com.apple.speech.synthesis.voice.` 前缀。因此源码中的现代 Samantha ID，在运行对象中变成了重复前缀的 ID。这个 ID 不在系统可用列表中，原生 NSSpeech 的属性查询把它解析到系统默认的 Tingting／`zh_CN`。仅检查对象创建成功或 `voice()` 返回的字符串不足以确认所选英语声音。

本次改用独立的小型 Swift `AVSpeechSynthesizer` helper。它通过 AVSpeech 自己的枚举读取语言和质量，创建后同时核对 voice ID、语言及 utterance 的实际 voice/rate。默认自动选择只在同口音内按质量排序，排除娱乐音色与个人声音；显式保存的声音始终优先。目标声音失效时，同口音回退会有状态说明和工作屏提示；没有可用同口音声音时失败，不悄悄切换口音。

本机检查时没有已安装的 enhanced/premium 英语声音，Samantha 与 Daniel 均为基础级。因此没有把“换 API”或基础级音色称为高质量资源升级。本轮没有下载额外语音模型，没有接入联网词典音频或付费 TTS。

## 请求、取消与隐私

- 原选区通过 JSON 标准输入传递，朗读不使用词典还原后的词头。`children`、`went`、`responses` 会保持原样。
- 采用纯字符串 utterance，不解释选文中的 shell 或 SSML 标记。
- 每个请求有唯一 ID。新词替换旧词时先停止旧助手，等其退出后才启动最后一个等待请求。
- 同词再次按键可以取消尚未开始的请求；模块停止或重载会使迟到回调失效。
- 停止只向已验证的语音助手 PID 发信号，拒绝 PID 0、进程组或 Hammerspoon 自身。助手也监测父进程退出，防止孤立的旧音频继续播放。
- 请求使用明确的 JSON 行边界。Hammerspoon 的输入管道保持打开时，助手也能立即处理，不再等待 EOF。
- 实际使用单次 `hs.task`，通过一个仅含声音/运行元数据的进度快照更新状态，避免依赖流式任务的取消收尾。

本地设置目录为 `~/.hammerspoon/mac-selection-translator/`：

| 文件 | 用途 |
|---|---|
| `speech-preferences.json` | 口音、声音 ID、语速与用户选择状态 |
| `speech-status.json` | 当前声音、等待/播放/停止状态及回退原因 |
| `speech-progress.json` | 当前助手的进度元数据，覆盖写入 |
| `speech-command.json` | 固定试听、停止与刷新声音的本地控制消息 |
| `speech-settings-window.json` | 本任务设置窗口的显示器与位置验证 |

这些文件不保存选区正文、个人释义或英语库内容。日常播放不产生磁盘音频缓存。显式生成的合成试听文件与测试报告保存在项目的被 Git 忽略的 `runtime/` 和工作目录，未写入正式英语库。

孤立的 `read`、`record`、`live` 可能有不同读法，状态会标记需要语境；选取包含它们的整句更有参考价值。

## 验证范围

- 真实 AVSpeech 枚举和实例化确认美音 Samantha、英音 Daniel 的 ID 与语言一致。
- 同一合成文本生成正常及适度慢读样本。比较文件只做固定整体增益调整到接近的响度，不改变内部重音和停顿。
- 原生助手在 stdin 保持打开时成功处理请求并生成有效音频；此项覆盖了接入时出现的无声等待问题。
- 当前运行中的 Hammerspoon 控制器已实测 Daniel 播放完成、等待中取消、同词停止和快速替换。最后一轮全部通过，宿主进程保持运行。
- 规则测试覆盖显式声音不被更高质量自动排序覆盖、缺失声音同口音回退、禁止跨口音静默回退、旧 185 WPM 参数拒绝、原词形和完整句子保真，以及迟到回调隔离。
- 用户确认 Obsidian 的实际划词快捷键可以听到 Daniel。
- 原有翻译、词性、个人库测试及文件校验同时验证。英语正式数据只读。

程序回调与音频文件证明合成/播放链路成功，不替代用户对长时间舒适度的反馈。

## 更新与回滚

只更新朗读文件：

```bash
bash scripts/build_speech.sh
python3 scripts/install.py --speech-only --apply
bash scripts/reload_speech.sh
```

这条路径只更新三份朗读相关 Lua 文件和 `SpeechHelper.app`，不改 `init.lua`、翻译程序、选区逻辑或英语索引。安装器为每次变更创建 `mac-selection-speech-时间戳` 备份。

回滚到本次改进前的原版时，应选首次备份，不要随意挑选调试过程中的中间备份：

```bash
hs -c 'selectionTranslator.stop()' </dev/null
python3 scripts/rollback_speech.py /path/to/the/first/mac-selection-speech-backup --apply
bash scripts/reload_speech.sh
```

回滚只恢复该备份记录的朗读代码和助手。用户已保存的声音偏好保留，其他快捷键和学习数据保持原样。原版不支持新声音设置界面，恢复原版也会恢复其旧朗读路径。

## 参考与许可

[British Council 的英美音说明](https://takeielts.britishcouncil.org/blog/british-or-american-english-ielts)及[IELTS 口语评分描述](https://ielts.org/cdn/ielts-guides/ielts-speaking-band-descriptors.pdf)支持按可理解性、重音、语调与节奏选择，而不是因为考试偏好某一种口音。

参考了 [Easydict 的语言筛选设计](https://github.com/tisfeng/Easydict/blob/be3b012b37cd10e5a9874d71f7d2bdb0bb05e139/Easydict/Swift/Service/Apple/AppleSpeechService/AppleSpeechService.swift)和英美音分别绑定来源的思路；Easydict 为 GPL-3.0。也读取了 NextAI Translator 的本地 TTS 设计（AGPL-3.0），但未引入其代码、模型或架构。本项目实现独立编写，使用 Apple 公共 API。
