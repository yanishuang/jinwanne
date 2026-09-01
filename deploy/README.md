# 正式服务部署

正式地址：`https://jinwanne.woaizhuzhu.com`

- Nginx 只把请求转发到 `127.0.0.1:3356`。
- Node 以无登录权限的 `jinwanne` 用户运行，程序目录只读，SQLite 数据位于 `/var/lib/jinwanne/journal.sqlite`。
- systemd 服务文件：`/etc/systemd/system/jinwanne.service`。
- Nginx 站点文件：`/etc/nginx/conf.d/jinwanne.woaizhuzhu.com.conf`。
- TLS 文件：`/etc/nginx/ssl/jinwanne.woaizhuzhu.com/`，私钥权限为 `0600`。
- 运行版本目录：`/opt/jinwanne/releases/`，`/opt/jinwanne/current` 指向当前版本。

证书有效期截止 2026-11-30。续期时替换证书链与私钥，先执行 `nginx -t`，通过后再 reload Nginx。
