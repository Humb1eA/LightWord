# LightWord · 轻词

一个纯离线的背单词 iOS App（参考百词斩的学习节奏），本机 Windows 上写代码、
云端 macOS 编译、回到 Windows 自签装机。词库为高考 3500 词，随包携带，不联网。

```
翻卡学新词 → 复习阶段四选一测验 → 生词本 / 连续天数 / 每日提醒
```

## 现在能做什么

| 功能 | 状态 |
| --- | --- |
| 高考 3500 词库（音标 + 中文释义，3853 词） | 已完成，解析校验通过 |
| 遗忘曲线调度（9 档 Leitner） | 已完成，单元测试覆盖 |
| 翻卡学新词 + 系统 TTS 发音 | 已完成 |
| 复习阶段四选一测验（干扰项来自同词库） | 已完成 |
| 生词本（搜索 / 收藏筛选 / 记忆等级） | 已完成 |
| 连续天数、每日目标、每日提醒（本地通知） | 已完成 |
| 数据持久化（Application Support 单文件 JSON） | 已完成 |
| 词书切换 / 云同步 / 例句 | 未做（词库有例句字段，现词表未带） |

## 为什么这样架构

- **Core 与 UI 分离**：`Sources/WordCore` 只 import Foundation，不碰 UIKit/SwiftUI。
  因此调度算法、日期、持久化都能在**没有模拟器、没有 Mac 的 Windows 上**通过
  `swift test` 验证。
- **不依赖 .xcodeproj**：`tools/build-ipa.sh` 直接用 `xcrun swiftc` + `actool`
  拼装 .app，CI 里少一个工程文件出错的可能。
- **词库用「源表 + 生成脚本」**：`tools/vendor/gaokao3500.raw.txt` 是源，
  `Resources/Wordbooks/gaokao.json` 是产物，格式错误在 CI 第一步就会被拦住。

## 目录

```
Sources/WordCore/      纯逻辑：DayKey / Word / Scheduler / SessionBuilder / Quiz / Study
Sources/LightWord/      SwiftUI 界面、AppStore、TTS、通知
Resources/             Info.plist、PrivacyInfo.xcprivacy、Assets.xcassets、Wordbooks/
Tests/CoreTests/       单元测试（期望值与 tools/reference_scheduler.py 一致）
tools/                 build-ipa.sh / inspect_ipa.py / 词库导入与校验 / 静态检查
.github/workflows/     云端 macOS 构建（出无签名 IPA）
docs/install-signing.md 自签装机步骤与排错
```

## 构建与测试

```bash
# 任意平台：词库、源码静态检查、调度算法参考实现
python tools/validate_wordbook.py
python tools/check_sources.py
python tools/reference_scheduler.py

# 有 Swift 工具链的机器（macOS 或 CI）
swift test

# 只有 macOS 能出 IPA
bash tools/build-ipa.sh
python tools/inspect_ipa.py build/LightWord-unsigned.ipa
```

CI（`.github/workflows/ios.yml`）在 GitHub Actions 的 macOS runner 上依次跑：
词库校验 → 单元测试 → 编译 → 检查 IPA 结构 → 上传 artifact。

## 词库

- 来源：[pluto0x0/word3500](https://github.com/pluto0x0/word3500)（高考 3500 词表，
  词 / 音标 / 中文释义）。仅作个人学习使用；若要分发请自行确认授权。
- 导入：`python tools/import_gaokao.py`，产物 `Resources/Wordbooks/gaokao.json`。
- 解析器以「音标行」为锚点反推词条，因此 `arise (arose, arisen)`、`afterward(s)`
  这类词形不会被误判；同一词的名词义/动词义会合并成一张卡（21 组）。
- 已知源数据瑕疵：`war` 的第二条释义（"警告"）实际属于 `warn`；共 44 条无音标，
  App 会隐藏空音标行。要修就改 `tools/vendor/` 源文件后重新导入。
- 换词库：把新词表按同样结构导出成 `Resources/Wordbooks/<id>.json`，
  再改 `Sources/LightWord/AppStore.swift` 里的 `loadBundled(name:)`。

## 签名与安装

免费 Apple ID + 7 天有效期，iOS 27 还需先开「开发者模式」。完整步骤、常见报错
和续签办法见 [docs/install-signing.md](docs/install-signing.md)。

## 把工程推到 GitHub（无需装 git）

```powershell
# 需要一个有 repo 权限的 PAT（Fine-grained: Contents = Read and write）
$env:GITHUB_TOKEN = "github_pat_xxx"
powershell -ExecutionPolicy Bypass -File tools\push_to_github.ps1 -Repo "你的用户名/lightword" -Private

# 先预览会上传哪些文件：
powershell -ExecutionPolicy Bypass -File tools\push_to_github.ps1 -Repo "你的用户名/lightword" -DryRun
```
