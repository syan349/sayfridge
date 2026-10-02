# CS734 Project Scope Draft: SayFridge Smart Household Inventory Assistant / CS734 项目范围草案：SayFridge 智能家庭库存助手

> Version / 版本：v0.1  
> Positioning / 定位：A household inventory assistant for individuals and families to manage food, fresh produce, and everyday supplies. / 面向个人及家庭用户的食品、生鲜与日用品库存管理助手。

## Delivery status / 交付状态

This document defines product scope, not a release checklist. The feature journeys below include future goals. / 本文定义产品范围，不是已交付清单；下文功能与交互包含未来目标。

| Capability / 能力 | Current boundary / 当前边界 |
| --- | --- |
| Authentication, spaces, catalog and inventory APIs / 认证、空间、词典和库存接口 | Implemented endpoints are listed in [API reference](../reference/API_REFERENCE.md). / 已实现接口以 API 参考为准。 |
| Text Agent V0.2 / 文本 Agent | Local six-node implementation, memory, estimates and per-item resume/recovery; deployment requires storage checks. / 六节点、记忆、估算和逐项恢复已有本地实现，部署前仍需检查数据库。 |
| Web/mobile experiences / Web 与移动端交互 | Product requirements; component code/readmes determine actual page coverage. / 属于产品要求，页面完成度以对应组件为准。 |
| Voice, images, proactive notifications and historical recalculation / 语音、图片、主动提醒与历史重算 | Future goals, not current Agent V0.2 capabilities. / 未来目标，不属于当前 Agent V0.2 能力。 |

Current implementation structure: [Architecture](../architecture/AGENT_DESIGN.md). Historical voice/dual-Agent design: [archived draft](../../../2026-09-25/ARCHITECTURE_REALTIME_DRAFT.md). / 当前实现结构与历史方案分开维护。

## 1. Project Overview / 项目概述

SayFridge is an application consisting of a cross-platform mobile app, a user-facing web application, and an administrator web portal. It helps users build and maintain a household inventory with minimal manual entry, and proactively reminds them about expired or soon-to-expire items and missing consumption records.

SayFridge 由跨平台手机 App、用户 Web 和管理员 Web 组成，帮助用户以较低输入成本建立和维护家庭库存，并主动提醒已过期、即将过期的物品及可能遗漏的消耗记录。

Instead of requiring complex forms, users can photograph purchased items, receipts, or invoices; describe purchases or consumption by voice or text; manually correct inventory when needed; and receive scheduled reminders.

系统不要求用户填写复杂表单。用户可以拍摄购买物品、购物小票或发票；通过语音或文字描述购买与消耗；在需要时手动修正库存；并接收定时提醒。

The core Agent interprets multimodal inputs and chooses controlled backend tools, such as creating inventory records, recording consumption, or querying expiry status. The Agent **never accesses the database directly**. Every tool invocation is validated, authorised, executed transactionally, and audited by the backend.

核心 Agent 负责理解多模态输入并选择受控的后端工具，例如创建库存记录、记录消耗或查询临期状态。Agent **不直接访问数据库**；每一次工具调用都由后端完成参数校验、权限校验、事务执行和审计。

## 2. Target Users and Scenarios / 目标用户与使用场景

### 2.1 Target users / 目标用户

| User type / 用户类型 | Needs and pain points / 需求与痛点 | Primary platforms / 主要使用端 |
| --- | --- | --- |
| Individual user / 个人用户 | Forgetting what is already at home, food waste from expiry, difficulty maintaining records / 忘记家中已有物品、食品过期浪费、难以持续记录 | Mobile app first; web as a companion / 手机为主，Web 为辅 |
| Administrator / 系统管理员 | Managing accounts, handling abnormal tasks, and monitoring system operation and audits / 维护账户、处理异常任务、监控系统运行与审计 | Administrator web only / 仅管理员 Web |

The MVP targets individual users. Each account may create multiple flat storage spaces, such as fridges, freezers, and warehouses. The first release does not support nested spaces or inventory sharing between users.

