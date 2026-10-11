//! Ephemeral byte acknowledgements for the local host UI, independent of history.
use backupduck_core::{AssetStatus, ProcessingState, ReceiptState};
use serde::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    sync::{Condvar, Mutex},
    time::Duration,
};

#[derive(Clone, Serialize, Deserialize)]
pub struct ProgressItem {
    pub id: String,
    pub confirmed_bytes: u64,
    pub total_bytes: u64,
    pub received: bool,
    pub processing: ProcessingState,
    pub processing_error: Option<String>,
}
#[derive(Clone, Default, Serialize, Deserialize)]
pub struct ProgressSnapshot {
    pub revision: u64,
    pub items: VecDeque<ProgressItem>,
}
#[derive(Default)]
pub struct ProgressFeed {
    state: Mutex<ProgressSnapshot>,
    changed: Condvar,
}
impl ProgressFeed {
    pub fn publish(&self, status: &AssetStatus, total_bytes: u64) {
        // Presentation failure must never turn a durable write into a failure.
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        let item = ProgressItem {
            id: status.asset_id.clone(),
            total_bytes,
            confirmed_bytes: status.resources.iter().map(|r| r.offset).sum(),
            received: status.receipt == ReceiptState::Received,
            processing: status.processing.clone(),
            processing_error: status.processing_error.clone(),
        };
        if state.items.iter().any(|old| {
            old.id == item.id
                && old.confirmed_bytes == item.confirmed_bytes
                && old.received == item.received
                && old.processing == item.processing
                && old.processing_error == item.processing_error
        }) {
            return;
        }
        state.items.retain(|old| old.id != item.id);
        state.items.push_back(item);
        while state.items.len() > 128 {
            state.items.pop_front();
        }
        state.revision = state.revision.saturating_add(1);
        self.changed.notify_all();
    }
    pub fn wait(&self, after: u64, timeout: Duration) -> ProgressSnapshot {
        let Ok(state) = self.state.lock() else {
            return ProgressSnapshot::default();
        };
        let state = if state.revision == after {
            match self
                .changed
                .wait_timeout_while(state, timeout.min(Duration::from_secs(1)), |s| {
                    s.revision == after
                }) {
                Ok((state, _)) => state,
                Err(_) => return ProgressSnapshot::default(),
            }
        } else {
            state
        };
        state.clone()
    }
}
