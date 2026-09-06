import os


# 测试进程显式覆盖全部必需配置，既不依赖也不改写本机真实 .env。
os.environ["DATABASE_URL"] = (
    "postgresql+psycopg://test_user@localhost/sayfridge_test"
)
os.environ["DATABASE_URL_DIRECT"] = (
    "postgresql+psycopg://test_user@localhost/sayfridge_test"
)
os.environ["JWT_SECRET_KEY"] = "s" * 40
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "15"
