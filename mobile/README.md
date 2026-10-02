# SayFridge Mobile

SayFridge 的 Flutter 手机端，面向 Android 和 iOS，包含登录注册、首页、库存、AI Assistant 和 Profile 页面。

AI Assistant 作为二级页面打开：从 Home 或 Profile 进入后，左上角返回按钮回到进入前的页面，不显示底部导航。登录后的输入框固定在底部安全区域上方，距安全区域底边 28 个逻辑像素，键盘弹出时随可用页面高度上移；游客在同一位置显示登录入口。Inventory 的 Delete 图标进入批量选择，Confirm 打开删除确认弹窗，Cancel 退出选择并清空勾选。

底部导航统一使用 `AppBottomNavigation`，固定放在页面 `SafeArea` 的底端、滚动内容之外。白色导航栏居中占可用宽度的 78%，左右入口在栏内中央 80% 的宽度中与中间入口等距排列；中间绿色图标（含外圈）的下沿与两侧图标对齐，图标与文字统一间隔 3 个逻辑像素。底部保留 28 个逻辑像素的间距，页面不要再添加导航外边距。游客和登录状态使用相同布局，只切换选中状态；输入框和内容的预留空间使用组件的 `extent`。

## 环境要求

- Flutter SDK
- Android Studio / Android SDK（Android 开发）
- Xcode（iOS 开发，仅 macOS）

## 本地运行

```bash
flutter pub get
flutter run
```

## 基础检查

```bash
flutter analyze
flutter test
```

应用包名：`com.appix.sayfridge`。

## 浏览器版本 / Render 部署

本工程现在包含 Flutter Web 平台文件。它展示手机端 Flutter 界面，与仓库根目录的 React `web/` 是两个独立站点。

电脑浏览器在足够大的窗口中自动显示居中的手机外框，内部宽度为 390px，高度最多 844px；窗口变窄或变矮时使用全部可用区域。手机触摸浏览器使用 Flutter 原有的全屏模式与键盘处理。外框覆盖所有页面和弹窗，只影响浏览器展示，不改变 Android/iOS 原生应用。

```bash
flutter run -d chrome --web-port=5174 -t lib/main.dart --dart-define=API_BASE_URL=https://YOUR-BACKEND-HOST/api/v1
flutter build web --release -t lib/main.dart --no-web-resources-cdn --dart-define=API_BASE_URL=https://YOUR-BACKEND-HOST/api/v1
```

替换示例域名后运行。网页未配置 `API_BASE_URL` 时使用同源 `/api/v1`；在只托管静态文件的 Render 上，这只能用于先查看游客界面，登录、库存和 AI 需接通后端后再验收。Android 模拟器的默认地址保持不变。

Render 正式站跟踪 `main`；另建测试站跟踪 `mobile-render`，每次向测试分支提交并推送即可更新测试站，稳定后再通过 PR 合入 `main`。两个站点都使用 **Static Site**，Root Directory 填 `mobile`，Build Command 填 `bash scripts/render-build.sh`，Publish Directory 填 `build/web`，Auto-Deploy 选 `On Commit`。脚本准备 Flutter 3.44.8，并把各站点的 `API_BASE_URL` 变量传给 Dart 编译器；不使用 React 的 `VITE_API_BASE_URL`。详细步骤和上线检查见 [手机端 Render 部署](../docs/archive/deployment/RENDER_DEPLOY.md)。

## 真实 API 入口与联调

