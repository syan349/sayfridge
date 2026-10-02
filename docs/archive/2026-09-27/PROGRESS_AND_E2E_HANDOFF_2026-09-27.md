# SayFridge 项目进度与端到端联调交接

> **后续更新**：本文件保留的是 API 写入/Agent 接线之前的状态快照。最新接入范围、100 个 Flutter 测试结果和待联调事项见 [Flutter API 接入更新](API_INTEGRATION_2026-09-27.md)。另外，随后抓取的 `origin/main` 已有 Web/CORS 新实现，本文“Web 占位页”仅描述当时本地版本。

记录日期：2026-09-27（新西兰时间）
记录范围：当前本地代码、此前 UI 验证记录，以及本次 Neon 只读连接检查。
本地分支：`mobile_frontend_integration`；当前 HEAD：`d51df8c`（`profile`）。

> 当前结论：Flutter 手机端已有主要页面和部分真实 API 接入；本地后端已能连接 Neon，但数据库结构与最新后端代码存在差异。尚未完成“新用户注册 → 登录 → 创建库存 → 修改库存 → 重启后数据保留”的完整端到端验收，也尚未验证 Render 上的最终用户端。
>
> 按当前要求，暂停共享数据库的结构修改和数据写入。本记录不包含数据库密码、JWT 密钥或模型 API Key。

## 1. 可以直接转发给同学的摘要

- Flutter 手机端已制作 Home、AI Assistant、Profile 及相关子页，近期调整了游客登录按钮、底部导航间距、Profile 区块间距、对话气泡和搜索页标题布局。
- 游客点击 Profile 现在进入游客资料页；点击其中的登录入口才进入 Sign in。
- 注册、登录、当前用户、空间列表、库存列表/筛选/搜索/详情、临期汇总已有前端 API 调用代码，但不等于已在共享数据库完成实测验收。
- 离线预览使用独立入口，包含 Demo User、8 件示例库存和空库存切换；这些是假数据，不是真实登录，也不是云端演示账号。
- 后端本地环境和依赖已配置，Neon 的连接池、直连均通过只读连接检查。
- 当前 `neondb` 缺少 `inventory_item.notes` 字段和 `agent_inventory_action` 表；已记录，未修改。
- AI 前端尚未接入后端 Agent，个人资料/提醒部分仍为本地偏好，找回密码及实际通知发送尚未实现。
- 若最终要在 Render 上打开现有手机界面，应先确认采用 Flutter Web 复用，还是另行实现 React 用户端。现在仓库 `web/` 仅有 React 占位页，部署它不会出现目前的 Flutter 页面。
- 建议先确定独立联调数据库及结构版本，完成 Android 原生客户端的真实业务链路，再补浏览器验收和 Render/Vercel 上线验收。最终目标为网页，因此 Web 可构建性和插件兼容性也应尽早检查。

## 2. 当前实现与验证状态

以下“已接入”指代码中已有真实服务调用；“已验证”仅指明确完成过的检查，二者不能混用。

