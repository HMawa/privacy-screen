# 隐私屏 Privacy Screen

> 离开座位时，用「截图豁免」的全屏遮罩挡住屏幕，AI 的截图调试不受影响，路过的人看不到桌面内容。
>
> A fullscreen privacy overlay with screenshot exclusion — physical screen shows a fake maintenance screen, AI screenshots see the real desktop underneath.

---

## 目录 Table of Contents

- [用途 Purpose](#用途-purpose)
- [环境要求 Requirements](#环境要求-requirements)
- [已知缺陷 Limitations](#已知缺陷-limitations)
- [注意事项 Notes](#注意事项-notes)
- [快速开始 Quick Start](#快速开始-quick-start)
- [更多文档 Full Documentation](#更多文档-full-documentation)
- [许可与免责 License & Disclaimer](#许可与免责-license--disclaimer)

---

## 用途 Purpose

### 解决什么问题

人离开电脑时，项目/AI 还要继续跑。锁屏会中断 AI 的截图调试（锁屏后黑屏，AI 抓不到东西）；不锁屏屏幕内容会被路过的人看到。

### 怎么解决的

利用 Windows 的 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` API，做一个全屏置顶遮罩窗口：

| 视角 | 看到的内容 |
|---|---|
| **物理屏幕前的人** | "系统维护中 · 请勿操作" 遮罩（看不清桌面） |
| **AI 软件截图**（GDI / DXGI / WGC） | Windows 自动把遮罩从截图里剔除 → 看到**真实桌面**，调试不受影响 |
| **AI 键鼠自动化** | 遮罩点击穿透、不抢焦点 → 自动化照常工作 |

### 额外功能

- **静默密码解锁**：遮罩时直接打字输入密码即可解锁，全程无任何提示，室友乱按也不会动到你的项目
- **真人鼠标/触控板屏蔽**：键鼠钩子吞掉真人输入，AI 注入式输入放行；触控板支持设备级禁用（连三指手势都能切断）
- **远程控制联动**：检测到向日葵/AweSun 被控时自动收起遮罩，断开后自动恢复
- **防烧屏**：文字像素漂移 + 背景亮度微变，OLED/IPS 长时间显示也不留残影
- **托盘菜单**：所有功能开关、模式切换、密码管理都在托盘右键里运行时操作，设置自动保存

### 不解决什么

- ❌ 不是安全锁（任务管理器可结束进程）——是"防窥"不是"防盗"
- ❌ 防不了手机拍照/摄像头——只作用于软件截图
- ❌ 不能在锁屏状态下工作——锁屏本身就会中断 AI 截图

---

## 环境要求 Requirements

| 项目 | 要求 |
|---|---|
| **系统** | Windows 10 2004 (build 19041) 及以上（WDA_EXCLUDEFROMCAPTURE 从这版开始支持） |
| **运行时** | PowerShell 5.1（Windows 自带），无需安装额外依赖 |
| **.NET** | 随 PowerShell 附带的 .NET Framework 4.x 即可（WinForms / GDI+ / P/Invoke） |
| **权限** | 普通用户即可运行；设备级触控板禁用需一次管理员权限（配置计划任务，之后不用再提权） |
| **显示器** | 单屏/多屏均可；混合 DPI 多屏可能有几像素偏差 |
| **截图豁免验证** | 不同截图路径对豁免的支持程度不同，**首次使用请跑 `selfcheck.ps1` 实测** |

### AI 工具兼容性参考

| 截图路径 | 代表工具 | 豁免是否生效 |
|---|---|---|
| GDI (BitBlt) | mss、PIL ImageGrab、pyautogui | ✅ 生效（已实测） |
| DXGI (Desktop Duplication) | OBS、基于 Desktop Duplication 的截图 | ✅ 生效（已实测） |
| WGC (Windows.Graphics.Capture) | 新版电脑操作类代理、Win11 截图工具 | ✅ 按微软文档应生效（建议实测） |

---

## 已知缺陷 Limitations

1. **不是安全锁**：任何能碰到电脑的人都可以 `Ctrl+Alt+Del` → 任务管理器 → 结束 PowerShell 进程，遮罩随之消失。本工具是"防路过的人瞟一眼"，不是"防有物理接触的攻击者"。

2. **个别抓屏方式可能不尊重豁免**：`WDA_EXCLUDEFROMCAPTURE` 是 Windows 提供的机制，但某些驱动级或内核级的截屏软件可能绕过它。以 `selfcheck.ps1` 实测为准。

3. **注册表触控板开关在 Win11 新版本上对手势无效**：`HKCU\...\PrecisionTouchPad\Status\Enabled` 写成功了，但三指/四指手势仍然可用（Win11 build 26200 实测）。需要真正切断手势请配置设备级禁用（`setup-touchpad.cmd`）。

4. **混合 DPI 多显示器有像素偏差**：不同缩放比例的显示器混插时，遮罩可能有 ±几像素的错位。单屏或同缩放比例无此问题。

5. **进程被强杀后亮度可能不恢复**：如果用了 `-DimBrightness` 且进程被强制结束，显示器亮度会停在最低值。重新运行脚本再正常退出一次即可恢复；或者手动调亮度。

6. **DXGI 排他性**：每个显示器同一时刻只能有一个程序用 Desktop Duplication。AI 工具若正在用 DXGI 抓屏，selfcheck 的 DXGI 部分会提示不可用（先关掉 AI 再测）。

7. **灭屏后无法看到输入反馈**：`-ScreenOff` 模式下显示器断电，键盘仍能捕获密码但没有任何视觉反馈，输错了也不知道。这是设计使然（静默解锁），但首次使用可能不适应。

8. **远程检测依赖"可见窗口"判据**：如果远程工具被控时不弹可见窗口（或者你用的工具不在默认进程列表里），自动检测不会触发。可用 `-RemoteProcesses` 自定义进程名，或用热键 `Ctrl+Shift+Alt+R` 手动切换。

---

## 注意事项 Notes

### 使用前必做

- **先跑 selfcheck**：`selfcheck.ps1` 用 GDI+DXGI 双路径实测豁免是否生效，确认你的 AI 工具对应的截图路径能正常看到桌面再日常使用
- **设个密码**：默认密码 `1234`，首次使用建议改掉。托盘 → 密码管理 → 修改密码

### 紧急情况

| 情况 | 怎么办 |
|---|---|
| 鼠标触控板都没反应，是不是死机了？ | 敲密码解锁；或 `Ctrl+Alt+Del` → 任务管理器 → 结束 PowerShell |
| 触控板卡在禁用状态 | 双击 `restore-touchpad.cmd`，或 `privacy-screen.ps1 -FixTouchpad` |
| 亮度没恢复 | 重新运行脚本再正常退出一次，或手动调显示器亮度 |
| 新旧版本冲突（提示已有实例） | 用 `silent-launch.exe -Replace` 让新版顶掉旧版 |

### 日常使用建议

- **双击 `silent-launch.exe` 启动**（完全无窗口），程序常驻托盘，离开前按热键或托盘菜单开启遮罩
- OLED 屏幕长时间离开建议用 `-Mode black`（纯黑）+ 防烧屏，减少残影风险
- 担心室友按 Win+L 锁屏中断 AI？可参考 README 末尾的"防误锁屏"章节禁用锁定功能
- 所有运行时开关状态自动保存到 `settings.conf`，下次启动恢复上次的配置
- **Num Lock 不会被屏蔽**——数字键盘锁开关始终可用，不影响密码输入

---

## 快速开始 Quick Start

```bat
:: Simplest: double-click
run.cmd

:: Or from command line
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1
```

启动后遮罩立即盖住所有显示器。**Ctrl+Shift+Alt+F12** 显示/隐藏遮罩；托盘图标（蓝色圆点）双击切换、右键菜单可操作。程序常驻托盘，离开前开一次即可。

---

## 托盘菜单 Tray Menu

| Item | Description |
|---|---|
| 显示遮罩 | Show overlay immediately |
| 遮罩模式 → | Submenu: 维护伪装 / 纯黑屏 / 锁屏伪装 (switches live if overlay is shown) |
| 功能开关 → | All toggles work at runtime: |
| 　☑ 防烧屏 | Pixel drift + subtle brightness variation |
| 　☑ 屏蔽鼠标 | Block real mouse input; AI injected input passes through |
| 　☑ 屏蔽触控板 | Device-level / registry touchpad + gesture disable |
| 　☐ 吞掉点击 | Overlay eats clicks (off by default — clicks pass through to AI) |
| 　☐ 灭屏 | Turn off monitor power when overlay is shown |
| 　☐ 压亮度 | Lower physical brightness when overlay is shown |
| 　☑ 远程检测 | Detect Sunlogin/AweSun remote control sessions |
| 　☑ 远控收遮罩 | Hide overlay when remotely controlled (off = only pass through input) |
| 密码管理 → | Password management: |
| 　修改密码... | Dialog to set new password, saved to `password.txt`, effective immediately |
| 　关闭密码 | Clear password and delete `password.txt` (also disables mouse block & screen-off) |
| 热键设置 → | Hotkey settings: |
| 　修改切换热键... | Dialog to change the show/hide hotkey, saved to `settings.conf` |
| 　当前: xxx | Shows current hotkey |
| 隐藏遮罩 | Hide overlay (disabled when password is set — type password to unlock) |
| 退出 | Exit program |

> Checkmarks reflect current state. Switching while overlay is shown auto-refreshes it.
> All settings are persisted to `settings.conf` automatically.

### 互斥与联动规则 Constraints & Dependencies

To prevent unrecoverable states or wasted resources, these rules apply automatically:

| Rule | Description |
|---|---|
| 灭屏需密码 | Can't enable screen-off without a password (can't unlock otherwise); clearing password disables screen-off |
| 灭屏→防烧屏 | Screen-off auto-disables anti-burn (meaningless when screen is off); restored when screen-off is turned off |
| 灭屏→压亮度 | Screen-off auto-disables dim-brightness; restored when screen-off is turned off |
| 屏蔽鼠标需密码 | Can't enable mouse block without a password; clearing password disables it |
| 远控收遮罩需远程检测 | Can't enable remote-hide without remote-detect; disabling remote-detect auto-disables remote-hide |

---

## 自检 Self-Check

**Before first use, verify the screenshot exclusion works on your machine** (~6 seconds, a pink test block appears twice in the bottom-right corner — confirm you can see it with your eyes):

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\selfcheck.ps1
```

The self-test compares three phases (baseline / no-exclusion control / with-exclusion) across both GDI and DXGI capture paths. The result tells you directly whether your AI's screenshot library will see the real desktop or the overlay:

- **GDI** path ≈ mss, PIL ImageGrab, pyautogui (most common for Python AI agents)
- **DXGI** path ≈ OBS, Desktop Duplication-based capture
- **WGC** (Windows.Graphics.Capture, used by newer capture tools / computer-use agents) should also respect the exclusion per Microsoft docs; not directly tested here — verify with your actual AI tool.

---

## 常用参数 Parameters

| Parameter | Description |
|---|---|
| `-Mode maintenance` (default) | Dark overlay + "System maintenance" + fake progress percentage |
| `-Mode black` | Pure black screen (looks like monitor is off) |
| `-Mode lockstyle` | Lock screen wallpaper + large clock + "Locked · Do not touch" |
| `-Mode image -ImagePath path` | Custom image overlay |
| `-Text 'line1\|line2'` | Custom overlay text; use `\|` or newlines (or `\n`) for multiple lines; works with any mode. **If `-Text` is not set, reads from `overlay-text.txt` in the same directory** |
| `-Password 1234` | **Default: 1234**. Type password silently to unlock while overlay is shown (no prompts, nothing typed into your project); pass `-Password ''` to disable password (hotkey toggles directly) |
| `-Hotkey 'Ctrl+Shift+Alt+F12'` | Custom hotkey (supports F1-F24, letters, Esc, Pause, etc.) |
| `-ScreenOff` | Turn off monitor power when overlay is shown (more convincing "away" look; any keyboard/mouse input wakes the monitor, but overlay remains) |
| `-DimBrightness` | Lower physical brightness to minimum when overlay is shown, auto-restore when hidden (fallback beyond `-ScreenOff`) |
| `-EatClicks` | Overlay eats mouse clicks (default: clicks pass through for AI; **enabling this also blocks AI mouse input**) |
| `-BlockMouse` (on by default) | **Block real mouse input** during overlay (movement, clicks, scroll all ignored); AI injected mouse input passes through. `-BlockMouse:$false` to disable |
| `-BlockTouchpad` (on by default) | **Disable entire precision touchpad** during overlay (3/4-finger gestures, tap all disabled), auto-restore on unlock. `-BlockTouchpad:$false` to disable |
| `-FixTouchpad` | Emergency: restore touchpad and exit (use if touchpad is stuck disabled) |
| `-RemoteDetect` (on by default) | Detect remote control (Sunlogin/AweSun) and don't interfere |
| `-RemoteHideOverlay` (on by default) | **Hide entire overlay** when remotely controlled, auto-restore on disconnect; `:$false` to only pass through input while keeping overlay |
| `-RemoteEndDelaySec 15` | Debounce seconds for disconnect detection (brief disappearance of detection criteria won't immediately restore overlay) |
| `-RemoteProcesses names` | Remote tool process names to monitor, default `AweSun,awesun_guard,SunloginClient,SunloginRemote` |
| `-ScanRemote` | Diagnostic: print remote tool process/window/TCP connections and detection result |
| `-SetupTouchpadDevice` | One-time setup: create scheduled tasks for touchpad device disable/enable (requires admin, UAC prompt) |
| `-RemoveTouchpadDevice` | Remove the two scheduled tasks and device record |
| `-TouchpadMode auto\|registry\|device\|off` | Touchpad blocking mode, default `auto` (device-level if configured, registry otherwise) |
| `-TouchpadInstanceId "ID"` | Manually specify touchpad device instance ID (when auto-detection is inaccurate) |
| `-Replace` | Kill old Privacy Screen instances before starting (use when old instance holds the single-instance lock) |
| `-AntiBurn` (on by default) | Anti-burn-in: text/image drifts slightly every 20s + subtle background brightness change. `-AntiBurn:$false` to disable |
| `-HideConsole` | Hide console window (use with `silent-launch.exe` for completely windowless operation) |
| `-StartHidden` | Start without showing overlay; press hotkey to show |
| `-SelfTest` | Quick GDI self-test (use selfcheck.ps1 for full dual-path test) |
| `-CompileOnly` | Compile-check only, no windows |

Examples:

```bat
:: Maintenance overlay + password + screen-off (double protection)
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Password 1234 -ScreenOff

:: No password (hotkey toggles overlay directly)
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Password ''

:: Lock screen wallpaper disguise
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Mode lockstyle

:: Custom text (| separates lines) with password
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Text 'Running experiment|Do not touch|Be right back' -Password 1234

:: Silent windowless operation (daily use: just double-click silent-launch.exe)
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -HideConsole

:: Keep physical mouse usable (rely only on touchpad disable for gestures)
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -BlockMouse:$false
```

---

## 鼠标 / 触控板 / 手势屏蔽 Mouse & Touchpad Blocking

Three layers of blocking during overlay:

| Layer | Parameter | Effect |
|---|---|---|
| Keyboard/mouse hook | `-BlockMouse` (on) | Blocks real mouse movement, clicks, scroll; AI injected input passes through |
| Touchpad disable | `-BlockTouchpad` (on) | Two modes: registry / device-level |
| Gesture switches | Follows touchpad | Registry mode also sets `ThreeFingerSlide/Tap`, `FourFingerSlide/Tap` to 0 |

**Why gestures need separate handling**: 3/4-finger gestures are processed by the system gesture engine directly and don't generate mouse/keyboard events, so hooks can't block them — the touchpad itself must be disabled.

### Registry mode (default, no admin needed)
Writes `HKCU\...\PrecisionTouchPad\Status\Enabled=0`.

> ⚠️ **On Win11 build 26200 this switch writes successfully but 3-finger gestures still work** — Windows doesn't apply it to the gesture engine in real time. Use as fallback only.

### Device-level mode (recommended, truly blocks gestures)
One-time setup (one UAC prompt, then no more elevation needed) — **just double-click `setup-touchpad.cmd`**, or run from this directory:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -SetupTouchpadDevice
```

It auto-detects the touchpad device (use `-TouchpadInstanceId "ID"` to specify manually if detection is off) and creates two scheduled tasks `PrivacyScreen-TouchpadOff/On` (`pnputil /disable-device` and `/enable-device`, running with highest privileges). After that, starting Privacy Screen disables the touchpad device via the task — **pointer and 3/4-finger gestures all stop working** — and re-enables on unlock.

- Undo: `privacy-screen.ps1 -RemoveTouchpadDevice`
- Touchpad stuck disabled? Run `restore-touchpad.cmd` (device mode triggers the enable task and **verifies the actual device state**)
- **State is verified**: after disable/enable, device node status is confirmed via `cfgmgr32`, logs say "and confirmed working" or "not confirmed (status=… problem=…)"
- **Startup self-healing**: every launch checks touchpad state; if previous run was killed while disabled, it auto-restores
- Restore points: the moment you type password to hide overlay, and when you exit from tray
- Other options: `-TouchpadMode auto|registry|device|off`

### Notes

- Unlock is by password only (typing), so mouse block **requires a password**; if you pass `-Password ''`, the program auto-disables mouse block and warns
- Keep touchpad enabled: `-TouchpadMode off`
- **Emergency exit**: `Ctrl+Alt+Del` → Task Manager → End `Windows PowerShell`. This key combo is handled by the system and can't be blocked
- Mouse/keyboard hooks are global — a USB mouse will also be blocked

Every show/unlock event is logged to **`privacy-screen.log`** (e.g. "touchpad device disabled via scheduled task" or failure reason). Check it first when troubleshooting.

---

## 诊断 Diagnostics

For issues like "blocking not working" or "remote detection not triggering", run the diagnostic script to capture real signals:

```bat
diagnose.cmd
```

It guides you through three phases (idle baseline → connect with phone Sunlogin and do various operations/gestures → disconnect), takes ~100 seconds total, only listens — never blocks. Results written to **`diagnose.log`**, including:

- `injected` flag and `extra` info for every keyboard/mouse event (determines if input is "real HID" or "injected")
- Raw Input detected **input device names** (distinguishes touchpad / Sunlogin virtual HID / regular mouse)
- Sunlogin process count, windows (with visibility/class/title), TCP/UDP connection changes
- Touchpad and other PnP device list (for device-level disable setup)

---

## 远程控制联动 Remote Control Integration

Use case: you're away from your PC, controlling it via phone with Sunlogin; after disconnect, privacy protection auto-restores.

**Default behavior (`-RemoteHideOverlay`, tested and working)**:

- **Detection criterion**: the remote tool (default `AweSun` / `awesun_guard`, also `SunloginClient`) shows a **visible top-level window** — when idle, it's entirely in the tray with all windows `visible=False`; when being controlled, a prompt bar / main window appears
- **Remote control detected** → **auto-hides entire overlay**, restores mouse/keyboard/touchpad → remote side definitely sees real desktop, operations work normally (doesn't depend on whether Sunlogin respects screenshot exclusion)
- **Remote control ends** → **auto-restores overlay**, mouse block and touchpad device-level disable both come back
- **15-second debounce** (`-RemoteEndDelaySec`): brief disappearance of the detection criterion (e.g. prompt bar auto-hides) won't immediately restore, prevents flicker
- **Fallback hotkey `Ctrl+Shift+Alt+R`**: handled inside the keyboard hook, so it works **even when input is blocked**. Press once = manual remote mode (hide overlay), press again = exit immediately and restore overlay. Use this if auto-detection ever fails
- Keep overlay, only pass through input (relies on screenshot exclusion for remote to see desktop): `-RemoteHideOverlay:$false`
- Disable this feature: `-RemoteDetect:$false`

> ⚠️ Two trade-offs: ① While overlay is hidden, the physical screen shows your real desktop (people nearby can see). This is the cost of "remote must see the screen". If you don't want this, use `-RemoteHideOverlay:$false`. ② AweSun normally has 1-2 persistent TCP connections to its server when idle, so "having connections" can't be the detection criterion.

To debug detection: run `privacy-screen.ps1 -ScanRemote` during a remote session, or check `privacy-screen.log` for the reason logged each time the state changes (includes window class/title). If still stuck, run `diagnose.cmd` to capture real signals.

---

## 静默运行 Silent Launch

On Windows 11, the default terminal host is **Windows Terminal**, which ignores `-WindowStyle Hidden` and similar parameters — so launching via .vbs/.cmd still pops up a terminal window. The solution is to use a GUI-subsystem launcher (which doesn't create a console itself):

| Launcher | Description |
|---|---|
| `silent-launch.exe` (**recommended**) | GUI-subsystem program, launches main script with `CreateNoWindow` — zero windows pop up (Windows Terminal never gets invoked) |
| `silent-launch.vbs` | Fallback; may still flash on Windows Terminal default setups |
| `silent-launch.cmd` | Fallback; same as above, plus a brief flash |
| `run.cmd` | With console window (for debugging / first use, shows startup info and errors) |

`silent-launch.exe` supports passing through arguments, e.g. `silent-launch.exe -Mode black -Text "Training"`.
Launcher source is in `build-launcher.ps1`; run it to recompile.

With the console hidden, there's no window to close: exit via tray icon (type password to unlock first) or Task Manager; diagnostic info is in `privacy-screen.log`.

---

## 防烧屏 Anti-Burn-In

On by default (`-AntiBurn`). Long-running static images can cause burn-in on OLED/IPS displays. The program does three things:

- **Pixel drift**: text (or lock screen wallpaper) moves slowly within ±5 pixels every 20 seconds, barely perceptible
- **Brightness variation**: overlay background slowly cycles between several nearly-identical dark shades, preventing a perfectly constant full-screen image
- **Low brightness**: default background is nearly pure black (`#090C10`), OLED pixels barely emit light

To further reduce burn-in risk:

- Use `-Mode black`: pure black means OLED pixels are basically off — best choice for long absences
- Add `-DimBrightness`: also lower physical brightness to minimum
- Avoid long sessions with `-Mode lockstyle` (static wallpaper + large clock is the worst combination for image retention)

---

## 自定义文字 Custom Text (txt file)

Simplest way: edit **`overlay-text.txt`** in the same directory (one line per text line), save, and it takes effect next time the overlay shows — no command line changes needed.

- Priority: command line `-Text` > `overlay-text.txt` > built-in "System maintenance" animation
- Delete `overlay-text.txt` to restore the built-in animated maintenance screen
- UTF-8 and ANSI/GBK encodings are auto-detected
- `|` also works as a line separator within the file

```txt
System maintenance · Do not touch
Background task running, please do not touch keyboard or mouse
```

---

## 密码静默解锁 Silent Password Unlock

Default password: **1234**.

Three ways to change the password (choose one):

1. **Tray menu** (recommended): Right-click tray → Password management → Change password... → enter new password in the dialog. Effective immediately, auto-saved to `password.txt`.
2. **Edit file**: Create/edit **`password.txt`** in the same directory, write the password (digits and letters only), effective on next launch.
3. **Command line**: `-Password newpassword` parameter (for single-launch use).

Priority: `password.txt` > `-Password` parameter > default `1234`.

Clear password: Right-click tray → Password management → Clear password (deletes `password.txt` and auto-disables mouse block), or `-Password ''`.

> **Num Lock is not blocked**: the Num Lock toggle works normally during overlay and won't be consumed.

While the overlay is shown, just type your password on the keyboard to unlock — **completely silent, no prompts**:

- No password box pops up, no asterisks shown, no feedback on wrong input
- Characters you type (including the password itself) are consumed and won't reach your project behind the overlay; random keystrokes from roommates won't affect your work
- AI injected keyboard input passes through, debugging works normally
- With password set: hotkey and tray "Hide overlay" no longer directly hide it (prevents bypass); tray "Show overlay" still works
- Mouse/touchpad blocking is on by default (see previous section), so "typing password" is the only human unlock method during overlay

---

## 开机自启 Auto-Start (optional)

As administrator, create a logon-triggered scheduled task that runs with `-StartHidden`:

```bat
schtasks /create /tn PrivacyScreen /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\path\to\privacy-screen.ps1 -StartHidden" /sc onlogon /rl limited
```

Press the hotkey when you leave to show the overlay. To remove: `schtasks /delete /tn PrivacyScreen /f`

---

## 防误锁屏 Anti-Accidental Lock (optional)

If you're worried about someone pressing **Win+L** to lock the screen (which would interrupt your AI), disable the lock function (admin PowerShell, takes effect after restart; set back to 0 to revert):

```powershell
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name DisableLockWorkstation -Value 1 -PropertyType DWord -Force
```

---

## 注意事项 Notes & Limitations

1. **System requirement**: Windows 10 2004 (build 19041) or later.
2. **Not a security lock**: Anyone with physical access can end the process via Task Manager (overlay disappears) or power off the machine. This is "privacy screen" not "anti-theft" — it prevents passersby from seeing screen content.
3. **Doesn't prevent physical camera/phone photos**: Screenshot exclusion only works for software capture; a phone photo of the screen still shows the overlay (which still hides the content).
4. **Some capture methods may not respect the exclusion**: Verify with `selfcheck.ps1`. If a particular capture path includes the overlay, AI screenshots will see "system maintenance" (harmless but full-screen) — suggest switching AI to mss/PIL-style capture, or use `-ScreenOff`.
5. **Brightness not restored after crash**: If you used `-DimBrightness` and the process was force-killed, run the script again and exit normally to restore brightness.
6. **Mixed-DPI multi-monitor**: Script handles DPI awareness, but mixed-scaling setups may have a few pixels of offset; single-monitor or same-scaling setups have no issue.
7. **DXGI exclusivity**: Only one program can use Desktop Duplication per monitor at a time; if your AI tool is capturing with DXGI, the DXGI part of selfcheck will report unavailable (close AI first).
8. Keep the console window open/minimized; closing it = exiting the program (overlay disappears). With silent launcher there's no console, exit via tray or Task Manager.
9. **Mouse and touchpad being completely unresponsive during overlay is normal**, not a crash: type your password to unlock; if truly stuck use `Ctrl+Alt+Del` to end the process; if touchpad is stuck disabled, run `restore-touchpad.cmd`. **Num Lock is an exception** — it always works normally.
10. Whether blocking actually works — check `privacy-screen.log` entries from each overlay show.
11. **After editing the script/upgrading you must restart**: the old instance holds the single-instance mutex, new processes will just say "already running". Use `silent-launch.exe -Replace` to let the new version take over, or exit the old instance from tray first.

---

## 文件清单 Project Structure

```
隐私屏/
├── privacy-screen.ps1      # 主程序 Main program
├── silent-launch.exe       # 推荐启动器（无窗口）Recommended launcher (windowless)
├── silent-launch.vbs       # 备用启动器 Fallback launcher
├── silent-launch.cmd       # 备用启动器 Fallback launcher
├── run.cmd                 # 带窗口启动 Console launcher (for debugging)
├── build-launcher.ps1      # 编译 silent-launch.exe 的脚本 Build script for silent-launch.exe
├── restore-touchpad.cmd    # 触控板卡在禁用时手动恢复 Manual touchpad restore
├── setup-touchpad.cmd      # 配置触控板设备级屏蔽 Configure touchpad device-level blocking
├── selfcheck.ps1           # GDI+DXGI 截图豁免自检 Screenshot exclusion self-test
├── diagnose.ps1            # 输入与远程诊断 Input & remote diagnostic
├── diagnose.cmd            # 诊断启动器 Diagnostic launcher
├── overlay-text.txt        # (可选) 自定义遮罩文字 Custom overlay text
├── touchpad-device.txt     # (自动生成) 触控板设备 ID Touchpad device ID
├── password.txt            # (自动生成) 密码 Password
├── settings.conf           # (自动生成) 开关持久化 Settings persistence
├── privacy-screen.log      # (自动生成) 运行日志 Runtime log
├── .gitignore              # Git 忽略规则 Git ignore rules
└── README.md               # 本说明 This file
```

> Files marked "(auto-generated)" or "(optional)" are excluded from git via `.gitignore`.

---

## 原理 How It Works

The overlay window sets `WDA_EXCLUDEFROMCAPTURE` via `SetWindowDisplayAffinity` — it's visible on the physical display, but Windows strips it from software captures, so AI screenshots see the real desktop underneath.

---

## 许可与免责 License & Disclaimer

### 非商用声明 Non-Commercial Use Only

本软件**仅供个人学习、研究和非商业用途**。禁止将本软件或其衍生作品用于任何商业目的，包括但不限于：
- 出售、出租、授权本软件
- 将本软件集成到商业产品或服务中
- 利用本软件提供付费服务

This software is **for personal learning, research, and non-commercial use only**. Commercial use of this software or any derivative works is strictly prohibited, including but not limited to:
- Selling, renting, or licensing the software
- Integrating the software into commercial products or services
- Using the software to provide paid services

### 免责条款 Disclaimer

本软件按"现状"提供，**不提供任何明示或暗示的保证**，包括但不限于适销性、特定用途适用性和非侵权性的保证。

使用本软件产生的**一切风险和后果由使用者自行承担**。作者不对任何直接、间接、偶然、特殊、惩罚性或后果性的损害承担责任，包括但不限于：
- 数据丢失或损坏
- 系统故障或死机
- 因误操作导致的工作中断
- 触控板/亮度等硬件状态异常
- 任何形式的经济损失

在任何情况下，作者均不对因使用或无法使用本软件而产生的任何索赔、损害或其他责任承担责任。

This software is provided **"AS IS"** without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement.

**Use at your own risk.** The author shall not be liable for any direct, indirect, incidental, special, punitive, or consequential damages arising from the use of this software, including but not limited to:
- Data loss or corruption
- System crashes or freezes
- Work interruption due to misuse
- Hardware state abnormalities (touchpad, brightness, etc.)
- Any form of economic loss

In no event shall the author be liable for any claim, damages, or other liability arising from the use or inability to use the software.

---

## License

MIT

### 附加条款 Additional Terms

在 MIT License 的基础上，附加以下条款：
1. **非商用**：不得用于商业用途（见上文"非商用声明"）
2. **后果自负**：使用本软件的一切风险由使用者承担（见上文"免责条款"）
3. **保留声明**：再分发时必须保留本许可与免责声明的完整内容

Additional terms on top of MIT License:
1. **Non-commercial**: No commercial use (see "Non-Commercial Use Only" above)
2. **Use at your own risk**: All risks are borne by the user (see "Disclaimer" above)
3. **Attribution**: Redistributions must retain this full license and disclaimer text
