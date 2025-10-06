from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_register_and_login():
    # Register
    payload = {"username": "testuser", "email": "testuser@example.com", "password": "secret123"}
    r = client.post("/auth/register", json=payload)
    assert r.status_code in (200, 400)  # 400 if already exists from previous run

    # Login
    r2 = client.post("/auth/login", data={"username": payload["username"], "password": payload["password"]})
    assert r2.status_code == 200, r2.text
    data = r2.json()
    assert "access_token" in data
    assert data.get("token_type") == "bearer"
