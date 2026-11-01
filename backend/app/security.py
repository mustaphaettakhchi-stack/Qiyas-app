"""Primitives de sécurité : mots de passe, jetons, double authentification TOTP.

Choix documentés dans SECURITY.md §3.
"""

import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pyotp
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from cryptography.fernet import Fernet, InvalidToken
from zxcvbn import zxcvbn

from .config import get_settings

MIN_PASSWORD_LENGTH = 12
MAX_PASSWORD_LENGTH = 128
MIN_PASSWORD_SCORE = 3  # échelle zxcvbn 0–4
BACKUP_CODES_COUNT = 10

_hasher = PasswordHasher()  # Argon2id, paramètres RFC 9106 (profil « faible mémoire »)
# Empreinte factice utilisée quand l'adresse est inconnue, pour que la durée de réponse
# ne révèle pas l'existence du compte.
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))


def now() -> datetime:
    return datetime.now(UTC)


# ---------- mots de passe ----------


def password_problems(password: str, user_inputs: list[str] | None = None) -> list[str]:
    """Liste des raisons pour lesquelles un mot de passe est refusé (vide = accepté)."""
    if len(password) < MIN_PASSWORD_LENGTH:
        return [f"Le mot de passe doit contenir au moins {MIN_PASSWORD_LENGTH} caractères."]
    if len(password) > MAX_PASSWORD_LENGTH:
        return [f"Le mot de passe ne doit pas dépasser {MAX_PASSWORD_LENGTH} caractères."]
    result = zxcvbn(password, user_inputs=[u for u in (user_inputs or []) if u])
    if result["score"] < MIN_PASSWORD_SCORE:
        return [
            "Ce mot de passe est trop facile à deviner. "
            "Utilisez une phrase de plusieurs mots sans lien entre eux."
        ]
    return []


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


# ---------- jetons opaques ----------


def new_opaque_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ---------- JWT ----------

ACCESS = "access"
MFA_SETUP = "mfa_setup"
MFA_VERIFY = "mfa_verify"


def create_jwt(subject: uuid.UUID, typ: str, minutes: int, **claims: object) -> str:
    settings = get_settings()
    issued = now()
    payload = {
        "sub": str(subject),
        "typ": typ,
        "iat": issued,
        "exp": issued + timedelta(minutes=minutes),
        "jti": secrets.token_hex(8),
        **claims,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_jwt(token: str, typ: str) -> dict:
    """Décode et vérifie signature, expiration et type. Lève jwt.InvalidTokenError sinon."""
    payload = jwt.decode(
        token,
        get_settings().jwt_secret,
        algorithms=["HS256"],
        options={"require": ["exp", "iat", "sub", "typ"]},
    )
    if payload.get("typ") != typ:
        raise jwt.InvalidTokenError("type de jeton inattendu")
    return payload


# ---------- TOTP ----------


def _fernet() -> Fernet:
    return Fernet(get_settings().totp_encryption_key.encode())


def new_totp_secret() -> str:
    return pyotp.random_base32()


def encrypt_secret(secret: str) -> str:
    return _fernet().encrypt(secret.encode()).decode()


def decrypt_secret(token: str) -> str:
    try:
        return _fernet().decrypt(token.encode()).decode()
    except InvalidToken as exc:  # clé changée ou donnée corrompue
        raise RuntimeError("Secret TOTP illisible : vérifier LAMAALAM_TOTP_ENCRYPTION_KEY") from exc


def totp_uri(secret: str, email: str) -> str:
    return pyotp.TOTP(secret).provisioning_uri(name=email, issuer_name=get_settings().totp_issuer)


def verify_totp(secret: str, code: str, last_step: int | None) -> int | None:
    """Vérifie un code TOTP (tolérance ± 1 pas de 30 s).

    Renvoie le pas de temps accepté, ou None si le code est faux ou a déjà servi
    (protection contre le rejeu).
    """
    code = code.strip().replace(" ", "")
    if not (len(code) == 6 and code.isdigit()):
        return None
    totp = pyotp.TOTP(secret)
    current = totp.timecode(now())
    for step in (current - 1, current, current + 1):
        if hmac.compare_digest(totp.generate_otp(step), code):
            if last_step is not None and step <= last_step:
                return None
            return step
    return None


# ---------- codes de secours ----------


def new_backup_codes() -> list[str]:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # sans caractères ambigus (I, O, 0, 1)
    codes = []
    for _ in range(BACKUP_CODES_COUNT):
        raw = "".join(secrets.choice(alphabet) for _ in range(10))
        codes.append(f"{raw[:5]}-{raw[5:]}")
    return codes


def hash_backup_code(code: str) -> str:
    normalized = code.strip().upper().replace("-", "").replace(" ", "")
    key = hashlib.sha256(b"lamaalam-backup-code:" + get_settings().jwt_secret.encode()).digest()
    return hmac.new(key, normalized.encode(), hashlib.sha256).hexdigest()
