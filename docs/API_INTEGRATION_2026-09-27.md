# Flutter ↔ 后端 API 接入更新

日期：2026-09-27。接入对象是 `mobile/` 的正常入口 `lib/main.dart`，不是离线预览或根目录 React `web/`。

## 可以发给同学的结论

本轮已把 Flutter 的主要库存写入流程和文本 AI Agent 接到现有 FastAPI 接口，保留原有注册登录、查询和 Profile UI。代码接线和本地自动化测试已完成，但**尚未完成真实数据库/模型的端到端验收**。没有修改共享 Neon、创建真实演示账号、调用付费模型、提交/推送代码或部署。

当前默认地址仍是 Android 模拟器访问本机后端的 `http://10.0.2.2:8000/api/v1`，不是 GitHub 或已经确认的 Vercel 地址。GitHub 保存源码；运行时请求的是启动/部署后的 API 服务。

## 1. 文档与代码核对

核对依据：`docs/API_REFERENCE.md`、`docs/ARCHITECTURE.md`、`docs/QUANTITY_STATE_DESIGN.md`，并参考 `docs/PROJECT_SCOPE_BILINGUAL.md` 的产品边界、`docs/testing/AGENT_V02_TEST_RESULTS.md` 和 `backend/README.md`。请求结构同时核对了 `backend/app/schemas/` 和路由实现。

- 产品 scope 包含未来目标，不代表所有接口已经实现。目前 Agent 是文本工作流；语音、图片/OCR、Worker 通知不能因设计图有按钮就宣称已接通。
- 普通编辑接口只能修改日期、空间、备注。数量必须走 ADD / CONSUME / RECONCILE，不能上传前端自行算出的余额或更改估算标记。
- 数量按十进制字符串提交，携带 `expected_version` 和 `Idempotency-Key`。盘点提交实际剩余总量，不是增减量；比例消耗提交 `p/q` 与 `remaining`。
- 空间 archive / restore 必须是零请求体，不能发送 `{}` 或 JSON `null`。
- 单件操作历史返回 JSON 数组。文档第 7 节的 “history endpoints remain planned” 是过时文字，与后面的 B14 及现有实现冲突；本轮按已实现的 B14 接入，未改团队接口文档。
- Agent 的 `done` 不等于每一项成功；必须逐项看状态。确认操作使用服务端返回的 item / proposal / interrupt ID，不能自造批准字段或余额。
- 当前本地 HEAD 为 `d51df8c`，已抓取的 `origin/main` 为 `b802ea0`；路由契约对比未见差异，但 main 有新 Web/CORS 工作。本次未合并 main，也未覆盖同学的 Web 实现。

## 2. 已接线范围

以下路径均以 `/api/v1` 开头。“已接线”只表示 UI 会发真实请求，不代表共享环境已验收。

| 功能 | API / 行为 | 本轮状态 |
| --- | --- | --- |
| 注册、登录、恢复用户 | `/auth/register`、`/auth/login`、`/auth/me` | 保留已有接入；注册后需登录；令牌保存在安全存储 |
| 首页、搜索、详情、临期汇总 | 库存/空间 GET、expiry-summary | 保留读取；写入和 AI 回合后刷新 |
| 空间管理 | POST / PATCH `/storage-spaces`，archive / restore | 接入创建、编辑、归档、恢复；空账号可创建首个空间 |
| 入库目录选择 | GET `/item-categories`、`/item-definitions` | 获取所有分页，不仅前 20 条 |
| 私人物品定义 | POST `/item-definitions` | 入库前可新建；依赖后端已准备有效公共分类 |
| 新建库存 | POST `/inventory-items` | 从 Inventory Overview 的 Add inventory 进入 |
| 修改/移动库存 | PATCH `/inventory-items/{id}` | 详情 → Edit item，仅提交已改变字段及版本；空日期/备注提交 null |
| 增加、消耗、盘点 | POST `/inventory-items/{id}/operations` | Add quantity / Use quantity / Use a fraction / Confirm remaining |
| 库存状态 | POST `/inventory-items/{id}/discard`、`archive` | 先确认，再按版本提交；不是删除记录 |
| 单件操作历史 | GET `/inventory-items/{id}/operations` | 展示服务端记录；区分失败/撤销与有效成功记录 |
| 文本 AI | POST `/agent/chat` | 真实输入与 SSE 增量回复，不使用固定示例回复 |
| AI 交互 | POST `/agent/resume` | 逐项确认、取消、补充、编辑；可选择服务端候选库存 |
| AI 恢复 | GET `/agent/conversations/{id}/state` | 查询最近会话状态；同请求重试；不是完整聊天历史列表 |

## 3. 失败、重复提交及账号隔离

- 写入期间禁用重复提交。普通创建/编辑响应丢失后，不自动重发；页面提示先返回并检查最新数据，避免重复入库。
- 数量操作在同一个弹窗中保留幂等键和原始输入；不确定结果后冻结输入，重试仍使用同一键。关闭弹窗前应先核对结果；未实现手工写入的跨重启待办队列。
- 版本冲突要求关闭表单并重新读取，不用陈旧版本直接覆盖。
- Agent 在发请求前，按用户保存最近 conversation ID 与尚未确认的完整请求（含 request ID）。恢复/重试不生成新身份，不自动重放写操作；不可把未完成请求作为新消息重复提交。
- SSE UTF-8 分片、多行 data、心跳均能处理；连接断开不假定失败回滚，也不假定成功。先查会话状态，再允许同请求重试。
- 过期 proposal / interrupt 会先刷新，再允许处理服务端当前提案。`EXECUTION_UNCERTAIN` 只允许核实原操作，不允许随意编辑/取消。
- 登出/换账号清空库存、空间、临期和 AI 界面状态；忽略旧账号的迟到响应。AI 的恢复资料按用户隔离，并使用现有安全存储，不把 token 写进会话内容。
- 当前会话恢复不能替代完整历史 API；重启后不保证恢复整段聊天文字，只能恢复服务端最新状态和待确认事项。
- 401 会提示重新登录；当前后端没有 refresh token，不实现伪造的自动续期。

