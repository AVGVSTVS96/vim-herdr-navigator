//! `doctor`: environment diagnostics.

use std::path::PathBuf;

use crate::config::HELPER_NAME;
use crate::{herdr, marker};

#[derive(Clone, Copy)]
enum Status {
    Ok,
    Warn,
    Fail,
    Info,
}

impl Status {
    fn symbol(self) -> &'static str {
        match self {
            Status::Ok => "[ ok ]",
            Status::Warn => "[warn]",
            Status::Fail => "[FAIL]",
            Status::Info => "[ -- ]",
        }
    }
}

/// Find an executable named `name` on `PATH`.
fn which(name: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path) {
        let candidate = dir.join(name);
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

#[cfg(unix)]
fn is_executable(path: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .map(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &std::path::Path) -> bool {
    path.is_file()
}

fn in_herdr_session() -> bool {
    std::env::var("HERDR_ENV").as_deref() == Ok("1")
        || std::env::var_os("HERDR_SOCKET_PATH").is_some_and(|value| !value.is_empty())
}

fn cache_writable() -> bool {
    let dir = marker::entry_dir();
    if std::fs::create_dir_all(&dir).is_err() {
        return false;
    }
    let probe = dir.join(".doctor-write-test");
    if std::fs::write(&probe, b"").is_err() {
        return false;
    }
    let _ = std::fs::remove_file(&probe);
    true
}

/// Print a diagnostic report. Returns 0 when healthy, 1 on a hard failure.
pub fn run() -> i32 {
    let mut checks: Vec<(Status, String)> = Vec::new();

    checks.push((
        Status::Ok,
        format!("{HELPER_NAME} {}", env!("CARGO_PKG_VERSION")),
    ));

    match which("herdr") {
        Some(path) => {
            let suffix = herdr::version()
                .filter(|v| !v.is_empty())
                .map(|v| format!(" ({v})"))
                .unwrap_or_default();
            checks.push((
                Status::Ok,
                format!("herdr found: {}{suffix}", path.display()),
            ));
        }
        None => checks.push((
            Status::Fail,
            "herdr not found on PATH; install Herdr and ensure `herdr` is runnable".to_string(),
        )),
    }

    if in_herdr_session() {
        let flag = if std::env::var("HERDR_ENV").as_deref() == Ok("1") {
            "HERDR_ENV=1"
        } else {
            "HERDR_SOCKET_PATH set"
        };
        checks.push((Status::Info, format!("Herdr session: active ({flag})")));
    } else {
        checks.push((
            Status::Info,
            "Herdr session: not detected (run inside a Herdr pane for live checks)".to_string(),
        ));
    }

    if let Some(pane) = std::env::var("HERDR_ACTIVE_PANE_ID")
        .ok()
        .or_else(|| std::env::var("HERDR_PANE_ID").ok())
        .filter(|value| !value.is_empty())
    {
        checks.push((Status::Info, format!("Pane id: {pane}")));
    }

    if cache_writable() {
        checks.push((
            Status::Ok,
            format!("Cache dir writable: {}", marker::entry_dir().display()),
        ));
    } else {
        checks.push((
            Status::Warn,
            format!(
                "Cache dir not writable: {} (entry markers will be skipped)",
                marker::entry_dir().display()
            ),
        ));
    }

    println!("{HELPER_NAME} doctor\n");
    for (status, message) in &checks {
        println!("  {} {message}", status.symbol());
    }

    let failures = checks
        .iter()
        .filter(|(status, _)| matches!(status, Status::Fail))
        .count();
    let warnings = checks
        .iter()
        .filter(|(status, _)| matches!(status, Status::Warn))
        .count();

    println!();
    if failures > 0 {
        println!("Summary: {failures} problem(s) found.");
        return 1;
    }
    if warnings > 0 {
        println!("Summary: ok with {warnings} warning(s).");
        return 0;
    }
    println!("Summary: all good.");
    0
}
