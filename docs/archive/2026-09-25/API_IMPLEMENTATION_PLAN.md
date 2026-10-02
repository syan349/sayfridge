> 已归档 / Archived — 2026-09-25。以下内容保留历史决策和当时状态，不是当前实施指令。当前入口：[当前后端设计](../../architecture/BACKEND_DESIGN.md)与[接口参考](../../reference/API_REFERENCE.md)。旧文中的阶段限制、能力和部署说明仅代表当时方案。

# SayFridge 基础业务 API 实施计划

> 更新：2026-09-11。状态：本轮范围与文件清单，尚未实施。逐接口字段、数据库读写、数量精度、历史查询及事务规则见 [API 与数据库实施规则](API_DATABASE_IMPLEMENTATION_DRAFT.md)。

## 1. 本轮范围

本轮完成：

**登录 → 管理空间和物品 → 手动入库 → 查询库存 → 增加、扣减和盘点 → 查看操作历史。**

同时提供批量管理、库存概览、临期查询和基础管理员接口，让前端可以开始开发。

### 已删除的功能

整套提醒和通知暂不做，包括：

- 提醒设置、用户时区设置。
- 定时提醒和后台任务。
- 手机绑定、FCM、手机推送。
- 通知列表、未读数、已读状态。
- 提醒设置表、通知表、用户推送字段。

**保留库存页面主动查询临期物品的接口，它只是查询数据库，不发送通知。**

其他暂不做的内容：

- AI Agent、语音、图片识别、对话、记忆、撤回和历史重算。
- 昵称、头像、忘记密码、令牌刷新。
- 管理员审计、完整修改历史、历史快照。
- 库存物品关联纠正、已丢弃或归档库存的恢复。空间和词典的恢复接口仍保留。
- 手动/Agent 来源区分、来源字段和操作到对话的关联，留到 Agent 阶段设计。
- 前端页面和部署。

本次只实现后端代码和文档；不运行测试，不执行实际数据库迁移，不提交或推送 Git。

## 2. 文件清单

预计 **新增 10 个文件，修改 9 个现有文件**。其中新增 API 路由文件 5 个，新增请求响应模型文件只有 1 个。

以下后端路径均相对于 `backend/`。本计划文件本身不计入未来实施的文件数量。

### 新增文件：10 个

| 编号 | 文件 | 职责 |
|---|---|---|
| N01 | `app/api/routes/storage_spaces.py` | 空间查询、创建、修改、归档、恢复 |
| N02 | `app/api/routes/catalog.py` | 公共品类查询、物品查询、私有物品维护 |
| N03 | `app/api/routes/inventory.py` | 库存查询、入库、资料修改、丢弃归档、批量管理、概览和临期查询 |
| N04 | `app/api/routes/inventory_operations.py` | 数量预览、增加、消耗、盘点和操作历史 |
| N05 | `app/api/routes/admin.py` | 查询账号、修改普通用户状态、管理公共词典 |
| N06 | `app/schemas/business.py` | 本轮全部业务请求与响应模型，按功能分段 |
| N07 | `app/services/catalog.py` | 空间和词典的必要业务规则，普通用户和管理员共用 |
| N08 | `app/services/inventory.py` | 数量计算、库存事务、版本校验、数量操作防重及批量处理 |
| N09 | `migrations/versions/<revision>_add_inventory_notes.py` | 唯一增量迁移，只增加备注字段 |
| N10 | 项目根目录下 `docs/reference/API_REFERENCE.md` | 完整接口文档、文件职责和验证状态 |

### 修改文件：9 个

| 编号 | 文件 | 具体修改 |
|---|---|---|
| M01 | `app/main.py` | 直接注册五个业务路由，增加跨域配置及必要错误处理 |
| M02 | `app/api/dependencies.py` | 增加管理员身份校验，复用现有用户认证 |
| M03 | `app/api/routes/auth.py` | 新增改密码接口，补充中英文接口说明 |
| M04 | `app/schemas/auth.py` | 增加旧密码、新密码请求模型 |
| M05 | `app/services/auth.py` | 校验旧密码并更新密码哈希 |
| M06 | `app/db/models.py` | 只增加 `inventory_item.notes` |
| M07 | `app/core/config.py` | 增加可配置的 Web 跨域来源 |
| M08 | `.env.example` | 补充跨域配置示例 |
| M09 | `README.md` | 更新启动、迁移说明和前端文档入口 |

