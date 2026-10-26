//! A bounded, receiver-scoped feed of accepted backup requests. Preparation
//! remains a different record type, not a fake transfer with invented bytes.
use super::*;
impl Sender {
    fn attach_preparations(&self, maintenance_db: &Path) -> Result<()> {
        let attached: bool = self
            .conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM pragma_database_list WHERE name='preparations')",
                [],
                |r| r.get(0),
            )
            .map_err(db)?;
        if !attached {
            self.conn
                .execute(
                    "ATTACH DATABASE ?1 AS preparations",
                    [maintenance_db.to_string_lossy().as_ref()],
                )
                .map_err(db)?;
        }
        Ok(())
    }

    /// Count confirmed gallery publications for the frozen historical members.
    /// Enumeration, original preparation and receipt are not publication. The
    /// latest attempt for the exact source revision owns the observed result.
    pub fn history_published(&self, maintenance_db: &Path, receiver: &str) -> Result<i64> {
        self.attach_preparations(maintenance_db)?;
        self.conn
            .query_row(
                "SELECT COUNT(*) FROM preparations.history_members h
             JOIN jobs j ON j.id=(SELECT MAX(id) FROM jobs WHERE receiver_id=h.receiver
               AND json_extract(manifest,'$.source_id')=h.source
               AND json_extract(manifest,'$.revision')=h.revision)
             JOIN processing_observations p ON p.job_id=j.id
             WHERE h.receiver=?1 AND j.state='received' AND p.state='complete'",
                [receiver],
                |r| r.get(0),
            )
            .map_err(db)
    }

    pub fn backup_tasks(
        &self,
        maintenance_db: &Path,
        query: JobQuery<'_>,
        source_filter: Option<&str>,
    ) -> Result<serde_json::Value> {
        self.attach_preparations(maintenance_db)?;
        let sort = match query.sort {
            "added" => "added",
            "capture" => "captured",
            "activity" => "activity",
            "retry" => "retry",
            _ => return Err(Error::Invalid("backup task sort".into())),
        };
        if !matches!(
            query.state,
            None | Some("all" | "active" | "attention" | "saved" | "running")
        ) {
            return Err(Error::Invalid("backup task category".into()));
        }
        let receiver = query
            .receiver
            .ok_or_else(|| Error::Invalid("backup task receiver".into()))?;
        let common = r#"WITH task_rows AS (
          SELECT COALESCE(l.cursor,j.id) AS cursor,
            COALESCE('preparation:'||l.request,'transfer:'||j.id) AS identity,
            j.id AS job_id,NULL AS request_id,NULL AS source,NULL AS revision,NULL AS error,
            CASE WHEN j.state='received' AND o.state='complete' THEN 'saved'
                 WHEN j.state='failed' OR (j.state='received' AND o.state='failed') THEN 'attention' ELSE 'active' END AS category,
            j.state AS execution,COALESCE(l.added_at_ms,j.added_at_ms) AS added,
            CAST(json_extract(j.manifest,'$.metadata.created_at_ms') AS INTEGER) AS captured,
            j.state_changed_at_ms AS activity,j.next_attempt_at*1000 AS retry
          FROM jobs j LEFT JOIN processing_observations o ON o.job_id=j.id
            LEFT JOIN job_preparations l ON l.rowid=(SELECT MIN(rowid) FROM job_preparations WHERE job_id=j.id AND receiver=j.receiver_id)
          WHERE j.receiver_id=?1 AND (?2 IS NULL OR COALESCE(json_extract(j.manifest,'$.metadata.source_ref'),'library')=?2)
          UNION ALL
          SELECT p.feed_cursor,'preparation:'||p.source,NULL,p.source,COALESCE(r.source_ref,p.source),COALESCE(r.revision,''),p.error_code,
            CASE WHEN p.error_code IS NULL OR p.error_code IN ('local_cache_budget','local_free_space','network') THEN 'active' ELSE 'attention' END,
            'preparing',p.added_at_ms,p.created_at_ms,p.state_changed_at_ms,p.retry_at*1000
          FROM preparations.pending_sources p LEFT JOIN preparations.source_preparations r ON r.receiver=p.receiver AND r.request=p.source
          WHERE p.receiver=?1 AND (?2 IS NULL OR ?2='library') AND NOT EXISTS(
            SELECT 1 FROM job_preparations l JOIN jobs j ON j.id=l.job_id WHERE l.receiver=p.receiver AND l.request=p.source AND j.receiver_id=p.receiver)
        )"#;
        let tx = self.conn.unchecked_transaction().map_err(db)?;
        let mut summary = self.summary_source(receiver, source_filter)?;
        for key in [
            "total",
            "active",
            "attention",
            "saved",
            "preparation_waiting",
            "preparation_failed",
        ] {
            summary[key] = 0.into();
        }
        {
            let mut stmt=tx.prepare(&format!("{common} SELECT category,job_id IS NULL,COUNT(*) FROM task_rows GROUP BY category,job_id IS NULL")).map_err(db)?;
            let rows = stmt
                .query_map(params![receiver, source_filter], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, bool>(1)?,
                        r.get::<_, i64>(2)?,
                    ))
                })
                .map_err(db)?;
            for row in rows {
                let (category, preparation, count) = row.map_err(db)?;
                summary["total"] = (summary["total"].as_i64().unwrap() + count).into();
                summary[&category] = (summary[&category].as_i64().unwrap() + count).into();
                if preparation {
                    summary[if category == "attention" {
                        "preparation_failed"
                    } else {
                        "preparation_waiting"
                    }] = count.into();
                }
            }
        }
        let unknown = if query.descending { i64::MIN } else { i64::MAX };
        let value = format!("CASE WHEN {sort}>0 THEN {sort} ELSE {unknown} END");
        let direction = if query.descending { "DESC" } else { "ASC" };
        let compare = if query.descending { "<" } else { ">" };
        let cursor = if query.after == 0 {
            0
        } else {
            query
                .after_value
                .ok_or_else(|| Error::Invalid("backup task cursor".into()))?
        };
        let sql=format!("{common} SELECT cursor,identity,job_id,request_id,source,revision,error,captured,{value},retry FROM task_rows WHERE (?3 IS NULL OR ?3='all' OR category=?3 OR (?3='running' AND execution='running')) AND (?4=0 OR ({value},cursor){compare}(?5,?4)) ORDER BY {value} {direction},cursor {direction} LIMIT ?6");
        let mut items = {
            let mut stmt = tx.prepare(&sql).map_err(db)?;
            let rows=stmt.query_map(params![receiver,source_filter,query.state,query.after,cursor,query.limit.clamp(1,500)],|r| {
                let job=r.get::<_,Option<i64>>(2)?;
                Ok(serde_json::json!({"id":r.get::<_,String>(1)?,"cursor":r.get::<_,i64>(0)?,"sort_value":r.get::<_,i64>(8)?,"job_id":job,"preparation":if job.is_none() {serde_json::json!({"cursor":r.get::<_,i64>(0)?,"request_id":r.get::<_,String>(3)?,"source":r.get::<_,String>(4)?,"revision":r.get::<_,String>(5)?,"error_code":r.get::<_,Option<String>>(6)?,"created_at_ms":r.get::<_,Option<i64>>(7)?,"retry_at":r.get::<_,i64>(9)?/1000,"state":"preparing"})}else{serde_json::Value::Null}}))
            }).map_err(db)?;
            rows.collect::<std::result::Result<Vec<_>, _>>()
                .map_err(db)?
        };
        for item in &mut items {
            if let Some(id) = item["job_id"].as_i64() {
                item["job"] = serde_json::to_value(self.job(id)?)?;
            }
        }
        tx.commit().map_err(db)?;
        Ok(serde_json::json!({"items":items,"summary":summary}))
    }
}