## 4. 本轮验证

已执行：

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub`：**100 个测试通过**，包含已有 UI 回归和新增请求/状态测试。
- `flutter build apk --debug -t lib/main.dart --no-pub`：通过；产物 `mobile/build/app/outputs/flutter-apk/app-debug.apk`，为真实入口（默认本机模拟器 API 地址），不是离线预览。仅完成构建，本轮未安装或进行真实账号验收。
- 14 组代表性前端请求通过实际后端 Pydantic 模型验证（注册登录另有既有测试）。这是离线契约验证，不是 HTTP/数据库联调。
- 新增覆盖：零请求体、版本与 null、数量字面量/幂等重试、目录分页、无 token 拒绝写入、SSE 分片与恢复、旧提案冲突、账号切换迟到响应、手机尺寸 AI 确认与失败展示、表单未知结果保护。

所有本轮测试均未写共享 Neon，也未使用真实模型。未将本轮测试与团队历史后端验收结果相加。

## 5. 仍未接通/仍需团队处理

1. **数据库结构**：此前只读检查发现当前共享 `neondb` 缺 `inventory_item.notes` 和 `agent_inventory_action`。本轮未重新检查或修改；需要后端同学在获准的联调环境同步并验证。已有初始迁移执行记录不能证明新增字段/表已同步。
2. **Agent 配置**：此前本机模型 Key 未配置。后端负责模型 Key、Agent checkpoint/store 兼容性与回执表，不将密钥放进 Flutter。
3. **联调地址与数据**：需要一个实际可用的后端 Base URL、允许写入的独立测试库、有效分类及测试账号。公共分类由获准的初始化/管理流程建立，前端不直接写数据库。
4. **现有 API 但本轮未做 UI**：手工批量入库/移动/归档、全局操作历史、私有目录的完整编辑/归档管理、管理员页面。此轮覆盖当前手机端主要单件业务闭环，不等于每个后端 API 都已有页面。
5. **缺后端支持的功能**：真实找回/修改密码、资料跨设备同步、通知调度、语音/图片/OCR、完整会话历史、语音额度。Profile 姓名头像/提醒仍为本机偏好；真实入口不把演示额度当成真实数据。
6. **最终 Render 交付**：Flutter 手机端与根目录 React Web 是不同工程。未生成 Flutter Web 平台目录或部署；main 的新 Web/CORS 工作需由团队确认如何整合。Android 构建通过不代表浏览器已通过；还需 HTTPS、CORS、存储/插件和 SSE 的浏览器验收。

## 6. 获准联调后的操作顺序

先由后端同学提供可写的独立联调环境并处理第 5 节前置条件。不要在共享生产库直接试写或未经确认执行初始化脚本。

如使用本机后端，在 `backend/` 中，用项目 Python 环境启动：

```powershell
# 本机现有环境的 python 位于 .venv 根目录；标准 venv 通常是 .venv/Scripts/python.exe。
.\.venv\python.exe -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

在 `mobile/` 中启动真实入口：

```powershell
flutter run -t lib/main.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

若使用已部署后端，把地址换成团队确认的 HTTPS 地址，保留 `/api/v1`。真机不能照抄模拟器的 `10.0.2.2`；需真机可达地址。修改构建参数后重新启动，不仅 hot reload。出现 `UI PREVIEW · OFFLINE` 说明启动了错误的预览入口。

验收顺序：

1. 游客 → 注册新测试用户 → 登录 → 重启恢复；新用户不应出现离线演示库存。
2. All Spaces → Manage storage spaces → 创建空间。
3. View all items → Add inventory → 选择/创建私有物品定义 → 选择空间 → 入库。
4. Home、搜索、详情、临期概览核对同一条记录；修改备注/日期/位置。
5. 增加数量、消耗指定数量或比例、盘点；核对服务端余额、版本、估算标记与操作历史。
6. AI 先问库存，再测试精确操作、估算确认、多候选选择、取消与断线恢复。逐项检查，不以一句 AI 回复当作写入证据。
7. 退出并换另一个账号，确认没有上一账号的空间/库存/会话；测试错误密码、401、409、断网和服务不可达。
8. 通过后再进行真实手机浏览器/Render 测试站验收。上线、迁移和演示账号初始化另行批准执行。

## 7. 主要改动位置

- `mobile/lib/repositories/workspace_repository.dart`：手工业务 API。
- `mobile/lib/screens/stock_editor_screen.dart`、`widgets/inventory_actions.dart`、`widgets/business_forms.dart`：入库、编辑、数量、历史与提交保护。
- `mobile/lib/services/api_client.dart`：PATCH、无请求体 POST、数组响应与 SSE。
- `mobile/lib/state/agent_controller.dart`、`services/agent_session_store.dart`、`screens/agent_conversation_screen.dart`：真实文本 AI 与恢复。
- `mobile/lib/main.dart`、业务 Controller：依赖接线、刷新与账号隔离。
- `mobile/test/`：对应契约、恢复、隔离与页面测试。

当前源码仍在本地工作树，未提交推送。同学需要收到源码和测试后才能使用；不要共享 `.env`、缓存、安全存储或含凭据的日志。