```bash
flutter run -t lib/main.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

- 默认地址适用于 Android 模拟器访问本机后端。云端/真机需替换为可达的后端地址（云端使用 HTTPS），保留 `/api/v1`；不要填写 GitHub 或 Neon 连接地址。改变构建参数后重新启动。
- 保留注册/登录/当前用户、库存/空间查询、搜索与临期汇总；已增加空间创建/编辑/归档/恢复、私人物品定义创建、入库、元数据编辑/移动、ADD/CONSUME/RECONCILE、库存归档/丢弃与单件操作历史。
- 新账号可从空间管理创建首个空间，从 Inventory Overview 的 Add inventory 入库。创建私有定义依赖后端已有有效公共分类。
- 登录后的 AI Assistant 使用真实文本 Agent chat/resume/state，支持 SSE、逐项确认/补充/编辑/取消。精确操作可能直接执行，估算/新关联按后端要求确认。
- AI 初始页复用原设计的欢迎区和三个快捷提示，快捷提示发送对应的真实 Agent 消息。白色输入栏默认按住说话，右侧键盘切换文字输入；松开语音后进入可编辑文本，选择照片后可直接发送纯图片。AI Assistant 和 Daily Check-in 共用 `AgentInputPanel`，统一处理语音、拍照、选图、图片预览和校验；请求身份和库存变更仍由 Agent 控制器及后端负责。
- Daily Check-in 保留回忆主题卡片，底部使用同款输入栏。点击发送后将文字和图片一起带到 AI Assistant，并请求先提出库存扣减方案、等待确认。语音识别结果仍可编辑，滑动取消保留已有文字；发送失败或有待处理请求时保留整份输入。Daily Check-in 最多 1000 字，每次最多 4 张图片，与 AI Assistant 共用图片大小和格式限制。
- AI Assistant 顶部返回、标题、新建及历史固定，滚动渐隐从标题下方开始；已上传照片显示在用户气泡下方，并随本机近期会话保存。仅上传图片时直接请求识别并准备审核卡片，仍须通过按钮确认后才写入库存。卡片放大图片，整理识别文本，使用并排 Confirm / Cancel；真正缺失的信息仍需补充或选择批次。
- Issue #147：两项以上待审核方案显示 Confirm all，每次通过现有 `/agent/resume` 提交当前方案列表（最多 20 项）。缺失信息或执行结果待核实的项目不进入批量确认；失败/断线使用原请求身份重试，各项执行结果分别展示。
- Item details 的 More actions / Archive 已移除，Quantity 操作使用整行按钮。编辑页可直接修改名称、数量、自由输入单位、日期、空间和备注；Added on 只读。Exact 显示绿色并允许填写，AI-estimate 显示橙色 `≈` 且锁定数量/单位。保存使用扩展的库存 PATCH 接口原子提交；数量精确测量记录 RECONCILE，初始入库信息保持不变。前后端需一起部署。
- 文字模式中的麦克风只切换回语音栏，点击或长按该图标均不启动识别。仅按住语音栏中间区域开始英文识别（`en-US`），松开停止采集并等待最终文字，上滑取消；实时文字显示在输入栏上方，识别结果需手动发送。浏览器开始监听和返回最终结果都是异步事件，首次授权后若已松手不会继续后台监听。
- Agent 最近会话及未确认请求按用户保存在安全存储，断线后先查询再使用同一请求身份重试；没有完整聊天历史列表接口。普通非幂等写入丢失响应后先关闭表单并重新核对数据，不能盲目重复入库。
- 退出/换账号会重置业务列表与会话状态。没有自动刷新令牌；过期后重新登录。
- **代码接线不等于云端已通**：共享数据库此前发现缺字段/回执表，模型 Key 及联调环境仍需后端准备。本轮没有对共享 Neon 写入、创建真实演示账号或部署。

详细范围、文档差异、验证记录与端到端步骤见 [API 接入更新](../docs/archive/2026-09-27/API_INTEGRATION_2026-09-27.md)。

## 离线登录后 UI 预览（仅 Debug）

```bash
flutter run --debug -t lib/main_preview.dart
```

- 独立入口默认打开 Demo User 的登录后 Profile，右上角持续显示 `UI PREVIEW · OFFLINE`。
- 可检查 Home、AI Assistant、Profile 及其子页；语音 12 / 50 为示例，Home 默认有 8 件示例库存，包含 3 件临期商品及 Fridge / Freezer / Pantry 三个空间。日期相对本次启动当天生成。
- 登录预览状态下，点击右上角 `UI PREVIEW · OFFLINE` 可切换 `Sample inventory (8 items)` / `Empty inventory`，会回到 Home 并重置筛选。库存列表、空间筛选、搜索、临期概览和商品详情均使用同一份离线数据；库存写入不提供模拟成功反馈。
- 姓名、头像和提醒设置仅保存在本次运行的内存中。Log out 可切换游客状态，再点 Log in / Sign up → Enter preview 重新进入，无需密码。
- 预览不读取或修改真实登录令牌和本机个人资料，不发起网络请求；邮件、密码修改和通知发送仍未接入。
- 正常入口 `lib/main.dart` 未接入任何预览逻辑。回到真实登录版本运行 `flutter run -t lib/main.dart`。预览入口在 release/profile 构建中拒绝启动。

## Profile 页面

- 游客和登录用户均可从 Home / AI Assistant 的底部导航进入 Profile。
- 游客点击锁定菜单或登录按钮会进入登录页；登录成功返回 Profile。
- 登录后可进入个人资料、密码重置、提醒设置、语音用量页；子页返回 Profile。
- 姓名、头像、提醒开关、提前天数和时间通过 `ProfilePreferencesRepository` 按用户 ID 保存在本机，未同步到后端。保存失败会提示，取消编辑不覆盖已保存的资料。
- 登录邮箱由后端管理；当前没有邮箱或密码修改 API，界面不会伪造修改成功。密码只存在于表单内存中。
- 提醒偏好按用户保存在本机。用户从提醒设置页主动开启设备通知后，Android/iOS 会按所选时间安排每日库存/临期提醒；网页端受浏览器限制，关闭网页后不能后台定时发送，但每次打开 SayFridge 时会根据实时临期汇总显示仍未读的浏览器通知和首页通知卡。
- 首页分别显示过期、即将到期和每日检查提醒。未读提醒在重新打开应用时仍会出现；用户选择 `Mark as read` 后当天不再重复，次日若条件仍成立会重新出现。过期提醒的 `Process now` 会打开仅显示过期物品的列表，用户进入物品详情后使用现有 `Discard` 二次确认流程处理，记录不会被删除。
- 效果图以 requests 统计语音额度；当前后端模型的 `voice_*_seconds` 以秒计量，且 `/auth/me` 不返回这些字段。生产页面显示用量暂不可用，待确认请求次数接口后传入 `VoiceUsage`。测试中的 12 / 50 仅用于效果图核对。

Profile 跳转、表单校验、本地保存、账号切换隔离和小屏布局测试在 `test/screens/profile_flow_test.dart` 与 `test/state/profile_controller_test.dart`。
