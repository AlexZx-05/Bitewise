from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    groq_api_key: SecretStr | None = None
    groq_model: str = "qwen/qwen3.8-27b"
    usda_api_key: SecretStr | None = None
    database_url: str = (
        "postgresql+psycopg://foodscan:foodscan_dev@localhost:5432/foodscan"
    )

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
