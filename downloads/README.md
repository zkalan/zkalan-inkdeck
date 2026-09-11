# 下载 · 0.5.1 预览版

- [Apple Silicon 应用与说明文档](ZkalanInkDeck-0.5.1-macOS-arm64.zip)
- [验证图像与结果包](ZkalanInkDeck-0.5.1-validation.zip)
- [SHA-256 校验文件](SHA256SUMS.txt)
- [GitHub Release](https://github.com/zkalan/zkalan-inkdeck/releases/tag/v0.5.1)

要求：macOS 13+，Apple Silicon。应用采用临时签名，尚无 Apple 公证；安装说明见根目录 README。

0.5.1 默认按住空格画图、松开预览；按住 E 临时擦除、松开结束，黑白双层指针，桌面暂停后可单击菜单栏画笔恢复。保留调色盘与最近六色，连续书写与按压落笔可选，主画板和桌面均可用。模型检查 63 项通过；完整桌面回归受前台焦点阻塞，本版先供试用，实际触控板手感仍需试用，详见 [验证记录](../artifacts/v0.5.1/VALIDATION.md)。

应用包包含说明文档，验证包包含合成输入图像和结果。个人草稿、备份及凭据不包含在发布内容中。

旧版 0.4 的下载和对应校验文件保留在 [0.4.0 Release](https://github.com/zkalan/zkalan-inkdeck/releases/tag/v0.4.0)。新版草稿增加了自定义颜色和擦除信息；升级前可用 `zsh scripts/install.sh` 自动备份，不应用旧版本覆盖新版草稿。
