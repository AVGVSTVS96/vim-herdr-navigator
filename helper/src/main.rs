//! Seamless Herdr + Vim/Neovim pane navigation — the Herdr side of a
//! vim-tmux-navigator-style setup.
//!
//! - From Herdr keybindings, `dispatch <direction>` decides whether to send the
//!   Ctrl-h/j/k/l key into Vim/Neovim/FZF or move Herdr focus.
//! - From Neovim, `focus <direction>` is called when Vim window navigation hits
//!   an edge, so focus moves to the neighboring Herdr pane.
//! - `split <right|down>` mirrors a couple of tmux split bindings.

mod config;
mod detect;
mod doctor;
mod herdr;
mod marker;

use std::process::ExitCode;

use anyhow::{bail, Result};
use clap::{Parser, Subcommand, ValueEnum};

use detect::Direction;

const HELPER_NAME: &str = "herdr-vim-navigator";

#[derive(Parser)]
#[command(
    name = HELPER_NAME,
    version,
    about = "Herdr + Vim/Neovim pane navigator",
    disable_help_subcommand = true
)]
struct Cli {
    /// Print debug messages to stderr.
    #[arg(long, global = true)]
    debug: bool,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Herdr keybinding entrypoint: send key into Vim or move Herdr focus.
    Dispatch {
        direction: DirArg,
        /// Source pane id; defaults to Herdr env/current pane.
        #[arg(long = "pane")]
        pane_id: Option<String>,
    },
    /// Move Herdr focus toward a neighboring pane (called by Neovim at an edge).
    Focus {
        direction: DirArg,
        #[arg(long = "pane")]
        pane_id: Option<String>,
    },
    /// Split the current pane right or down.
    Split {
        direction: DirArg,
        #[arg(long = "pane")]
        pane_id: Option<String>,
    },
    /// Run environment diagnostics.
    #[command(visible_alias = "check")]
    Doctor,
    /// Print a Herdr keybinding snippet (TOML) to paste into your config.
    Config {
        /// Also emit ctrl+arrow bindings.
        #[arg(long)]
        arrows: bool,
        /// Also emit commented split-binding examples.
        #[arg(long)]
        splits: bool,
        /// Command name to use in the snippet.
        #[arg(long, default_value = HELPER_NAME)]
        helper: String,
    },
}

#[derive(Clone, Copy, ValueEnum)]
enum DirArg {
    Left,
    Down,
    Up,
    Right,
}

impl DirArg {
    fn as_str(self) -> &'static str {
        match self {
            DirArg::Left => "left",
            DirArg::Down => "down",
            DirArg::Up => "up",
            DirArg::Right => "right",
        }
    }
}

fn debug(enabled: bool, message: &str) {
    if enabled {
        eprintln!("{HELPER_NAME}: {message}");
    }
}

fn resolve_pane(pane_id: Option<String>) -> Result<String> {
    match pane_id {
        Some(id) if !id.is_empty() => Ok(id),
        _ => herdr::current_pane_id(),
    }
}

/// Prepare an entry marker if the neighbor in this direction is a Vim-like pane.
fn prepare_entry_marker(source: &str, dir: &Direction, debug_enabled: bool) -> Result<()> {
    match herdr::neighbor_pane_id(source, dir.name)? {
        Some(target) if target != source => {
            if herdr::is_vim_like_pane(&target)? {
                if let Err(err) = marker::write_entry_marker(&target, dir.entry_wincmd) {
                    debug(
                        debug_enabled,
                        &format!("could not write entry marker: {err}"),
                    );
                } else {
                    debug(
                        debug_enabled,
                        &format!("prepared entry marker for {target}: {}", dir.entry_wincmd),
                    );
                }
            }
        }
        _ => debug(
            debug_enabled,
            &format!("no {} neighbor for {source}", dir.name),
        ),
    }
    Ok(())
}

fn focus_pane(pane: &str, dir: &Direction, debug_enabled: bool) -> Result<()> {
    prepare_entry_marker(pane, dir, debug_enabled)?;
    herdr::focus(pane, dir.name)
}

fn run(cli: Cli) -> Result<()> {
    let debug_enabled = cli.debug;

    match cli.command {
        Command::Config {
            arrows,
            splits,
            helper,
        } => {
            print!("{}", config::render(&helper, arrows, splits));
            Ok(())
        }
        Command::Doctor => unreachable!("doctor handled before run()"),
        Command::Dispatch { direction, pane_id } => {
            let pane = resolve_pane(pane_id)?;
            let dir = detect::direction(direction.as_str()).expect("valid direction");
            if herdr::is_vim_like_pane(&pane)? {
                debug(
                    debug_enabled,
                    &format!("{pane} is vim-like; sending {}", dir.ctrl_key),
                );
                herdr::send_key(&pane, dir.ctrl_key)
            } else {
                debug(
                    debug_enabled,
                    &format!("{pane} is not vim-like; focusing {}", dir.name),
                );
                focus_pane(&pane, &dir, debug_enabled)
            }
        }
        Command::Focus { direction, pane_id } => {
            let pane = resolve_pane(pane_id)?;
            let dir = detect::direction(direction.as_str()).expect("valid direction");
            focus_pane(&pane, &dir, debug_enabled)
        }
        Command::Split { direction, pane_id } => {
            let name = direction.as_str();
            if name != "right" && name != "down" {
                bail!("split only supports right or down");
            }
            let pane = resolve_pane(pane_id)?;
            let cwd = herdr::pane_cwd(&pane);
            herdr::split(&pane, name, cwd.as_deref())
        }
    }
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    // doctor manages its own exit code and never errors out.
    if matches!(cli.command, Command::Doctor) {
        return ExitCode::from(doctor::run() as u8);
    }

    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{HELPER_NAME}: {err}");
            ExitCode::FAILURE
        }
    }
}
