//! Direction table and Vim-like process detection.
//!
//! This mirrors `vim-tmux-navigator`'s process test (with `fzf`/`sk` added) so
//! those TUIs keep their own Ctrl-h/j/k/l bindings instead of Herdr stealing
//! focus.

use std::sync::OnceLock;

use regex::Regex;
use serde::Deserialize;

/// A navigation direction and the keys/commands associated with it.
pub struct Direction {
    pub name: &'static str,
    /// Ctrl key sent into a Vim-like pane (e.g. `ctrl+h`).
    pub ctrl_key: &'static str,
    /// When moving from a non-Vim pane into a Vim pane, focus the split nearest
    /// the side we entered from. Moving left enters the target from its right
    /// edge, so select the target's rightmost Vim split (`wincmd l`).
    pub entry_wincmd: &'static str,
    /// Arrow-key equivalent, used for generated config snippets.
    pub arrow_key: &'static str,
}

/// Direction names in the canonical order used for generated config snippets.
pub const DIRECTION_NAMES: [&str; 4] = ["left", "down", "up", "right"];

/// Look up a [`Direction`] by name, or `None` if the name is unknown.
pub fn direction(name: &str) -> Option<Direction> {
    Some(match name {
        "left" => Direction {
            name: "left",
            ctrl_key: "ctrl+h",
            entry_wincmd: "l",
            arrow_key: "ctrl+left",
        },
        "down" => Direction {
            name: "down",
            ctrl_key: "ctrl+j",
            entry_wincmd: "k",
            arrow_key: "ctrl+down",
        },
        "up" => Direction {
            name: "up",
            ctrl_key: "ctrl+k",
            entry_wincmd: "j",
            arrow_key: "ctrl+up",
        },
        "right" => Direction {
            name: "right",
            ctrl_key: "ctrl+l",
            entry_wincmd: "h",
            arrow_key: "ctrl+right",
        },
        _ => return None,
    })
}

/// A foreground process as reported by `herdr pane process-info`. Every field is
/// optional so we tolerate schema differences across Herdr versions.
#[derive(Debug, Default, Clone, Deserialize)]
pub struct Process {
    #[serde(default)]
    pub argv: Vec<String>,
    #[serde(default)]
    pub argv0: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub cmd: Option<String>,
    #[serde(default)]
    pub cmdline: Option<String>,
}

fn vim_like_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(concat!(
            r"(?i)^(?:",
            r"g?\.?view(?:diff)?(?:-wrapped)?|",
            r"g?\.?vi(?:m)?(?:diff)?(?:-wrapped)?|",
            r"g?\.?nvim(?:diff)?(?:-wrapped)?|",
            r"g?\.?lvim(?:diff)?(?:-wrapped)?|",
            r"gvim(?:diff)?(?:-wrapped)?|",
            r"vimx(?:diff)?(?:-wrapped)?|",
            r"fzf(?:-tmux)?|",
            r"sk|skim",
            r")$",
        ))
        .expect("vim-like process regex is valid")
    })
}

/// User-supplied extra detection pattern from `$HERDR_VIM_NAVIGATOR_PATTERN`.
///
/// When set, it is OR-ed into the built-in detection (it extends, never narrows,
/// the set of "Vim-like" commands) — the Herdr counterpart to tmux's
/// `@vim_navigator_pattern`. Matched case-insensitively and unanchored, like
/// tmux's `=~`. An empty or invalid regex is ignored.
fn user_re() -> Option<&'static Regex> {
    static RE: OnceLock<Option<Regex>> = OnceLock::new();
    RE.get_or_init(|| {
        std::env::var("HERDR_VIM_NAVIGATOR_PATTERN")
            .ok()
            .filter(|pattern| !pattern.is_empty())
            .and_then(|pattern| Regex::new(&format!("(?i){pattern}")).ok())
    })
    .as_ref()
}

/// Strip login-shell dashes (`-nvim`) and any leading path so we match on the
/// bare executable name.
pub fn executable_basename(value: &str) -> &str {
    let trimmed = value.trim_start_matches('-');
    trimmed.rsplit('/').next().unwrap_or(trimmed)
}

