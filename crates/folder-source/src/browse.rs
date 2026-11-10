//! Read-only browse projection. Transfer receipts and gallery publication stay distinct.
use super::*;
use std::collections::BTreeMap;

pub fn unsupported_kind(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?.to_ascii_lowercase();
    matches!(
        ext.as_str(),
        "bmp"
            | "avif"
            | "jxl"
            | "jp2"
            | "j2k"
            | "psd"
            | "psb"
            | "cr2"
            | "cr3"
            | "nef"
            | "nrw"
            | "arw"
            | "srf"
            | "sr2"
            | "raf"
            | "orf"
            | "rw2"
            | "rwl"
            | "dng"
            | "pef"
            | "ptx"
            | "srw"
            | "3fr"
            | "fff"
            | "iiq"
            | "kdc"
            | "dcr"
            | "x3f"
    )
    .then_some(ext)
}
#[derive(Debug, Clone, Default, Serialize)]
pub struct Observation {
    pub state: String,
    pub saved_at_ms: Option<u64>,
}
#[derive(Debug, Serialize)]
pub struct BrowseEntry {
    #[serde(flatten)]
    pub entry: Entry,
    pub folder_id: String,
    pub capture_ms: u64,
    pub date_source: String,
    pub backup: String,
    pub saved_at_ms: Option<u64>,
}
/// Supported media split; non-video supported formats retain the photo vocabulary.
#[derive(Debug, Clone, Copy, Default, Serialize, PartialEq, Eq)]
pub struct MediaCounts {
    pub photos: u64,
    pub videos: u64,
}
impl MediaCounts {
    pub(crate) fn record(&mut self, mime: &str) {
        if mime.starts_with("video/") {
            self.videos += 1;
        } else {
            self.photos += 1;
        }
    }
}
#[derive(Debug, Default, Serialize, PartialEq, Eq)]
pub struct DeliveryProgress {
    pub delivered: u64,
    pub total: u64,
}

#[derive(Debug, Default, Serialize)]
pub struct FolderFacts {
    pub supported: u64,
    pub supported_kinds: MediaCounts,
    pub saved: u64,
    pub saved_kinds: MediaCounts,
    pub in_flight: u64,
    pub in_flight_kinds: MediaCounts,
    pub in_flight_bytes: u64,
    pub needs_you: u64,
    pub needs_you_kinds: MediaCounts,
    pub not_backed_up: u64,
    pub not_backed_up_kinds: MediaCounts,
    pub available: Option<bool>,
    pub unsupported_by_kind: BTreeMap<String, u64>,
}
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BrowseFilter {
    #[default]
    All,
    NotBackedUp,
    NeedsYou,
    Recent,
}
#[derive(Debug, Clone, Copy, Default, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BrowseMediaKind {
    #[default]
    All,
    Photo,
    Video,
    // File inventory currently exposes independent stills and clips.
    Motion,
    Burst,
}

#[derive(Default)]
pub struct BrowseQuery<'a> {
    pub source: Option<&'a str>,
    pub receiver: &'a str,
    pub search: &'a str,
    pub filter: BrowseFilter,
    pub kind: BrowseMediaKind,
    pub since_ms: u64,
}

