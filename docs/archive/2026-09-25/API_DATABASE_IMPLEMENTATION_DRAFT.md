> 已归档 / Archived — 2026-09-25。以下内容保留历史决策和当时状态，不是当前实施指令。当前入口：[当前后端设计](../../BACKEND_DESIGN.md)与[接口参考](../../API_REFERENCE.md)。旧文中的阶段限制、能力和部署说明仅代表当时方案。

# SayFridge API 与数据库对应实施方案草稿

> 更新日期：2026-09-11。状态：实施规则整理版，尚未编写业务代码、执行迁移或行为测试。
> 本文第 4–10 节是本轮具体实施规则；API_IMPLEMENTATION_PLAN.md 是范围与文件清单。两份文档已同步本轮收缩决定。
> 用户确认的范围与本次确定的实现细节分列于第 12 节，不把新规定冒充现有代码行为。“删除后重建”已确定采用归档旧库存后重新入库，本轮业务待确认项已关闭。

## 1. 依据、当前状态与交付边界

已核对以下仓库文件：

| 文件 | 当前实际作用 | 本方案如何使用 |
| --- | --- | --- |
| [实施计划](API_IMPLEMENTATION_PLAN.md) | 本轮接口与文件清单，尚未实施 | 作为范围依据，不直接覆盖 |
| [数据库设计](../../DATABASE_DESIGN.md) | 表、字段和权限关系 | 对照 ORM 和初始迁移 |
| [数量设计](../../QUANTITY_STATE_DESIGN.md) | 确认量、估算量、盘点与历史目标 | 确定数量更新规则；历史缩减单独标注 |
| [架构](ARCHITECTURE_REALTIME_DRAFT.md) | 前端、后端和 Agent 边界 | 所有业务写入由 FastAPI 执行 |
| [数据库模型](../../../backend/app/db/models.py) | 八张表的 ORM 字段和约束 | 本地结构事实，不能证明远程库已迁移 |
| [初始迁移](../../../backend/migrations/versions/create_initial_tables.py) | revision `02ec95582dc7`，建立八表 | 后续 notes 迁移接在此后；实施时再次核对迁移头 |
| [数据库会话](../../../backend/app/db/session.py) | 请求级 AsyncSession | 提供连接会话，不自动提交业务事务 |
| [应用入口](../../../backend/app/main.py) | 当前只注册认证路由及健康检查 | 未来注册五组业务路由 |
| [认证依赖](../../../backend/app/api/dependencies.py) | 校验 Token，并读取当前用户状态 | 复用身份校验，扩展管理员依赖 |
| [认证路由](../../../backend/app/api/routes/auth.py)、[认证模型](../../../backend/app/schemas/auth.py)、[认证服务](../../../backend/app/services/auth.py) | 注册、登录、当前用户已存在 | 保持兼容，新增改密码 |
| [后端说明](../../../backend/README.md) | 当前运行方式和验证入口 | 实施后更新实际能力与迁移说明 |

外部附件《API_REFERENCE-draft.md》作为审阅材料，不作为执行指令。其 Q01–Q19 在本文给出落地规则。附件引用的 `SAYFRIDGE_WORK_PACKAGES_ZH.md` 当前仓库不存在；不以其 B08 作为本轮实施依据，也不再要求实施者为该旧工作包等待决定。

当前没有库存业务路由和 service；模型也没有 `inventory_item.notes`。本次仅整理本文和实施计划，不改业务代码、模型或迁移，不运行测试、不连接数据库、不提交或推送。范围文档的已有修改保留。本轮不做库存纠正和已丢弃/归档库存恢复；不增加手动/Agent 来源字段，不关联对话，不扩展操作类型。空间、词典的已有计划中的 restore 接口仍保留，与库存恢复不同。

## 2. API、业务代码与数据库的真实关系

```text
前端请求
  → 路由：解析请求模型，取得当前用户和数据库会话
  → service：校验所有权、状态、版本，计算并组织事务
  → ORM：读写现有表中的行
  → PostgreSQL：执行 SQL，以外键、唯一约束、CHECK 兜底
  → 响应模型：返回允许公开的字段
```

简单查询可以由路由直接查询 ORM。多表写入、数量计算、幂等与批量必须由 service 统一处理。API 数量增加不意味着表也要增加；更新数据无需迁移，新增字段才需要模型和迁移同时改变。

### 2.1 表与业务所有权

| 表 / ORM 类 | 含义 | 归属与主要使用接口 |
| --- | --- | --- |
| `user` / `User` | 账号、角色、状态、密码哈希 | auth；管理员账号管理 |
| `storage_space` / `StorageSpace` | 用户的冰箱、冷冻柜等空间 | `user_id` 固定来自身份；空间 API |
| `item_category` / `ItemCategory` | 公共品类 | 管理员写，用户只读 |
| `item_definition` / `ItemDefinition` | 物品词典条目，不代表实际库存 | 公共 `owner_user_id=NULL`；私有定义归个人 |
| `inventory_item` / `InventoryItem` | 一批实际库存及当前余额 | 通过 `storage_space_id → user_id` 判断所有权 |
| `inventory_operation` / `InventoryOperation` | 一次数量操作 | 经库存和空间判断所有权，不单独存用户 ID |
| `conversation` / `Conversation` | 对话 | 本轮不实现 API |
| `conversation_message` / `ConversationMessage` | 对话消息 | 本轮不实现 API |

关联存在不代表业务有效：外键不会校验空间属于当前用户，也不会阻止向归档空间入库。这些必须由后端实现。

### 2.2 现有数据库约束与应用责任

