use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Machine {
    pub installed: bool,
    pub connected: bool,
    pub tailnet: Option<String>,
    pub ip: Option<String>,
    pub user: String,
    pub sid: String,
    pub ssh_ready: bool,
}
#[derive(Clone, Default, Deserialize, Serialize)]
pub struct Event {
    pub stage: String,
    pub message: String,
    #[serde(default)]
    pub done: bool,
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub report: String,
}
pub fn validate_key(value: &str) -> anyhow::Result<String> {
    let key = value.trim();
    anyhow::ensure!(
        key.len() <= 512
            && key
                .strip_prefix("tskey-auth-")
                .is_some_and(|s| s.len() >= 10
                    && s.bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')),
        "관리자에게 전달받은 Tailscale 등록 키를 확인해 주세요."
    );
    Ok(key.to_string())
}
pub fn redact(value: &str) -> String {
    static KEY: OnceLock<Regex> = OnceLock::new();
    static JWT: OnceLock<Regex> = OnceLock::new();
    let value = KEY
        .get_or_init(|| Regex::new(r"tskey-[A-Za-z0-9_-]+").unwrap())
        .replace_all(value, "[비밀 삭제]");
    JWT.get_or_init(|| Regex::new(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+").unwrap())
        .replace_all(&value, "[토큰 삭제]")
        .into_owned()
}
pub fn report(events: &[Event], user: &str) -> String {
    redact(&format!(
        "Onboarding {} — 지원 리포트\nSSH 대상 계정: {user}\nSSH 방화벽: 모든 네트워크의 TCP 22\n관리자 측 원격 접속: 이 앱에서는 검증하지 않음\n{}",
        env!("CARGO_PKG_VERSION"),
        events
            .iter()
            .map(|e| format!("[{}] {}\n{}", e.stage, e.message, e.report))
            .collect::<Vec<_>>()
            .join("\n")
    ))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn uninstalled_network_fields_can_be_null() {
        let machine: Machine = serde_json::from_str(r#"{"installed":false,"connected":false,"tailnet":null,"ip":null,"user":"TEST\\user","sid":"S-1-5-21-1-2-3-1001","sshReady":false}"#).unwrap();
        assert!(!machine.installed && !machine.connected);
    }
    #[test]
    fn keys_and_reports() {
        assert!(validate_key(" tskey-auth-test-only-key ").is_ok());
        for key in [
            "bad",
            "tskey-auth-short",
            "tskey-auth-test-only;whoami",
            "tskey-auth-한글등록키입니다",
        ] {
            assert!(validate_key(key).is_err());
        }
        assert!(validate_key(&format!("tskey-auth-{}", "a".repeat(513))).is_err());
        let events = [Event {
            message: "tskey-auth-private-key eyJsecret.payload.signature".into(),
            ..Default::default()
        }];
        let r = report(&events, "TEST\\user");
        assert!(!r.contains("private-key"));
        assert!(!r.contains("eyJsecret"));
        assert!(r.contains("TCP 22"));
    }
}
