use anyhow::{Context, Result, ensure};
use semver::Version;
use serde::Deserialize;
use std::{
    io::Read,
    process::Stdio,
    time::{Duration, Instant},
};

const SCRIPT: &str = include_str!("../../src/update.ps1");
const PUBLIC_KEY: &str = include_str!("../../config/update-public-key.xml");
#[derive(Clone, Debug)]
pub struct Release {
    pub version: Version,
    pub tag: String,
}
#[derive(Deserialize)]
struct Asset {
    name: String,
}
#[derive(Deserialize)]
struct Candidate {
    tag_name: String,
    assets: Vec<Asset>,
}
fn arch() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        "x64"
    }
}
fn select(json: &str, current: &Version, arch: &str) -> Result<Option<Release>> {
    let candidates: Vec<Candidate> = serde_json::from_str(json)?;
    Ok(candidates
        .into_iter()
        .filter_map(|c| {
            let version = Version::parse(c.tag_name.strip_prefix('v')?).ok()?;
            if version.cmp_precedence(current).is_le() || c.tag_name != format!("v{version}") {
                return None;
            }
            let name = format!("onboarding-{version}-windows-{arch}-setup.exe");
            [
                name.clone(),
                format!("{name}.sig"),
                format!("{name}.manifest.json"),
            ]
            .iter()
            .all(|n| c.assets.iter().any(|a| a.name == *n))
            .then_some(Release {
                version,
                tag: c.tag_name,
            })
        })
        .max_by(|a, b| a.version.cmp_precedence(&b.version)))
}
fn quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "''"))
}
fn run(prefix: &str, timeout: Duration) -> Result<String> {
    let mut child = crate::windows::ps(&format!("{prefix}; & {{ {SCRIPT} }}"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let read = |pipe: Box<dyn Read + Send>| {
        std::thread::spawn(move || {
            let mut text = String::new();
            pipe.take(16 * 1024 * 1024)
                .read_to_string(&mut text)
                .map(|_| text)
        })
    };
    let out = read(Box::new(stdout));
    let err = read(Box::new(stderr));
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            let output = out
                .join()
                .map_err(|_| anyhow::anyhow!("업데이트 응답 읽기 실패"))??;
            let error = err
                .join()
                .map_err(|_| anyhow::anyhow!("업데이트 오류 읽기 실패"))??;
            ensure!(status.success(), "{}", crate::core::redact(error.trim()));
            return Ok(output.trim().trim_start_matches('\u{feff}').into());
        }
        if start.elapsed() > timeout {
            let _ = child.kill();
            let _ = child.wait();
            anyhow::bail!("업데이트 요청 시간이 초과되었습니다.");
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}
pub fn check() -> Result<Option<Release>> {
    if !cfg!(windows) {
        return Ok(None);
    }
    select(
        &run("$Mode='check'", Duration::from_secs(60))?,
        &Version::parse(env!("CARGO_PKG_VERSION"))?,
        arch(),
    )
}
pub fn prepare(release: &Release) -> Result<()> {
    let directory = tempfile::Builder::new()
        .prefix("onboarding-update-")
        .tempdir()?;
    let exe = std::env::current_exe()?;
    let install_dir = exe.parent().context("앱 설치 경로를 찾을 수 없습니다.")?;
    let result = run(
        &format!(
            "$Mode='prepare'; $Tag={}; $Version={}; $Arch={}; $PublicKey={}; $Directory={}; $InstallDir={}; $ParentId={}",
            quote(&release.tag),
            quote(&release.version.to_string()),
            quote(arch()),
            quote(PUBLIC_KEY),
            quote(&directory.path().to_string_lossy()),
            quote(&install_dir.to_string_lossy()),
            std::process::id()
        ),
        Duration::from_secs(400),
    );
    result?;
    // The detached installer helper owns cleanup after this process exits.
    let _ = directory.keep();
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    fn candidate(v: &str, arch: &str) -> serde_json::Value {
        let name = format!("onboarding-{v}-windows-{arch}-setup.exe");
        serde_json::json!({"tag_name":format!("v{v}"),"assets":[{"name":name},{"name":format!("{name}.sig")},{"name":format!("{name}.manifest.json")}]})
    }
    #[test]
    fn selects_signed_newer_same_arch_including_prerelease() {
        let current = Version::parse("0.3.0").unwrap();
        let json = serde_json::json!([candidate("0.4.0-beta.2","x64"), candidate("0.4.0-beta.10","x64"),candidate("0.5.0","arm64"),candidate("0.2.0","x64"),{"tag_name":"v9.0.0","assets":[]}]).to_string();
        assert_eq!(
            select(&json, &current, "x64")
                .unwrap()
                .unwrap()
                .version
                .to_string(),
            "0.4.0-beta.10"
        );
        assert!(
            select(
                &serde_json::json!([candidate("0.3.0", "x64"), candidate("0.2.0", "x64")])
                    .to_string(),
                &current,
                "x64"
            )
            .unwrap()
            .is_none()
        );
        assert!(select("invalid", &current, "x64").is_err());
    }
}