| 已有约束 | 后端仍须完成 |
| --- | --- |
| 活动空间按用户和 `lower(name)` 唯一 | 去首尾空白、冲突转换为 409；归档空间恢复时重新校验 |
| 品类 normalized_name 全局唯一；公共定义全局唯一；私有定义按用户唯一 | 统一生成 normalized_name；归档词典仍占用名称，不创建重复项 |
| 数量 `NUMERIC(12,3)` 且非负 | 输入、转换结果、实际变化量、最终余额均验证范围与精度 |
| 估算数量、单位、时间必须同时空或同时非空 | 一起更新或清空三字段 |
| `version >= 1`，默认 1 | 显式校验并递增；模型不会自动执行乐观锁 |
| 幂等键全局唯一且最长 128 | 用户隔离、请求比较、并发冲突恢复 |
| 操作类型限 ADD / CONSUME / RECONCILE | 不借这些类型伪造丢弃、归档、移动事件 |
| 实际变化量非负，量与单位成对存在 | CONSUME 保存正的扣减量；方向由 operation_type 表示 |
| `updated_at` 配有 ORM onupdate | 使用统一 ORM 更新路径；不能把此字段当完整历史或专用丢弃时间 |

## 3. 文件实施对应表

以下未来文件名属于计划，不代表已存在。backend 下路径均以 `backend/` 为根。

| 编号 | 文件 | 计划承担的接口或职责 | 读写表 |
| --- | --- | --- | --- |
| N01 新增 | `app/api/routes/storage_spaces.py` | 空间 GET/POST/PATCH、archive/restore | storage_space；校验 inventory_item |
| N02 新增 | `app/api/routes/catalog.py` | 品类 GET；私有物品维护及可见定义查询 | item_category、item_definition |
| N03 新增 | `app/api/routes/inventory.py` | 库存查询、创建、PATCH、discard/archive、三种批量、概览、临期 | inventory_item 及关联表 |
| N04 新增 | `app/api/routes/inventory_operations.py` | preview、operations POST、三种历史 GET | inventory_item、inventory_operation |
| N05 新增 | `app/api/routes/admin.py` | 用户状态、公共品类及公共定义管理 | user、item_category、item_definition |
| N06 新增 | `app/schemas/business.py` | 下文请求与响应模型，按业务分段 | 不访问数据库 |
| N07 新增 | `app/services/catalog.py` | 空间和词典写入、状态和名称规则 | storage_space、item_category、item_definition；归档查库存 |
| N08 新增 | `app/services/inventory.py` | 纯数量计算、库存写入、版本、幂等、批量事务 | inventory_item、inventory_operation；锁定校验相关空间/词典 |
| N09 新增 | `migrations/versions/<revision>_add_inventory_notes.py` | 仅给 inventory_item 添加可空 TEXT notes | 仅结构变更 |
| N10 新增 | 根目录 `docs/API_REFERENCE.md` | 实施后的前端契约、示例和验证状态 | 不访问数据库 |
| M01 修改 | `app/main.py` | 注册五组路由、跨域、新业务错误处理 | 无直接业务写入 |
| M02 修改 | `app/api/dependencies.py` | `require_admin`，复用当前用户查询 | user |
| M03–M05 修改 | `app/api/routes/auth.py`、`app/schemas/auth.py`、`app/services/auth.py` | change-password 请求、校验、更新 | user.password_hash |
| M06 修改 | `app/db/models.py` | 仅新增 InventoryItem.notes | inventory_item |
| M07–M08 修改 | `app/core/config.py`、`.env.example` | 可配置跨域来源；示例不含真实密钥 | 无 |
| M09 修改 | `README.md` | backend README，非根 README | 无 |

service 内使用有业务含义的函数，例如 `create_inventory_item`、`move_inventory_items`、`apply_inventory_operation`、`calculate_inventory_operation`。计算函数不提交事务；批量复用内部写入函数，不能调用会逐条 commit 的单项入口。

本文是本次规划新增文档，不计入未来业务实施的 N01–N10；未来如调整文件清单，先更新方案说明。

## 4. 通用请求、响应与字段规则

- 除 health 外统一 `/api/v1`；所有业务接口要求有效身份。公共词典表示所有权公共，不表示匿名可访问。
- 未知请求字段拒绝。ID 用 UUID。服务端生成 ID、用户归属、状态初值、版本、时间戳、操作计算字段。
- POST 创建返回 201；查询、PATCH、状态操作和改密码返回 200；数量操作首次成功返回 201，重放返回 200。
- 新业务错误格式：`{"detail":{"code":"VERSION_CONFLICT","message":"库存已变化，请刷新后重试","item_index":0}}`。item_index 仅批量错误存在；认证保留当前格式。
- 未找到和无权访问资源统一 404；身份失效 401；非管理员调用管理员接口 403；参数 422；版本、状态、唯一性、幂等冲突 409。
- PATCH 省略字段表示不改；日期和 notes 显式 null 表示清空；其他字段不允许 null；空业务 PATCH 拒绝。expected_version 不算业务修改字段。
- 名称 trim 后长度 1–100；词典 normalized_name 使用统一的 Unicode NFKC、trim、casefold。这是新增写入规则；不批量重写旧词典。新建/改名时还须按相同算法检查同一唯一范围内已有名称，命中旧格式同名项则返回 NAME_CONFLICT；数据库现有唯一索引继续兜底。规范化后的长度也须为 1–100。
- 数量采用普通非负十进制字符串，最多三位小数，拒绝科学计数法、NaN、Infinity；最大值 `999999999.999`。
- 单位 trim 后 1–16 字符；已知质量/体积单位统一为 g/kg/ml/l。其他单位保留规范化后的字面形式，仅完全同单位可计算，不猜测“个=each”。
- 时间戳以带时区 ISO 8601 返回；日期保持 YYYY-MM-DD，不由服务器时区替换用户日期。
- 所有列表分页统一 items/total/page/page_size，默认 20，最大 100，page 最小 1，越界返回空 items；total 为全部过滤结果数。
- 普通创建不承诺幂等。数量提交必须有 Idempotency-Key。批量操作事务原子但不承诺响应重放。

### 4.1 响应模型

