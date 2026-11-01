"""Point d'entrée de l'API LAMAALAM."""

import logging
import uuid

from fastapi import APIRouter, Depends, FastAPI, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from .config import get_settings
from .db import get_db
from .routes import auth, client_space, dashboard, files, library, sync, users

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
        ("POST", f"{API_PREFIX}/password-reset/accept"),
        # Lien signé à durée limitée (15 min), lié à l'utilisateur : la signature tient lieu de session.
        ("GET", f"{API_PREFIX}/files/download/{{file_id}}"),
    }
)

health = APIRouter(tags=["exploitation"])


@health.get("/health")
def health_check(db: Session = Depends(get_db)) -> dict:
    db.execute(text("select 1"))
    return {"status": "ok"}


INVITATION_PAGE = """<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Lien LAMAALAM</title>
<style>body{font-family:sans-serif;background:#151515;color:#fff;max-width:32rem;margin:2rem auto;padding:1rem;line-height:1.5}
h1{color:#F28C00;font-size:1.4rem}</style></head>
<body><h1>Lien LAMAALAM</h1>
<p>Ce lien (invitation ou nouveau mot de passe) s'utilise dans l'application LAMAALAM, pas dans le navigateur.</p>
<ol><li>Copiez l'adresse complète de cette page.</li>
<li>Ouvrez l'application LAMAALAM et touchez « J'ai reçu un lien ».</li>
<li>Collez le lien et choisissez votre mot de passe.</li></ol>
<p>Le lien est personnel, à durée limitée et utilisable une seule fois.</p></body></html>"""


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

    @app.get("/invitation", response_class=HTMLResponse, include_in_schema=False)
    @app.get("/reinitialisation", response_class=HTMLResponse, include_in_schema=False)
    def invitation_page() -> str:
        # Le jeton est dans le fragment (#…) : il n'est jamais transmis au serveur.
        return INVITATION_PAGE

    app.include_router(health, prefix=API_PREFIX)
    app.include_router(auth.router, prefix=API_PREFIX)
    app.include_router(users.router, prefix=API_PREFIX)
    app.include_router(sync.router, prefix=API_PREFIX)
    app.include_router(library.router, prefix=API_PREFIX)
    app.include_router(dashboard.router, prefix=API_PREFIX)
    app.include_router(files.router, prefix=API_PREFIX)
    app.include_router(client_space.router, prefix=API_PREFIX)
    return app


app = create_app()
