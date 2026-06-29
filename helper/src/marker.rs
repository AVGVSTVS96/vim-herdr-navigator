//! Entry markers shared with the Neovim plugin.
//!
//! When Herdr focuses into a Vim-like neighbor, we drop a one-character `wincmd`
//! hint at `<cache>/vim-herdr-navigator/entry/<pane-id>`. The plugin reads it on
//! focus and jumps to the split nearest the edge that was entered.

use std::path::PathBuf;

fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default()
}

/// `${XDG_CACHE_HOME:-~/.cache}/vim-herdr-navigator`.
pub fn cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".cache"));
    base.join("vim-herdr-navigator")
}

/// Directory holding per-pane entry markers.
pub fn entry_dir() -> PathBuf {
    cache_dir().join("entry")
}

/// Write the `wincmd` hint for `pane_id`.
///
/// `wincmd` is always one of `h`/`j`/`k`/`l` (from the direction table). We
/// write to a temp file and rename it into place so the plugin, which may read
/// on any focus event, never observes a half-written marker. The rename is
/// atomic on the same filesystem; the temp file shares the marker's directory.
pub fn write_entry_marker(pane_id: &str, wincmd: &str) -> std::io::Result<()> {
    let dir = entry_dir();
    std::fs::create_dir_all(&dir)?;
    let tmp = dir.join(format!(".{pane_id}.tmp"));
    std::fs::write(&tmp, wincmd)?;
    std::fs::rename(&tmp, dir.join(pane_id))
}
