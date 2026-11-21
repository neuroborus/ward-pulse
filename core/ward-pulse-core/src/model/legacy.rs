//! Private Serde boundary: preserve tokens and optional keys rather than deriving
//! persisted values from a family or an inferred source.

use serde::{Deserialize, Serialize};

/// Legacy wire and display compatibility only; source decisions use the canonical model.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderKind {
    #[serde(rename = "openai")]
    OpenAi,
    Codex,
    Claude,
    Cursor,
    Mock,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Source {
    pub provider: ProviderKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub connection: Option<String>,
}
