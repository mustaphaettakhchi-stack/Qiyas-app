import uuid

import jwt
import pyotp
import pytest

from app.ids import uuid7
from app.security import (
    ACCESS,
    MFA_SETUP,
    create_jwt,
    decode_jwt,
    hash_backup_code,
    hash_password,
    new_backup_codes,
    password_problems,
    verify_password,
    verify_totp,
)


def test_uuid7_version_and_order():
    a, b = uuid7(), uuid7()
    assert a.version == 7 and b.version == 7
    assert a.variant == uuid.RFC_4122
    assert a.int >> 80 <= b.int >> 80  # horodatage croissant


@pytest.mark.parametrize(
    "password",
    ["court", "motdepasse123", "azertyuiop123", "lamaalam2026!", "000000000000"],
)
def test_weak_passwords_rejected(password):
    assert password_problems(password, ["lamaalam"])


def test_strong_password_accepted():
    assert password_problems("Tanger-chantier-volet-orange-42") == []


def test_password_containing_user_name_is_weakened():
    assert password_problems("BenaliBenali2026", ["benali"])


def test_password_hash_roundtrip():
    h = hash_password("Tanger-chantier-volet-orange-42")
    assert h.startswith("$argon2id$")
    assert verify_password(h, "Tanger-chantier-volet-orange-42")
    assert not verify_password(h, "autre-mot-de-passe-long")
    assert not verify_password(None, "Tanger-chantier-volet-orange-42")


def test_jwt_type_is_enforced():
    token = create_jwt(uuid.uuid4(), MFA_SETUP, 5)
    with pytest.raises(jwt.InvalidTokenError):
        decode_jwt(token, ACCESS)
    assert decode_jwt(token, MFA_SETUP)["typ"] == MFA_SETUP


def test_expired_jwt_rejected():
    token = create_jwt(uuid.uuid4(), ACCESS, -1, sid=str(uuid.uuid4()))
    with pytest.raises(jwt.ExpiredSignatureError):
        decode_jwt(token, ACCESS)


def test_totp_replay_and_format():
    secret = pyotp.random_base32()
    code = pyotp.TOTP(secret).now()
    step = verify_totp(secret, code, None)
    assert step is not None
    assert verify_totp(secret, code, step) is None  # rejeu refusé
    assert verify_totp(secret, "12345", None) is None
    assert verify_totp(secret, "abcdef", None) is None


def test_backup_codes_unique_and_normalized():
    codes = new_backup_codes()
    assert len(codes) == 10 and len(set(codes)) == 10
    c = codes[0]
    assert hash_backup_code(c) == hash_backup_code(c.lower().replace("-", " "))