MVP 面向个人用户。每个账户可以建立冰箱、冷柜、仓库等多个平级存储空间；首轮不支持空间嵌套或用户之间共享库存。

### 2.2 Typical scenarios / 典型场景

1. **Initial inventory setup / 首次建库**: The user photographs newly purchased items and their receipt. The system extracts candidate items, quantities, and dates, then asks the user to confirm before creating inventory records. / 用户拍摄刚购买的物品及小票；系统提取候选物品、数量和日期，用户确认后批量入库。
2. **Daily stock-in / 日常入库**: The user says, “I bought two cartons of milk and one bag of rice.” Speech is transcribed, structured information is extracted, and a confirmation card is shown before the data is saved. / 用户说“我买了两盒牛奶和一袋米”；系统转写并提取结构化信息，展示确认卡片后保存。
3. **Daily consumption / 日常消耗**: The user says, “We used three eggs and finished one carton of milk.” The system proposes deductions, using explicit batch preferences or asking the user to choose, and allows correction. / 用户说“晚饭用了三个鸡蛋，喝掉一盒牛奶”；系统按明确批次偏好或用户选择提出扣减，并允许修正。
4. **Expiry handling / 临期处理**: At 9:00 AM, the system sends a summary of expired and soon-to-expire food. Users can mark an item as consumed, discarded, or view details. / 每日早上 9 点，系统推送已过期和即将过期食品摘要；用户可标记“已食用”“已丢弃”或查看详情。
5. **End-of-day recall / 回顾式记录**: At 9:00 PM, the system gently prompts the user to recall today's usage, either through a guided category-by-category flow or a single free-form statement. / 每日晚上 9 点，系统提醒用户回顾当天使用情况；用户可按类别逐步记录，也可直接自由输入。
6. **Web management / Web 管理**: Users use a desktop browser for bulk viewing, filtering, and editing current inventory; administrators handle system-level exceptions and operations. / 用户在电脑上批量查看、筛选和编辑当前库存；管理员处理系统级异常与运营工作。

## 3. Product Scope / 产品范围

### 3.1 Product goals across phases / 分阶段产品目标

| Module / 模块 | Scope / 功能范围 |
| --- | --- |
| Accounts and personal inventory / 账户与个人库存 | Registration/login, profile, personal inventory, and access isolation by authenticated user / 注册登录、用户资料、个人库存、按认证用户进行权限隔离 |
| Inventory management / 库存管理 | Create, view, edit, and delete items; quantity, unit, category, purchase date, expiry date, storage location, and notes / 物品增删改查；数量、单位、类别、购买日期、到期日、储存位置和备注 |
| Multimodal input / 多模态录入 | Camera/image upload, receipt or invoice OCR, product-image recognition, voice input, and text input / 拍照上传、小票或发票 OCR、商品图像识别、语音与文字输入 |
| Agent assistant / Agent 助手 | Intent parsing and controlled tool use; clarify missing/ambiguous information and confirm estimates or image-derived entries / 意图解析、受控工具调用；缺失或歧义信息需补充，估算或图片入库需要确认 |
| Reminders / 提醒机制 | 09:00 expiry reminder, 21:00 daily-recall reminder, and configurable schedule/on-off preferences / 09:00 临期提醒、21:00 使用情况回顾提醒、可配置时间与开关 |
| User mobile app / 用户手机 App | Inventory overview, camera, voice/text entry, push notifications, item details, and manual maintenance / 库存概览、相机、语音/文字录入、推送、详情与手动维护 |
| User web / 用户 Web | Shared inventory data with the app; large-screen browsing, filtering, and bulk editing / 与手机端共享数据；大屏浏览、筛选和批量编辑 |
| Administrator web / 管理员 Web | Account status, task/recognition failures, restricted exception handling, and basic audit views / 账户状态、任务与识别失败记录、受控异常处理、基础审计查看 |
| Testing and security / 测试与安全 | Automated tests, device/emulator testing, API controls, and audit trails for sensitive actions / 自动化测试、真机/模拟器测试、API 安全控制和关键操作审计 |