### 组织原则

- 所有路由直接在现有 `main.py` 注册，不新增总路由文件。
- 简单只读查询可以直接写在路由里；计算、事务和复用规则放进 service。
- 不创建 Repository、通用 CRUD 框架、后台任务或文档生成脚本。
- 不给每个接口机械地创建一对模型：详情和列表复用响应模型，无请求体的接口不创建请求模型。
- `business.py` 内按空间、词典、库存、操作、管理员分段，各模型清楚命名。
- 文件数量不是硬指标；如确实需要改变上述清单，先说明原因，不自行扩大范围。

### 每个接口的注释

每个接口都要有：

1. 中英文 `summary`，显示在 Swagger。
2. 简短中英文函数说明，解释用途和重要限制。
3. 必要的中英文业务注释，例如为什么估算余额不能被普通扣减覆盖。

```python
@router.post(
    "/{item_id}/operation-preview",
    summary="预览库存变化 / Preview inventory change",
)
async def preview_operation(...):
    """
    计算操作后的数量，不修改库存或操作历史。
    Calculate the resulting quantity without changing inventory or history.
    """
```

## 3. 数据库变更

**不新增任何表。只给现有库存表增加一个字段：**

| 表 | 字段 | 类型 | 规则 |
|---|---|---|---|
| `inventory_item` | `notes` | TEXT，可空 | 用户备注，API 最多允许 1,000 字 |

迁移要求：

- 新增一份增量迁移，不修改原始八表迁移。
- 已有库存的备注为空，不改现有数量或历史。
- 不修改 `inventory_operation` 的类型、字段或约束。
- 不增加推送字段、令牌版本、幂等表或审计表。
- 本轮只编写迁移文件；实际执行前单独确认目标数据库。

## 4. API 清单与行为

除现有 `/health` 外，以下路径统一带 `/api/v1` 前缀。

### A. 认证：现有 `auth.py`

| 接口 | 功能 |
|---|---|
| `POST /auth/register` | 注册，保留现有实现 |
| `POST /auth/login` | 登录，保留现有实现 |
| `GET /auth/me` | 当前用户，保留现有实现 |
| `POST /auth/change-password` | 验证旧密码后修改密码 |

改密码只更新现有密码哈希，不新增令牌撤销机制。当前客户端成功后清除登录状态并重新登录；已签发令牌在自然过期前仍有效，默认有效期 15 分钟。

### B. 空间：N01

| 接口 | 功能 |
|---|---|
| `GET /storage-spaces` | 查询自己的空间 |
| `POST /storage-spaces` | 创建空间 |
| `GET /storage-spaces/{id}` | 空间详情 |
| `PATCH /storage-spaces/{id}` | 修改名称、类型 |
| `POST /storage-spaces/{id}/archive` | 归档空间 |
| `POST /storage-spaces/{id}/restore` | 恢复空间 |

只允许操作自己的空间。存在在库物品时不能归档；归档空间不能接收入库。保留已有的活动空间名称唯一规则。

### C. 品类和物品：N02

| 接口 | 功能 |
|---|---|
| `GET /item-categories` | 可用公共品类 |
| `GET /item-definitions` | 搜索公共物品和自己的私有物品 |
| `GET /item-definitions/{id}` | 物品定义详情 |
| `POST /item-definitions` | 创建私有物品 |
| `PATCH /item-definitions/{id}` | 修改自己的私有物品 |
| `POST /item-definitions/{id}/archive` | 停用私有物品 |
| `POST /item-definitions/{id}/restore` | 恢复私有物品 |

普通用户不能编辑公共词典或访问别人的私有词典。停用物品定义不删除已有库存；修改定义名称会影响关联库存的当前显示。

### D. 库存、批量和概览：N03

| 接口 | 功能 |
|---|---|
| `GET /inventory-items` | 分页查询，按名称、空间、品类、状态和日期筛选 |
| `POST /inventory-items` | 新建一批库存 |
| `GET /inventory-items/{id}` | 查询详情 |
| `PATCH /inventory-items/{id}` | 修改日期、位置和备注；不允许更换物品关联 |
| `POST /inventory-items/{id}/discard` | 标记整批丢弃 |
| `POST /inventory-items/{id}/archive` | 归档 |
| `POST /inventory-items/batch-create` | 批量入库 |
| `POST /inventory-items/batch-move` | 批量移动位置 |
| `POST /inventory-items/batch-archive` | 批量归档 |
| `GET /inventory-summary` | 在库批次数及空间、品类分布 |
| `GET /expiry-summary` | 过期、今天到期、临期统计和分页明细 |

