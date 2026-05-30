# 离线 Node.js 安装包

把官方 Node.js 压缩包放到这个目录即可。

## Windows

推荐文件名：

- `node-v20.12.2-win-x64.zip`
- `node-v20.12.2-win-arm64.zip`
- `node-v20.12.2-win-x86.zip`

Windows 安装脚本会按下面顺序查找：

1. `node-v20.12.2-win-<arch>.zip`
2. `node-win-<arch>.zip`
3. `node.zip`
4. `node-*-win-<arch>.zip`

也可以在可联网的 Mac/Linux 机器上运行项目根目录的：

```bash
./prepare-word-match-offline-assets.sh x64
```

下载完成后，把整个项目目录复制到离线 Windows 机器，再运行 `install-word-match.cmd`。

Windows 原生脚本默认优先级：

1. `.runtime\node` 中已安装的本地运行时
2. `offline-assets\node` 中的离线 zip 包
3. 系统里的兼容 Node.js
4. 显式允许的在线下载（需手动设置 `WORD_MATCH_ALLOW_ONLINE_DOWNLOAD=1`）

## Mac

推荐文件名：

- `node-v20.12.2-darwin-arm64.tar.gz`
- `node-v20.12.2-darwin-x64.tar.gz`

Mac / Unix 脚本默认优先级：

1. `.runtime/node` 中已安装的本地运行时
2. `offline-assets/node` 中的离线压缩包
3. 系统里的兼容 Node.js
4. 显式允许的在线下载（需手动设置 `WORD_MATCH_ALLOW_ONLINE_DOWNLOAD=1`）
