# SayFridge 数据库设计

> 状态：已确认并完成第一阶段数据库基础实施
>
> 数据库：Neon PostgreSQL
>
> 范围：个人用户、公共与私有物品词典、库存状态、操作历史与对话历史

## 1. 总体结构

当前设计包含八张表：

~~~text
item_category
└── item_definition
    ├── owner_user_id = NULL       公共物品定义
    └── owner_user_id = user.id    用户私有物品定义

user
├── storage_space
│   └── inventory_item
│       ├── item_definition_id → item_definition
│       └── inventory_operation
│
└── conversation
    └── conversation_message
~~~

- 一个用户可以拥有多个平级存储空间；不建立嵌套空间或 household。
- item_category 是公共品类词典，例如蔬菜、乳制品、肉类、日用品。
- item_definition 是物品定义词典，例如西红柿、黄瓜、香蕉；它不是条码、SKU 或某一批具体库存。
- item_definition.owner_user_id 为 NULL 时是公共物品；有用户 ID 时仅该用户可见和维护。
- inventory_item 是某用户、某存储空间中的一批具体库存；名称和品类通过 item_definition 关联，不在库存表重复保存。
- inventory_operation 是一条单物品库存操作，可来自 AI 或手动按钮；它不是通用会计流水，也不按小票建立操作主表。
- 一张照片或小票识别 N 个物品时，创建 N 条独立的 inventory_operation。
- 对话历史与库存操作历史不设置外键。

## 2. user 用户表

| 字段 | 含义 |
| --- | --- |
| id | 用户主键 |
| email | 登录邮箱，必须唯一 |
| password_hash | 本地登录密码哈希，禁止保存明文密码 |
| auth_provider | 登录来源，例如 LOCAL 或第三方认证提供商 |
| role | 用户角色，例如 USER、ADMIN |
| status | 账号状态，例如 ACTIVE、SUSPENDED、DISABLED |
| voice_limit_seconds | 当前额度周期允许使用的语音秒数 |
| voice_used_seconds | 当前额度周期已经使用的语音秒数 |
| voice_quota_reset_at | 语音额度下次重置时间 |
| created_at | 用户创建时间 |
| updated_at | 用户最后更新时间 |

## 3. storage_space 存储空间表

| 字段 | 含义 |
| --- | --- |
| id | 存储空间主键 |
| user_id | 所属用户，外键关联 user.id |
| name | 用户定义名称，例如厨房冰箱、车库冷柜 |
| type | 空间类型，例如 FRIDGE、FREEZER、PANTRY、WAREHOUSE、OTHER |
| status | 空间状态，例如 ACTIVE、ARCHIVED |
| created_at | 空间创建时间 |
| updated_at | 空间最后更新时间 |

主要约束与索引：

- 所有库存查询和写入均通过 storage_space.user_id 验证当前认证用户。
- 建立 (user_id, status) 索引；同一用户的活动空间名称建议唯一。
- 空间归档时不得让仍在库物品失去归属。

## 4. item_category 公共品类词典表

一行代表一个可筛选的公共品类。首批可预置蔬菜、水果、肉类、乳制品、主食、日用品、其他等类别。

| 字段 | 含义 |
| --- | --- |
| id | 品类主键 |
| name | 展示名称，例如蔬菜 |
| normalized_name | 规范化名称，用于搜索和去重 |
| status | ACTIVE 或 ARCHIVED |
| sort_order | 前端展示顺序 |
| created_at | 创建时间 |
| updated_at | 最后更新时间 |

- 品类不归普通用户私有；公共品类由系统初始化或管理员维护。
- 不物理删除已被物品定义引用的品类，改为 ARCHIVED。

## 5. item_definition 物品定义词典表

一行代表一个物品名称及其所属品类。

| 字段 | 含义 |
| --- | --- |
| id | 物品定义主键 |
| name | 展示名称，例如西红柿、黄瓜、香蕉 |
| normalized_name | 规范化名称，用于搜索和去重 |
| category_id | 所属品类，外键关联 item_category.id |
| owner_user_id | 可为空；NULL 为公共物品，有值为该用户私有物品 |
| status | ACTIVE 或 ARCHIVED |
| created_at | 创建时间 |
| updated_at | 最后更新时间 |