固定规则：

- 入库直接初始化初始数量和当前确认数量，不再额外记一次 ADD。
- 普通资料编辑不能修改数量。
- 整批丢弃改为 `DISCARDED`，归档改为 `ARCHIVED`；保留最后数量，不记成正常消耗。
- 本轮不保存资料修改、丢弃或归档的详细操作历史。
- 不物理删除、不合并批次、不提供部分丢弃记录。
- 录错物品时，先通过已有 archive 接口归档旧库存，保留原记录及数量历史，再独立创建正确的新批次。不新增物理 DELETE、更正记录或新旧批次关联；两个请求不承诺一起回滚。
- 已归档或丢弃记录只读；已用完记录可通过增加或盘点恢复在库。
- 批量最多 100 条，一条失败整批回滚，并指出失败位置。
- 库存列表默认展示在库批次，未知到期日排在最后。
- 概览按批次数统计，不混加不同单位。

临期查询不再依赖提醒设置：

- 前端传入 `as_of=YYYY-MM-DD`，表示用户当地今天。
- `days_before` 默认 3，允许 0–365。
- 早于 `as_of` 为过期，当天为今天到期，随后 1–N 天为临期，三项不重复。
- 只统计在库且有到期日的物品。
- 后端不保存用户时区，不运行定时任务。

### E. 数量和历史：N04

| 接口 | 功能 |
|---|---|
| `POST /inventory-items/{id}/operation-preview` | 预览，不写数据 |
| `POST /inventory-items/{id}/operations` | 增加、消耗、盘点 |
| `GET /inventory-items/{id}/operations` | 单件数量操作历史 |
| `GET /inventory-operations` | 自己的全部数量操作历史 |
| `GET /inventory-operations/{id}` | 单条操作详情 |

实际处理方式：

```text
提交“消耗 2 个”
→ 当前库存从 10 改成 8
→ 同时保存本次消耗 2 个的记录
→ 查询库存直接返回 8
```

具体规则：

- `ADD`、`CONSUME` 接收本次变化量；`RECONCILE` 接收确认后的剩余总量。
- 支持明确数量，以及消耗当前余额的明确比例。
- 使用 Decimal 计算，支持同单位和 `g/kg`、`ml/l` 换算。
- 计算出的变化量按当前单位保留三位小数，ROUND_HALF_UP；先舍入变化量，再计算余额。拒绝舍入为零的正操作、超扣和舍入抹去正余额的情形，细节见实施规则第 6.2 节。仅盘点才清除已有估算。
- 无法确定的单位换算返回错误，不调用 AI。
- 有估算余额时，普通增减继续作用于估算；盘点才更新确认值并清空估算。
- 不允许负库存；确定归零才标记用完。
- 预览不写库存或历史；正式提交重新校验和计算。
- 库存更新与成功操作记录同事务提交。
- 历史仅返回现有表保存的信息，不推算或伪造完整前后状态。
- 本轮 input_method 由服务端固定 MANUAL，不新增来源字段，不扩展操作类型，不关联对话。失败不写数量操作记录。

数量操作复用现有 `idempotency_key`：

- 前端通过 `Idempotency-Key` 请求头传键。
- 后端按用户隔离，并核对物品、操作类型和原始数量参数。
- 重复成功请求不再执行，返回原操作记录及当前库存，并标明重放。
- 不保证重放时库存仍等于第一次提交后的库存，因为之后可能已有其他操作。

### F. 管理员：N05

| 接口 | 功能 |
|---|---|
| `GET /admin/users` | 查询账号 |
| `GET /admin/users/{id}` | 基础账号信息 |
| `PATCH /admin/users/{id}/status` | 修改普通用户状态 |
| `GET/POST /admin/item-categories` | 查询、新增公共品类 |
| `PATCH /admin/item-categories/{id}` | 修改公共品类 |
| `GET/POST /admin/item-definitions` | 查询、新增公共物品 |
| `PATCH /admin/item-definitions/{id}` | 修改公共物品 |

不提供管理员审计、角色提升、私人库存读取或修改他人密码接口。