| 模型 | 字段 |
| --- | --- |
| StorageSpaceRead | id、name、type、status、created_at、updated_at |
| ItemCategoryRead | id、name、status、sort_order |
| ItemDefinitionRead | id、name、category_id、status、scope=PUBLIC/PRIVATE；不暴露他人 owner_user_id |
| InventoryItemRead | id、storage_space_id、item_definition_id、当前关联名称/品类、purchase_date、expiry_date、notes、status、initial_*、confirmed_current_*、confirmed_at、estimated_current_*、estimated_at、version、created_at、updated_at |
| 库存派生展示字段 | display_amount、display_unit、is_estimated；来自估算非空优先规则，不存新列；估算为 0 也必须优先显示，不能按真假值选择 |
| InventoryOperationRead | id、inventory_item_id、operation_type、quantity_kind/value/unit、input_method、calculation_method、affects_state、applied_change_*、status、created_at、updated_at、undone_at |
| OperationResult | operation、inventory、replayed；inventory 是响应读取时的当前库存，不是操作后历史快照 |
| OperationPreview | inventory_item_id、based_on_version、before 展示状态、after 候选状态、实际变化量、计算方式、affects_state、rounded；不提供可绕过重算的授权凭证 |

操作响应不公开派生后的数据库幂等键。数量字段统一字符串；关联名称明确为当前名称，不是历史快照。

## 5. 核心写接口：六项契约

### 5.1 POST /inventory-items：新建库存

1. **请求字段**：storage_space_id、item_definition_id、amount、unit 必填；purchase_date、expiry_date、notes 可选。amount > 0；notes 最多 1,000 字。未来模型 `InventoryCreate`。
2. **允许状态**：所属空间 ACTIVE；定义及其品类 ACTIVE；公共定义或自己的私有定义。输入不能指定 status。
3. **读取与校验**：当前用户、空间归属、定义可见性和品类状态；数量范围。允许过期物品入库，不强制 purchase_date ≤ expiry_date，以支持补录真实过期购买；仅校验日期合法性。
4. **写入字段**：新增一行 inventory_item；initial_amount=confirmed_current_amount=amount；initial_unit=confirmed_current_unit=unit；confirmed_at=服务端时间；估算三字段 NULL；status=IN_STOCK；version=1；关联、日期、notes 按请求写入。
5. **历史**：按当前计划不新增 ADD；以后历史列表可为空。initial_* 保留首次事实，不能当成完整入库事件。
6. **失败与重试**：任何校验失败不新增行；成功响应丢失无法可靠自动判重，客户端提示核对，不能自动重试并宣称安全。

### 5.2 PATCH /inventory-items/{id}：资料与位置

1. **请求字段**：expected_version 必填；storage_space_id、purchase_date、expiry_date、notes 至少一项。禁止 item_definition_id、数量、status、初始量和时间戳。
2. **允许状态**：IN_STOCK、EMPTY 可改；DISCARDED、ARCHIVED 只读。EMPTY 在归档空间时允许移动到自己的活动空间或更正日期备注。
3. **读取与校验**：库存归属和版本；移动时检查目标空间归属及 ACTIVE；目标不能是别人的空间。
4. **写入字段**：只写允许的实际变化字段，version + 1，updated_at 更新。不改变数量、confirmed_at、estimated_at、initial_*。值与当前完全相同则返回现状、不递增版本，但仍检查 expected_version。
5. **历史**：本轮不保存资料或位置修改事件。
6. **失败与重试**：版本不符 409；同旧请求重试可能得到版本冲突，应重新查询；无数量操作幂等保证。

本轮不提供库存物品纠正，item_definition_id 创建后不可修改。定义自身重命名仍会改变所有引用的当前显示名。

### 5.3 POST /inventory-items/{id}/operation-preview：预览

1. **请求字段**：与正式数量请求相同，expected_version 必填，不要求幂等键。
2. **允许状态**：与正式操作一致。
3. **读取与校验**：当前库存及归属、空间状态、版本、数量和单位。
4. **写入字段**：无；运行与提交相同的计算函数，返回 based_on_version 及候选值。
5. **历史**：无。
6. **失败与重试**：版本冲突 409；可重新读取后预览。预览成功不预留库存，提交仍须检查并重算；无需强制每次提交前调用预览。

### 5.4 POST /inventory-items/{id}/operations：正式数量操作

1. **请求字段**：expected_version、operation_type、quantity_kind、quantity_value、quantity_unit；头部 Idempotency-Key 必填。未来模型 `InventoryOperationCreate`。
2. **允许状态**：见第 7 节状态表。RECONCILE 是用户确认当前总量，不能按增减量处理。
3. **读取与校验**：身份及归属 → 成功幂等记录 → 新请求的版本与状态 → 单位、精度、非负余额。前端不能提交 after、affects_state 或 calculation_method 作为写入依据。
4. **写入字段**：按第 6 节同时更新库存和新增 SUCCESS 操作记录；version + 1；只提交一次事务。
5. **历史**：成功操作一条；失败不写 FAILED 行。数据库允许 FAILED 不代表本轮必须使用；现有其他状态历史仍可以查询。
6. **失败与重试**：同键同业务参数成功重放；不同参数 409；新请求版本不符 409；计算失败 422；库存和成功记录全部回滚。详细顺序见第 8 节。

### 5.5 POST /inventory-items/{id}/discard 和 /archive

1. **请求字段**：expected_version；不接收数量或任意状态字段。
2. **允许状态**：discard 仅 IN_STOCK；archive 允许 IN_STOCK、EMPTY。DISCARDED 和 ARCHIVED 终态只读；重复动作返回 409，不改版本。
3. **读取与校验**：归属、版本和来源状态。
4. **写入字段**：仅 status=DISCARDED 或 ARCHIVED、version + 1、updated_at。所有数量和数量时间戳不变。
5. **历史**：不写 inventory_operation；不能用 CONSUME 伪装。不能从 updated_at 承诺完整丢弃历史。
6. **失败与重试**：失败不修改；响应丢失后查询状态。旧版本重试返回冲突，不重复改变数据。

### 5.6 三种批量接口

| 项目 | batch-create | batch-move | batch-archive |
| --- | --- | --- | --- |
| 请求 | items: InventoryCreate[] | target_storage_space_id，items: [{id, expected_version}] | items: [{id, expected_version}] |
| 状态 | 同单项入库 | IN_STOCK、EMPTY；目标自己的 ACTIVE 空间 | 同单项 archive |
| 校验 | 每个空间、定义和数量 | 每项所有权、版本、目标空间 | 每项所有权、版本、状态 |
| 写入 | 多行库存初始化 | storage_space_id、version、updated_at | status、version、updated_at |
| 历史 | 无 ADD | 无移动事件 | 无归档事件 |
| 失败/重试 | 任一失败整批回滚；不保证创建幂等 | 任一失败整批回滚；不保证响应重放 | 任一失败整批回滚；不保证响应重放 |

