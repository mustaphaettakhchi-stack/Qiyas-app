"""Point d'entrée de l'API LAMAALAM."""

import logging
import uuid

from fastapi import APIRouter, Depends, FastAPI, Request
from sqlalchemy import text
from sqlalchemy.orm import Session

from .config import get_settings
from .db import get_db
from .routes import auth, users

API_PREFIX = "/api/v1"

# Routes accessibles sans session. Toute autre route doit dépendre de deps.get_context
# (vérifié par tests/test_routes_security.py).
PUBLIC_ROUTES = frozenset(
    {
        ("GET", f"{API_PREFIX}/health"),
        ("POST", f"{API_PREFIX}/auth/login"),
        ("POST", f"{API_PREFIX}/auth/mfa/setup"),
        ("POST", f"{API_PREFIX}/auth/mfa/confirm"),
        ("POST", f"{API_PREFIX}/auth/mfa/verify"),
        ("POST", f"{API_PREFIX}/auth/refresh"),
        ("POST", f"{API_PREFIX}/invitations/accept"),
    }
)

health = APIRouter(tags=["exploitation"])


@health.get("/health")
def health_check(db: Session = Depends(get_db)) -> dict:
    db.execute(text("select 1"))
    return {"status": "ok"}


def create_app() -> FastAPI:
    settings = get_settings()
    logging.basicConfig(level=logging.INFO)
    app = FastAPI(
        title="API LAMAALAM",
        version="0.1.0",
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_production else "/openapi.json",
    )

    @app.middleware("http")
    async def request_id(request: Request, call_next):  # type: ignore[no-untyped-def]
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex
        response = await call_next(request)
        response.headers["X-Request-ID"] = rid[:64]
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    app.include_router(health, prefix=API_PREFIX)
    app.include_router(auth.router, prefix=API_PREFIX)
    app.include_router(users.router, prefix=API_PREFIX)
    return app


app = create_app()