/// Complete metadata membership for one browse query.
#[derive(Debug, Serialize)]
pub struct BrowseResult {
    pub rows: Vec<BrowseEntry>,
}
impl Index {
    /// Availability is an explicit host filesystem observation, retained by the core.
    pub fn set_available(&self, source: &str, available: bool) -> Result<()> {
        self.conn.execute("INSERT INTO folder_availability VALUES(?1,?2) ON CONFLICT(source) DO UPDATE SET available=excluded.available WHERE available<>excluded.available", params![source,available]).map_err(db)?;
        Ok(())
    }
    pub fn unsupported(&self, source: &str) -> Result<BTreeMap<String, u64>> {
        self.conn.prepare("SELECT kind,COUNT(*) FROM unsupported_media WHERE source=?1 AND present=1 GROUP BY kind").map_err(db)?
            .query_map([source], |r| Ok((r.get(0)?,r.get::<_,i64>(1)? as u64))).map_err(db)?
            .collect::<std::result::Result<_,_>>().map_err(db)
    }
    pub fn record_date(
        &self,
        source: &str,
        relative: &str,
        revision: &str,
        capture_ms: u64,
        embedded: bool,
    ) -> Result<()> {
        let entry = self.entry(source, relative)?;
        if entry.revision != revision {
            return Err(Error::Conflict("folder metadata changed".into()));
        }
        self.conn.execute("INSERT INTO media_dates VALUES(?1,?2,?3,?4,?5) ON CONFLICT(source,relative) DO UPDATE SET revision=excluded.revision,capture_ms=excluded.capture_ms,date_source=excluded.date_source", params![source,relative,revision,capture_ms as i64,if embedded {"embedded"} else {"file_modified"}]).map_err(db)?;
        Ok(())
    }
    pub fn undated(&self, source: &str) -> Result<Vec<Entry>> {
        let mut stmt = self.conn.prepare("SELECT relative FROM files f WHERE source=?1 AND present=1 AND NOT EXISTS(SELECT 1 FROM media_dates d WHERE d.source=f.source AND d.relative=f.relative AND d.revision=f.revision) ORDER BY modified DESC,relative LIMIT 8").map_err(db)?;
        let paths = stmt
            .query_map([source], |r| r.get::<_, String>(0))
            .map_err(db)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db)?;
        paths.into_iter().map(|p| self.entry(source, &p)).collect()
    }
    /// Walk the inventory in query order. Summaries reduce the rows in place.
    fn visit(
        &self,
        query: &BrowseQuery<'_>,
        ordered: bool,
        mut observe: impl FnMut(i64) -> Result<Observation>,
        mut visit: impl FnMut(BrowseEntry),
    ) -> Result<()> {
        let source = if query.source.is_some() {
            "AND f.source=?1"
        } else {
            "AND ?1 IS NULL"
        };
        let kind = match query.kind {
            BrowseMediaKind::All => "",
            BrowseMediaKind::Photo => "AND f.mime NOT GLOB 'video/*'",
            BrowseMediaKind::Video => "AND f.mime GLOB 'video/*'",
            BrowseMediaKind::Motion | BrowseMediaKind::Burst => return Ok(()),
        };
        let order = if ordered {
            "ORDER BY capture_ms DESC,f.source,f.relative"
        } else {
            ""
        };
        let mut stmt = self.conn.prepare(&format!(
            "SELECT f.source,f.relative,f.identity,f.revision,f.size,f.mime,f.modified,
                (SELECT job FROM submitted s WHERE s.source=f.source AND s.identity=f.identity AND s.receiver=?2 AND s.revision=f.revision),
                COALESCE(d.capture_ms,f.modified) AS capture_ms,COALESCE(d.date_source,'file_modified'),
                EXISTS(SELECT 1 FROM ignored i WHERE i.source=f.source AND i.relative=f.relative AND i.revision=f.revision AND i.until_ms=0),
                EXISTS(SELECT 1 FROM selected_requests q WHERE q.source=f.source AND q.relative=f.relative AND q.revision=f.revision AND q.receiver=?2),
                EXISTS(SELECT 1 FROM selected_requests q WHERE q.source=f.source AND q.relative=f.relative AND q.revision=f.revision AND q.receiver=?2 AND q.repeat_job IS NOT NULL)
            FROM files f LEFT JOIN media_dates d ON d.source=f.source AND d.relative=f.relative AND d.revision=f.revision
            WHERE f.present=1 {source} {kind} AND (?3='' OR instr(lower(f.relative),lower(?3))>0)
                AND NOT EXISTS(SELECT 1 FROM files g INDEXED BY folder_identity
                    WHERE g.source=f.source AND g.identity=f.identity AND g.present=1 AND g.relative<f.relative)
            {order}"
        )).map_err(db)?;
        let mut rows = stmt
            .query(params![query.source, query.receiver, query.search])
            .map_err(db)?;
        while let Some(r) = rows.next().map_err(db)? {
            let folder_id: String = r.get(0).map_err(db)?;
            let job_id: Option<i64> = r.get(7).map_err(db)?;
            let ignored: bool = r.get(10).map_err(db)?;
            let observation = match job_id.filter(|id| *id > 0) {
                Some(id) => observe(id)?,
                None => Observation::default(),
            };
            let backup = if r.get::<_, bool>(12).map_err(db)? {
                "sending"
            } else if observation.state.is_empty() {
                if r.get::<_, bool>(11).map_err(db)? {
                    "sending"
                } else if ignored {
                    "needs_you"
                } else {
                    "not_backed_up"
                }
            } else {
                &observation.state
            };
            let entry = BrowseEntry {
                entry: Entry {
                    relative: r.get(1).map_err(db)?,
                    source_id: asset_id(&folder_id, &r.get::<_, String>(2).map_err(db)?),
                    revision: r.get(3).map_err(db)?,
                    size: r.get::<_, i64>(4).map_err(db)? as u64,
                    media_type: r.get(5).map_err(db)?,
                    modified_ms: r.get::<_, i64>(6).map_err(db)? as u64,
                    job_id,
                },
                folder_id,
                capture_ms: r.get::<_, i64>(8).map_err(db)? as u64,
                date_source: r.get(9).map_err(db)?,
                backup: backup.to_owned(),
                saved_at_ms: observation.saved_at_ms,
            };
            visit(entry);
        }
        Ok(())
    }
    /// Count indexed originals in the source's backup scope. A paired photo and
    /// clip share one receipt but advance two files. Do not read a partial scan.
    pub fn delivery_progress(
        &self,
        source: &str,
        receiver: &str,
        max_created_ms: Option<u64>,
        mut received: impl FnMut(i64) -> Result<bool>,
    ) -> Result<Option<DeliveryProgress>> {
        if self.scan.as_ref().is_some_and(|scan| scan.source == source) {
            return Ok(None);
        }
        let mut statement = self
            .conn
            .prepare_cached(
                "WITH scope AS (
                SELECT DISTINCT f.identity,f.revision,s.job
                FROM files f
                LEFT JOIN submitted s ON s.source=f.source AND s.identity=f.identity
                    AND s.receiver=?2 AND s.revision=f.revision AND s.job>0
                WHERE f.source=?1 AND f.present=1 AND (?3 IS NULL OR f.created<=?3)
                    AND NOT EXISTS(SELECT 1 FROM dismissed d WHERE d.source=f.source
                        AND d.relative=f.relative AND d.revision=f.revision)
                    AND NOT EXISTS(SELECT 1 FROM ignored i WHERE i.source=f.source
                        AND i.relative=f.relative AND i.revision=f.revision AND i.until_ms=0)
                    AND (s.job IS NOT NULL OR NOT EXISTS(SELECT 1 FROM submitted b
                        WHERE b.source=f.source AND b.identity=f.identity AND b.revision=f.revision
                        AND b.receiver IN (?2,'@baseline') AND b.job=0))
            ) SELECT job,COUNT(*) FROM scope GROUP BY job",
            )
            .map_err(db)?;
        let rows = statement
            .query_map(
                params![source, receiver, max_created_ms.map(|value| value as i64)],
                |row| Ok((row.get::<_, Option<i64>>(0)?, row.get::<_, i64>(1)? as u64)),
            )
            .map_err(db)?;
        let mut progress = DeliveryProgress::default();
        for row in rows {
            let (job, count) = row.map_err(db)?;
            progress.total += count;
            if let Some(job) = job {
                if received(job)? {
                    progress.delivered += count;
                }
            }
        }
        Ok(Some(progress))
    }

    pub fn facts(
        &self,
        source: &str,
        receiver: &str,
        observe: impl FnMut(i64) -> Result<Observation>,
    ) -> Result<FolderFacts> {
        let mut facts = FolderFacts {
            available: self
                .conn
                .query_row(
                    "SELECT available FROM folder_availability WHERE source=?1",
                    [source],
                    |r| r.get(0),
                )
                .optional()
                .map_err(db)?,
            unsupported_by_kind: self.unsupported(source)?,
            ..Default::default()
        };
        let query = BrowseQuery {
            source: Some(source),
            receiver,
            ..Default::default()
        };
        self.visit(&query, false, observe, |row| {
            facts.supported += 1;
            facts.supported_kinds.record(&row.entry.media_type);
            match row.backup.as_str() {
                "saved" => {
                    facts.saved += 1;
                    facts.saved_kinds.record(&row.entry.media_type);
                }
                "needs_you" => {
                    facts.needs_you += 1;
                    facts.needs_you_kinds.record(&row.entry.media_type);
                }
                "sending" | "saving" => {
                    facts.in_flight += 1;
                    facts.in_flight_kinds.record(&row.entry.media_type);
                    facts.in_flight_bytes += row.entry.size;
                }
                _ => {
                    facts.not_backed_up += 1;
                    facts.not_backed_up_kinds.record(&row.entry.media_type);
                }
            }
        })?;
        Ok(facts)
    }
    pub fn browse(
        &self,
        query: BrowseQuery<'_>,
        observe: impl FnMut(i64) -> Result<Observation>,
    ) -> Result<BrowseResult> {
        let mut rows = Vec::new();
        self.visit(&query, true, observe, |row| {
            let matches = match query.filter {
                BrowseFilter::All => true,
                BrowseFilter::NotBackedUp => row.backup == "not_backed_up",
                BrowseFilter::NeedsYou => row.backup == "needs_you",
                BrowseFilter::Recent => {
                    row.backup == "saved" && row.saved_at_ms.is_some_and(|t| t >= query.since_ms)
                }
            };
            if matches {
                rows.push(row);
            }
        })?;
        Ok(BrowseResult { rows })
    }
    pub fn request_selected(
        &mut self,
        source: &str,
        receiver: &str,
        selections: &[(String, String)],
    ) -> Result<()> {
        self.request_selected_with_repeats(
            source,
            receiver,
            selections,
            &std::collections::BTreeMap::new(),
        )
    }
    /// Repeat consent is anchored to the previously observed job. It never
    /// removes a receipt or grants permission for a later file revision.
    pub fn request_selected_with_repeats(
        &mut self,
        source: &str,
        receiver: &str,
        selections: &[(String, String)],
        repeats: &std::collections::BTreeMap<String, i64>,
    ) -> Result<()> {
        if selections.len() > 400 || receiver.is_empty() {
            return Err(Error::Invalid("folder selection".into()));
        }
        for (relative, revision) in selections {
            if let Some(id) = repeats.get(relative) {
                if *id <= 0 || self.job_id(source, relative, receiver)? != Some(*id) {
                    return Err(Error::Conflict("folder repeat changed".into()));
                }
            }
            if self.entry(source, relative)?.revision != *revision {
                return Err(Error::Conflict("folder selection changed".into()));
            }
        }
        let tx = self.conn.transaction().map_err(db)?;
        for (relative, revision) in selections {
            tx.execute("INSERT INTO selected_requests(source,relative,revision,receiver,repeat_job) VALUES(?1,?2,?3,?4,?5) ON CONFLICT(source,relative,receiver) DO UPDATE SET revision=excluded.revision,repeat_job=CASE WHEN selected_requests.revision=excluded.revision THEN COALESCE(selected_requests.repeat_job,excluded.repeat_job) ELSE excluded.repeat_job END",params![source,relative,revision,receiver,repeats.get(relative)]).map_err(db)?;
            tx.execute(
                "DELETE FROM ignored WHERE source=?1 AND relative=?2",
                params![source, relative],
            )
            .map_err(db)?;
            tx.execute(
                "DELETE FROM dismissed WHERE source=?1 AND relative=?2",
                params![source, relative],
            )
            .map_err(db)?;
        }
        tx.commit().map_err(db)?;
        Ok(())
    }
    pub fn selected_repeat_job(
        &self,
        source: &str,
        relative: &str,
        revision: &str,
        receiver: &str,
    ) -> Result<Option<i64>> {
        self.conn.query_row("SELECT q.repeat_job FROM selected_requests q JOIN files f ON f.source=q.source AND f.relative=q.relative AND f.revision=q.revision AND f.present=1 WHERE q.source=?1 AND q.relative=?2 AND q.revision=?3 AND q.receiver=?4", params![source,relative,revision,receiver], |row| row.get(0)).optional().map_err(db).map(Option::flatten)
    }
    pub fn selected_pending(&self, source: &str, receiver: &str) -> Result<bool> {
        self.conn.query_row("SELECT EXISTS(SELECT 1 FROM selected_requests q JOIN files f ON f.source=q.source AND f.relative=q.relative AND f.revision=q.revision AND f.present=1 WHERE q.source=?1 AND q.receiver=?2 AND NOT EXISTS(SELECT 1 FROM submitted s WHERE s.source=f.source AND s.identity=f.identity AND s.revision=f.revision AND s.receiver=q.receiver AND s.job>0 AND (q.repeat_job IS NULL OR q.repeat_job!=s.job)))",params![source,receiver],|r| r.get(0)).map_err(db)
    }
    pub fn selected_candidates(
        &self,
        source: &str,
        receiver: &str,
        now: u64,
    ) -> Result<Vec<Entry>> {
        let mut stmt = self.conn.prepare("SELECT q.relative FROM selected_requests q JOIN files f ON f.source=q.source AND f.relative=q.relative AND f.revision=q.revision AND f.present=1 WHERE q.source=?1 AND q.receiver=?2 ORDER BY f.modified DESC,q.relative LIMIT 200").map_err(db)?;
        let paths = stmt
            .query_map(params![source, receiver], |r| r.get::<_, String>(0))
            .map_err(db)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db)?;
        let mut entries = Vec::new();
        for p in paths {
            entries.extend(self.candidates_for(source, receiver, now, 1, Some(&p))?);
            if entries.len() == 8 {
                break;
            }
        }
        Ok(entries)
    }
}