统一规则：items 必须 1–100 条；move/archive 拒绝重复库存 ID；create 不按内容去重，因为相同输入可代表两批真实库存。返回结果按输入顺序排列，不按加锁顺序排列。失败报告首个确定错误及从 0 开始的 item_index；缺失或无权访问统一 NOT_FOUND。检查顺序固定，以减少同输入产生不稳定错误。移动到原空间是无变化项，仍验证版本和目标 ACTIVE，不递增版本。

## 6. 数量字段如何真实写入

### 6.1 请求形式

| 类型 | quantity_kind | quantity_value | quantity_unit |
| --- | --- | --- | --- |
| ADD / CONSUME 明确量 | AMOUNT | 大于零的十进制字符串 | 必填单位 |
| CONSUME 当前余额比例 | FRACTION | `p/q`，p、q 为正整数且 p ≤ q，总长度 ≤ 32 | 固定 remaining |
| RECONCILE | AMOUNT | 非负十进制字符串，允许 0 | 新确认单位，可不同于原单位 |

不支持 ADD 比例、盘点比例、QUALITATIVE、AI_ESTIMATED 输入。比例属于表达，不受“三位小数输入”语法约束，但其计算结果仍受三位小数存储限制。quantity_value 保留用户提交的合法字面表达，不把 `1/2` 改成 `0.5`；quantity_unit 保存原始合法单位，另行生成用于计算的规范单位。

### 6.2 库存写入矩阵

| 场景 | confirmed_current_* / confirmed_at | estimated_current_* / estimated_at | initial_* | status |
| --- | --- | --- | --- | --- |
| 入库 | 初始量、单位、当前时间 | 全 NULL | 写首次量和单位 | IN_STOCK |
| 无估算 ADD / CONSUME | 当前确认量加减换算后的变化量；更新时间 | 保持 NULL | 不改 | 精确余额 0 → EMPTY，否则 IN_STOCK |
| 有估算 ADD / CONSUME | 全部不改 | 在估算量上加减；更新估算时间 | 不改 | 估算归零仍 IN_STOCK |
| RECONCILE | 直接写输入总量、新单位、当前时间 | 三字段一起清空 | 不改 | 0 → EMPTY，正数 → IN_STOCK |
| 日期、位置、备注 | 不改 | 不改 | 不改 | 不改 |
| discard/archive | 不改 | 不改 | 不改 | 写对应终态 |

普通加减保存为当前有效余额的单位，支持 g↔kg、ml↔l。其他不同单位拒绝；RECONCILE 不需要把新单位换算回旧单位。

精度规则：输入仍最多三位小数；换算及比例计算的实际变化量按当前有效单位保留三位小数，使用 ROUND_HALF_UP（非负数四舍五入）。不是把所有数量取为整数。比例采用整数比计算到 0.001 单位，避免先把 1/3 截断；单位换算用 Decimal。

执行顺序：

1. 先算未舍入的变化量。CONSUME 若已超过当前余额，直接返回 INSUFFICIENT_QUANTITY，不能通过舍入掩盖超扣。
2. 将变化量舍入到三位小数，再用当前余额加减该变化量得出保存余额；不对扣减量和余额各自独立舍入。
3. 正变化量舍入为零，返回 QUANTITY_TOO_SMALL，不创建成功记录。未舍入剩余大于零但舍入后变成零，返回 QUANTITY_PRECISION_UNSUPPORTED；用户可以明确消耗全部或实际盘点，不自动把微小剩余当成用完。
4. 原始输入、实际保存变化量和最终余额都必须在 NUMERIC(12,3) 范围内；超范围返回 QUANTITY_OUT_OF_RANGE，不能依赖数据库截断。
5. 预览返回 rounded（是否发生舍入）、实际变化量和最终余额。正式提交与重放使用统一 OperationResult，原始请求保存在 quantity_*，舍入结果保存在 applied_change_*，inventory 返回当前余额。不在历史/重放中推算缺失的原基数或舍入标志，不新增数据库列。
6. 舍入是保存精度规则，不代表 AI 估算；无估算时仍更新确认量，有估算时仍更新估算量。calculation_method 继续表达同单位/规则换算，不新增枚举。

例如 1 kg 消耗 1/3：记录扣减 0.333 kg，余额 0.667 kg，rounded=true。0.001 kg 消耗一半：因舍入会抹去正余额而拒绝。仅换单位不等于实际盘点，不要求用户虚假确认剩余来通过精度校验。

### 6.3 操作记录字段矩阵

| 字段 | 服务端写入规则 |
| --- | --- |
| inventory_item_id | 当前目标库存 |
| operation_type | 经校验的 ADD / CONSUME / RECONCILE |
| quantity_kind/value/unit | 保留合法原始数量表达；不存转换后的表达冒充原值 |
| input_method | 本轮固定 MANUAL，前端不能指定 VOICE/PHOTO 等虚构来源 |
| calculation_method | 同单位、明确比例及直接盘点 EXACT；确定单位换算 CONVERTED |
| affects_state | 无估算加减和盘点 CONFIRMED；估算余额上加减 ESTIMATED |
| applied_change_amount/unit | ADD/CONSUME 的实际正变化量及保存单位；盘点统一 NULL，不跨单位计算虚假差值 |
| status | 新增时固定 SUCCESS |
| idempotency_key | 按第 8 节用户隔离派生 |
| created_at/updated_at | 服务端/数据库时间；undone_at=NULL |

即使 RECONCILE 总量与现有确认量相同，也记录一次实际盘点并更新确认时间和版本。这是新确认事实，与无变化资料 PATCH 不同。

### 6.4 一个完整例子

库存 A 当前 confirmed=10 each、estimated=NULL、version=4。

```json
{
  "expected_version": 4,
  "operation_type": "CONSUME",
  "quantity_kind": "AMOUNT",
  "quantity_value": "2",
  "quantity_unit": "each"
}
```