| 模块 | 当前状态 | 尚需完成/验证 |
| --- | --- | --- |
| 游客 Home / AI Assistant / Profile | 页面、底部导航、登录入口已实现 | 在真实 API 入口再次验收游客/登录状态切换 |
| UI 细节 | 三页复用底部布局和游客按钮；AI 示例气泡统一字重、增加左侧尾巴；Profile 区块上移、缩小间距；搜索等页面返回按钮与标题分开布局 | 最终手机浏览器、不同屏幕和键盘弹出状态仍需验收 |
| 注册 / 登录 | 调用 `/auth/register`、`/auth/login`；注册成功后返回登录页，不是自动登录 | 获准后用真实测试账号跑完整链路；重复邮箱、错误密码、断网等 |
| 注册姓名 / 头像 | 注册界面有输入和选择 | 注册请求目前只发送邮箱与密码；姓名/头像未随注册提交，也未在该流程中持久化 |
| 登录恢复 / 退出 | 保存访问令牌，启动时调用 `/auth/me`；退出清除本地令牌 | 令牌过期、退出后切换账号、库存/空间缓存隔离需专门验收；目前无 refresh token |
| 库存与空间读取 | 空间列表、库存列表/搜索/筛选/详情、临期汇总已有真实 API 调用 | 先解决数据库差异，再核对返回数据、分页、空状态和异常状态 |
| 库存与空间写入 | 后端已有相应 API；前端部分按钮仍是未接通提示 | 新建空间/入库/编辑/消耗/盘点/归档/历史等需要按演示范围接线和验收 |
| Profile 子页 | 个人资料、密码、提醒设置、语音用量页面已制作 | 不能将页面完成当作全部后端功能完成 |
| 个人资料 / 提醒偏好 | 正常入口下按用户 ID 保存在本机；预览入口只保存在内存 | 姓名头像跨设备同步、后端更新接口、通知权限与实际调度未完成 |
| 忘记密码 / 修改密码 | 有表单/提示；忘记密码弹窗流程已调整并补回归测试 | 没有发送重置邮件或修改真实密码；当前后端无相应 API |
| 语音额度 | 预览显示 12 / 50；正常入口不会将示例用量当真 | 效果图按请求次数，后端模型按秒；`/auth/me` 未返回用量，需先统一接口和单位 |
| AI Assistant | 页面和示例交互已实现，仍使用固定示例内容 | 接入 Agent chat/resume/SSE、确认操作、实际库存结果；语音/相机入口也不代表识别已接通 |
| 后端 Agent | 仓库已有工作流、持久化和操作确认相关代码 | 本机模型 Key 未配置；回执表缺失；真实模型和前端链路未验证 |
| Render 用户端 | 最终交付目标，尚未在本次工作中部署/验证 | 确定 Flutter Web 或 React，实现浏览器适配和部署流程 |

### 近期主要代码位置

- 正常入口：`mobile/lib/main.dart`
- 离线入口：`mobile/lib/main_preview.dart`、`mobile/lib/preview/`
- API 地址：`mobile/lib/config/api_config.dart`
- 真实 API 服务：`mobile/lib/services/auth_api_service.dart`、`inventory_api_service.dart`、`storage_space_api_service.dart`
- 共享底部布局：`mobile/lib/widgets/app_page_footer.dart`
- 主要 UI 调整：`mobile/lib/screens/home_screen.dart`、`ai_assistant_screen.dart`、`profile_screen.dart`、`sign_in_screen.dart`
- 气泡与标题布局：`mobile/lib/widgets/assistant_widgets.dart`、`inventory_visuals.dart`
- 相关回归测试：`mobile/test/screens/forgot_password_test.dart`、`preview_app_test.dart`、`mobile/test/widgets/overview_header_test.dart`，以及已有 Profile 流程测试。

## 3. 两种 Flutter 入口不要混淆

| 入口 | 用途 | 数据和账号 |
| --- | --- | --- |
| `lib/main_preview.dart` | 离线检查 UI 和状态，仅 Debug 可用 | 右上角显示 `UI PREVIEW · OFFLINE`；模拟用户和库存；不调用网络 |
| `lib/main.dart` | 真实 API 联调和最终构建入口 | 实际注册/登录、访问令牌，以及后端返回的数据 |

离线预览中的 Demo User、8 件库存、12 / 50 语音额度，不证明数据库里存在对应账号或数据。最终演示账号必须通过真实认证链路登录，不能拿离线预览冒充端到端功能。

## 4. 本地后端和 Neon 检查结果

### 已完成

- 已创建本地 `backend/.env`，配置连接池 URL、直连 URL、本机 JWT 签名密钥等；该文件已确认受 Git 忽略。
- 用户在本机填写数据库密码后，两种连接均成功，执行 `SELECT 1` 返回正常。
- 检查事务明确设置为只读，并确认 `transaction_read_only = on`。
- 查询目标为 Neon 项目 `sayfridge-dev` 的 `production` 分支、`neondb` 数据库。分支名字不代表已获准对其写入。
- 已读取公开表名、字段名/可空性、迁移版本，以及 `agent` schema 下的表名。没有读取用户邮箱、密码哈希或库存内容。

### 与当前代码的差异

| 检查项 | 结果 | 影响 / 处理意见 |
| --- | --- | --- |
| `inventory_item.notes` | 数据库缺少，当前 ORM 有该字段 | 使用该 ORM 字段的库存查询/写入会受影响；由后端负责人确认目标库后同步 |
| `agent_inventory_action` | 数据库缺少，当前 ORM 有该表 | Agent 库存写入回执能力不能视为可用；由后端负责人处理 |
| Alembic 版本 | `02ec95582dc7` | 版本号相同不代表字段相同；项目会更新初始迁移，不能假定对旧库执行 `upgrade head` 会自动补字段 |
| `agent` schema | 存在，包含 checkpoint/store 相关表 | 仅确认表存在；未验证完整结构、版本兼容性或真实 Agent 请求 |

