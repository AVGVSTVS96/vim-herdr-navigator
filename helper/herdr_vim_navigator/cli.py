#!/usr/bin/env python3
"""Seamless Herdr + Vim/Neovim pane navigation.

This is the Herdr side of a vim-tmux-navigator-style setup:

- From Herdr keybindings, ``dispatch <direction>`` decides whether to send the
  Ctrl-h/j/k/l key into Vim/Neovim/FZF or move Herdr focus.
- From Neovim, ``focus <direction>`` is called when Vim window navigation hits an
  edge, so focus moves to the neighboring Herdr pane.
- Optional ``split <right|down>`` mirrors a couple of tmux split bindings.

The implementation intentionally shells out to the public ``herdr`` CLI instead of
speaking an internal socket protocol. It is slower than a native client, but the
surface area is tiny, stable, and easy to debug.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, List, Mapping, Sequence

from . import __version__

HERDR_TIMEOUT_SECONDS = 2.0

# Default name of the helper command, used in generated config snippets.
HELPER_NAME = "herdr-vim-navigator"


@dataclass(frozen=True)
class Direction:
    name: str
    ctrl_key: str
    vim_wincmd: str
    # When moving from a non-Vim pane into a Vim pane, focus the split nearest
    # the side we entered from. Example: moving left enters the target pane from
    # its right edge, so select the target's rightmost Vim split (`wincmd l`).
    entry_wincmd: str
    # Arrow-key equivalent, used for generated config snippets.
    arrow_key: str


DIRECTIONS: "dict[str, Direction]" = {
    "left": Direction("left", "ctrl+h", "h", "l", "ctrl+left"),
    "down": Direction("down", "ctrl+j", "j", "k", "ctrl+down"),
    "up": Direction("up", "ctrl+k", "k", "j", "ctrl+up"),
    "right": Direction("right", "ctrl+l", "l", "h", "ctrl+right"),
}

# Based on vim-tmux-navigator's process test, with fzf/sk added so those TUIs
# keep their Ctrl-j/k bindings instead of Herdr stealing focus.
VIM_LIKE_PROCESS_RE = re.compile(
    r"^(?:"
    r"g?\.?view(?:diff)?(?:-wrapped)?|"
    r"g?\.?vim(?:diff)?(?:-wrapped)?|"
    r"g?\.?nvim(?:diff)?(?:-wrapped)?|"
    r"g?\.?lvim(?:diff)?(?:-wrapped)?|"
    r"gvim(?:diff)?(?:-wrapped)?|"
    r"vimx(?:diff)?(?:-wrapped)?|"
    r"fzf(?:-tmux)?|"
    r"sk|skim"
    r")$",
    re.IGNORECASE,
)


def cache_home() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))


def cache_dir() -> Path:
    return cache_home() / "herdr-vim-navigator"


def entry_dir() -> Path:
    return cache_dir() / "entry"


def debug(message: str, *, enabled: bool) -> None:
    if enabled:
        print(f"herdr-vim-navigator: {message}", file=sys.stderr)


def run_herdr(args: Sequence[str], *, timeout: float = HERDR_TIMEOUT_SECONDS) -> "dict[str, Any]":
    completed = subprocess.run(
        ["herdr", *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "herdr {} failed with exit code {}{}".format(
                " ".join(args),
                completed.returncode,
                f": {completed.stderr.strip()}" if completed.stderr.strip() else "",
            )
        )
    stdout = completed.stdout.strip()
    if not stdout:
        return {}
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"herdr {' '.join(args)} returned invalid JSON: {exc}") from exc


def result(response: Mapping[str, Any]) -> Mapping[str, Any]:
    error = response.get("error")
    if error:
        if isinstance(error, Mapping):
            message = error.get("message") or error
        else:
            message = error
        raise RuntimeError(f"Herdr request failed: {message}")
    value = response.get("result", {})
    return value if isinstance(value, Mapping) else {}


def current_pane_id() -> str:
    # HERDR_ACTIVE_PANE_ID is expected for Herdr keybinding commands. HERDR_PANE_ID
    # is expected when called from inside a pane, e.g. from Neovim.
    for name in ("HERDR_ACTIVE_PANE_ID", "HERDR_PANE_ID"):
        value = os.environ.get(name)
        if value:
            return value

    # Fallback for manual debugging from a non-pane environment.
    data = result(run_herdr(["pane", "current", "--current"]))
    pane = data.get("pane")
    if isinstance(pane, Mapping) and isinstance(pane.get("pane_id"), str):
        return pane["pane_id"]
    raise RuntimeError("could not determine current Herdr pane id")


def pane_info(pane_id: str) -> Mapping[str, Any]:
    data = result(run_herdr(["pane", "get", pane_id]))
    pane = data.get("pane")
    return pane if isinstance(pane, Mapping) else {}


def pane_cwd(pane_id: str) -> "str | None":
    for name in ("HERDR_ACTIVE_PANE_CWD", "HERDR_PANE_CWD"):
        value = os.environ.get(name)
        if value:
            return value

    info = pane_info(pane_id)
    for key in ("foreground_cwd", "cwd"):
        value = info.get(key)
        if isinstance(value, str) and value:
            return value
    return os.environ.get("PWD")


def process_info(pane_id: str) -> Mapping[str, Any]:
    data = result(run_herdr(["pane", "process-info", "--pane", pane_id]))
    info = data.get("process_info")
    return info if isinstance(info, Mapping) else {}


def process_candidates(process: Mapping[str, Any]) -> Iterable[str]:
    argv = process.get("argv")
    if isinstance(argv, list) and argv and isinstance(argv[0], str):
        yield argv[0]

    for key in ("argv0", "name", "cmd"):
        value = process.get(key)
        if isinstance(value, str) and value:
            yield value

    cmdline = process.get("cmdline")
    if isinstance(cmdline, str) and cmdline.strip():
        # Avoid importing shlex on the hot path? No: correctness is more useful.
        import shlex

        try:
            parts = shlex.split(cmdline)
        except ValueError:
            parts = cmdline.split()
        if parts:
            yield parts[0]


def executable_basename(value: str) -> str:
    # Foreground commands sometimes appear as login-style names (`-nvim`) or full
    # paths. Strip both before matching.
    return Path(value.lstrip("-")).name


def is_vim_like_process_name(name: str) -> bool:
    return bool(VIM_LIKE_PROCESS_RE.match(executable_basename(name)))


def is_vim_like_processes(processes: Iterable[Mapping[str, Any]]) -> bool:
    for process in processes:
        for candidate in process_candidates(process):
            if is_vim_like_process_name(candidate):
                return True
    return False


def is_vim_like_pane(pane_id: str) -> bool:
    info = process_info(pane_id)
    processes = info.get("foreground_processes", [])
    if not isinstance(processes, list):
        return False
    return is_vim_like_processes(p for p in processes if isinstance(p, Mapping))


def neighbor_pane_id(pane_id: str, direction: str) -> "str | None":
    data = result(run_herdr(["pane", "neighbor", "--direction", direction, "--pane", pane_id]))
    neighbor = data.get("neighbor")
    if not isinstance(neighbor, Mapping):
        return None
    value = neighbor.get("neighbor_pane_id")
    return value if isinstance(value, str) and value else None


def write_entry_marker(pane_id: str, wincmd: str) -> None:
    path = entry_dir() / pane_id
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(wincmd, encoding="utf-8")


def prepare_entry_marker(source_pane_id: str, direction: Direction, *, debug_enabled: bool) -> None:
    target = neighbor_pane_id(source_pane_id, direction.name)
    if not target or target == source_pane_id:
        debug(f"no {direction.name} neighbor for {source_pane_id}", enabled=debug_enabled)
        return
    if is_vim_like_pane(target):
        write_entry_marker(target, direction.entry_wincmd)
        debug(
            f"prepared entry marker for {target}: {direction.entry_wincmd}",
            enabled=debug_enabled,
        )


def focus_pane(pane_id: str, direction: Direction, *, debug_enabled: bool) -> None:
    prepare_entry_marker(pane_id, direction, debug_enabled=debug_enabled)
    run_herdr(["pane", "focus", "--direction", direction.name, "--pane", pane_id])


def send_key_to_pane(pane_id: str, key: str) -> None:
    run_herdr(["pane", "send-keys", pane_id, key])


def split_pane(pane_id: str, direction: Direction) -> None:
    if direction.name not in {"right", "down"}:
        raise RuntimeError("split only supports right or down")

    args = ["pane", "split", "--pane", pane_id, "--direction", direction.name, "--focus"]
    cwd = pane_cwd(pane_id)
    if cwd:
        args.extend(["--cwd", cwd])
    run_herdr(args)


# --------------------------------------------------------------------------- #
# config snippet
# --------------------------------------------------------------------------- #


def render_herdr_config(*, helper: str = HELPER_NAME, arrows: bool = False, splits: bool = False) -> str:
    """Return a ready-to-paste Herdr keybinding snippet (TOML)."""

    def block(key: str, command: str, description: str) -> str:
        return (
            "[[keys.command]]\n"
            f'key = "{key}"\n'
            'type = "shell"\n'
            f'command = "{command}"\n'
            f'description = "{description}"\n'
        )

    lines: List[str] = [
        f"# {HELPER_NAME} — add these to your Herdr config (keybindings).",
        f"# Generated by: {HELPER_NAME} config"
        + ("".join([" --arrows" if arrows else "", " --splits" if splits else ""])),
        "",
    ]

    blocks: List[str] = []
    for direction in DIRECTIONS.values():
        blocks.append(
            block(
                direction.ctrl_key,
                f"{helper} dispatch {direction.name}",
                f"vim-aware pane {direction.name}",
            )
        )

    if arrows:
        for direction in DIRECTIONS.values():
            blocks.append(
                block(
                    direction.arrow_key,
                    f"{helper} dispatch {direction.name}",
                    f"vim-aware pane {direction.name}",
                )
            )

    snippet = "\n".join(lines) + "\n".join(blocks)

    if splits:
        snippet += (
            "\n# Optional split bindings — choose keys that don't clash with your setup:\n"
            "# [[keys.command]]\n"
            '# key = "<your-key>"\n'
            '# type = "shell"\n'
            f'# command = "{helper} split right"\n'
            '# description = "vim-aware split right"\n'
            "#\n"
            "# [[keys.command]]\n"
            '# key = "<your-key>"\n'
            '# type = "shell"\n'
            f'# command = "{helper} split down"\n'
            '# description = "vim-aware split down"\n'
        )

    return snippet


# --------------------------------------------------------------------------- #
# doctor
# --------------------------------------------------------------------------- #


def _herdr_version() -> "str | None":
    try:
        completed = subprocess.run(
            ["herdr", "--version"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=HERDR_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    output = (completed.stdout or completed.stderr or "").strip()
    return output.splitlines()[0] if output else None


def in_herdr_session() -> bool:
    return os.environ.get("HERDR_ENV") == "1" or bool(os.environ.get("HERDR_SOCKET_PATH"))


def _cache_writable() -> bool:
    try:
        target = entry_dir()
        target.mkdir(parents=True, exist_ok=True)
        probe = target / ".doctor-write-test"
        probe.write_text("", encoding="utf-8")
        probe.unlink()
        return True
    except OSError:
        return False


def run_doctor() -> int:
    """Print a diagnostic report. Returns 0 when healthy, 1 on a hard failure."""

    checks: "List[tuple[str, str]]" = []  # (status, message)

    py = "{}.{}.{}".format(*sys.version_info[:3])
    checks.append(("ok", f"{HELPER_NAME} {__version__} (python {py})"))

    herdr_path = shutil.which("herdr")
    if herdr_path:
        version = _herdr_version()
        suffix = f" ({version})" if version else ""
        checks.append(("ok", f"herdr found: {herdr_path}{suffix}"))
    else:
        checks.append(("fail", "herdr not found on PATH — install Herdr and ensure `herdr` is runnable"))

    if in_herdr_session():
        flag = "HERDR_ENV=1" if os.environ.get("HERDR_ENV") == "1" else "HERDR_SOCKET_PATH set"
        checks.append(("info", f"Herdr session: active ({flag})"))
    else:
        checks.append(("info", "Herdr session: not detected (run inside a Herdr pane for live checks)"))

    pane = os.environ.get("HERDR_ACTIVE_PANE_ID") or os.environ.get("HERDR_PANE_ID")
    if pane:
        checks.append(("info", f"Pane id: {pane}"))

    if _cache_writable():
        checks.append(("ok", f"Cache dir writable: {entry_dir()}"))
    else:
        checks.append(("warn", f"Cache dir not writable: {entry_dir()} (entry markers will be skipped)"))

    symbols = {"ok": "[ ok ]", "warn": "[warn]", "fail": "[FAIL]", "info": "[ -- ]"}
    print(f"{HELPER_NAME} doctor\n")
    for status, message in checks:
        print(f"  {symbols.get(status, '[ -- ]')} {message}")

    failures = sum(1 for status, _ in checks if status == "fail")
    warnings = sum(1 for status, _ in checks if status == "warn")
    print("")
    if failures:
        print(f"Summary: {failures} problem(s) found.")
        return 1
    if warnings:
        print(f"Summary: ok with {warnings} warning(s).")
        return 0
    print("Summary: all good.")
    return 0


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=HELPER_NAME,
        description="Herdr + Vim/Neovim pane navigator",
    )
    parser.add_argument("--version", action="version", version=f"{HELPER_NAME} {__version__}")
    parser.add_argument("--debug", action="store_true", help="print debug messages to stderr")

    sub = parser.add_subparsers(dest="command", required=True, metavar="command")

    for command, help_text in (
        ("dispatch", "Herdr keybinding entrypoint: send key into Vim or move Herdr focus"),
        ("focus", "move Herdr focus toward a neighboring pane (called by Neovim at an edge)"),
        ("split", "split the current pane right or down"),
    ):
        p = sub.add_parser(command, help=help_text)
        p.add_argument("direction", choices=sorted(DIRECTIONS))
        p.add_argument("--pane", dest="pane_id", help="source pane id; defaults to Herdr env/current pane")

    sub.add_parser("doctor", aliases=["check"], help="run environment diagnostics")

    cfg = sub.add_parser("config", help="print a Herdr keybinding snippet (TOML) to paste into your config")
    cfg.add_argument("--arrows", action="store_true", help="also emit ctrl+arrow bindings")
    cfg.add_argument("--splits", action="store_true", help="also emit commented split-binding examples")
    cfg.add_argument(
        "--helper",
        default=HELPER_NAME,
        help=f"command name to use in the snippet (default: {HELPER_NAME})",
    )

    return parser


def main(argv: "Sequence[str] | None" = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    command = args.command

    if command == "config":
        sys.stdout.write(render_herdr_config(helper=args.helper, arrows=args.arrows, splits=args.splits))
        return 0

    if command in ("doctor", "check"):
        return run_doctor()

    try:
        pane_id = args.pane_id or current_pane_id()

        if command == "dispatch":
            direction = DIRECTIONS[args.direction]
            if is_vim_like_pane(pane_id):
                debug(f"{pane_id} is vim-like; sending {direction.ctrl_key}", enabled=args.debug)
                send_key_to_pane(pane_id, direction.ctrl_key)
            else:
                debug(f"{pane_id} is not vim-like; focusing {direction.name}", enabled=args.debug)
                focus_pane(pane_id, direction, debug_enabled=args.debug)
        elif command == "focus":
            focus_pane(pane_id, DIRECTIONS[args.direction], debug_enabled=args.debug)
        elif command == "split":
            split_pane(pane_id, DIRECTIONS[args.direction])
        else:
            parser.error(f"unknown command: {command}")
    except Exception as exc:  # Keep Herdr keybinding failures readable.
        print(f"herdr-vim-navigator: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
