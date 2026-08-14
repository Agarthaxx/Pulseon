//! Lecture seule de la base remplie par les collecteurs Python.
//!
//! Le SQL vit ici plutôt que dans le frontend : les requêtes d'agrégation
//! restent côté Rust et le frontend ne reçoit que des structures typées.

use std::path::PathBuf;

use chrono::{Duration, Local, NaiveDate, TimeZone};
use rusqlite::Connection;
use serde::Serialize;

pub fn db_path() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME is always set on macOS");
    PathBuf::from(home)
        .join("Library/Application Support/Pulseon")
        .join("screentime.db")
}

fn open() -> Result<Connection, String> {
    Connection::open(db_path()).map_err(|e| e.to_string())
}

/// Une source dont les sessions ont un début et une fin ('session') peut être
/// tracée précisément sur la timeline. Une source à compteur cumulatif
/// ('counter', la PlayStation) ne connaît qu'un total journalier : le frontend
/// l'affiche différemment plutôt que d'inventer un placement horaire.
#[derive(Serialize)]
pub struct Block {
    pub entity: Option<String>,
    /// Secondes écoulées depuis minuit local.
    pub start_offset: i64,
    pub duration: i64,
}

#[derive(Serialize)]
pub struct EntityTotal {
    pub entity: String,
    pub seconds: i64,
}

#[derive(Serialize)]
pub struct Lane {
    pub source: String,
    pub kind: String,
    pub total_seconds: i64,
    pub blocks: Vec<Block>,
    pub top_entities: Vec<EntityTotal>,
    /// Faux quand la source n'a jamais rien écrit — le frontend distingue
    /// "journée à zéro" de "collecteur pas encore branché".
    pub connected: bool,
}

#[derive(Serialize)]
pub struct DayView {
    pub date: String,
    pub lanes: Vec<Lane>,
    pub total_seconds: i64,
}

fn local_day_bounds(date: NaiveDate) -> (i64, i64) {
    let start = Local
        .from_local_datetime(&date.and_hms_opt(0, 0, 0).unwrap())
        .earliest()
        .expect("valid local midnight");
    let end = start + Duration::days(1);
    (start.timestamp(), end.timestamp())
}

