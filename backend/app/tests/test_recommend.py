from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_recommend_basic():
    # Using user id 1 (after seeding, or just fallback scoring even if user absent)
    r = client.get("/recommend/user/1?limit=5")
    assert r.status_code == 200
    data = r.json()
    assert isinstance(data, list)
    # Each item should have track_id & score
    if data:
        first = data[0]
        assert "track_id" in first and "score" in first
