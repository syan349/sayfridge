# SayFridge 手机界面：Flutter Web → Render

目标：老师通过手机 Safari、Chrome 或电脑浏览器打开一个 HTTPS 网址，使用 Flutter 手机界面。这个站点与已上线的 React Web 分开创建，共用实际后端。

## 1. 正式站与测试站

同一个 GitHub 仓库可以创建两个独立的 Flutter Static Site，分别跟踪不同分支：

| 用途 | Render 站点名称 | Branch |
| --- | --- | --- |
| 正式展示 | `sayfridge-mobile`（现有站点） | `main` |
| 日常测试 | `sayfridge-mobile-test`，或另一个可用名称 | `mobile-render` |

日常使用 GitHub Desktop：

1. **Current branch** 保持 `mobile-render`，检查 Changes，填写 Summary，再点击 **Commit to mobile-render**。
2. 点击 **Push origin**（分支尚未发布时为 **Publish branch**）。只有本地 Commit 不会触发云端部署。
3. 测试站在 `On Commit` 模式下自动重新部署；到该站的 **Deploys** 等待成功，再打开测试网址验收。日常测试不需要创建 PR。
4. 一批修改验证稳定后，再创建 Pull Request：**base: main**，**compare: mobile-render**。按小组流程审批合并后，正式站自动更新。
5. 在下一批工作开始前，先提交保存本地改动并 **Fetch origin**；保持 `mobile-render`，通过 **Branch → Merge into current branch** 将最新 `origin/main` 合入测试分支（若界面只有 `main`，先确保本地 `main` 已拉取到最新）。处理冲突、检查后再 Push。同步方向是 `main → mobile-render`。

