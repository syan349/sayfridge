# SayFridge Backend

SayFridge 的 FastAPI 后端。当前版本提供健康检查、基础本地邮箱密码认证，以及 Neon PostgreSQL、SQLAlchemy 2.x ORM 和 Alembic 迁移基础设施；库存 CRUD、Agent、Worker 等业务功能尚未实现。

## 环境要求

- Python 3.11

## Windows 本地运行

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
uvicorn app.main:app --reload
```

服务启动后可访问：

- 健康检查：`GET http://127.0.0.1:8000/health`
- 注册：`POST http://127.0.0.1:8000/api/v1/auth/register`
- 登录：`POST http://127.0.0.1:8000/api/v1/auth/login`
- 当前用户：`GET http://127.0.0.1:8000/api/v1/auth/me`
- API 文档：`http://127.0.0.1:8000/docs`

## 认证配置

- `JWT_SECRET_KEY`：HS256 签名密钥，至少 32 个字符，只能保存在本机或部署环境中；
- `ACCESS_TOKEN_EXPIRE_MINUTES`：Access Token 有效分钟数，默认 `15`。

认证仅支持本地邮箱密码、短期 Bearer Access Token。当前没有 Refresh Token、服务端会话、Logout、第三方登录、邮箱验证、密码恢复或 MFA。

## 数据库配置与迁移

复制 `.env.example` 为 `.env`，只在本机填写真实连接信息：

- `DATABASE_URL`：FastAPI 运行时使用的 Neon 池化连接；
- `DATABASE_URL_DIRECT`：Alembic 使用的 Neon 直连地址。

两个地址都必须使用 `postgresql+psycopg://` 前缀。`.env` 已被 Git 忽略，禁止把连接串或密码写入代码、迁移或文档。

```powershell
# 查看当前迁移版本
alembic current

# 应用所有迁移
alembic upgrade head

# 检查 ORM 与数据库是否还有未生成的差异
alembic check
```

首份迁移创建设计文档规定的八张表。后续修改模型时必须同时生成并提交新的迁移，不在 Neon SQL Editor 手工改表。

## 测试

```powershell
python -m pytest
```