### 3.2 Explicitly out of scope for the first MVP / 明确不在首轮 MVP 的范围

- Real supermarket ordering, payment, delivery, or retailer-inventory integration / 自动下单、支付、配送或对接超市真实库存。
- OCR or image recognition that changes inventory without any user confirmation / 无需用户确认即可修改库存的全自动 OCR 或图像识别。
- Medical or nutritional advice, or definitive food-safety judgement / 医疗、营养建议或食品安全责任判断。
- Smart-fridge hardware, IoT sensors, Bluetooth, or NFC device integration / 智能冰箱硬件、IoT 传感器、蓝牙或 NFC 设备接入。
- Nested inventory spaces, shared inventory, fine-grained roles, or social features / 嵌套库存空间、用户共享库存、细粒度角色体系或社交功能。多个平级空间已在范围内。
- Fully automatic long-term consumption prediction or generative recipe recommendations / 全自动长期消耗预测或生成式食谱推荐。

These may become stretch goals, but must not delay the MVP's core flow. / 它们可作为 Stretch Goals，但不能阻碍 MVP 主链路完成。

## 4. Responsibilities of the Three Frontends / 三端职责与双端存在理由

| Platform / 端 | User / 用户 | Main responsibility / 核心职责 | Why it is distinct / 不可替代的原因 |
| --- | --- | --- | --- |
| Flutter mobile app / Flutter 手机 App | General user / 普通用户 | Photography, voice entry, push notifications, and quick recording / 拍照、语音、推送与快速记录 | Direct access to camera, microphone, native notifications, and convenient use while shopping or cooking / 直接使用摄像头、麦克风和原生推送，适合购物和厨房场景 |
| User web / 用户 Web | General user / 普通用户 | Large-screen inventory viewing, advanced filters, and bulk editing / 大屏库存浏览、复杂筛选和批量编辑 | Better for organising larger datasets and completing longer editing tasks / 适合整理较多数据，降低手机端表单负担 |
| Administrator web / 管理员 Web | Administrator / 管理员 | Account, task, audit, and exception management / 用户、任务、审计和异常管理 | Administrative work needs desktop efficiency and restricted permissions, not a consumer mobile experience / 管理操作需要桌面效率和受限后台权限，不应放入普通用户 App |

The mobile app and user web share core business data but serve different contexts and tasks; they are not merely duplicated interfaces.

手机端和用户 Web 共享核心业务数据，却服务于不同场景和任务，因此并非简单重复。

## 5. Core Workflow / 核心业务流程

```mermaid
flowchart LR
    A["User: photo / voice / text\n用户：拍照 / 语音 / 文字"] --> B["Flutter App or User Web\nFlutter App 或用户 Web"]
    B --> C["API Gateway / Backend\nAPI 网关 / 后端"]
    C --> D["Recognition services: OCR, image, speech\n识别服务：OCR、图像、语音转写"]
    D --> E["Agent: intent parsing and tool selection\nAgent：意图解析与工具选择"]
    E --> F["Controlled inventory tools\n受控库存工具"]
    F --> G[("Business database\n业务数据库")]
    E --> H["Confirmation card or follow-up\n确认卡片或追问"]
    H --> B
    G --> I["Scheduled expiry and recall jobs\n临期与回顾定时任务"]
    I --> J["Push notification service\n推送通知服务"]
    J --> B
```

### 5.1 Stock-in flow / 入库流程

1. The user uploads a photo/receipt or describes a purchase by voice or text. / 用户上传物品照片、小票，或用语音、文字描述购买内容。
2. The backend stores the original input and invokes OCR, image recognition, or speech transcription. / 后端保存原始输入并调用 OCR、图像识别或语音转写。
3. The Agent converts results into a candidate operation, such as `add_inventory_item`. / Agent 将结果转换成候选操作，例如 `add_inventory_item`。
4. The frontend presents a confirmation card containing item name, quantity, unit, expiry date, and other fields. Missing or low-confidence fields require user input or confirmation. / 前端展示物品名称、数量、单位、到期日等确认卡片；缺失或低置信度字段必须由用户补充或确认。
5. After confirmation, the backend creates or updates current inventory within a database transaction. / 用户确认后，后端在数据库事务中写入或更新当前库存。

