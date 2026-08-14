-- Screen Time Tracker — schéma SQLite partagé
--
-- Deux façons de mesurer le temps selon la source :
--   - "session"  : on connaît un début et une fin (écran actif sur PC,
--                  prise TV allumée/éteinte) -> table `sessions`.
--   - "counter"  : on ne connaît qu'un total cumulé relevé périodiquement
--                  (playDuration PSN) -> table `counter_snapshots`, le temps
--                  journalier se déduit par delta entre deux relevés.
--
-- Écrit par les collecteurs Python, lu par le dashboard Tauri.

CREATE TABLE IF NOT EXISTS sources (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,      -- 'pc' | 'playstation' | 'tv' | 'iphone'
    kind TEXT NOT NULL              -- 'session' | 'counter'
        CHECK (kind IN ('session', 'counter'))
);

INSERT OR IGNORE INTO sources (name, kind) VALUES
    ('pc', 'session'),
    ('tv', 'session'),
    ('playstation', 'counter');

-- Une session = un intervalle continu d'activité.
-- `entity` précise le contexte quand pertinent (nom de l'app active sur PC,
-- NULL pour la TV où on ne mesure que allumé/éteint).
CREATE TABLE IF NOT EXISTS sessions (
    id               INTEGER PRIMARY KEY,
    source_id        INTEGER NOT NULL REFERENCES sources(id),
    entity           TEXT,
    started_at       INTEGER NOT NULL,   -- unix timestamp (UTC, secondes)
    ended_at         INTEGER,            -- NULL tant que la session est en cours
    duration_seconds INTEGER             -- rempli à la clôture de la session
);

CREATE INDEX IF NOT EXISTS idx_sessions_source_started
    ON sessions (source_id, started_at);

-- Un relevé ponctuel d'un compteur cumulatif (ex: playDuration d'un jeu PSN
-- à l'instant du poll). `entity` = nom du jeu.
CREATE TABLE IF NOT EXISTS counter_snapshots (
    id          INTEGER PRIMARY KEY,
    source_id   INTEGER NOT NULL REFERENCES sources(id),
    entity      TEXT NOT NULL,
    value_seconds INTEGER NOT NULL,      -- valeur cumulée du compteur au relevé
    recorded_at INTEGER NOT NULL         -- unix timestamp (UTC, secondes)
);

CREATE INDEX IF NOT EXISTS idx_counter_snapshots_source_entity_time
    ON counter_snapshots (source_id, entity, recorded_at);