fn sources(conn: &Connection) -> Result<Vec<(i64, String, String)>, String> {
    let mut stmt = conn
        .prepare("SELECT id, name, kind FROM sources ORDER BY id")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

fn session_lane(
    conn: &Connection,
    source_id: i64,
    day_start: i64,
    day_end: i64,
) -> Result<(Vec<Block>, i64), String> {
    let mut stmt = conn
        .prepare(
            "SELECT entity, started_at, COALESCE(ended_at, ?3) \
             FROM sessions \
             WHERE source_id = ?1 AND started_at < ?3 \
               AND COALESCE(ended_at, ?3) > ?2 \
             ORDER BY started_at",
        )
        .map_err(|e| e.to_string())?;

    let now = Local::now().timestamp();
    // Une session encore ouverte est bornée à maintenant, pas à minuit :
    // sinon une journée en cours afficherait du temps pas encore écoulé.
    let open_end = now.min(day_end);

    let rows = stmt
        .query_map([source_id, day_start, open_end], |r| {
            let entity: Option<String> = r.get(0)?;
            let started: i64 = r.get(1)?;
            let ended: i64 = r.get(2)?;
            Ok((entity, started, ended))
        })
        .map_err(|e| e.to_string())?;

    let mut blocks = Vec::new();
    let mut total = 0i64;
    for row in rows {
        let (entity, started, ended) = row.map_err(|e| e.to_string())?;
        // Une session à cheval sur minuit est tronquée aux bornes du jour.
        let clamped_start = started.max(day_start);
        let clamped_end = ended.min(open_end);
        let duration = clamped_end - clamped_start;
        if duration <= 0 {
            continue;
        }
        total += duration;
        blocks.push(Block {
            entity,
            start_offset: clamped_start - day_start,
            duration,
        });
    }
    Ok((blocks, total))
}

fn counter_lane(
    conn: &Connection,
    source_id: i64,
    day_start: i64,
    day_end: i64,
) -> Result<(Vec<EntityTotal>, i64), String> {
    // Le compteur est cumulatif : le temps du jour est la progression entre le
    // dernier relevé d'avant minuit et le dernier relevé du jour.
    let mut stmt = conn
        .prepare(
            "SELECT entity, \
                MAX(CASE WHEN recorded_at < ?3 THEN value_seconds END) \
              - COALESCE( \
                  (SELECT c2.value_seconds FROM counter_snapshots c2 \
                    WHERE c2.source_id = c.source_id AND c2.entity = c.entity \
                      AND c2.recorded_at < ?2 \
                    ORDER BY c2.recorded_at DESC LIMIT 1), \
                  MIN(CASE WHEN recorded_at >= ?2 THEN value_seconds END)) \
             FROM counter_snapshots c \
             WHERE source_id = ?1 AND recorded_at < ?3 \
             GROUP BY entity",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([source_id, day_start, day_end], |r| {
            let entity: String = r.get(0)?;
            let delta: Option<i64> = r.get(1)?;
            Ok((entity, delta.unwrap_or(0)))
        })
        .map_err(|e| e.to_string())?;

    let mut totals = Vec::new();
    let mut total = 0i64;
    for row in rows {
        let (entity, delta) = row.map_err(|e| e.to_string())?;
        if delta <= 0 {
            continue;
        }
        total += delta;
        totals.push(EntityTotal {
            entity,
            seconds: delta,
        });
    }
    totals.sort_by(|a, b| b.seconds.cmp(&a.seconds));
    Ok((totals, total))
}

fn has_any_data(conn: &Connection, source_id: i64, kind: &str) -> Result<bool, String> {
    let sql = match kind {
        "counter" => "SELECT EXISTS(SELECT 1 FROM counter_snapshots WHERE source_id = ?1)",
        _ => "SELECT EXISTS(SELECT 1 FROM sessions WHERE source_id = ?1)",
    };
    conn.query_row(sql, [source_id], |r| r.get(0))
        .map_err(|e| e.to_string())
}

fn top_entities(blocks: &[Block]) -> Vec<EntityTotal> {
    let mut totals: std::collections::HashMap<&str, i64> = std::collections::HashMap::new();
    for b in blocks {
        if let Some(name) = b.entity.as_deref() {
            *totals.entry(name).or_insert(0) += b.duration;
        }
    }
    let mut out: Vec<EntityTotal> = totals
        .into_iter()
        .map(|(entity, seconds)| EntityTotal {
            entity: entity.to_string(),
            seconds,
        })
        .collect();
    out.sort_by(|a, b| b.seconds.cmp(&a.seconds));
    out.truncate(6);
    out
}

pub fn day_view(date_str: &str) -> Result<DayView, String> {
    let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d").map_err(|e| e.to_string())?;
    let (day_start, day_end) = local_day_bounds(date);
    let conn = open()?;

    let mut lanes = Vec::new();
    let mut grand_total = 0i64;

    for (id, name, kind) in sources(&conn)? {
        let connected = has_any_data(&conn, id, &kind)?;
        let (blocks, top, total) = if kind == "counter" {
            let (totals, total) = counter_lane(&conn, id, day_start, day_end)?;
            (Vec::new(), totals, total)
        } else {
            let (blocks, total) = session_lane(&conn, id, day_start, day_end)?;
            let top = top_entities(&blocks);
            (blocks, top, total)
        };
        grand_total += total;
        lanes.push(Lane {
            source: name,
            kind,
            total_seconds: total,
            blocks,
            top_entities: top,
            connected,
        });
    }

    Ok(DayView {
        date: date_str.to_string(),
        lanes,
        total_seconds: grand_total,
    })
}
