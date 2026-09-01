# 今晚呢

原生 iOS App，采用用户选择的 B 白蓝风格。首页只有「今晚发起了」，点击后立即选择「成功 / 失败」，选完直接保存。SwiftUI 工程位于 [ios/JinwanNe.xcodeproj](ios/JinwanNe.xcodeproj)，现有 Node 服务端负责私人记录和真实排行榜。

这是一个带点自嘲的婚后生活记录 App：吐槽男人鼓起勇气发起亲密请求，却经常收到「今晚不行」的共同经历。它只记录双方已经沟通后的结果，不代替沟通，也不鼓励施压。

## 运行 iOS App

1. 用 Xcode 打开 `ios/JinwanNe.xcodeproj`。
2. 选择 iPhone 模拟器或真机，运行 `JinwanNe` Scheme。

Debug 与 Release 版都连接正式 HTTPS 服务端 `https://jinwanne.woaizhuzhu.com/api`，手机不需要与 Mac 处于同一网络。当前开发签名 Bundle ID 为 `com.yanis.jinwanne`。

项目还保留 React 网页版，便于本地快速预览。正式域名不提供网页版记录功能：首页只展示只读匿名排行榜，并提供隐私政策和用户支持页面。

## 运行网页版预览

需要 Node.js 24.14 或更新的 24.x 版本。

```sh
npm ci
npm run dev
```

打开 http://localhost:3000 。前端修改会自动更新；修改服务端后需重新启动。

使用生产构建在本机运行：

```sh
npm run build
npm start
```

双击 macOS 的「启动今晚呢.command」也能构建并启动。保持终端窗口开启；按 Ctrl+C 停止。

## 已有功能

- 两步记录今晚结果，保存后显示确认，可修改当天结果；没有弹窗表单或额外保存按钮。「今晚发起了」仅切换界面，不会向伴侣发送消息。
- 首页不放日历、统计卡片、最近记录或排行榜预览。历史记录与修改、删除放在「设置 → 我的记录」。已有私人备注仍保留。
- 按北京时间计日，同一天只有一个最终结果；「失败」指提出请求后被拒绝，未记录或只点击发起不会算作失败。
- 成功天数榜、拒绝天数榜；支持本月、今年、全部；天数相同并列，后续名次跳位（1、1、3）。
- 数据存入 SQLite，排行榜由服务端 SQL 聚合，不使用前端伪造数据。显示前 50 个用户，同时返回自己的完整名次。
- 首次自动分配随机用户名，可在设置中修改；服务端规范化并保证用户名不重复。主动同意后参与排行榜，随时退出；只公开用户名与天数，不返回逐日记录、备注或内部账号 ID。
- 导出个人 JSON 文件、永久删除身份和全部记录。
- 白底蓝色、手机单列布局，底部仅「记录 / 排行榜」两项导航；支持键盘操作、加载与错误重试。

## 使用时要知道

首次访问会创建当前浏览器的匿名身份。身份通过 HttpOnly Cookie 保持，使用时有效期延长一年。清除 Cookie、换浏览器或设备、无痕窗口关闭后不能找回身份；本版不支持跨设备登录或导入恢复。导出仅用于保留可阅读的数据副本。

不收集姓名、手机号或伴侣资料。私人记录对其他用户不可见，但**不是端到端加密，服务器管理员可访问数据库**；共用同一浏览器的人也能进入日记。没有第三方统计、外部字体或追踪脚本。

所有数据由用户自报，榜单未经独立验证，不具备可靠防刷身份体系。请勿把天数作为衡量伴侣、关系质量或施压的依据。

## 服务端与配置

- 前端：React、TypeScript、Vite；后端：Express、Node 内置 SQLite。
- 数据文件默认位于 `data/journal.sqlite`（运行后自动创建，已排除版本控制）。删除该目录会丢失全部账号和记录。
- 环境变量：`PORT`、`HOST`、`DATABASE_PATH`、`APP_ORIGIN`、`COOKIE_SECURE`、`TRUST_PROXY`。示例见 `.env.example`，环境文件不会自动读取；可在启动命令中设置，或用 `node --env-file=.env server/index.mjs`。
- 默认仅监听 `127.0.0.1:3000`。正式服务通过 Nginx 接收 HTTPS，再转发到服务器本机回环端口。
- 正式站点静态文件位于 `site/`：`/` 为匿名排行榜，`/privacy` 为隐私政策，`/support` 为用户支持。公开排行榜只读，不创建身份或下发 Cookie；私人数据接口仍要求 App 的匿名身份。
- 公网运行必须启用 HTTPS，配置精确的 `APP_ORIGIN=https://实际域名`、`COOKIE_SECURE=true`。Nginx 与 Node 位于同一服务器时，Node 保持 `HOST=127.0.0.1`，并设置 `TRUST_PROXY=1`。部署方需要准备持久化磁盘、最小权限、加密与有保留期限的备份、隐私条款和删除备份策略；没有这些条件不应存放真实敏感记录。
- SQLite 适合本首版的单实例部署。多实例部署需要共享数据库或改为服务型数据库；请求限速目前按单进程和 IP 计数。
- 应用删除是数据库逻辑删除，备份、SQLite 空闲页或管理员留存副本不是应用删除承诺的一部分。需要强擦除保证时必须另行设计加密密钥销毁和备份生命周期。

实现参考：[Node.js SQLite](https://nodejs.org/api/sqlite.html)、[Express 安全实践](https://expressjs.com/en/advanced/best-practice-security/)。

## 接口

`/api/session` 创建 / 续期匿名身份，其余私人接口均通过 Cookie 验证身份。写入需 JSON 和 `X-Journal-Request: 1` 请求头，并检查同源。

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| POST | `/api/session` | 创建或读取身份、服务器日期 |
| GET | `/api/records?month=2026-08` | 私人月度记录与统计 |
| PUT / DELETE | `/api/records/2026-08-31` | 保存 / 删除一天 |
| PATCH | `/api/profile` | 主动开启 / 退出匿名排行榜 |
| GET | `/api/leaderboard?metric=success&period=month` | 服务端榜单，metric 为 success / declined，period 为 month / year / all |
| GET | `/api/export` | 导出个人记录 |
| DELETE | `/api/account` | 输入「删除」后删除账号与关联记录 |

## 验证

```sh
npm run check
```

集成测试使用隔离数据库，覆盖身份隔离、同日幂等与并发、输入验证、上海时区、排名并列与时间范围、退出排行、删除级联和重启持久化。构建时执行 TypeScript 检查。

选中的风格参考是 `design/styles/B-white-cobalt.png`，但布局按用户后续要求进一步简化。最新设计约束见根目录 `DESIGN.md`，实际页面截图在 `output/simple-home.png` 与 `output/simple-choice.png`。界面是可交互组件，不是设计图片拼贴。
