"""Configuration lue dans les variables d'environnement préfixées LAMAALAM_.

Aucun secret n'a de valeur par défaut : le serveur refuse de démarrer s'il manque.
"""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="LAMAALAM_", env_file=".env", extra="ignore")

    environment: str = Field(default="development", pattern="^(development|test|production)$")
    database_url: str
    jwt_secret: str = Field(min_length=32)
    totp_encryption_key: str = Field(min_length=44)  # clé Fernet (32 octets en base64 url)

    access_token_minutes: int = 15
    refresh_token_days: int = 30
    mfa_token_minutes: int = 5
    invitation_hours: int = 72
    max_failed_logins: int = 5
    totp_issuer: str = "LAMAALAM"

    public_base_url: str = "http://localhost:8000"

    # Dossier des fichiers (photos partagées, PDF de devis), hors de toute racine web.
    files_dir: str = "/var/lib/lamaalam/files"
    max_upload_bytes: int = 15 * 1024 * 1024
    file_link_minutes: int = 15

    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_from: str | None = None

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @property
    def smtp_configured(self) -> bool:
        return bool(self.smtp_host and self.smtp_from)


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
