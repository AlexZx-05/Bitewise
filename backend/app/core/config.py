from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = (
        "postgresql+psycopg://foodscan:foodscan_dev@localhost:5432/foodscan"
    )

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
