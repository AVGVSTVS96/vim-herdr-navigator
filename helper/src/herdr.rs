//! Thin wrapper around the public `herdr` CLI.
//!
//! Like the original helper, this shells out to `herdr pane ...` commands and
//! parses their JSON instead of speaking Herdr's socket protocol directly. The
//! surface area is tiny, stable, and easy to debug.

use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;
use serde_json::Value;

use crate::detect::{self, Process};

/// Bound each `herdr` invocation so a stuck socket can't hang a keybinding.
const TIMEOUT: Duration = Duration::from_secs(2);

/// How often to poll the child while waiting for it to exit.
const POLL_INTERVAL: Duration = Duration::from_millis(10);

/// Top-level JSON envelope returned by every `herdr` CLI command. Note that the
/// CLI exits 0 even on logical errors and signals them via `error`.
#[derive(Deserialize)]
struct Envelope {
    #[serde(default)]
    error: Option<HerdrError>,
    #[serde(default)]
    result: Option<Value>,
}

#[derive(Deserialize)]
struct HerdrError {
    #[serde(default)]
    message: Option<String>,
    #[serde(default)]
    code: Option<String>,
}

/// Run `herdr <args>` with a timeout and return its captured output.
///
/// We poll the child with `try_wait` and, on timeout, kill and reap it before
/// returning an error — otherwise a stuck `herdr` would be left running as an
/// orphan and undercut the timeout. `herdr` emits small JSON, so reading its
/// piped output after it exits won't deadlock on a full pipe.
///
/// This kills the direct `herdr` process only, not a whole process tree. The
/// `herdr` CLI is a single short-lived process that talks to the server over a
/// socket and does not fork long-lived children, so killing it is sufficient;
/// if it ever spawned grandchildren, those would not be reaped here.
fn run_raw(args: &[String]) -> Result<std::process::Output> {
    let mut child = Command::new("herdr")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| anyhow!(err).context("failed to run `herdr` (is it on PATH?)"))?;

    let deadline = Instant::now() + TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(_status)) => {
                return child
                    .wait_with_output()
                    .context("failed to read herdr output");
            }
            Ok(None) => {
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("herdr {} timed out after {:?}", args.join(" "), TIMEOUT);
                }
                thread::sleep(POLL_INTERVAL);
            }
            Err(err) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(anyhow!(err).context("failed to wait on herdr"));
            }
        }
    }
}

/// Run a `herdr` command and return its `result` object, raising on either a
/// process failure or a logical `error` in the JSON.
fn call(args: &[&str]) -> Result<Value> {
    let owned: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let output = run_raw(&owned)?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stderr = stderr.trim();
        if stderr.is_empty() {
            bail!("herdr {} failed with {}", args.join(" "), output.status);
        }
        bail!("herdr {} failed: {stderr}", args.join(" "));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stdout = stdout.trim();
    if stdout.is_empty() {
        return Ok(Value::Null);
    }

    let envelope: Envelope = serde_json::from_str(stdout)
        .with_context(|| format!("herdr {} returned invalid JSON", args.join(" ")))?;

    if let Some(err) = envelope.error {
        let message = err
            .message
            .or(err.code)
            .unwrap_or_else(|| "unknown error".to_string());
        bail!("Herdr request failed: {message}");
    }

    Ok(envelope.result.unwrap_or(Value::Null))
}

fn str_at<'a>(value: &'a Value, path: &[&str]) -> Option<&'a str> {
    let mut current = value;
    for key in path {
        current = current.get(key)?;
    }
    current.as_str().filter(|s| !s.is_empty())
}

/// Resolve the current pane id from Herdr env vars, falling back to the CLI.
///
/// `HERDR_ACTIVE_PANE_ID` is set for Herdr keybinding commands; `HERDR_PANE_ID`
/// is set when called from inside a pane (e.g. from Neovim).
pub fn current_pane_id() -> Result<String> {
    for var in ["HERDR_ACTIVE_PANE_ID", "HERDR_PANE_ID"] {
        if let Some(value) = non_empty_env(var) {
            return Ok(value);
        }
    }

    let result = call(&["pane", "current", "--current"])?;
    str_at(&result, &["pane", "pane_id"])
        .map(str::to_string)
        .ok_or_else(|| anyhow!("could not determine current Herdr pane id"))
}

/// Best-effort working directory for a pane, used to inherit cwd on split.
pub fn pane_cwd(pane_id: &str) -> Option<String> {
    for var in ["HERDR_ACTIVE_PANE_CWD", "HERDR_PANE_CWD"] {
        if let Some(value) = non_empty_env(var) {
            return Some(value);
        }
    }

    if let Ok(result) = call(&["pane", "get", pane_id]) {
        for key in ["foreground_cwd", "cwd"] {
            if let Some(value) = str_at(&result, &["pane", key]) {
                return Some(value.to_string());
            }
        }
    }

    non_empty_env("PWD")
}

/// True when the pane is running a Vim-like foreground process.
pub fn is_vim_like_pane(pane_id: &str) -> Result<bool> {
    let result = call(&["pane", "process-info", "--pane", pane_id])?;
    let processes: Vec<Process> = result
        .get("process_info")
        .and_then(|info| info.get("foreground_processes"))
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default();
    Ok(detect::is_vim_like(&processes))
}

/// The pane neighboring `pane_id` in `direction`, if any.
pub fn neighbor_pane_id(pane_id: &str, direction: &str) -> Result<Option<String>> {
    let result = call(&[
        "pane",
        "neighbor",
        "--direction",
        direction,
        "--pane",
        pane_id,
    ])?;
    Ok(str_at(&result, &["neighbor", "neighbor_pane_id"]).map(str::to_string))
}

/// Send a key (e.g. `ctrl+h`) into a pane.
pub fn send_key(pane_id: &str, key: &str) -> Result<()> {
    call(&["pane", "send-keys", pane_id, key]).map(drop)
}

/// Move Herdr focus from `pane_id` toward `direction`.
pub fn focus(pane_id: &str, direction: &str) -> Result<()> {
    call(&["pane", "focus", "--direction", direction, "--pane", pane_id]).map(drop)
}

/// Split a pane right or down, inheriting `cwd` when known, and focus the split.
pub fn split(pane_id: &str, direction: &str, cwd: Option<&str>) -> Result<()> {
    let mut args = vec![
        "pane",
        "split",
        "--pane",
        pane_id,
        "--direction",
        direction,
        "--focus",
    ];
    if let Some(cwd) = cwd {
        args.push("--cwd");
        args.push(cwd);
    }
    call(&args).map(drop)
}

/// Run `herdr --version` and return its first line, if available.
pub fn version() -> Option<String> {
    let output = run_raw(&["--version".to_string()]).ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    let text = if text.trim().is_empty() {
        String::from_utf8_lossy(&output.stderr).into_owned()
    } else {
        text.into_owned()
    };
    text.lines().next().map(str::trim).map(str::to_string)
}

fn non_empty_env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|value| !value.is_empty())
}