可见性规则：

~~~text
owner_user_id IS NULL
OR owner_user_id = 当前认证用户 id
~~~

建议建立两个部分唯一约束：

- 公共物品：normalized_name 在 owner_user_id IS NULL 范围内唯一；
- 私有物品：(owner_user_id, normalized_name) 在 owner_user_id IS NOT NULL 范围内唯一。

## 6. inventory_item 具体库存表

一行代表一个具体库存物品或批次。同一物品在购买日期、到期日期或存储空间不同时可保存为多行。

| 字段 | 含义 |
| --- | --- |
| id | 库存物品主键 |
| storage_space_id | 所属存储空间，外键关联 storage_space.id |
| item_definition_id | 物品定义，外键关联 item_definition.id |
| purchase_date | 购买日期，可以为空 |
| expiry_date | 到期日期，可以为空；无法确认时不得由模型擅自推断 |
| status | IN_STOCK、EMPTY、DISCARDED 或 ARCHIVED |
| initial_amount | 首次入库数量；创建后不随普通操作改变 |
| initial_unit | 首次入库单位 |
| confirmed_current_amount | 用户最后一次可确认的当前库存数量 |
| confirmed_current_unit | 已确认当前库存单位 |
| confirmed_at | 已确认当前库存最后更新时间 |
| estimated_current_amount | 当前有效估算库存数量；无有效估算时为 NULL |
| estimated_current_unit | 当前有效估算库存单位；无有效估算时为 NULL |
| estimated_at | 当前估算最后生成或更新时间；无有效估算时为 NULL |
| version | 乐观锁版本号，每次正式更新递增 |
| created_at | 库存记录创建时间 |
| updated_at | 库存记录最后更新时间 |

数量状态规则：

~~~text
initial_*
= 首次入库历史事实，永远不变

confirmed_current_*
= 用户最后一次能够确认的实际库存基线

estimated_current_*
= 在确认基线之后，包含不确定换算或 AI 推测的当前结果
~~~

- 新建库存时：confirmed_current_* 等于 initial_*；estimated_current_* 和 estimated_at 均为 NULL。
- estimated_current_amount 与 estimated_current_unit 必须同时为空或同时有值；estimated_at 必须与它们同时为空或同时有值。
- 数量统一使用 NUMERIC(12,3)，禁止浮点类型；所有已存数量不得小于 0。
- 当前界面展示规则：estimated_current_* 非空时展示它并标注“约 / AI 估算”；否则展示 confirmed_current_*。
- status 只有在确定库存为 0 时才自动变为 EMPTY；估算为 0 只能提示“可能用完”，不能自动隐藏库存。

所有权关系：

~~~text
inventory_item.storage_space_id
→ storage_space.user_id
→ 当前认证用户
~~~

## 7. inventory_operation 单物品库存操作表

一行代表对一个 inventory_item 的一次正式增减、估算或重新确认。Agent 和前端都不能绕过该记录直接修改库存。

| 字段 | 含义 |
| --- | --- |
| id | 操作主键 |
| inventory_item_id | 被操作库存，外键关联 inventory_item.id |
| operation_type | ADD、CONSUME 或 RECONCILE |
| affects_state | CONFIRMED 或 ESTIMATED，说明本次操作修改哪一层当前状态 |
| input_method | TEXT、VOICE、PHOTO、RECEIPT 或 MANUAL |
| quantity_kind | 用户表达类型：AMOUNT、FRACTION、QUALITATIVE |
| quantity_value | 用户原始值，例如 2、1/2、some 或盘点后的 18.5 |
| quantity_unit | 用户原始单位，例如 kg、g、each、cup、remaining；定性表达可为空 |
| calculation_method | EXACT、CONVERTED 或 AI_ESTIMATED |
| applied_change_amount | ADD 或 CONSUME 正式应用的变化量；RECONCILE 时可为空 |
| applied_change_unit | applied_change_amount 的单位；RECONCILE 时可为空 |
| status | PENDING_CONFIRMATION、SUCCESS、FAILED 或 UNDONE |
| idempotency_key | 幂等键，防止重试造成重复操作 |
| created_at | 操作创建时间 |
| updated_at | 操作最后更新时间 |
| undone_at | 撤回时间；未撤回时为空 |