### 5.2 Consumption flow / 消耗流程

1. The user says or enters, “Used three eggs.” / 用户说或输入“用了三个鸡蛋”。
2. The Agent calls a query tool to locate plausible inventory batches. / Agent 调用查询工具定位可能的库存批次。
3. If there are multiple batches, use an applicable user preference or ask the user to choose. / 多批次时使用适用的用户偏好；仍有歧义则让用户选择，不默认取第一批。
4. After required clarification/confirmation, the backend reduces stock. Only confirmed zero becomes EMPTY; estimated zero remains visible as possibly used up. / 完成必要的补充或确认后，由后端扣减；只有确认归零才标记 EMPTY，估算为零仍保留为可能用完。数量语义见 [数量设计](../architecture/QUANTITY_STATE_DESIGN.md)。

### 5.3 Scheduled reminders / 每日提醒流程

- **09:00 AM / 早上 09:00**: A background job finds expired and soon-to-expire food/fresh items, generates a summary, and sends a notification. The default threshold (for example, three days) is still to be decided. / 后台任务查询已过期和未来 N 天内到期的食品/生鲜，生成摘要并推送；默认阈值（如 3 天）待小组确定。
- **09:00 PM / 晚上 21:00**: A lightweight prompt invites the user to record today's consumption. The user may follow a guided flow, skip it, or enter a free-form statement. / 轻量提醒邀请用户记录当天消耗；用户可按引导完成、跳过或自由输入。
- Users can turn reminders off or change the schedule. Duplicate notifications for the same event must be prevented. / 用户可关闭提醒或调整时间；同一事件必须避免重复推送。

## 6. Agent and Tool Boundaries / Agent 与工具边界

The Agent interprets requests and proposes controlled actions. The backend validates
identity, ownership and quantity rules, computes final balances and owns transactions.
Current node/tool names and memory behavior are maintained only in
[Architecture](../architecture/AGENT_DESIGN.md); public contracts are in [API reference](../reference/API_REFERENCE.md).
The old conceptual tool list is preserved with the archived implementation plan.

Agent 负责理解请求、选择目标和提出候选；后端负责身份、归属、数量校验、余额计算和正式事务。
当前节点、工具与记忆设计只在架构文档维护，接口只在 API 参考维护。
缺少信息需要补充；估算及图片入库需要确认；明确物品和用户明确指定的新空间随入库自动创建，完整的确定性操作不增加固定确认。
模型输出使用受控结构，不能将模型文字拼接为 SQL 或执行任意命令。

## 7. Current Basic Data Model / 当前数据库基础模型

The current business schema contains nine tables: the original user, storage_space, item_category, item_definition, inventory_item, inventory_operation, conversation and conversation_message, plus agent_inventory_action. LangGraph checkpoint/Store tables are maintained separately in the Agent schema. See [database design](../architecture/DATABASE_DESIGN.md). / 当前业务结构为原八表加 agent_inventory_action，共九表；LangGraph 检查点和 Store 表在 Agent schema 中单独维护，不计入业务九表。字段与约束见数据库设计。