客户端另传 Idempotency-Key。事务更新 A：confirmed=8 each、confirmed_at=当前时间、version=5；新增操作：CONSUME、AMOUNT、原值 2 each、EXACT、CONFIRMED、实际变化 2 each、SUCCESS。失败则两者都不提交。

如果操作前 confirmed=10 each、estimated=7 each，则结果为 confirmed=10 each、estimated=5 each，操作 affects_state=ESTIMATED。精确减少 2 不会让原本不确定的余额变确定。

## 7. 状态与关联规则

| 库存来源状态 | 资料 PATCH / 移动 | ADD | CONSUME | RECONCILE | discard | archive |
| --- | --- | --- | --- | --- | --- | --- |
| IN_STOCK | 允许 | 允许 | 有足够有效余额时允许 | 允许 | 允许 | 允许 |
| EMPTY | 允许 | 所在空间 ACTIVE 时允许，恢复在库 | 拒绝 | 0 保持 EMPTY；正数需 ACTIVE 空间并恢复在库 | 拒绝 | 允许 |
| DISCARDED | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 拒绝 |
| ARCHIVED | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 拒绝 |

空间仅 ACTIVE / ARCHIVED。存在 IN_STOCK 库存不能归档；EMPTY 不阻止归档。归档空间不能创建或接收移动库存；其 EMPTY 库存应先移动或恢复空间，再做正数盘点/增加。空间重复归档/恢复成功返回现状；空间名称/类型只在 ACTIVE 可编辑。恢复遇活动空间重名返回 409。

词典归档不删除或冻结已有库存。新建库存或新建/改关联定义时要求定义和品类 ACTIVE；已有库存仍允许消耗、盘点、补充及移动，否则停用词典会阻断真实库存管理。恢复定义要求品类 ACTIVE。归档品类不级联修改定义状态；查询可选择时同时过滤定义和品类状态。私有定义归档后只允许恢复，不允许普通编辑。

停用与新关联创建应协调并发；停用不追溯使既有引用非法。普通用户不能修改 owner_user_id；空间不能修改 user_id；库存不支持跨用户移动。

## 8. 事务、版本与幂等的实施方案

### 8.1 事务归属

一个写请求由外层 service 负责一次 commit；失败 rollback。路由不再额外提交；内部校验和批量子函数不提交。当前认证查询会让同一 AsyncSession 开始事务，不能在已有事务上机械套一层 `session.begin()`；实施时沿用请求会话，明确现有事务由哪个写入口结束。

数据库会话依赖仅 yield 会话，不能误认为退出依赖就会替业务 commit。已有注册 service 自己提交，保持现有行为；新增业务用一致的写入口约定。

### 8.2 并发保护

- 先非锁定读取目标关联用于规划，再按统一顺序锁相关空间、品类、定义和库存；同类按 UUID 排序，最终锁定后重新确认归属、关联、状态和版本。
- 涉及空间归档、入库、移动、EMPTY 恢复的路径必须协调锁同一空间行，使“归档后新增在库”不能穿透检查。读取库存规划后若发现空间已被移动，不在原锁集合上继续，应回滚并让请求刷新/重试。
- 锁定库存后比较 expected_version，再更新并递增；也可用带版本条件的 UPDATE，但不能省略跨表空间状态保护。
- 词典停用和新关联建立使用一致锁顺序协调。避免只做“查询 ACTIVE 后无保护地插入”。
- 批量按锁顺序处理，响应恢复输入顺序；事务失败后不得保留任何已写子项。
- 预览不持有跨请求锁。列表、预览是读取时的状态，正式写入必须重新检查。

实现注意：锁后必须从数据库重新取得最新字段，不能继续使用认证或预读阶段缓存的 ORM 对象值。空间归属不可转移，词典 owner 不可修改。锁顺序固定为空间 → 品类 → 定义 → 库存，同类按 ID 排序；只锁本操作需要的记录。管理员仅改单个品类/定义时也遵守相关顺序。批量预读发现关联在等待期间改变时回滚，返回 RESOURCE_CHANGED，不在持有部分锁时临时反向补锁。

该方案偏向本轮可理解的串行保护，同空间写入可能互相等待；如后续性能需要优化，再以一致性验证为前提细化锁粒度。

### 8.3 用户级幂等实现规则

1. 请求头键为 1–64 个 ASCII 可见字符，不允许空白，区分大小写。
2. 数据库键生成 `当前用户UUID:客户端键`，长度不超过 101，符合现有 128 上限。不能加入物品 ID，否则同键用于不同物品不能被识别为冲突。
3. 校验身份和目标归属后查键；发现成功记录时比较 inventory_item_id、operation_type、quantity_kind/value/unit。原值 `2` 和 `2.0` 视为不同请求；客户端重试保留原表达。
4. expected_version 不纳入业务请求比较。成功重放先于版本/终态校验，所以原请求成功后即使库存又变化或归档仍可返回原操作及当前库存；已失去访问权则不能重放。
5. 找不到记录才执行新请求的状态、版本、数量校验。锁等待后再次查键，避免另一相同请求已完成却被旧版本挡住。
6. 库存修改与新增操作同事务。数据库唯一约束最终兜底；若确认为该键唯一冲突，先完整回滚，再开启读取以核对已提交记录。不能吞掉所有 IntegrityError 当作重放。
7. 若已有同键非 SUCCESS 记录，返回明确冲突，不自动重新应用历史状态。失败请求本轮不留记录，可在未成功时用原键重试。
8. 不设自动删除期限；键随操作记录保留。后续若清理记录，必须重新设计幂等保留承诺。

## 9. 其他写接口的六项对应