语义规则：

- quantity_value 和 quantity_unit 保留用户的原始表达，不得被标准单位覆盖。
- EXACT 与 CONVERTED 表示普通后端可确定计算；AI_ESTIMATED 表示需要 AI 给出候选值并经用户确认。
- 当前没有有效估算时，确定的 ADD 或 CONSUME 更新 CONFIRMED 状态。
- 当前有有效估算时，后续增减基于估算结果并更新 ESTIMATED 状态；不能因为“本次扣减可确定”就丢弃历史估算。
- RECONCILE 表示用户重新称重、盘点或明确说明“现在还剩 X”；它更新 confirmed_current_*，并在同一事务中清空 estimated_current_* 和 estimated_at。
- 只有 SUCCESS 操作影响库存；PENDING_CONFIRMATION、FAILED 和 UNDONE 均不影响当前状态。
- 普通 ADD、CONSUME 可按已确认变化量撤回；RECONCILE 如录入错误，以新的 RECONCILE 更正，不恢复旧估算链。

## 8. conversation 会话表

| 字段 | 含义 |
| --- | --- |
| id | 会话主键 |
| user_id | 所属用户，外键关联 user.id |
| title | 会话标题 |
| created_at | 创建时间 |
| updated_at | 最后一条消息或会话信息更新时间 |

建立 (user_id, updated_at DESC) 索引，用于列出最近会话。

## 9. conversation_message 消息表

| 字段 | 含义 |
| --- | --- |
| id | 消息主键 |
| conversation_id | 所属会话，外键关联 conversation.id |
| role | USER 或 ASSISTANT |
| content | 用户消息、转写文本或需要向用户展示的回复；不保存模型隐藏推理 |
| created_at | 消息创建时间 |

- 消息按 (conversation_id, created_at, id) 稳定排序。
- 不保存系统提示词、隐藏推理、API 密钥或访问令牌。
- 对话记录不作为库存事实或库存审计来源。

## 10. 数量状态与展示示例

~~~text
买入 20 kg 西红柿
→ confirmed = 20 kg
→ estimated = NULL
→ 展示：20 kg（已确认）

用户说“用了一半”
→ 确定扣减 10 kg
→ confirmed = 10 kg
→ estimated = NULL
→ 展示：10 kg（已确认）

用户说“又用了两个”
→ 两个无法直接换算为 kg
→ 估算约扣减 0.3 kg，经用户确认
→ confirmed = 10 kg
→ estimated = 9.7 kg
→ 展示：约 9.7 kg（AI 估算）

用户重新称重：“现在还剩 9.5 kg”
→ confirmed = 9.5 kg
→ estimated = NULL
→ 展示：9.5 kg（已确认）
~~~

## 11. 正式写入流程

~~~text
用户输入
→ Agent 提取原始数量表达并提出候选操作
→ 后端以 confirmed 或有效 estimated 为正确基数计算
→ 对 AI_ESTIMATED 候选向用户展示原始表达和拟采用结果
→ 用户确认
→ FastAPI 校验身份、可见性、单位、数量、状态、version 与幂等键
→ PostgreSQL 事务更新 inventory_item 并写入 inventory_operation
~~~

事务必须保证：

- 用户只能操作自己 storage_space 下的库存，也只能选择公共或自己的 item_definition；
- 估算不存在时，确定操作更新 confirmed；估算存在时，后续增减更新 estimated；
- RECONCILE 原子更新 confirmed 并清空 estimated；
- CONSUME 不得将所修改状态的数量减至小于 0；
- 库存更新和 SUCCESS 操作记录同时提交或同时回滚；
- idempotency_key 阻止同一正式请求执行两次。

## 12. 实现状态

本文是已确认的数据库设计基线。当前仓库已建立 Neon 连接配置、SQLAlchemy ORM 模型和首份八表 Alembic 迁移；库存 CRUD、Repository 和受控业务接口尚未实现。Flutter、Web 与 Agent 均不得直接访问数据库。