| Entity / 实体 | Key fields / 关键字段 | Description / 说明 |
| --- | --- | --- |
| User / 用户 | id, email, passwordHash/authProvider, role, voiceLimitSeconds, voiceUsedSeconds, voiceQuotaResetAt | User account and current voice-call quota / 用户账户和当前语音通话额度 |
| StorageSpace / 存储空间 | id, userId, name, type, status | One flat storage space owned by the user / 用户拥有的一个平级存储空间 |
| ItemCategory / 物品品类 | id, name, normalizedName, status | Shared category dictionary, such as vegetables, dairy, and household supplies / 公共品类词典，例如蔬菜、乳制品和日用品 |
| ItemDefinition / 物品定义 | id, name, normalizedName, categoryId, ownerUserId, status | Shared or user-private item definition; a null ownerUserId means shared / 公共或用户私有的物品定义；ownerUserId 为空表示公共 |
| InventoryItem / 库存物品 | id, storageSpaceId, itemDefinitionId, initialAmount/unit, confirmedCurrentAmount/unit, estimatedCurrentAmount/unit, version | Concrete inventory with a confirmed baseline and an optional estimate overlay / 具有确认基线和可选估算覆盖层的具体库存 |
| InventoryOperation / 库存操作 | id, inventoryItemId, operationType, affectsState, inputMethod, quantityValue/unit, calculationMethod, appliedChangeAmount/unit, status | A single-item AI or manual change, reconciliation, and reversal basis / 单物品的 AI 或手动变更、重新确认与撤回依据 |
| Conversation / 会话 | id, userId, title, createdAt, updatedAt | One multi-turn conversation / 一次多轮对话 |
| ConversationMessage / 会话消息 | id, conversationId, role, content, createdAt | One message in a conversation / 会话中的单条消息 |

`Household` and a generic `InventoryTransaction` are not created. Users manage multiple flat spaces through `StorageSpace`, without sharing. `InventoryOperation` stores single-item AI and manual operations; a user reconciliation creates a new confirmed baseline and clears the active estimate. Conversation history remains independent from inventory-operation history, and database transactions keep inventory and operation writes atomic. / 当前不建立 `Household` 或通用 `InventoryTransaction`。用户通过 `StorageSpace` 管理多个平级空间但不共享；`InventoryOperation` 保存单物品 AI 和手动操作；用户重新盘点会建立新的确认基线并清空当前估算。对话历史与库存操作历史保持独立，数据库事务保证库存和操作记录同时成功或同时失败。

## 8. Proposed Architecture and Protocols / 技术架构与通信协议（建议）

- **Mobile / 移动端**: Flutter for Android and iOS, using camera, image picker, microphone, gestures, and local/remote notifications. / Flutter 支持 Android 与 iOS，使用相机、图片选择、麦克风、手势和本地/远程推送。
- **Web / Web 前端**: User and administrator web interfaces may share a technology stack, while routes, permissions, and interfaces remain separated by role. / 用户 Web 和管理员 Web 可共用技术栈，但按角色隔离路由、权限与界面。
- **Backend/API Gateway / 后端/API 网关**: Central authentication, rate limiting, input validation, routing, and auditing; versioned REST APIs for clients. / 统一认证、限流、输入校验、路由与审计；对客户端提供版本化 REST API。
- **Business services / 业务服务**: Inventory, identity/access, reminders, media processing, and Agent orchestration are modular. Start as a modular monolith, while keeping service boundaries clear. / 库存、身份权限、提醒、媒体处理和 Agent 编排模块化；首版可采用模块化单体，但保持清晰服务边界。
- **Data and media / 数据与媒体**: Use a relational database for business data and object storage for receipts, images, and audio. / 关系型数据库保存业务数据；对象存储保存小票、图片和音频。
- **Async work / 异步任务**: A queue and scheduler handle OCR, image recognition, speech transcription, and notifications without blocking CRUD requests. / 通过消息队列和调度器处理 OCR、图像识别、语音转写和推送，避免阻塞 CRUD 请求。