其余已存在的业务表，在本次比较范围内没有发现字段缺失/额外字段/可空性差异。此次不是完整约束、索引、权限、数据内容或业务一致性审计。

### 明确未执行

- 未运行数据库迁移、`ALTER TABLE` 或任何初始化脚本的 `--initialize`。
- 未创建/删除表，未补 `notes`，未建立 Agent 回执表。
- 未创建演示账号、未重置 Neon 密码、未插入或清空库存。
- 未调用收费的真实模型接口。
- 未将秘密配置提交到 Git，未替团队部署服务或推送代码。

后端说明把 `sayfridge_auth_test` 用作自动化测试隔离库。不要直接拿它作为演示应用数据库，也不要让共享 `neondb` 承担自动化测试夹具的初始化工作。

## 5. 验证证据与边界

- 前序 UI 工作记录：Flutter 测试 80 项通过；这些是本地代码/Widget 测试，不是 Android → FastAPI → Neon 的真实链路验收。本次编写记录未重跑该测试集。
- 本机后端依赖补齐后：`pip check` 通过。
- 已执行后端数据库无关测试：`python -m pytest -q -m "not postgres"`，结果 **131 passed，440 deselected**。
- 被 deselect 的测试没有执行，不能写成后端所有数据库功能已通过本机验收。
- 本次已完成两条 Neon 只读连接检查；尚未用真实用户凭据从 App 完成登录/库存验收。
- `/health` 只返回服务存活信息，不查询数据库；能打开 `/health` 或 `/docs` 不等于数据库和业务都正常。

## 6. 现在如何验证端到端功能

### 6.1 不必先部署 Render

Android Studio/模拟器不是只能检查 UI。运行真实入口并连接真实后端后，同样可以验证业务端到端链路：

```text
Android 模拟器中的 Flutter App（main.dart）
    → 本机 FastAPI 或团队测试 API
    → 获准使用的联调数据库
    → API 返回真实结果
    → App 展示；重新读取后仍能得到相同数据
```

但 Android 原生测试不能代替最终浏览器验收。Render 上的网页还涉及 CORS、浏览器存储、页面刷新、权限和移动浏览器适配。

### 6.2 先确定不会影响同学的测试环境

优先由团队提供独立联调数据库/分支，或使用单独本地 PostgreSQL；由负责人初始化最新结构并准备必要公共分类。若复用当前共享库，必须先明确写入范围和结构修改许可。

当前限制下，可以继续分析代码或做经允许的只读检查。真实注册、入库、编辑都属于数据库写入，暂不执行。认证表本次未发现字段差异，可在获得账号和测试许可后单独验收认证；不能据此承诺完整库存链路可用。

### 6.3 当前 Windows 电脑的启动示例（仅说明，本文编写时未执行）

前提：后端 `.env` 已指向团队批准的联调目标；不是未经确认的共享环境。

终端 A：运行后端，保持窗口运行。

```powershell
Set-Location 'E:\Projects\project-implementation-appix\backend'
& '.\.venv\python.exe' -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

这里 `.venv\python.exe` 是本机已核实的路径。其他同学用标准 Windows venv 时通常为 `.venv\Scripts\python.exe`，应按自己的环境调整。Windows 下 psycopg 的事件循环要求见后端 README；此处使用其 reload 开发方式。

电脑浏览器可检查 `http://127.0.0.1:8000/health` 和 `http://127.0.0.1:8000/docs`。Swagger 可以帮助定位 API 问题，但在 Swagger 中调用注册/创建接口仍会真实写库。

终端 B：关闭此前离线预览运行会话，启动模拟器，确认设备编号后运行真实入口。

