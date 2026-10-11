from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app import models  # noqa: F401

engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
    Base.metadata.create_all(bind=engine)

    app.dependency_overrides[get_db] = get_test_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)


def get_test_db() -> Generator[Session, None, None]:
    with TestingSessionLocal() as session:
        yield session


@pytest.fixture
def db_session(client: TestClient) -> Generator[Session, None, None]:
    yield from get_test_db()