| Communication scenario / 通信场景 | Protocol / 协议 | Justification / 理由 |
| --- | --- | --- |
| App/web to backend / App、Web 与后端 | HTTPS REST + JSON | Clear resource model, mature cross-platform support, and easy testing/access control / 资源模型清晰、跨平台成熟、便于测试和权限控制 |
| Image/audio upload / 图片、音频上传 | HTTPS multipart or presigned object-storage upload / HTTPS multipart 或预签名对象存储上传 | Supports larger files without keeping API connections busy / 支持大文件，避免 API 长时间承载媒体流 |
| Long-running task status / 长任务状态 | REST polling for MVP; WebSocket/SSE later / MVP 用 REST 轮询；后续可用 WebSocket/SSE | AI jobs are asynchronous; MVP is simpler and stable, with a path to higher real-time responsiveness / AI 任务异步；MVP 更稳定简单，后续可升级实时性 |
| Backend to notification provider / 后端至推送服务 | Platform push API / 平台推送 API | Uses operating-system notification channels on Android and iOS / 使用 Android、iOS 系统通知通道 |

## 9. Scalability / 可扩展性设计

- Keep API services stateless so they can scale horizontally behind a load balancer. / API 服务保持无状态，可在负载均衡后横向扩展。
- Put image, OCR, speech, and Agent work into asynchronous queues and independent workers. / 图像、OCR、语音和 Agent 请求进入异步队列，由独立 worker 消费。
- Store media in object storage rather than the database, using CDN and lifecycle policies when needed. / 媒体文件进入对象存储而非数据库，必要时采用 CDN 与生命周期策略。
- Design database access and indexes around `userId`, current-inventory queries, and expiry checks. / 围绕 `userId`、当前库存查询和到期检查设计访问控制与索引。
- Apply timeout, retry, rate-limit, and degradation strategies to external AI services; manual data entry remains available when AI is unavailable. / 对外部 AI 服务设置超时、重试、限流和降级策略；AI 不可用时仍可手动录入。
- Make reminder jobs idempotent: a user should receive at most one successful notification of a given type per day. / 提醒任务必须幂等：同一用户、同种提醒、同一天最多成功发送一次。

## 10. Testing Strategy / 测试策略

| Test level / 层级 | Coverage / 覆盖内容 | Example / 示例 |
| --- | --- | --- |
| Unit tests / 单元测试 | Flutter state/components, backend services, and Agent tool validation / Flutter 状态/组件、后端服务、Agent 工具参数校验 | Expiry calculation; quantity cannot become negative; intent-to-tool mapping / 到期计算、库存不可为负、意图到工具映射 |
| API/integration tests / API 与集成测试 | Authentication, isolation, inventory transactions, media callbacks / 认证、权限隔离、库存事务、媒体回调 | User A cannot read User B's inventory; a draft creates stock only after confirmation / A 用户不能读 B 的库存；草稿确认后才入库 |
| Agent contract tests / Agent 合约测试 | Fixed inputs, structured-output schema, tool allowlist / 固定输入集、结构化输出 schema、工具白名单 | “Used two eggs” yields only a valid consumption draft / “用了两个鸡蛋”仅产生合法消耗草稿 |
| UI/end-to-end tests / UI 与端到端测试 | Critical app and web journeys / App、Web 关键路径 | Register, photo stock-in, confirm, expiry view, manual correction / 注册、拍照入库、确认、查看临期、手动更正 |
| Device/emulator tests / 真机与模拟器测试 | Android/iOS camera, microphone, permissions, notifications / Android/iOS 相机、麦克风、权限和推送 | A user declining microphone permission can still use text input / 拒绝麦克风后仍可文字输入 |
| Performance/reliability tests / 性能与可靠性测试 | Concurrent API requests, bulk upload, scheduled jobs, queue backlog / 并发 API、批量上传、定时任务、队列积压 | Inventory remains queryable during peak load and reminders are deduplicated / 高峰下仍可查库存且提醒不重复 |
| Security tests / 安全测试 | Authorisation, validation, upload controls, relevant OWASP risks / 鉴权、输入校验、上传限制、相关 OWASP 风险 | Broken access control, malicious file, injection, rate limiting / 越权、恶意文件、注入、限流 |

The final demonstration should include at least one complete path: photo or voice input on a real/simulated device → confirmation → stock-in or consumption → synchronised web view → expiry notification.

最终演示至少展示一条完整主线：真实或模拟设备上的照片/语音输入 → 确认 → 入库或消耗 → Web 同步显示 → 到期提醒。