使用现有管理员账号；若没有，作为部署准备事项处理，本任务不自动提升账号。

### 通用约定

- 身份从登录令牌获取，不能通过请求指定其他用户。
- 分页默认 20 条、最大 100 条，统一返回 `items、total、page、page_size`。
- 数量使用非负十进制字符串，最多三位小数；新增和普通增减必须大于零，盘点允许零。
- 修改库存需要 `expected_version`，实际修改后递增；过期返回 `409`。同值资料 PATCH 不递增，实际盘点即使数量相同也记录并递增。
- 普通创建和批量接口不承诺请求幂等，前端禁用重复点击，结果不明时先查询，不盲目重试。
- 日期和备注可以明确传 null 清空，其他必需字段不可清空。
- 保留现有认证响应兼容性，新业务错误提供稳定错误码和可读说明。
- 不在错误中回显密码，不返回密码哈希。

## 5. 实施顺序、交付与验收边界

### 实施顺序

| 阶段 | 工作 | 对应文件 |
|---|---|---|
| 1 | 业务模型、备注字段和迁移文件 | N06、N09、M06 |
| 2 | 空间和词典 | N01、N02、N07 |
| 3 | 库存、数量、历史、批量和概览 | N03、N04、N08 |
| 4 | 管理员和改密码 | N05、M02–M05 |
| 5 | 注册路由、跨域配置、文档整理 | M01、M07–M09、N10 |

### 文档交付

只新增一份 `docs/reference/API_REFERENCE.md`，包含：

- 每个已实现接口的方法、路径、中英文用途和权限。
- 请求字段、响应字段、默认值、枚举和错误码。
- 登录、创建空间、选择物品、入库、预览、扣减、盘点和历史查询示例。
- 版本冲突和重复请求的处理方式。
- 主动临期查询的日期参数说明。
- 新增和修改文件的职责。
- 启动方法、备注迁移说明、已验证和未验证项。

使用 FastAPI 自带的 `/docs`、`/redoc`、`/openapi.json`，不另建文档导出脚本。

### 当前验证边界

允许进行：

- 代码阅读、语法和导入检查。
- 不连接数据库的 OpenAPI 生成检查。
- 检查迁移内容是否只增加备注字段。

继续暂停：

- 自动化测试和集成测试。
- 新建或修改测试文件。
- 创建、启动测试数据库。
- 实际执行迁移。

恢复测试后再验证权限隔离、数量计算、估算与盘点、事务回滚、重复数量请求、并发版本冲突和批量原子性。

### 范围保护与完成汇报

- 保留 `docs/product/README.md` 现有修改。
- 不改前端、真实 `.env`、原始迁移、现有设计文档、图片和根 README。
- 不新增任何推送依赖或后台进程。
- 不提交或推送 Git。
- 完成时逐项汇报 N01–N10、M01–M09，任何偏离清单的改动单独说明。
- 未运行的测试、未执行的迁移明确写出，不把代码交付说成已经完成数据库和前端联调。

**本次任务的边界：基础业务 API、一个备注字段、一份前端文档。提醒和推送整套移出。**

## 附录：从项目范围文档移出的旧实施计划

> 来源：Agent V0.2 基线中 PROJECT_SCOPE_BILINGUAL.md 第 3.2 节标题内误嵌的旧计划。下文仅作历史记录，当前产品范围见[范围文档](../../product/README.md)。

SayFridge 非 Agent API 实施计划

## 1. 范围调整

采用上一版确认的业务范围，并删除以下接口：

- `PATCH /users/me`
- `PUT /users/me/avatar`
- `DELETE /users/me/avatar`

不增加昵称、头像字段及文件上传存储。保留改密码。

时区放进提醒设置，由 `GET/PATCH /users/me/reminder-settings` 读取和修改，供临期统计和定时提醒共用；默认 `Pacific/Auckland`，允许设置其他有效 IANA 时区。

本轮实现：