```powershell
Set-Location 'E:\Projects\project-implementation-appix\mobile'
& 'D:\develop\flutter\bin\flutter.bat' devices
& 'D:\develop\flutter\bin\flutter.bat' run -d emulator-5554 -t lib/main.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

`emulator-5554` 为此前本机设备编号，以 `flutter devices` 实际输出为准。`10.0.2.2` 是 Android 模拟器访问电脑回环地址的特殊地址；模拟器中的 `localhost` 指向模拟器自己。参见 [Android 官方网络地址说明](https://developer.android.com/studio/run/emulator-networking-address)。

也可以在 Android Studio 的 Flutter Run Configuration 中，将 Dart entrypoint 设为 `lib/main.dart`，Additional run args 设为上述 `--dart-define`，选择同一设备运行。不要同时用两个运行会话反复覆盖同一 App。

使用团队已部署的后端时，将 `API_BASE_URL` 改为已确认的 HTTPS API 地址并保留 `/api/v1`。修改构建参数后重新启动运行会话，不仅做 hot reload。

| 客户端场景 | API 地址应指向哪里 |
| --- | --- |
| Android 模拟器 → 本机后端 | `http://10.0.2.2:8000/api/v1` |
| 本机浏览器 → 本机后端 | `http://127.0.0.1:8000/api/v1`，并配置浏览器来源的 CORS |
| 手机浏览器 / Render 网页 / 原生客户端 → 云端后端 | 团队实际的 `https://.../api/v1` |

真实手机不能照抄模拟器的 `10.0.2.2`；本地真机调试另需 LAN 可达地址或 USB 端口转发。公开 Render 网页也不能使用开发者电脑的 `localhost` 作为对所有访问者有效的 API。

### 6.4 按顺序验收，不把“页面能打开”当作成功

以下写入测试仅在获准的联调库中进行。

1. **首次使用 / 游客**：全新安装或退出状态下进入 Home；Profile 显示 Guest；受限操作引导到登录。不要为了测试直接清除已有个人数据。
2. **新用户注册**：使用新的测试邮箱注册；数据库产生真实账号；按当前实现返回 Sign in。验证重复邮箱、密码不符合规则和错误提示。姓名头像同步暂不算已支持。
3. **登录和恢复**：登录后 `/auth/me` 对应同一个 user ID；显示本人状态；重启在令牌有效期内能恢复。当前令牌默认 15 分钟，无自动刷新，应明确处理到期后重新登录。
4. **读取空数据**：新用户应看到自己的空空间/空库存，不应自动出现离线预览的 8 件商品。
5. **准备基础资料并入库**：先有有效公共分类、本人空间及可用物品定义，再创建库存。目前前端写入入口尚未接完；可先通过批准的 API 测试验证后端，但不能将其算作前端完整流程通过。
6. **读取与更新**：首页、搜索、详情、临期汇总读取同一记录；接通编辑/消耗/归档后检查服务端数据和操作历史；刷新或重启后结果仍正确。
7. **账号隔离**：A 退出，B 登录；B 不应看见 A 的库存、空间或残留页面数据。需检查并处理前端共享 Controller 的缓存清理/重载，不能只检查 Profile 的本地隔离。
8. **异常处理**：断网、后端不可达、401、422、服务错误不应伪装为空库存或成功；重试不应重复创建库存。
9. **AI（基础链路完成后）**：配置后端模型与存储 → 前端发送真实文本 → 展示服务端预览 → 用户确认 → 后端写入 → Home 再读取并显示变化。不能仅展示写死的聊天气泡。
10. **最终浏览器复测**：本地 Web、Render 测试站、真实手机浏览器分别重复关键流程，覆盖刷新、返回、键盘和权限行为。

记录每次验收的环境、版本、测试 user ID、操作步骤、API 状态和结果。截图/日志需脱敏，不包含访问令牌、数据库 URL 或真实密码。

## 7. Render 上的最终交付形态

### 7.1 需要团队确认的技术路线

当前移动界面在 `mobile/`（Flutter）；根目录 `web/` 是独立 React 项目。二者不是同一套前端代码。

