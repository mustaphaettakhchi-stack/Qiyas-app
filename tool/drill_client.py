"""Client de l'exercice de restauration (tool/restore_drill.sh).

Exécuté DANS le conteneur de l'API (python - seed|verify < tool/drill_client.py) : il n'a
besoin que de la bibliothèque standard et de pyotp, déjà présents dans l'image.

  seed    : connexion de l'administrateur, mise en place de la double authentification,
            un client, un projet, une photo partagée et un message ; affiche l'état en JSON.
  verify  : à partir de cet état (JSON sur la ligne de commande), après restauration :
            connexion avec le MÊME secret de double authentification, projet retrouvé,
            fichier identique octet pour octet, restauration inscrite au journal.
"""

import base64
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
import uuid

import pyotp

API = "http://127.0.0.1:8000/api/v1"
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAE0lEQVR4nGP81MOAFTBhFx6sEgAvfQGObY7uZgAAAABJRU5ErkJggg=="
)


def call(method, path, body=None, token=None, raw=False, headers=None):
    h = dict(headers or {})
    data = None
    if body is not None and not isinstance(body, bytes):
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    elif body is not None:
        data = body
    if token:
        h["Authorization"] = f"Bearer {token}"
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            payload = r.read()
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} -> {e.code} {e.read()[:300]!r}")
    return payload if raw else (json.loads(payload) if payload else None)


def fresh_code(secret, used_step=None):
    """Code TOTP d'un pas de 30 s pas encore utilisé (le serveur refuse le rejeu)."""
    while used_step is not None and int(time.time()) // 30 <= used_step:
        time.sleep(1)
    return pyotp.TOTP(secret).now(), int(time.time()) // 30


def multipart(fields, filename, content):
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n".encode() + content + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), {"Content-Type": f"multipart/form-data; boundary={boundary}"}


def seed(email, password):
    r = call("POST", "/auth/login", {"email": email, "password": password})
    assert r["mfa_setup_required"], r
    secret = call("POST", "/auth/mfa/setup", {"mfa_token": r["mfa_token"]})["secret"]
    code, step = fresh_code(secret)
    tok = call("POST", "/auth/mfa/confirm", {"mfa_token": r["mfa_token"], "code": code})["tokens"]["access_token"]

    from app.ids import uuid7  # disponible dans l'image

    cid, pid = str(uuid7()), str(uuid7())
    changes = [
        {"entity": "clients", "id": cid, "base_version": None, "deleted": False,
         "data": {"display_name": "Client de l'exercice", "phone": "0661000000", "city": "Tanger"}},
        {"entity": "projects", "id": pid, "base_version": None, "deleted": False,
         "data": {"client_id": cid, "name": "Projet de l'exercice", "site_city": "Tanger"}},
    ]
    res = call("POST", "/sync/push", {"changes": changes}, token=tok)["results"]
    assert all(x["status"] == "applied" for x in res), res
    body, h = multipart({"project_id": pid, "kind": "photo", "visible_to_client": "true", "caption": "Exercice"},
                        "photo.png", PNG)
    f = call("POST", "/files", body, token=tok, headers=h)
    call("POST", f"/projects/{pid}/messages", {"body": "Message de l'exercice"}, token=tok)
    original = call("GET", call("GET", f"/files/{f['id']}/link", token=tok)["url"].replace("/api/v1", ""), raw=True)
    return {"email": email, "password": password, "secret": secret, "step": step, "client_id": cid,
            "project_id": pid, "file_id": f["id"], "sha256": hashlib.sha256(original).hexdigest()}


def verify(state):
    r = call("POST", "/auth/login", {"email": state["email"], "password": state["password"]})
    assert r["mfa_required"], r
    code, _ = fresh_code(state["secret"], state["step"])
    tok = call("POST", "/auth/mfa/verify", {"mfa_token": r["mfa_token"], "code": code})["access_token"]
    records = call("GET", "/sync/pull?cursor=0", token=tok)["records"]
    ids = {x["id"] for x in records}
    assert state["project_id"] in ids and state["client_id"] in ids, "projet ou client absent après restauration"
    data = call("GET", call("GET", f"/files/{state['file_id']}/link", token=tok)["url"].replace("/api/v1", ""), raw=True)
    assert hashlib.sha256(data).hexdigest() == state["sha256"], "fichier différent après restauration"
    msgs = call("GET", f"/projects/{state['project_id']}/messages", token=tok)
    assert [m["body"] for m in msgs] == ["Message de l'exercice"], msgs
    actions = [a["action"] for a in call("GET", "/dashboard/activity?limit=50", token=tok)]
    assert "backup.restore" in actions, actions
    return {"ok": True, "records": len(records)}


if __name__ == "__main__":
    if sys.argv[1] == "seed":
        print(json.dumps(seed(sys.argv[2], sys.argv[3])))
    else:
        print(json.dumps(verify(json.loads(sys.argv[2]))))
