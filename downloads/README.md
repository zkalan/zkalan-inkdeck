# 下载 · 0.5.0

- [Apple Silicon 应用与说明文档](ZkalanInkDeck-0.5.0-macOS-arm64.zip)
- [验证图像与结果包](ZkalanInkDeck-0.5.0-validation.zip)
- [SHA-256 校验文件](SHA256SUMS.txt)
- [GitHub Release](https://github.com/zkalan/zkalan-inkdeck/releases/tag/v0.5.0)

要求：macOS 13+，Apple Silicon。应用采用临时签名，尚无 Apple 公证；安装说明见根目录 README。

0.5 默认按住空格画图、松开预览；新增原生调色盘、最近六个颜色与局部橡皮擦，主画板和桌面均可用。63 项模型检查、118 项应用检查全部通过，实际触控板手感仍需试用，详见 [验证记录](../artifacts/v0.5/VALIDATION.md)。

应用包包含说明文档，验证包包含合成输入图像和结果。个人草稿、备份及凭据不包含在发布内容中。

旧版 0.4 的下载和对应校验文件保留在 [0.4.0 Release](https://github.com/zkalan/zkalan-inkdeck/releases/tag/v0.4.0)。新版草稿增加了自定义颜色和擦除信息；升级前可用 `zsh scripts/install.sh` 自动备份，不应用旧版本覆盖新版草稿。
