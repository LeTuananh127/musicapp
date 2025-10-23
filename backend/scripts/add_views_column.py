"""Small helper to add `views` column to `tracks` table if it doesn't exist.

Run from the repository root (PowerShell) with:

    $env:PYTHONPATH = "$(Get-Location)\backend"; python backend\scripts\add_views_column.py

This script uses the same settings as the app to connect to the DB and will
execute an ALTER TABLE only when the `views` column is not present.
"""
from sqlalchemy import text
from app.core.config import get_settings
from app.core.db import engine


def has_column(column_name: str) -> bool:
    with engine.connect() as conn:
        dialect = conn.dialect.name
        if dialect.startswith("mysql"):
            q = text("SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME='tracks' AND COLUMN_NAME=:col")
        elif dialect == "sqlite":
            q = text("PRAGMA table_info('tracks')")
        else:
            # fallback generic - try selecting the column
            try:
                conn.execute(text(f"SELECT {column_name} FROM tracks LIMIT 1"))
                return True
            except Exception:
                return False

        res = conn.execute(q, {"col": column_name})
        rows = res.fetchall()
        if dialect == "sqlite":
            # pragma returns rows with column name in the 2nd position
            return any(r[1] == column_name for r in rows)
        return len(rows) > 0


def add_views_column():
    with engine.begin() as conn:
        dialect = conn.dialect.name
        if dialect.startswith("mysql"):
            sql = "ALTER TABLE tracks ADD COLUMN views INT DEFAULT 0"
        elif dialect == "sqlite":
            # sqlite doesn't support ADD COLUMN with NOT NULL default easily; use simple add
            sql = "ALTER TABLE tracks ADD COLUMN views INTEGER DEFAULT 0"
        else:
            sql = "ALTER TABLE tracks ADD COLUMN views INTEGER DEFAULT 0"
        print("Executing:", sql)
        conn.execute(text(sql))


if __name__ == "__main__":
    settings = get_settings()
    print("Using DB:", settings.database_url)
    if has_column("views"):
        print("Column 'views' already exists on 'tracks' — nothing to do.")
    else:
        print("Column 'views' not found, adding...")
        add_views_column()
        print("Done. Restart the API if needed.")
