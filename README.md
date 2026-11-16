# Codex Pet

macOS 原生悬浮狗狗，用于监测 Codex Desktop 与 VS Code Codex 插件的任务状态。

## 安装并启动

```bash
cd /Users/huang/Documents/myCode/codex-pet
make install
```

安装后会自动启动，并在以后登录 macOS 时自启。应用位于 `~/Applications/CodexPet.app`。

## 使用

- 平时只显示图片帧动画萨摩耶；鼠标移到狗狗上时才展开任务卡片，贴近任何屏幕边缘也会自动调整卡片位置。
- Finder 应用图标直接使用同一套萨摩耶坐姿帧，角色外观与悬浮宠物一致。
- 执行中：萨摩耶敲键盘，卡片列出执行中的任务。
- 全部结束：播放一次提示音并庆祝 6 秒，之后趴下睡觉；卡片保留最近完成的任务。
- 拖动宠物可调整位置。
- 右键宠物或点击菜单栏的 🐶：显示/隐藏、切换开机自启、切换菜单栏图标或退出。
- 退出后重新展示：在 Finder 按 `⌘⇧G`，输入 `~/Applications` 后双击 `CodexPet`，或运行：

```bash
open "$HOME/Applications/CodexPet.app"
```

## 卸载

```bash
cd /Users/huang/Documents/myCode/codex-pet
./scripts/uninstall.sh
```

卸载脚本会把应用和开机启动项移到废纸篓。
