"""Connexion SQLite partagée pour tous les collecteurs.

Le fichier de données vit dans data/screentime.db (gitignored), le schéma
dans db/schema.sql (versionné). connect() crée le fichier et applique le
schéma si besoin, donc chaque collecteur peut l'appeler sans setup préalable.
"""

import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = REPO_ROOT / "data" / "screentime.db"
SCHEMA_PATH = REPO_ROOT / "db" / "schema.sql"


def connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(SCHEMA_PATH.read_text())
    return conn


def source_id(conn: sqlite3.Connection, name: str) -> int:
    row = conn.execute("SELECT id FROM sources WHERE name = ?", (name,)).fetchone()
    if row is None:
        raise ValueError(f"unknown source: {name}")
    return row[0]