| 接口 | 请求字段 | 允许状态 | 读取与校验 | 写入字段 | 历史 | 失败与重试 |
| --- | --- | --- | --- | --- | --- | --- |
| POST /storage-spaces | name、type | 当前用户 ACTIVE | 用户、活动名称冲突 | user_id=当前用户、name/type、status=ACTIVE | 无 | 重名 409；创建不幂等 |
| PATCH /storage-spaces/{id} | name/type 至少一项 | 空间 ACTIVE | 自己的空间、名称唯一 | name/type、updated_at | 无 | 重名 409；无变化返回现状 |
| POST /storage-spaces/{id}/archive | 无 | ACTIVE；已归档返回现状 | 自己的空间、锁后查 IN_STOCK | status=ARCHIVED、updated_at | 无 | 有在库 409 |
| POST /storage-spaces/{id}/restore | 无 | ARCHIVED；已活动返回现状 | 所有权、活动名称冲突 | status=ACTIVE、updated_at | 无 | 重名 409 |
| POST /item-definitions | name、category_id | 品类 ACTIVE | 品类、自己词典名称唯一 | owner_user_id=当前用户、name、normalized_name、category_id、ACTIVE | 无 | 唯一冲突 409；不幂等 |
| PATCH /item-definitions/{id} | name/category_id | 自己的 ACTIVE 定义 | 所有权、目标品类、唯一性 | 对应字段、normalized_name、updated_at | 无 | 冲突 409；当前显示关联随之变化 |
| POST /item-definitions/{id}/archive | 无 | 自己的定义 | 所有权 | status=ARCHIVED、updated_at | 无 | 重复返回现状 |
| POST /item-definitions/{id}/restore | 无 | 自己的定义；品类 ACTIVE | 所有权、品类 | status=ACTIVE、updated_at | 无 | 品类归档 409；重复返回现状 |
| POST /auth/change-password | old_password、new_password | 当前 ACTIVE 本地账号 | 当前身份、密码哈希、旧密码校验 | password_hash、updated_at | 无 | 错旧密码 400；同密码 422；无哈希/非本地 409；响应丢失需重新登录确认 |
| PATCH /admin/users/{id}/status | status | 目标 role=USER | 当前管理员、目标账号 | status、updated_at | 无审计 | 三种既有状态间允许转换；管理员目标 403；重复返回现状 |
| POST /admin/item-categories | name、sort_order 可选默认 0 | 管理员 | 名称唯一 | name、normalized_name、sort_order、ACTIVE | 无审计 | 冲突 409；不幂等 |
| PATCH /admin/item-categories/{id} | name/sort_order/status | 管理员；允许维护归档词典 | 名称唯一、枚举 | 请求白名单字段、updated_at | 无审计 | 冲突 409；不级联改定义 |
| POST /admin/item-definitions | name、category_id | 管理员；品类 ACTIVE | 品类、公共名称唯一 | owner_user_id=NULL、name、normalized_name、category_id、ACTIVE | 无审计 | 冲突 409；不幂等 |
| PATCH /admin/item-definitions/{id} | name/category_id/status | 管理员；仅公共定义 | 公共归属、名称、改品类/恢复时品类 ACTIVE | 白名单字段、updated_at | 无审计 | 私有目标统一 404；冲突 409 |

改密码新旧字段复用当前 8–128 字符约束；成功响应为 `{"changed":true}`。不会让既有 Token 自动失效。管理员状态变更通过现有每请求用户查询，对后续认证请求生效；已在执行的请求不承诺被中途撤销。

空间、词典、用户没有 version，本轮串行校验后对请求包含的字段执行最后写入生效，不承诺防止这些资料的过期编辑覆盖；库存 version 不应被描述成全系统版本保护。

## 10. 只读接口对应与展示边界

所有以下接口不写业务表；除 health 外均有当前用户认证读取。

| API | 数据来源与过滤 | 返回与排序 |
| --- | --- | --- |
| GET /health | 当前不查数据库 | 当前原响应，不证明数据库可用 |
| GET /auth/me | user | 当前 UserPublic，保持兼容 |
| GET /storage-spaces 和 /{id} | 自己的 storage_space | 列表默认 ACTIVE，可筛状态；详情可读归档；name、id 升序 |
| GET /item-categories | item_category | 默认 ACTIVE；sort_order、name、id 升序 |
| GET /item-definitions 和 /{id} | 公共或自己的 item_definition，关联品类 | 列表默认定义/品类都 ACTIVE，q、category_id、scope、status 筛选；name、scope、id 稳定排序；详情允许读自己可见的归档定义 |
| GET /inventory-items 和 /{id} | inventory_item → storage_space.user_id；关联当前词典 | 默认 IN_STOCK；q、storage_space_id、category_id、status、purchase_from/to、expiry_from/to；日期边界包含端点；expiry_date 升序 NULLS LAST、id 升序 |
| GET /inventory-summary | 当前用户 IN_STOCK 库存 | total_batches、by_space、by_category；只返回有库存的分组，不加总异单位数量 |
| GET /expiry-summary | 当前用户 IN_STOCK 且 expiry_date 非空 | as_of 必填；days_before 默认 3，0–365；counts 三类总数及一个分页 items，item 带 bucket |
| GET /inventory-items/{id}/operations | 校验库存所有权后读 operation | created_at、id 降序；没有记录返回空列表 |
| GET /inventory-operations 和 /{id} | operation → inventory → space → 当前用户 | 列表支持 inventory_item_id、operation_type、status、created_from/to；时间区间含起点、不含终点；created_at、id 降序 |
| GET /admin/users 和 /{id} | 管理员权限下 user | 公开 id、email、role、status、created_at、updated_at；列表 q/role/status，created_at、id 降序；无哈希或库存 |
| GET /admin/item-categories | 全部公共品类 | 状态筛选，默认全部；sort_order、name、id 升序 |
| GET /admin/item-definitions | owner_user_id IS NULL | 默认全部状态；q/category_id/status；name、id 升序 |

补充规则：

