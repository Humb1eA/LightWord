# 自签装机（Windows + 免费 Apple ID + iOS 27）

目标：把 CI 产出的无签名 `LightWord-unsigned.ipa` 用你自己的 Apple ID 签好，
装到 iPhone 上。全程不需要 Mac。

---

## 0. 先确认三件事

| 项目 | 你的情况 | 影响 |
| --- | --- | --- |
| 账号类型 | 免费 Apple ID | 7 天过期、最多 3 个自签 App、不能用推送 |
| 系统版本 | iOS 27.2 beta | 必须开「开发者模式」；beta 系统上偶发安装失败属正常 |
| 设备 | iPhone 17 | 无 TrollStore 永久签可能，只能走 7 天重签 |

> TrollStore 只覆盖老系统（大致 iOS 17.0 以下），你的设备用不了，别在这上面花时间。

---

## 1. 准备 Windows 侧工具

1. 安装 **Sideloadly**：<https://sideloadly.io>（下载 exe 直接运行，免装）。
2. 你的机器已有 `Apple Mobile Device Support 19.4`，这是 Sideloadly 需要的驱动，
   一般不用再装 iTunes。
3. 数据线连接 iPhone → 手机上点「信任此电脑」→ 输入锁屏密码。

---

## 2. 打开 iPhone 的开发者模式（iOS 27 必做）

1. 用数据线连上电脑（或先装一次 App）。
2. 设置 → 隐私与安全性 → 拉到最底 → **开发者模式** → 打开。
3. 系统要求重启，重启后输入密码确认。

没开这个，装上去的 App 点开会直接闪退，且提示「开发者模式未开启」。

---

## 3. 拿到 IPA

两种方式，任选：

**A. 从 GitHub Actions 下载（推荐）**

1. 仓库 → Actions → 最新一次 `Build unsigned IPA` → 页面底部 Artifacts。
2. 下载 `LightWord-unsigned-ipa.zip`，解压得到 `LightWord-unsigned.ipa`。

> Artifacts 需要登录 GitHub 才能下载；默认保留 30 天。

**B. 本地 macOS 构建**

```bash
bash tools/build-ipa.sh
```

---

## 4. Sideloadly 签名安装

1. 打开 Sideloadly，`IPA` 处拖入 `LightWord-unsigned.ipa`。
2. `Apple ID` 填你的账号；`Password` 建议先去
   <https://account.apple.com> 生成一个 **App 专用密码**（避免二次验证卡住）。
3. 设备栏确认已识别到 iPhone。
4. 点 **Start**，等待日志出现 `done`。
5. 首次会要求安装描述文件：iPhone → 设置 → 通用 → **VPN与设备管理** →
   点开发者 App → 信任。
6. 回到桌面打开「轻词」。

### Bundle ID 冲突怎么办

免费账号要求每个 App 的 Bundle ID 唯一。Sideloadly 的 `Bundle ID` 框里可以改，
例如 `com.yourname.lightword`；本地构建时也可以：

```bash
BUNDLE_ID=com.yourname.lightword bash tools/build-ipa.sh
```

改 ID 等于装了一个新 App，学习进度会重新开始（进度存在 App 沙盒里）。

---

## 5. 7 天到期与续签

免费证书 7 天后失效，表现为：图标还在但点开立刻闪退。

**续签**：重复第 4 步，拖同一个 IPA、同一个 Apple ID，Sideloadly 会覆盖安装。
只要 Bundle ID 不变，App 内的学习进度会保留。

**想少折腾**：

- 付费开发者账号（$99/年）→ 证书 1 年，无需每周重签；
- 或使用 AltStore（Windows 装 AltServer，同一 Wi-Fi 下自动每 7 天续签）。

---

## 6. 常见报错对照

| 现象 / 报错 | 原因 | 处理 |
| --- | --- | --- |
| `Unable to install ...` | 开发者模式没开 | 做第 2 步 |
| 点开闪退、无提示 | 证书过期 / 未信任 | 重新签（第 4 步）并信任描述文件 |
| `Your maximum App ID limit has been reached` | 免费账号最多 3 个 App | 删掉其它自签 App，或换 Bundle ID 前先卸载 |
| `This device is not supported` | Sideloadly 版本太旧，不认 iOS 27 | 升级 Sideloadly |
| `Invalid anisette data` / 登录失败 | Apple 登录校验偶发 | 重试；换 App 专用密码；关掉代理 |
| 安装卡在 `Signing...` | 网络或 Apple 服务慢 | 等 1–2 分钟，仍不动就重开 Sideloadly |
| 提示「不受信任的开发者」 | 描述文件没信任 | 设置 → 通用 → VPN与设备管理 |

---

## 7. 数据在哪、什么时候会丢

- 位置：App 沙盒内 `Library/Application Support/LightWord/state.json`。
- 重签覆盖安装：保留。
- 卸载 App / 改 Bundle ID 重装：清空。
- 想备份：目前没有导出功能，需要的话可以加一个「导出 JSON」按钮
  （`LibraryRepository` 已经有 `load()`，加个 ShareLink 即可）。
