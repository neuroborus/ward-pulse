use serde::{Deserialize, Serialize};

use super::{connection, legacy, ProviderKind};

/// A grouping for presentation, never an account or authorization scope.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProviderFamily {
    OpenAi,
    Anthropic,
    Cursor,
}

impl ProviderFamily {
    pub const fn display_label(self) -> &'static str {
        match self {
            Self::OpenAi => "OpenAI",
            Self::Anthropic => "Anthropic",
            Self::Cursor => "Cursor",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectionKind {
    Plan,
    Platform,
}

/// The same family/kind pair and six storage keys as the phone catalog.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProviderConnectionId {
    pub family: ProviderFamily,
    pub kind: ConnectionKind,
}

impl ProviderConnectionId {
    pub const OPENAI_PLAN: Self = Self::new(ProviderFamily::OpenAi, ConnectionKind::Plan);
    pub const OPENAI_PLATFORM: Self = Self::new(ProviderFamily::OpenAi, ConnectionKind::Platform);
    pub const ANTHROPIC_PLAN: Self = Self::new(ProviderFamily::Anthropic, ConnectionKind::Plan);
    pub const ANTHROPIC_PLATFORM: Self =
        Self::new(ProviderFamily::Anthropic, ConnectionKind::Platform);
    pub const CURSOR_PLAN: Self = Self::new(ProviderFamily::Cursor, ConnectionKind::Plan);
    pub const CURSOR_PLATFORM: Self = Self::new(ProviderFamily::Cursor, ConnectionKind::Platform);

    pub const ALL: [Self; 6] = [
        Self::OPENAI_PLAN,
        Self::OPENAI_PLATFORM,
        Self::ANTHROPIC_PLAN,
        Self::ANTHROPIC_PLATFORM,
        Self::CURSOR_PLAN,
        Self::CURSOR_PLATFORM,
    ];

    pub const fn new(family: ProviderFamily, kind: ConnectionKind) -> Self {
        Self { family, kind }
    }

    pub const fn storage_key(self) -> &'static str {
        match (self.family, self.kind) {
            (ProviderFamily::OpenAi, ConnectionKind::Plan) => connection::CODEX_PLAN,
            (ProviderFamily::OpenAi, ConnectionKind::Platform) => connection::OPENAI_PLATFORM,
            (ProviderFamily::Anthropic, ConnectionKind::Plan) => connection::CLAUDE_PLAN,
            (ProviderFamily::Anthropic, ConnectionKind::Platform) => connection::ANTHROPIC_PLATFORM,
            (ProviderFamily::Cursor, ConnectionKind::Plan) => connection::CURSOR_PLAN,
            (ProviderFamily::Cursor, ConnectionKind::Platform) => connection::CURSOR_PLATFORM,
        }
    }

    pub fn from_storage_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|id| id.storage_key() == key)
    }

    const fn legacy_provider(self) -> ProviderKind {
        match (self.family, self.kind) {
            (ProviderFamily::OpenAi, ConnectionKind::Plan) => ProviderKind::Codex,
            (ProviderFamily::OpenAi, ConnectionKind::Platform) => ProviderKind::OpenAi,
            (ProviderFamily::Anthropic, _) => ProviderKind::Claude,
            (ProviderFamily::Cursor, _) => ProviderKind::Cursor,
        }
    }
}

/// Family membership with a retained legacy display/wire token. It proves no source.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(from = "ProviderKind", into = "ProviderKind")]
pub struct ProviderIdentity {
    family: Option<ProviderFamily>,
    legacy: ProviderKind,
}

impl ProviderIdentity {
    pub const fn family(self) -> Option<ProviderFamily> {
        self.family
    }

    /// Compatibility only: do not dispatch source capabilities on this token.
    pub const fn legacy_provider(self) -> ProviderKind {
        self.legacy
    }

