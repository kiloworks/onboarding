use crate::core::{Event, Machine, redact};
use anyhow::{Context, Result, bail};
use base64::{Engine, engine::general_purpose::STANDARD};
use rand::RngCore;
use sha2::{Digest, Sha256};
use std::{
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Read, Write},
    net::TcpListener,
    path::PathBuf,
    process::{Command, Stdio},
    time::{Duration, Instant},
};
use subtle::ConstantTimeEq;
use zeroize::{Zeroize, Zeroizing};

const BOOTSTRAP: &str = include_str!("../../src/windows.ps1");
const KEYS: &str = include_str!("../../config/administrators_authorized_keys");
fn powershell() -> PathBuf {
    PathBuf::from(std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into()))
        .join("System32/WindowsPowerShell/v1.0/powershell.exe")
}
fn encode(script: &str) -> String {
    STANDARD.encode(
        format!("$env:PSModulePath = \"$PSHOME\\Modules;\" + $env:PSModulePath; {script}")
            .encode_utf16()
            .flat_map(u16::to_le_bytes)
            .collect::<Vec<_>>(),
    )
}
fn ps(script: &str) -> Command {
    let mut cmd = Command::new(powershell());
    cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-EncodedCommand",
        &encode(script),
    ]);
    cmd.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000);
    }
    cmd
}
pub fn inspect() -> Result<Machine> {
    anyhow::ensure!(
        cfg!(windows),
        "현재 릴리스는 Windows 전용입니다. macOS·Linux는 준비 중입니다."
    );
    let mut child = ps(r#"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$s = $null
if (Test-Path $ts) { try { $s = (& $ts status --json 2>$null | Out-String) | ConvertFrom-Json } catch {} }
$ssh = Get-Service sshd -ErrorAction SilentlyContinue
@{ installed = (Test-Path $ts); connected = ($null -ne $s -and $s.BackendState -eq 'Running'); tailnet = [string]$s.CurrentTailnet.Name; ip = [string]($s.TailscaleIPs | Select-Object -First 1); user = $id.Name; sid = $id.User.Value; sshReady = ($null -ne $ssh -and $ssh.Status -eq 'Running') } | ConvertTo-Json -Compress
"#).stdout(Stdio::piped()).spawn().context("Windows PowerShell을 시작할 수 없습니다.")?;
    let stdout = child.stdout.take().unwrap();
    let reader = std::thread::spawn(move || {
        let mut s = String::new();
        stdout.take(65536).read_to_string(&mut s).map(|_| s)
    });
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            anyhow::ensure!(status.success(), "기기 상태를 확인할 수 없습니다.");
            let output = reader
                .join()
                .map_err(|_| anyhow::anyhow!("상태 확인 실패"))??;
            return serde_json::from_str(output.trim().trim_start_matches('\u{feff}'))
                .context("기기 상태를 확인할 수 없습니다.");
        }
        if start.elapsed() > Duration::from_secs(30) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("기기 상태 확인 시간이 초과되었습니다.");
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}
fn random_hex(len: usize) -> String {
    let mut b = vec![0; len];
    rand::rng().fill_bytes(&mut b);
    b.iter().map(|x| format!("{x:02x}")).collect()
}
fn quote(s: &str) -> String {
    s.replace('\'', "''")
}
// Bounded before allocation: an unauthenticated local peer cannot grow memory indefinitely.
fn line(reader: &mut impl BufRead) -> Result<Zeroizing<String>> {
    let mut bytes = Zeroizing::new(Vec::new());
    let read = reader.take(65538).read_until(b'\n', &mut bytes)?;
    anyhow::ensure!(
        read > 0 && read <= 65537 && bytes.last() == Some(&b'\n'),
        "관리자 작업 연결이 종료되었습니다."
    );
    let mut text = Zeroizing::new(String::from_utf8(bytes.to_vec()).context("잘못된 작업 응답")?);
    while text.ends_with(['\r', '\n']) {
        text.pop();
    }
    Ok(text)
}
pub fn onboard(
    machine: Machine,
    mut key: Zeroizing<String>,
    replace: bool,
    mut emit: impl FnMut(Event),
) -> Result<()> {
    let nonce = random_hex(32);
    let session = random_hex(16);
    let listener = TcpListener::bind("127.0.0.1:0")?;
    listener.set_nonblocking(true)?;
    let port = listener.local_addr()?.port();
    let helper_dir = tempfile::Builder::new().prefix("onboarding-").tempdir()?;
    let helper = helper_dir.path().join("bootstrap.ps1");
    fs::write(&helper, BOOTSTRAP)?;
    let hash = format!("{:x}", Sha256::digest(BOOTSTRAP.as_bytes()));
    let elevated = format!(
        "$bytes = [IO.File]::ReadAllBytes('{}'); $sha = [Security.Cryptography.SHA256]::Create(); $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant(); if ($hash -ne '{hash}') {{ exit 1 }}; $Port={port}; $Nonce='{nonce}'; . ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($bytes)))",
        quote(&helper.to_string_lossy())
    );
    let launcher = format!(
        "try {{ $p = Start-Process -FilePath '{}' -ArgumentList '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {}' -Verb RunAs -WindowStyle Hidden -Wait -PassThru; exit $p.ExitCode }} catch {{ exit 1223 }}",
        quote(&powershell().to_string_lossy()),
        encode(&elevated)
    );
    let mut child = ps(&launcher)
        .spawn()
        .context("관리자 작업을 시작하지 못했습니다.")?;
    let start = Instant::now();
    let stream = loop {
        if start.elapsed() > Duration::from_secs(120) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("관리자 권한 승인을 기다리는 시간이 초과되었습니다.");
        }
        if let Some(code) = child.try_wait()? {
            bail!(if code.code() == Some(1223) {
                "관리자 권한 요청이 취소되었습니다. 변경을 시작하지 않았습니다."
            } else {
                "관리자 작업이 종료되었습니다."
            });
        }
        match listener.accept() {
            Ok((stream, _)) => {
                stream.set_read_timeout(Some(Duration::from_secs(2)))?;
                let mut r = BufReader::new(stream);
                if let Ok(received) = line(&mut r) {
                    if received.as_bytes().ct_eq(nonce.as_bytes()).into() {
                        break r;
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(30))
            }
            Err(e) => return Err(e.into()),
        }
    };
    let mut stream = stream;
    stream
        .get_mut()
        .set_write_timeout(Some(Duration::from_secs(10)))?;
    stream
        .get_mut()
        .set_read_timeout(Some(Duration::from_secs(45 * 60)))?;
    #[derive(serde::Serialize)]
    struct Config<'a> {
        key: &'a str,
        replace: bool,
        sid: &'a str,
        keys: Vec<&'a str>,
        session: &'a str,
    }
    let mut payload = Zeroizing::new(serde_json::to_string(&Config {
        key: &key,
        replace,
        sid: &machine.sid,
        keys: KEYS.lines().filter(|s| !s.is_empty()).collect(),
        session: &session,
    })?);
    stream.get_mut().write_all(payload.as_bytes())?;
    stream.get_mut().write_all(b"\n")?;
    payload.zeroize();
    key.zeroize();
    let log_dir = PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap_or_else(|| ".".into()))
        .join("Kiloworks/Onboarding");
    let _ = fs::create_dir_all(&log_dir);
    loop {
        anyhow::ensure!(
            start.elapsed() < Duration::from_secs(45 * 60),
            "설치 시간이 초과되었습니다. 리포트를 관리자에게 전달해 주세요."
        );
        stream.get_mut().set_read_timeout(Some(
            Duration::from_secs(45 * 60)
                .saturating_sub(start.elapsed())
                .max(Duration::from_millis(1)),
        ))?;
        let raw = line(&mut stream)?;
        let Ok(mut event) = serde_json::from_str::<Event>(&raw) else {
            continue;
        };
        event.message = redact(&event.message);
        event.report = redact(&event.report);
        event.stage = redact(&event.stage);
        if let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_dir.join("install.log"))
        {
            let _ = writeln!(file, "{}: {}", event.stage, event.message);
        }
        let done = event.done;
        let ok = event.ok;
        let message = event.message.clone();
        emit(event);
        if done {
            anyhow::ensure!(ok, "{message}");
            return Ok(());
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn protocol_boundaries() {
        assert!(line(&mut BufReader::new(&b"nonce\r\n"[..])).is_ok());
        assert!(line(&mut BufReader::new(&b"unterminated"[..])).is_err());
        let huge = vec![b'a'; 70000];
        assert!(line(&mut BufReader::new(&huge[..])).is_err());
        assert_eq!(quote("a'b"), "a''b");
        assert!(!encode("hello").contains("hello"));
        assert_eq!(KEYS.lines().filter(|s| !s.is_empty()).count(), 2);
    }
}
