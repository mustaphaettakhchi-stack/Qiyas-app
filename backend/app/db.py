from collections.abc import Iterator
from functools import lru_cache

from sqlalchemy import Engine, create_engine, event, text
from sqlalchemy.orm import Session, sessionmaker

from .config import get_settings

ORG_KEY = "organization_id"


@lru_cache
def get_engine() -> Engine:
    return create_engine(get_settings().database_url, pool_pre_ping=True)


@lru_cache
def _session_factory() -> sessionmaker[Session]:
    return sessionmaker(bind=get_engine(), expire_on_commit=False)


def get_db() -> Iterator[Session]:
    with _session_factory()() as session:
        yield session


def bind_organization(session: Session, organization_id: object) -> None:
    """Restreint la session à une organisation pour la sécurité au niveau des lignes (RLS).

    Le réglage PostgreSQL app.org_id est local à la transaction : il est posé pour la
    transaction en cours puis, grâce à l'écouteur ci-dessous, au début de chaque
    transaction suivante de la même session.
    """
    session.info[ORG_KEY] = str(organization_id)
    session.execute(text("SELECT set_config('app.org_id', :org, true)"), {"org": str(organization_id)})


@event.listens_for(Session, "after_begin")
def _apply_org_on_begin(session: Session, transaction, connection) -> None:  # type: ignore[no-untyped-def]
    org = session.info.get(ORG_KEY)
    if org is not None:
        connection.execute(text("SELECT set_config('app.org_id', :org, true)"), {"org": org})