    pub const fn display_label(self) -> &'static str {
        match self.legacy {
            ProviderKind::OpenAi => "OpenAI",
            ProviderKind::Codex => "Codex",
            ProviderKind::Claude => "Claude",
            ProviderKind::Cursor => "Cursor",
            ProviderKind::Mock => "Mock",
        }
    }

    /// Historical alert routing, not evidence that a source is known.
    pub(crate) const fn legacy_alert_connection(self) -> &'static str {
        match self.legacy {
            ProviderKind::OpenAi => connection::OPENAI_PLATFORM,
            ProviderKind::Codex => connection::CODEX_PLAN,
            ProviderKind::Claude => connection::CLAUDE_PLAN,
            ProviderKind::Cursor => connection::CURSOR_PLAN,
            ProviderKind::Mock => connection::MOCK_PLAN,
        }
    }
}

impl From<ProviderKind> for ProviderIdentity {
    fn from(legacy: ProviderKind) -> Self {
        let family = match legacy {
            ProviderKind::OpenAi | ProviderKind::Codex => Some(ProviderFamily::OpenAi),
            ProviderKind::Claude => Some(ProviderFamily::Anthropic),
            ProviderKind::Cursor => Some(ProviderFamily::Cursor),
            ProviderKind::Mock => None,
        };
        Self { family, legacy }
    }
}

impl From<ProviderIdentity> for ProviderKind {
    fn from(identity: ProviderIdentity) -> Self {
        identity.legacy
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SourceOrigin {
    Connection(ProviderConnectionId),
    Mock,
    UnresolvedLegacy,
}

/// Canonical source plus the lossless legacy boundary. Neither is authorization.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(from = "legacy::Source", into = "legacy::Source")]
pub struct ProviderSource {
    provider: ProviderIdentity,
    origin: SourceOrigin,
    connection: Option<String>,
}

impl ProviderSource {
    pub fn connection(id: ProviderConnectionId) -> Self {
        Self::from_legacy(id.legacy_provider(), Some(id.storage_key().into()))
    }

    pub fn mock() -> Self {
        Self::from_legacy(ProviderKind::Mock, Some(connection::MOCK_PLAN.into()))
    }

    pub fn provider(&self) -> ProviderIdentity {
        self.provider
    }

    pub fn origin(&self) -> SourceOrigin {
        self.origin
    }

    /// Exact explicit boundary key, including unknown keys; no fallback is invented.
    pub fn explicit_connection(&self) -> Option<&str> {
        self.connection.as_deref()
    }

    pub(crate) fn alert_connection(&self) -> &str {
        self.explicit_connection()
            .unwrap_or_else(|| self.provider.legacy_alert_connection())
    }

    pub(crate) fn from_legacy(provider: ProviderKind, connection: Option<String>) -> Self {
        let origin = match connection.as_deref() {
            Some(key) => match ProviderConnectionId::from_storage_key(key) {
                Some(id) if id.legacy_provider() == provider => SourceOrigin::Connection(id),
                _ if key == connection::MOCK_PLAN && provider == ProviderKind::Mock => {
                    SourceOrigin::Mock
                }
                _ => SourceOrigin::UnresolvedLegacy,
            },
            None => match provider {
                ProviderKind::OpenAi => {
                    SourceOrigin::Connection(ProviderConnectionId::OPENAI_PLATFORM)
                }
                ProviderKind::Codex => SourceOrigin::Connection(ProviderConnectionId::OPENAI_PLAN),
                ProviderKind::Mock => SourceOrigin::Mock,
                ProviderKind::Claude | ProviderKind::Cursor => SourceOrigin::UnresolvedLegacy,
            },
        };
        Self {
            provider: provider.into(),
            origin,
            connection,
        }
    }
}

impl From<legacy::Source> for ProviderSource {
    fn from(source: legacy::Source) -> Self {
        Self::from_legacy(source.provider, source.connection)
    }
}

impl From<ProviderSource> for legacy::Source {
    fn from(source: ProviderSource) -> Self {
        Self {
            provider: source.provider.legacy,
            connection: source.connection,
        }
    }
}