- status 参数取对应数据库枚举或 ALL。词典查询 status=ACTIVE 时同时要求品类 ACTIVE；status=ARCHIVED 仅过滤定义自己的 ARCHIVED 状态；status=ALL 不过滤定义或品类状态。详情不受列表默认过滤影响。
- q 为 trim 后不超过 100 字符的字面子串搜索，空串按无筛选处理；SQL 参数绑定，百分号和下划线作为文字转义。日期/时间区间起点晚于终点返回 422；时间参数必须包含时区。
- 所有 PATCH 必须至少包含一个业务字段；sort_order 为 0–2147483647 整数；空间 type 取 FRIDGE/FREEZER/PANTRY/WAREHOUSE/OTHER。expected_version 为 1–2147483647 整数，实际写入不能溢出；抵达上限时返回 VERSION_LIMIT_REACHED。
- ItemDefinitionRead.category_id 对应当前品类；需要关联名称时统一使用 category_name、storage_space_name、item_definition_name。库存不返回 owner_user_id，数量展示值只派生不落库。
- 临期响应为 counts（overdue/today/upcoming）、items、total、page、page_size；total 为 bucket 筛选后的全部明细数。日期加 days_before 超出合法日期范围时返回 422。
- inventory-summary 返回 total_batches、by_space:[{storage_space_id,name,batch_count}]、by_category:[{category_id,name,batch_count}]，分组按 name、id 排序。
- 单项创建/修改/状态操作返回对应 Read 模型；批量返回 items 数组和 count，保持输入顺序；预览 200，批量入库 201，批量移动/归档 200。首次数量提交 201，成功重放 200。

- 状态过滤允许明确请求全部；不能仅因关联空间/定义归档而隐藏库存详情或操作历史。
- 库存概览支持 storage_space_id、category_id；临期同样支持这些筛选。counts 以全部筛选结果计算，不是本页长度。
- 临期 items 用可选 bucket 筛选 overdue/today/upcoming；counts 始终返回空间/品类过滤下全部三类数量。无 bucket 时合并三类分页；按 expiry_date、id 升序。
- `expiry_date < as_of` 为 overdue；相等 today；`as_of < expiry_date ≤ as_of+days_before` 为 upcoming；days_before=0 时 upcoming=0。未知日期不计入。
- 历史默认返回现有全部状态，新写入只有 SUCCESS；前端不能把 FAILED/UNDONE 显示成有效消耗。盘点展示“确认剩余 X 单位”，不展示伪造差值。
- 数量历史不承诺完整 before/after、历史名称、估算依据快照、资料变化或丢弃时间。
- counts 与 items 使用同一语句计算或同一读取快照；普通 READ COMMITTED 事务内分两条查询不保证这一点；普通 offset 分页只保证排序稳定，不承诺多次请求期间数据完全不变。

### 10.1 错误与路由实现约定

业务错误使用第 4 节格式。确定以下稳定错误码：422 为 VALIDATION_ERROR、UNIT_NOT_CONVERTIBLE、INSUFFICIENT_QUANTITY、QUANTITY_TOO_SMALL、QUANTITY_PRECISION_UNSUPPORTED、QUANTITY_OUT_OF_RANGE；409 为 VERSION_CONFLICT、VERSION_LIMIT_REACHED、STATE_CONFLICT、NAME_CONFLICT、IDEMPOTENCY_CONFLICT、RESOURCE_CHANGED；404 为 NOT_FOUND；403 为 ADMIN_REQUIRED。改密码错误保留认证现有 detail 字符串风格，状态码按第 9 节。

新业务请求参数验证错误也转换为 VALIDATION_ERROR，只返回字段位置与说明，不回显原始 input、请求头或密码。原 auth 接口验证保持现有兼容格式；不能全局改变已有认证成功/失败结构。

注册 /batch-create、/batch-move、/batch-archive 等静态路径时放在 /{id} 路由之前，避免路径被当作 UUID。数据库异常只把已识别的唯一约束冲突映射为业务冲突；其他错误回滚并返回通用服务错误，不输出 SQL 或连接参数。

本轮不新增公共 bootstrap API。管理员状态更新的事务放在 admin.py 的小型处理函数中，包含目标校验与一次提交，不扩展无业务需要的通用 service。跨域设置使用 CORS_ORIGINS 字符串列表，默认 []；允许 GET/POST/PATCH/OPTIONS 与 Authorization/Content-Type/Idempotency-Key 请求头，使用 Bearer Token，不启用 cookie credentials，不默认放开全部来源。

## 11. notes 数据库变更与实施阶段

### 11.1 唯一结构变更

| 项目 | 方案 |
| --- | --- |
| 表/字段 | inventory_item.notes |
| 类型 | TEXT，nullable=True，无默认文本 |
| 必要性 | 为本轮库存备注提供实际持久化位置 |
| 现有记录 | 保持 NULL，不修改数量、版本或历史 |
| API 限制 | 最多 1,000 字；PATCH 可 null 清空 |
| 影响 API | 单项/批量入库写；库存 PATCH 写；库存列表、详情和其他复用 InventoryItemRead 的响应返回 |
| ORM | 仅在 InventoryItem 新增 notes 映射 |
| 迁移 | 新 revision 增加列，downgrade 删除列；删除会丢备注，实际回滚需单独评估 |
| 时机 | 方案确认后编写模型与迁移；实际执行前确认目标数据库；列存在后才部署依赖该列的代码 |

本次未批准或执行迁移。不能仅改 ORM 就认为数据库已增加字段；也不能在旧库没有 notes 时宣称新增 API 可以运行。实施前先核对实际迁移头和目标环境，不读取或输出连接密钥。

### 11.2 实施顺序与交付条件

| 阶段 | 具体工作 | 完成条件 |
| --- | --- | --- |
| 0 交接核对 | 阅读本文与实施计划，按第 12 节已确定范围实施 | 业务规则已列明，不重复讨论已排除能力 |
| 1 字段与请求模型 | N06、N09、M06 | 请求白名单、响应模型及 notes 迁移可审阅；暂不执行迁移 |
| 2 空间与词典 | N01、N02、N07 | 归属、唯一性、归档/恢复完整；锁协议与库存实现一致 |
| 3 数量与库存 | N03、N04、N08 | 计算函数、单项事务、幂等、批量、查询均按契约实现 |
| 4 管理员与认证 | N05、M02–M05 | 当前角色检查、普通用户状态、公共词典、改密码 |
| 5 入口与文档 | M01、M07–M09、N10 | 路由注册、跨域、实际 API 参考及示例 |
| 6 验证与部署准备 | 经授权恢复测试，确定迁移目标 | 验证结果与未验证项单独列明，不把文档或语法检查等同联调通过 |

### 11.3 验证规划，尚未执行

