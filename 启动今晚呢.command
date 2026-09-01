#!/bin/zsh
set -e
cd -- "$(dirname -- "$0")"
if ! command -v node >/dev/null 2>&1; then
  print '请先安装 Node.js 24，然后重新打开此文件。'
  read '?按回车关闭…'
  exit 1
fi
if [[ ! -d node_modules ]]; then
  npm ci
fi
npm run build
print '今晚呢已启动，请在浏览器打开 http://localhost:3000'
exec npm start
