use std::cmp::Ordering;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppVersion {
    components: Vec<u64>,
}

impl AppVersion {
    pub fn parse(text: &str) -> Option<Self> {
        let mut value = text.trim();
        if let Some(stripped) = value.strip_prefix('v').or_else(|| value.strip_prefix('V')) {
            value = stripped;
        }
        if value.is_empty() {
            return None;
        }
        let mut components = Vec::new();
        for part in value.split('.') {
            components.push(part.parse::<u64>().ok()?);
        }
        Some(Self { components })
    }

    pub fn compare(&self, other: &Self) -> Ordering {
        let count = self.components.len().max(other.components.len());
        for index in 0..count {
            let left = self.components.get(index).copied().unwrap_or(0);
            let right = other.components.get(index).copied().unwrap_or(0);
            if left != right {
                return left.cmp(&right);
            }
        }
        Ordering::Equal
    }
}

pub fn is_newer(remote_version: &str, remote_build: i64, current_version: &str, current_build: i64) -> bool {
    match (AppVersion::parse(remote_version), AppVersion::parse(current_version)) {
        (Some(remote), Some(local)) => match remote.compare(&local) {
            Ordering::Equal => remote_build > current_build,
            Ordering::Greater => true,
            Ordering::Less => false,
        },
        _ => remote_build > current_build,
    }
}