当前只做文档静态核对。本草稿沿用实施计划的暂缓测试安排，不改变仓库最终验证要求。未来仅有语法和 OpenAPI 检查时，应标为“代码已交付，行为验证待完成”。

恢复验证后，使用隔离环境重点检查：

1. 跨用户库存、私有定义、移动目标及历史均无法越权访问。
2. 普通增减、估算继续计算、盘点换单位及清空估算符合字段矩阵。
3. 同版本两个并发写请求只能一个成功；相同幂等请求并发最多执行一次。
4. 成功后旧版本重放有效；同键不同库存/参数冲突；失败没有部分数量或成功记录残留。
5. 空间归档与入库/移动/EMPTY 恢复竞争后，不出现归档空间有 IN_STOCK 的结果。
6. 批量第 N 项失败，前 N-1 项也不持久化；重复 ID 拒绝。
7. 1/3 的舍入结果、极小比例拒绝、单位转换、最大数量及超范围结果符合第 6.2 节；预览与正式提交一致。
8. 归档词典名称仍占用；状态转换、历史可见性及日期三类统计正确。
9. notes 迁移只增加目标列；真实数据库版本、API 返回和部署状态分别验证。

## 12. 已落实决定、核实结果与交接边界

### 12.1 已落实的本轮范围

| 决策 | 本轮规则 | 影响 |
| --- | --- | --- |
| D01 历史范围 | 只新增成功的 ADD / CONSUME / RECONCILE；不记入库 ADD、资料修改、丢弃、归档事件 | 不增加历史表、不记录前后物品、不关联对话；这是数量设计完整历史目标的本轮例外 |
| D02 物品关联 | 库存 PATCH 禁止替换 item_definition_id | 收窄原计划，避免旧数量历史改挂到另一物品 |
| D03 精度 | 用户已允许合理取整；实现规则为第 6.2 节三位小数 ROUND_HALF_UP | 保持数量收支一致；不新增精度字段或操作枚举 |
| D04 状态 | DISCARDED/ARCHIVED 终态；EMPTY 可恢复；恢复在库要求 ACTIVE 空间 | 不提供丢弃后再归档；重复库存终态动作冲突 |
| D05 创建重试 | 本轮接受不保证创建幂等 | 网络不确定结果需核对，无法保证自动恢复 |
| D06 词典停用 | 禁止新建关联，已有库存仍可加减、盘点、移动 | 停用不阻断真实库存管理 |
| D07 数据库与验证 | notes 是唯一结构变更；代码/迁移编写与实际迁移分别授权；测试完成前不宣称可验收上线 | 本次规划未实施任何数据库变更 |
| D08 操作来源 | 手动/Agent 区分推迟到 Agent 实施时；本轮 input_method 固定 MANUAL | 不增加 source 字段，不修改 inventory_operation 的任何字段或约束 |

### 12.2 已核实的事实与已确定的实现细节

- 本地 ORM 和初始迁移支持现有三种数量操作，估算三字段联动、全局唯一幂等键和 128 字符上限均已有；不需要为这些能力新增表。
- 空间的活动名称唯一索引排除归档记录；词典唯一索引不排除归档记录，因此恢复词典不是重新创建同名项。
- 当前身份依赖每请求读取 user；数据库会话依赖不提交；注册 service 自己提交。新增写请求的事务归属按第 8 节统一。
- 字段白名单、返回结构、日期允许补录、名称规范化、同值 PATCH、比例语法、幂等键格式和舍入算法是本次确定的实施规则，并非已实现行为，不再逐项留待业务确认。
- 代码核对不能证明远程库已有八表、管理员或初始化词典；部署前检查目标库迁移版本及初始化数据。没有管理员时本轮不自动提升账号；没有品类时由部署准备提供公共品类。

### 12.3 已确认：录错后归档再重建

用户已确认：“删除后重建”采用已有 archive 接口，将旧库存从默认在库列表移除，保留原库存和已有数量操作记录，再通过入库接口创建正确的新批次。不新增物理 DELETE，不删除数量历史，不新增更正记录或新旧批次关联字段。

旧库存归档与新批次入库是两个独立请求，不承诺跨请求一起回滚。归档成功后再入库；新建失败时旧库存仍保持归档，用户可重新填写入库。新批次有独立 ID、初始数量和版本，不继承旧操作记录。已归档或丢弃的旧记录直接保持原状态，不重复执行归档。

### 12.4 实施与验收分开交接

本轮交付要求是实现代码、备注迁移文件与实际 API_REFERENCE。继续沿用暂停测试和实际迁移的边界；这不表示已通过质量验收。恢复测试后按第 11.3 节验证。实施者无需重新决定已列明的业务规则，但必须报告实际验证结果、无法验证的项目和实现偏差。

| 附件问题 | 本文落点 |
| --- | --- |
| Q01 公共契约 | 第 4、10 节 |
| Q02 改密码 | 第 9 节 |
| Q03 空间 | 第 7、9 节 |
| Q04 词典 | 第 2.2、7、9 节 |
| Q05 入库 | 第 5.1、5.6 节；D05 |
| Q06 库存 PATCH | 第 5.2 节；D02 |
| Q07 数量 | 第 6 节；D03 |
| Q08 版本 | 第 5、8 节 |
| Q09 幂等 | 第 8.3 节 |
| Q10 空间交叉 | 第 7、8.2 节 |
| Q11 状态转换 | 第 5.5、7 节；D04 |
| Q12 批量 | 第 5.6、8 节 |
| Q13 库存响应 | 第 4.1、10 节 |
| Q14 临期 | 第 10 节 |
| Q15 历史分歧 | 第 1、5、10 节；D01；不采用缺失的 B08 来源 |
| Q16 数量历史 | 第 6.3、10 节 |
| Q17 管理员账户 | 第 9、10 节 |
| Q18 公共词典 | 第 7、9、10 节 |
| Q19 范围与验收 | 第 1、11 节；提醒不在本轮，不擅自判断整个项目永久取消；AI、对话、记忆、重算仍为后续工作 |

实施计划已同步本轮范围，原数量设计中的完整历史与 Agent 目标属于后续范围。实际 API_REFERENCE 在实现后按真实字段和验证结果编写，不将本文直接改名充当已实现接口文档。
