//! Entry markers shared with the Neovim plugin.
//!
//! When Herdr focuses into a Vim-like neighbor, we drop a one-character `wincmd`
//! hint at `<cache>/herdr-vim-navigator/entry/<pane-id>`. The plugin reads it on
//! focus and jumps to the split nearest the edge that was entered.

use std::path::PathBuf;

fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default()
}

/// `${XDG_CACHE_HOME:-~/.cache}/herdr-vim-navigator`.
pub fn cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".cache"));
    base.join("herdr-vim-navigator")
}

/// Directory holding per-pane entry markers.
pub fn entry_dir() -> PathBuf {
    cache_dir().join("entry")
}

/// Write the `wincmd` hint for `pane_id`.
pub fn write_entry_marker(pane_id: &str, wincmd: &str) -> std::io::Result<()> {
    let dir = entry_dir();
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join(pane_id), wincmd)
}
