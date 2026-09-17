# 正式服务部署

正式地址：`https://jinwanne.woaizhuzhu.com`

- Nginx 只把请求转发到 `127.0.0.1:3356`。
- Node 以无登录权限的 `jinwanne` 用户运行，程序目录只读，SQLite 数据位于 `/var/lib/jinwanne/journal.sqlite`。
- systemd 服务文件：`/etc/systemd/system/jinwanne.service`。
- Nginx 站点文件：`/etc/nginx/conf.d/jinwanne.woaizhuzhu.com.conf`。
- TLS 文件：`/etc/nginx/ssl/jinwanne.woaizhuzhu.com/`，私钥权限为 `0600`。
- 运行版本目录：`/opt/jinwanne/releases/`，`/opt/jinwanne/current` 指向当前版本。

证书有效期截止 2026-11-30。续期时替换证书链与私钥，先执行 `nginx -t`，通过后再 reload Nginx。

## 中英文支持

英文只读排行榜 `/en`、隐私政策 `/en/privacy` 和支持页 `/en/support` 已部署；原中文路径保持不变。网页不会创建匿名身份。

iOS 界面以 Apple 商店地区为准：`CHN` 使用中文，其他地区使用英文；取不到商店信息时，先使用缓存的商店地区，再回退到设备地区，不读取 GPS。App 通过 `X-Journal-Language: en` 选择英文接口提示；旧客户端不带该请求头仍返回中文，鉴权和接口数据格式不变。

新建英文环境账号自动获得英文随机昵称，不会自动改名或修改旧账号记录。全球记录与排行榜仍使用 `Asia/Shanghai`（UTC+8）日期边界。部署需同时包含服务端代码和 `site/en/` 静态文件；网页英文可用不代表新版 App 已通过 Apple 审核或上线。