## 11. Cybersecurity and Privacy / 网络安全与隐私

The OWASP Top Ten will be used as a baseline. At minimum, the system will address the following. / 以 OWASP Top Ten 为检查基线，系统至少处理以下问题：

- **Broken access control / 访问控制失效**: Filter every inventory query and mutation by the `userId` derived from authenticated identity; separate administrator and ordinary-user permissions. / 所有库存读写均按认证身份得到的 `userId` 过滤；管理员与普通用户权限分离。
- **Authentication/session risks / 认证与会话风险**: Secure password storage, HTTPS, short-lived access tokens or secure refresh mechanisms, and login rate limits. / 密码安全存储、HTTPS、短期访问令牌或安全刷新机制、登录限流。
- **Injection and validation / 注入与输入校验**: Parameterised database access and schema validation for API input, tool arguments, and file metadata. / 参数化数据库访问；对 API 输入、工具参数和文件元数据进行 schema 校验。
- **Insecure design and AI risks / 不安全设计与 AI 风险**: Allowlisted tools, least privilege, confirmation before writes, and protection against prompt injection crossing permission boundaries. / 工具白名单、最小权限、写前确认，并防止提示词注入突破权限边界。
- **File-upload risks / 文件上传风险**: Restrict MIME type, size, and quantity; scan when feasible; never trust user-provided filenames. / 限制 MIME 类型、大小、数量；条件允许时扫描；不信任用户文件名。
- **Sensitive-data exposure / 敏感数据暴露**: Private media storage with short-lived access URLs; logs must not retain passwords, tokens, or unnecessary receipt content. / 媒体私有存储与短期访问链接；日志不记录密码、令牌或非必要票据内容。
- **Insufficient logging/monitoring / 日志与监控不足**: Record login, access failures, sensitive inventory changes, admin actions, and Agent tool outcomes without excessive data collection. / 记录登录、权限失败、敏感库存变更、管理员操作和 Agent 工具结果，同时避免过度收集。

## 12. Decisions Still Needed / 待小组确认的问题

1. What is the default “soon to expire” threshold, and should it vary by category? / “临期”默认阈值是几天，是否按类别不同？
2. Which cloud/model services will perform receipt, image, and speech recognition, and is a controlled mock fallback acceptable for the course demo? / 小票、图像、语音识别使用哪些云服务或模型；课程演示是否允许受控模拟结果作为备选？
3. When an expiry date cannot be read, should the user enter it, should the system infer a default, or should it remain unknown? / 到期日无法识别时，用户手填、系统规则推断，还是标记为未知？
4. Does initial setup cover only newly purchased items, or also loose/existing household items without a receipt? / 初始建库仅覆盖新购买物品，还是也支持无小票的家中散装/既有物品？
5. Should administrators access raw user images/audio, or only de-identified task status and error information? / 管理员是否可查看用户原始图片/语音，还是只能看脱敏任务状态和错误信息？
6. Which demo flow is the highest priority: receipt/photo stock-in, or voice consumption recording plus reminders? / 演示优先保证哪条主线：小票/拍照入库，还是语音消耗记录加智能提醒？

## 13. Recommended Next Outputs / 建议的后续产出

1. Confirm the open questions and freeze the MVP scope. / 确认待决问题并冻结 MVP 范围。
2. Produce a deployment/architecture diagram covering users, app, user web, admin web, API, Agent, database, and notification service. / 绘制涵盖用户、App、用户 Web、管理员 Web、API、Agent、数据库和通知服务的部署/架构图。
3. Break the MVP into user stories, API contracts, database schema, and iterations. / 将 MVP 拆成 user stories、接口契约、数据库 schema 和迭代计划。
4. Build the smallest end-to-end loop first: voice/text consumption → confirmation → inventory change; then integrate photo, receipt, and reminders. / 优先完成最小端到端闭环：语音/文字消耗 → 确认 → 库存变化；之后接入拍照、小票和提醒。
