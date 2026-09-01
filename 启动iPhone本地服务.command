#!/bin/zsh
set -e
cd -- "$(dirname -- "$0")"

if ! command -v node >/dev/null 2>&1; then
  print '请先安装 Node.js 24，然后重新打开此文件。'
  read '?按回车关闭…'
  exit 1
fi

LAN_ADDRESS=$(ipconfig getifaddr en0 2>/dev/null || true)
if [[ -z "$LAN_ADDRESS" ]]; then
  print '没有找到 Wi-Fi 局域网地址，请先让 Mac 连接 Wi-Fi。'
  read '?按回车关闭…'
  exit 1
fi

if [[ ! -d node_modules ]]; then
  npm ci
fi

print "今晚呢服务已准备在局域网启动：$LAN_ADDRESS:3000"
print '请让 iPhone 与 Mac 连接同一个可信 Wi-Fi；保持此窗口开启。'
exec env HOST="$LAN_ADDRESS" PORT=3000 npm run dev
