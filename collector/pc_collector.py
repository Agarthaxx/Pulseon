"""Collecteur PC.

Un poll = un instantané : app active + temps d'inactivité. Pensé pour être
invoqué à intervalle régulier par launchd (pas de boucle interne), il
maintient une session ouverte par app dans la table `sessions` et la
ferme dès que l'app change ou que l'utilisateur devient inactif.
"""

import sqlite3
import time

import Quartz
from AppKit import NSWorkspace

import db

IDLE_THRESHOLD_SECONDS = 120  # au-delà, on considère l'utilisateur inactif


def active_app_name() -> str | None:
    app = NSWorkspace.sharedWorkspace().frontmostApplication()
    return app.localizedName() if app else None


def idle_seconds() -> float:
    return Quartz.CGEventSourceSecondsSinceLastEventType(
        Quartz.kCGEventSourceStateHIDSystemState, Quartz.kCGAnyInputEventType
    )


def poll(conn: sqlite3.Connection) -> None:
    now = int(time.time())
    src_id = db.source_id(conn, "pc")
    open_session = conn.execute(
        "SELECT id, entity, started_at FROM sessions "
        "WHERE source_id = ? AND ended_at IS NULL",
        (src_id,),
    ).fetchone()

    is_active = idle_seconds() < IDLE_THRESHOLD_SECONDS
    app = active_app_name() if is_active else None

    if open_session:
        open_id, open_entity, started_at = open_session
        if is_active and app == open_entity:
            return  # session en cours, rien à changer
        conn.execute(
            "UPDATE sessions SET ended_at = ?, duration_seconds = ? WHERE id = ?",
            (now, now - started_at, open_id),
        )

    if is_active and app:
        conn.execute(
            "INSERT INTO sessions (source_id, entity, started_at) VALUES (?, ?, ?)",
            (src_id, app, now),
        )
    conn.commit()


def main() -> None:
    conn = db.connect()
    try:
        poll(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
