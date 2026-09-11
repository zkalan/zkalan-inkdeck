# 下载 · 0.4.0

- [Apple Silicon 应用与说明文档](ZkalanInkDeck-0.4.0-macOS-arm64.zip)
- [验证图像与结果包](ZkalanInkDeck-0.4.0-validation.zip)
- [SHA-256 校验文件](SHA256SUMS.txt)

要求：macOS 13+，Apple Silicon。应用采用临时签名，尚无 Apple 公证，安装说明见项目根目录 README。

模型 49 项检查与应用 69 项检查全部通过。测试使用合成触控/压力及真实窗口，实际书写手感与会议软件的共享效果仍需试用确认，见 [验证记录](../artifacts/v0.4/VALIDATION.md)。同样的下载文件也提供在 [GitHub Release](https://github.com/zkalan/zkalan-inkdeck/releases/tag/v0.4.0)。

使用 `zsh scripts/build.sh` 和 `zsh scripts/package.sh` 可从源码重新生成包；个人画稿、备份、发布凭据不包含在这些文件中。