提交和发布 `mobile-render` 本身不会修改远程 `main`；合并 PR 才会把这些改动加入 `main`。不要手动用旧目录覆盖 `main`，也不要强制推送。不要添加 `.env`、SDK、依赖目录或 `build/` 产物。Render 会从 GitHub 拉取源码并自行构建。[Render 分支自动部署说明](https://render.com/docs/deploys#automatic-deploys)

两个站点的部署与前端配置独立；如果 `API_BASE_URL` 指向同一个后端，仍共享该后端的数据。测试站不会自动创建独立数据库。现有 React 站点保持原配置。

## 2. 新建测试 Static Site

先将本地修改推送到 GitHub 的 `mobile-render`。Render → New → Static Site → 选择同一个 GitHub 仓库。保留现有正式站的 `main` 配置。

| 配置 | 值 |
| --- | --- |
| Name | `sayfridge-mobile-test`，或另一个可用名称 |
| Branch | `mobile-render` |
| Root Directory | `mobile` |
| Build Command | `bash scripts/render-build.sh` |
| Publish Directory | `build/web` |
| Auto-Deploy | `On Commit` |

Project 可选；Secret Files 和 Build Filters 保持空白。以后需要重建正式站时，使用同样的构建设置，将 Name 与 Branch 分别改为正式站名称和 `main`。

目录均相对 `mobile`，发布目录不要再重复添加 `mobile/`。配置依据：[Render Monorepo Support](https://render.com/docs/monorepo-support)。

在 Environment Variables 中添加：

| KEY | VALUE |
| --- | --- |
| `SKIP_INSTALL_DEPS` | `true` |
| `API_BASE_URL` | 实际后端的 HTTPS 地址，必须带 `/api/v1`，例如 `https://YOUR-BACKEND-HOST/api/v1` |

Flutter 构建不需要 `NODE_VERSION`，也不读取 `VITE_API_BASE_URL`。脚本使用已固定的 Flutter 3.44.8 / Dart 3.12.2，按锁文件安装依赖，再编译正常入口 `lib/main.dart`。不要把后端 `.env` 或数据库/模型密钥放进前端。

**后端尚未部署时，可以先不添加 `API_BASE_URL`。** 脚本会明确提示只部署界面；新浏览器可以查看游客 Home、AI 介绍页、Profile、登录与注册表单。它不会生成演示账号或库存，登录提交、真实数据及 AI 不会因此可用。请勿填一个虚构域名来伪装后端已连接。

后端上线后添加真实 `API_BASE_URL`，选择保存并重新构建部署。该变量是编译时参数，仅刷新浏览器无法更新。当前手机端默认浏览器 API 路径是同源 `/api/v1`；Android 默认仍是模拟器地址。

## 3. 发布后设置页面回退和后端来源

点击 Deploy Static Site。首次构建包含下载 Flutter SDK，通常比 React 构建多一个较大的下载过程；通过日志观察 SDK 下载、依赖安装、编译和上传结果。

Deploy succeeded 后，记录页面顶部实际的 `.onrender.com` 地址。不要提前把示例站名当成平台已经分配的地址。

在 Redirects/Rewrites 添加：

| Source | Destination | Action |
| --- | --- | --- |
| `/*` | `/index.html` | `Rewrite` |

Flutter 当前使用 Navigator 页面导航，不保证每个屏幕都有可分享的独立路径。回退规则用于让请求回到应用入口，不会自动为每个页面创建深链接。[Render 重写说明](https://render.com/docs/redirects-rewrites)

让后端负责人在 **后端服务**的 `CORS_ORIGINS` 中保留原来源，并添加测试站的实际来源。例如，下面三个域名都是需要替换的占位符：

```text
CORS_ORIGINS=["https://YOUR-REACT-SITE.onrender.com","https://YOUR-FLUTTER-SITE.onrender.com","https://YOUR-FLUTTER-TEST-SITE.onrender.com"]
```

这里填完整 HTTPS 来源，不带 `/api/v1` 或页面路径。后端需要部署已包含 CORS 中间件的版本，并配置各站点的来源；前端代码合入 `main` 不代表云端后端已同步部署或配置完成。

## 4. 老师访问前的验收

- [ ] 首页、AI 游客页面和 Profile 在手机与电脑浏览器正常显示。
- [ ] 从游客进入登录/注册页、页面返回、刷新、键盘弹出后布局正常。
- [ ] 网络请求指向真实 HTTPS 后端；浏览器不会请求开发电脑的 `10.0.2.2`。
- [ ] 注册、登录、刷新恢复登录、退出和换账号使用真实测试账号通过。
- [ ] 创建空间→入库→修改/消耗→刷新后的库存一致，数据来自同一后端。
- [ ] 文本 AI 确实流式展示；确认/取消、断线恢复和库存刷新通过。
- [ ] iPhone Safari 与 Android Chrome 分别真机验证。电脑模拟手机视口只能验证布局的一部分。
- [ ] iPhone 从 Safari 和 Chrome 添加到主屏幕后，冷启动、页面切换及键盘收起后无额外底部留白；记录 iOS 版本。
- [ ] 拍照、语音、提醒和历史等仍未完成的功能没有被当作已完成演示。

当前使用普通 JavaScript Web 构建，未启用 Wasm；CanvasKit 资源随站点发布，避免额外依赖 Flutter 资源 CDN。Flutter 官方产物目录说明见 [Build and release a web app](https://docs.flutter.dev/deployment/web)。

## 5. 日志排错

| 日志/现象 | 检查 |
| --- | --- |
| `scripts/render-build.sh: No such file` | 新文件是否已推送；Branch 是否正确；Root Directory 是否为 `mobile` |
| `flutter: command not found` | 应使用这里的脚本，让它先准备 SDK，不是直接运行裸 `flutter build web` |
| API 地址校验失败 | 填完整 HTTPS 后端地址，带 `/api/v1`，不要加引号、查询参数或页面路径 |
| Flutter SDK 下载失败 | 查看具体网络错误；修复后重试部署，保持 SDK 版本固定 |
| 依赖锁文件检查失败 | 在相同 SDK 上核对 `pubspec.yaml` / `pubspec.lock`，一起提交正确版本 |
| 页面能开，登录失败 | 检查编译时 API 地址、后端实际版本、CORS、数据库和测试账号 |
| 浏览器显示旧版本 | 确认最新部署成功后刷新；检查实际 URL 和部署 commit |
| iPhone 桌面 App 所有页面底部留白 | 核对发布的 `index.html` 中状态栏模式为 `default`；重新添加桌面图标后对照，记录 iOS 版本与添加图标的浏览器 |

iPhone 桌面模式已将 `apple-mobile-web-app-status-bar-style` 从 `black-translucent` 改为 `default`，准备绕开透明状态栏与视口高度处理异常。依据是 [WebKit 的透明状态栏/底部位置报告](https://bugs.webkit.org/show_bug.cgi?id=236445#c9) 及 [iOS 27 beta 的全屏问题确认](https://bugs.webkit.org/show_bug.cgi?id=301994#c14)；这些报告不能替代本站的真机验证。按照 [Apple 的状态栏定义](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariHTMLRef/Articles/MetaTags.html)，网页会布局在系统状态栏下方，语音遮罩无法保证覆盖该系统区域。

先在测试站部署并按上面的步骤验证，再合入正式站。已有桌面 App 可能仍使用安装时的设置；需要重新添加时只处理对应图标，不清空整个网站的存储。普通 Safari 标签页显示底部地址栏和浏览器按钮是正常行为。

老师使用正式站的公开访问链接；开发期间使用测试链接。两者都不需要 Render 后台账号或安装 APK。登录后的业务功能仍需要应用自身账号和可用后端。