/// True when `base` matches the built-in detection or the optional user pattern.
fn matches_vim_like(base: &str, extra: Option<&Regex>) -> bool {
    vim_like_re().is_match(base) || extra.is_some_and(|re| re.is_match(base))
}

/// True when `name` (a possibly path/dash-prefixed command) is a Vim-like editor
/// or picker, honoring `$HERDR_VIM_NAVIGATOR_PATTERN`.
pub fn is_vim_like_process_name(name: &str) -> bool {
    matches_vim_like(executable_basename(name), user_re())
}

/// Candidate command strings for a process, in priority order: `argv[0]`, then
/// `argv0`, `name`, `cmd`, then the first token of `cmdline`.
pub fn process_candidates(process: &Process) -> Vec<String> {
    let mut out = Vec::new();

    if let Some(first) = process.argv.first() {
        out.push(first.clone());
    }

    for s in [&process.argv0, &process.name, &process.cmd]
        .into_iter()
        .flatten()
    {
        if !s.is_empty() {
            out.push(s.clone());
        }
    }

    if let Some(cmdline) = &process.cmdline {
        if let Some(first) = cmdline.split_whitespace().next() {
            out.push(first.to_string());
        }
    }

    out
}

/// True when any foreground process looks like a Vim-like editor or picker.
pub fn is_vim_like(processes: &[Process]) -> bool {
    processes
        .iter()
        .flat_map(process_candidates)
        .any(|candidate| is_vim_like_process_name(&candidate))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_common_editors_and_pickers() {
        let names = [
            "vi",
            "vim",
            "nvim",
            "nvimdiff",
            "lvim",
            "view",
            "gvim",
            "vimx",
            "fzf",
            "fzf-tmux",
            "sk",
            "skim",
            "/opt/homebrew/bin/nvim",
            "-nvim",
            "nvim-wrapped",
        ];
        for name in names {
            assert!(is_vim_like_process_name(name), "expected vim-like: {name}");
        }
    }

    #[test]
    fn rejects_shells_and_agents() {
        for name in ["zsh", "bash", "fish", "node", "pi", "claude", "python3"] {
            assert!(
                !is_vim_like_process_name(name),
                "expected not vim-like: {name}"
            );
        }
    }

    #[test]
    fn candidates_prefer_argv_then_argv0_name_cmdline() {
        let process = Process {
            argv: vec!["/usr/local/bin/nvim".into(), "file.txt".into()],
            argv0: Some("ignored".into()),
            name: Some("ignored-too".into()),
            ..Default::default()
        };
        assert_eq!(
            process_candidates(&process).first().map(String::as_str),
            Some("/usr/local/bin/nvim")
        );

        let process = Process {
            argv0: Some("python3".into()),
            name: Some("node".into()),
            cmdline: Some("nvim --clean".into()),
            ..Default::default()
        };
        assert_eq!(process_candidates(&process), ["python3", "node", "nvim"]);
    }

    #[test]
    fn is_vim_like_scans_all_candidates() {
        let processes = vec![
            Process {
                argv0: Some("zsh".into()),
                ..Default::default()
            },
            Process {
                cmdline: Some("nvim file.rs".into()),
                ..Default::default()
            },
        ];
        assert!(is_vim_like(&processes));

        let only_shells = vec![Process {
            argv: vec!["bash".into()],
            ..Default::default()
        }];
        assert!(!is_vim_like(&only_shells));
    }

    #[test]
    fn user_pattern_extends_detection() {
        let extra = Regex::new("(?i)ssh").expect("valid extra pattern");
        // The user pattern adds new matches...
        assert!(matches_vim_like("ssh", Some(&extra)));
        assert!(!matches_vim_like("ssh", None));
        // ...without disturbing the built-ins.
        assert!(matches_vim_like("nvim", Some(&extra)));
        assert!(!matches_vim_like("zsh", Some(&extra)));
    }

    #[test]
    fn entry_wincmds_target_entered_edge() {
        assert_eq!(direction("left").unwrap().entry_wincmd, "l");
        assert_eq!(direction("right").unwrap().entry_wincmd, "h");
        assert_eq!(direction("up").unwrap().entry_wincmd, "j");
        assert_eq!(direction("down").unwrap().entry_wincmd, "k");
    }
}