建议优先评估 Flutter Web 复用现有界面，以减少重复实现；这是建议，尚未决定替换现有 React 用户/管理员端规划。Flutter 可构建 Web 静态产物，Render 可承载静态站点，组合路线可行，但本项目尚未验证构建和浏览器兼容性。参见 [Flutter Web 发布说明](https://docs.flutter.dev/deployment/web) 与 [Render Static Sites](https://render.com/docs/static-sites)。

目标链路为：

```text
手机或电脑浏览器
    → Render：可交互的 Web 前端
    → Vercel：FastAPI 后端（按团队计划，线上状态尚未核实）
    → Neon：账号与业务数据
```

这不是在 Render 里运行 Android 模拟器，也不是上传 APK 就能变成网页。可以复用 App 的界面和业务流程，但浏览器与原生手机的系统通知、后台任务、录音/拍照权限等能力不同，需要单独实现和验收；不能承诺百分之百等同原生 App。

### 7.2 采用 Flutter Web 前需要补的工作

- 当前 `mobile/` 没有 `web/` 平台目录；需在团队确认后补 Web 支持，并尽早尝试本地浏览器构建。不要把它和根目录 React `web/` 混淆。
- 检查 `flutter_secure_storage`、`image_picker` 等在所选浏览器上的行为；检查头像持久化、浏览器刷新/返回和移动端布局。
- 后端当前入口未配置 CORS；需允许实际本地开发来源和 Render 站点来源，并允许所用 HTTP 方法、`Authorization`、`Content-Type` 等请求头。Android 原生能访问不代表网页能访问。参见 [FastAPI CORS 文档](https://fastapi.tiangolo.com/tutorial/cors/)。
- 构建真实入口并通过 `API_BASE_URL` 指向 HTTPS 后端；编译时参数会进入前端产物，因此只能放公开 API 地址，不能放 Neon 密码/JWT 签名密钥/模型 Key。
- Web 平台准备完成后的命令形式：`flutter build web --release -t lib/main.dart --dart-define=API_BASE_URL=https://YOUR-BACKEND-HOST/api/v1`。其中域名是占位符，必须替换。产物是 Flutter 项目下 `build/web`。
- Render 构建流程需显式准备固定版本的 Flutter SDK，或使用团队批准的 CI 产物发布流程，不能假定 Render 默认有 Flutter。若 Root Directory 设为 `mobile`，发布目录相对为 `build/web`。
- 根据路由方式配置必要的单页应用回退；在部署后验证深链接/刷新不会 404。
- Vercel 后端需单独验证部署入口、环境变量、数据库连接，以及 AI 流式响应、超时和持久化在部署环境中的行为。不是“前端发布成功”就能证明后端可用。

本次仅记录这些工作，不生成 Web 平台文件、不改 CORS、不部署、不修改数据库。

## 8. 演示账号方案

- 当前没有通过本次工作创建真实演示账号；离线 Demo User 不算。
- 将“首次注册的新用户”与“有预置库存的演示用户”分开验收，避免演示数据掩盖首次使用的问题。
- 演示账号应是普通权限、使用虚构数据、不能访问他人库存；多人演示时确认共享数据被修改后的重置方案，最好按会话或用户隔离。
- 用户提出的简单演示密码仅适合受控、可丢弃的演示环境；不作为数据库密码，不复用于真实账号。公开可访问的演示需限制权限、滥用和模型额度，不在这里记录任何已生效凭据。
- 演示数据要通过经过批准的初始化或 API 流程建立，登录仍走正常认证；不要添加绕过后端鉴权的“万能演示登录”。

## 9. 请同学确认 / 协作清单

1. **交付形态**：用户手机界面是否采用 Flutter Web 部署 Render？React 用户端/管理员端分别保留什么范围？
2. **后端地址**：可用于联调的 HTTPS API Base URL、部署版本和 API 文档；或者暂时统一使用本地后端。
3. **测试数据库**：提供独立联调环境及允许写入范围；由后端负责人同步 `notes` 与 Agent 回执表，确认已有持久化表兼容性。
4. **基础数据**：公共分类/物品定义/空间由谁准备，新用户是否自动初始化空间，演示数据由谁维护。
5. **功能范围**：先完成注册登录和库存闭环，再接 AI；姓名头像同步、密码恢复、通知、语音额度哪些必须纳入本轮验收。
6. **浏览器配置**：CORS 白名单、HTTPS、令牌存储、过期处理、Web 兼容性和移动浏览器测试。
7. **验收账号**：新用户测试账号与演示账号的邮箱、普通角色权限、初始化/重置方式，通过安全渠道交接凭据。

## 10. 文件交接注意事项

当前工作树仍有未提交的 Flutter 改动和新增预览/测试文件；本记录没有代为提交、合并或推送。发给同学前需在 GitHub Desktop 检查并提交需要共享的源码，不要把“本地文件已修改”当作“同学已拿到最新代码”。

只交接源码、测试和本记录。不要交接 `.env`、虚拟环境、缓存、构建产物或包含令牌的日志。

本记录是 2026-09-27 的状态快照，不替代后续维护的接口契约。接口细节以 `docs/reference/API_REFERENCE.md`、环境与数据库流程以 `backend/README.md`、移动端使用说明以 `mobile/README.md` 为准。