| 模块 | 接口及功能 |
|---|---|
| 认证 | 保留注册、登录、当前用户查询；新增 `POST /auth/change-password` |
| 存储空间 | `/storage-spaces` 列表、创建；`/{id}` 详情、编辑；`/{id}/archive`、`/{id}/restore` 归档与恢复 |
| 品类 | `GET /item-categories`，供入库选择和库存筛选 |
| 私有物品词典 | `/item-definitions` 查询、创建；`/{id}` 详情、编辑；归档、恢复 |
| 库存 | `/inventory-items` 查询、入库；`/{id}` 详情、编辑；`/{id}/archive` 归档 |
| 数量操作 | `POST /inventory-items/{id}/operation-preview` 预览；`POST /inventory-items/{id}/operations` 正式增加、消耗、盘点、丢弃 |
| 历史 | 查询单件库存操作、全部操作及单条操作详情 |
| 批量 | `batch-create`、`batch-move`、`batch-archive`，分别用于批量入库、移动和归档 |
| 概览 | `GET /inventory-summary`、`GET /expiry-summary` |
| 提醒设置 | `GET/PATCH /users/me/reminder-settings` |
| 推送设备 | `PUT/DELETE /users/me/push-devices/{installation_id}` |
| 站内通知 | 查询列表、未读数量、标记单条及全部已读 |
| 管理员 | 用户列表及详情、修改普通用户状态；公共品类和物品词典管理；审计列表及详情 |

除 `/health` 外，路径统一以 `/api/v1` 开头。

不实现 Agent、识别、对话、任务调度、用户记忆、历史重估及撤回。手动纠错通过增加或重新盘点完成，保留原历史。

## 2. 文件组织与可读性

按功能组织，**不按每个 API 创建一个文件，也不把所有 API 放进同一个文件**。

```text
backend/
├── app/
│   ├── main.py                 # 创建应用，统一挂载 API
│   ├── api/
│   │   ├── router.py           # 汇总所有功能路由
│   │   ├── dependencies.py     # 当前用户、管理员等共同依赖
│   │   └── routes/             # auth、storage_spaces、catalog、
│   │                          # inventory、inventory_operations、
│   │                          # reminders、notifications、admin
│   ├── schemas/               # 各模块请求与响应模型
│   ├── services/              # 对应模块的计算、权限与事务逻辑
│   ├── workers/               # 提醒调度、通知投递
│   └── db/                    # ORM 模型及数据库连接
├── migrations/                # 本次新增迁移
└── tests/                     # 按业务模块组织测试
```

调用关系：

**请求 → 功能路由 → 业务服务 → 数据库 → 明确的响应模型。**

- `main.py` 只挂载总路由，不堆业务逻辑。
- 路由负责参数、身份依赖、调用服务和返回 HTTP 响应。
- 服务负责计算和事务，供手动操作及未来 Agent 共用。
- 批量接口复用单件操作的业务规则，事务由批量服务统一控制。
- 暂不添加通用 Repository 层；出现实际重复需求再引入。
- 每个 API 编写简洁的中英文 `summary`、说明和必要字段描述，显示在 Swagger 中。
- 注释解释数量状态、权限和事务等容易误解的规则，不逐行复述代码。

由于本轮包含数据库扩展、后台提醒和测试，实际会新增多个文件，并修改少量现有入口、认证、配置与模型文件；不为减少文件数量牺牲职责划分。

## 3. 业务规则与数据变更

- 支持多个平级空间，不支持共享或嵌套；存在在库物品的空间不能归档。
- 公共词典由管理员维护；普通用户仅维护自己的私有词典。
- 新购批次独立入库，不自动合并；首次入库数量保持不变。
- 普通库存编辑只能修改物品关联、日期、空间和备注，不能绕过操作接口直接修改数量。
- 数量使用 `Decimal`，API 使用最多三位小数的十进制字符串；支持同单位和 `g/kg`、`ml/l` 确定性换算。
- 有估算余额时，后续普通增减继续作用于估算；盘点更新确认余额并清空估算。
- 预览不写数据；正式提交重新计算，校验版本和幂等键，库存与历史同事务提交。
- 区分消耗、丢弃和归档；记录首次入库、数量操作、资料修改及归档的前后状态。
- 批量最多 100 条，全部成功或全部失败；失败响应指出条目位置与原因。
- 列表统一分页，默认 20 条、最多 100 条；库存默认按批次展示。
- 提醒默认当地时间 09:00 临期、21:00 回顾，临期阈值 3 天，可修改或关闭。
- 后台先保存站内通知，再推送；同一用户、提醒类型和当地日期不重复生成。
- 手机推送默认采用 FCM；实际设备验证需要可用的 Firebase/APNs 配置。
- 管理员只管理普通用户状态与公共词典，不提供私人库存或对话读取接口；管理写入同步记录审计。

