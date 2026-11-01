"""Toute route non publique doit exiger une session (SECURITY.md §4).

Test « boîte noire » : chaque route décrite par le schéma OpenAPI est appelée sans jeton,
puis avec un jeton invalide ; seules les routes de PUBLIC_ROUTES peuvent répondre autre
chose que 401.
"""

import re
import uuid

from app.main import PUBLIC_ROUTES, app


def _all_routes() -> list[tuple[str, str]]:
    routes = []
    for path, methods in app.openapi()["paths"].items():
        for method in methods:
            routes.append((method.upper(), path))
    return routes


def test_public_routes_list_is_accurate():
    assert PUBLIC_ROUTES <= set(_all_routes()), "PUBLIC_ROUTES cite une route inexistante"


def test_every_private_route_requires_a_session(client):
    private = [r for r in _all_routes() if r not in PUBLIC_ROUTES]
    assert len(private) >= 8  # garde-fou : le schéma n'est pas vide
    failures = []
    for method, path in private:
        url = re.sub(r"\{[^}]+\}", str(uuid.uuid4()), path)
        for headers in ({}, {"Authorization": "Bearer jeton.invalide.xyz"}):
            r = client.request(method, url, json={}, headers=headers)
            if r.status_code != 401:
                failures.append((method, path, headers != {}, r.status_code))
    assert failures == [], f"Routes accessibles sans session valide : {failures}"
