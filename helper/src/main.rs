//! Seamless Herdr + Vim/Neovim pane navigation: the Herdr side of a
//! vim-tmux-navigator-style setup.
//!
//! - From Herdr keybindings, `dispatch <direction>` decides whether to send the
//!   Ctrl-h/j/k/l key into Vim/Neovim/FZF or move Herdr focus.
//! - From Vim/Neovim, `focus <direction>` is called when editor window
//!   navigation hits an edge, so focus moves to the neighboring Herdr pane.

mod config;
mod detect;
mod doctor;
mod herdr;
mod marker;

use std::process::ExitCode;

use anyhow::Result;
use clap::{Parser, Subcommand, ValueEnum};

use config::HELPER_NAME;
use detect::Direction;

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
    Dispatch { direction: DirArg },
    /// Move Herdr focus toward a neighboring pane (called by Vim/Neovim at an edge).
    Focus { direction: DirArg },
    /// Run environment diagnostics.
    Doctor,
    /// Print a Herdr keybinding snippet (TOML) to paste into your config.
    Config {
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

/// True when `name` holds a truthy value (`1`/`true`).
fn env_enabled(name: &str) -> bool {
    matches!(std::env::var(name).ok().as_deref(), Some("1" | "true"))
}

/// Entry markers (jump to the split nearest the entered edge) are opt-in via a
/// single switch: `VIM_HERDR_NAVIGATOR_ENTRY_MARKERS`. The helper writes them
/// only when it is set, and the Vim/Neovim plugin (which inherits Herdr's
/// environment) reads the same variable.
fn entry_markers_enabled() -> bool {
    env_enabled("VIM_HERDR_NAVIGATOR_ENTRY_MARKERS")
}

/// When `VIM_HERDR_NAVIGATOR_ZOOM=unzoom`, un-maximize the pane before a
/// directional move. The default (`preserve`/unset) leaves Herdr's native zoom
/// behavior untouched.
fn unzoom_on_move() -> bool {
    std::env::var("VIM_HERDR_NAVIGATOR_ZOOM").ok().as_deref() == Some("unzoom")
}

/// Prepare an entry marker if the neighbor in this direction is a Vim-like pane.
fn prepare_entry_marker(source: &str, dir: &Direction, debug_enabled: bool) -> Result<()> {
    if !entry_markers_enabled() {
        return Ok(());
    }
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
    if unzoom_on_move() {
        if let Err(err) = herdr::unzoom(pane) {
            debug(debug_enabled, &format!("could not unzoom {pane}: {err}"));
        }
    }
    prepare_entry_marker(pane, dir, debug_enabled)?;
    herdr::focus(pane, dir.name)
}

fn run(cli: Cli) -> Result<()> {
    let debug_enabled = cli.debug;

    match cli.command {
        Command::Config { helper } => {
            print!("{}", config::render(&helper));
            Ok(())
        }
        Command::Doctor => unreachable!("doctor handled before run()"),
        Command::Dispatch { direction } => {
            let pane = herdr::current_pane_id()?;
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
        Command::Focus { direction } => {
            let pane = herdr::current_pane_id()?;
            let dir = detect::direction(direction.as_str()).expect("valid direction");
            focus_pane(&pane, &dir, debug_enabled)
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