新增迁移包括：库存备注、操作历史扩展、请求幂等记录、提醒设置、推送设备、通知及投递记录、管理审计，以及使改密码后旧令牌失效的用户令牌版本。保留现有数据，不重写初始迁移。

## 4. 前端 API 文档交付

新增 [API_REFERENCE.md](../../reference/API_REFERENCE.md)，提供完整前端接入说明；同步更新后端 README 的启动、迁移及提醒任务运行方法。

文档必须包含：

- 服务地址、`/api/v1` 前缀、Bearer Token 使用方式。
- 每个接口的方法、路径、中英文用途、权限要求。
- 路径参数、查询参数、请求字段、必填项、默认值和枚举。
- 成功响应、错误响应及可复制的请求示例。
- 数量字符串、日期、时区、分页和状态的统一约定。
- `expected_version` 与 `Idempotency-Key` 的具体使用方式。
- 新建空间和物品、入库、预览与确认消耗、盘点、查看历史的完整调用示例。
- 批量失败、版本冲突、令牌失效、未知单位等前端处理方式。
- 提醒设置、设备绑定、通知已读和管理员调用示例。
- 已实现能力与需要外部推送配置才能验证的能力。

同时交付与代码一致的 `/docs`、`/redoc`、`/openapi.json`，避免文档和实现各写一套。

## 5. 验收与完成汇报

使用 Python 3.11 执行后端测试，重点验证权限隔离、数量计算、操作历史、事务回滚、重复提交、并发冲突、批量原子性、改密码失效、提醒去重和管理员审计。

验证迁移能够应用，已有认证仍可使用，完整手动库存流程无需任何 AI 服务。

本轮仅实现后端和文档，不修改前端页面。实际推送在配置可用时做设备验证；否则明确报告尚未验证，不以模拟测试代替真实投递结论。

完成后向你汇报：

1. 已实现哪些 API，以及未完成或受外部配置影响的部分。
2. 实际新增、修改的文件及各自职责。
3. 运行过的测试与结果。
4. 启动服务、迁移数据库和运行提醒任务的方法。
5. 完整 API 文档位置与 Swagger 访问方式。

## 附录：原范围文档中的概念工具建议

> 这些是旧规划名称，不是当前工具清单；当前实现见[架构](../../architecture/AGENT_DESIGN.md)。

## 6. Agent and Tool Boundaries / Agent 与工具边界

The Agent's job is interpretation and orchestration, not database ownership. The following minimum tool set is proposed. / Agent 的职责是理解和编排，而非拥有数据库权限。建议最小工具集如下：

| Tool / 工具 | Purpose / 用途 | Safety and business constraints / 安全与业务约束 |
| --- | --- | --- |
| `search_inventory` | Query a user's inventory by name, category, or state / 按名称、类别、状态查询库存 | Derive `userId` from authenticated identity / 强制从认证身份获取 `userId` |
| `create_inventory_draft` | Create a proposed stock-in item / 创建待确认的入库候选项 | Does not take effect immediately; retains source and confidence / 不直接生效；保存来源与置信度 |
| `confirm_inventory_draft` | Confirm a proposal and formally add stock / 确认候选项并正式入库 | Requires explicit confirmation and server-side field validation / 必须用户确认，且服务端校验字段 |
| `record_consumption` | Record consumption and reduce stock / 记录消耗、减少库存 | Never allow negative quantity; batch selection must be traceable / 不允许负库存，批次选择可追溯 |
| `update_inventory_item` | Correct quantity, date, location, etc. / 更正数量、日期、位置等 | Field allowlist, authorisation, and audit / 字段白名单、权限校验、审计 |
| `delete_inventory_item` | Remove or archive an erroneous item / 删除或归档错误记录 | Second confirmation or soft delete, plus audit / 二次确认或软删除及审计 |
| `get_expiry_summary` | Retrieve expiry summary / 获取临期和过期摘要 | Return only data visible to the current user / 仅返回当前用户可见数据 |

For consequential actions, use a **draft first, user confirmation second** pattern. Model output must conform to a structured schema; the backend must never concatenate model text into SQL or execute arbitrary commands.

对高影响操作采用“**先生成草稿，再由用户确认执行**”的模式。模型输出必须遵循结构化 schema；后端绝不能将模型文本拼接为 SQL 或执行任意命令。
