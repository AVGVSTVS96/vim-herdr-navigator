import sys
import unittest
from pathlib import Path

# Make the package importable regardless of how the tests are invoked.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from herdr_vim_navigator import __version__
from herdr_vim_navigator import cli as navigator


class NavigatorTests(unittest.TestCase):
    def test_vim_like_process_detection_matches_common_editors(self):
        names = [
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
            "/opt/homebrew/bin/nvim",
            "-nvim",
        ]
        for name in names:
            with self.subTest(name=name):
                self.assertTrue(navigator.is_vim_like_process_name(name))

    def test_vim_like_process_detection_rejects_shells_and_agents(self):
        for name in ["zsh", "bash", "fish", "node", "pi", "claude", "python3"]:
            with self.subTest(name=name):
                self.assertFalse(navigator.is_vim_like_process_name(name))

    def test_process_candidates_prefers_argv_then_argv0_name_cmdline(self):
        process = {
            "argv": ["/usr/local/bin/nvim", "file.txt"],
            "argv0": "ignored",
            "name": "ignored-too",
        }
        self.assertEqual(next(navigator.process_candidates(process)), "/usr/local/bin/nvim")

        process = {"argv0": "python3", "name": "node", "cmdline": "nvim --clean"}
        self.assertEqual(list(navigator.process_candidates(process)), ["python3", "node", "nvim"])

    def test_entry_wincmds_target_entered_edge(self):
        self.assertEqual(navigator.DIRECTIONS["left"].entry_wincmd, "l")
        self.assertEqual(navigator.DIRECTIONS["right"].entry_wincmd, "h")
        self.assertEqual(navigator.DIRECTIONS["up"].entry_wincmd, "j")
        self.assertEqual(navigator.DIRECTIONS["down"].entry_wincmd, "k")


class VersionTests(unittest.TestCase):
    def test_version_is_a_dotted_string(self):
        self.assertIsInstance(__version__, str)
        self.assertRegex(__version__, r"^\d+\.\d+")


class ConfigSnippetTests(unittest.TestCase):
    def test_default_snippet_emits_all_dispatch_directions(self):
        snippet = navigator.render_herdr_config()
        for key, name in (("ctrl+h", "left"), ("ctrl+j", "down"), ("ctrl+k", "up"), ("ctrl+l", "right")):
            self.assertIn(f'key = "{key}"', snippet)
            self.assertIn(f"herdr-vim-navigator dispatch {name}", snippet)
        # Arrow bindings are opt-in.
        self.assertNotIn("ctrl+left", snippet)

    def test_arrows_flag_adds_arrow_bindings(self):
        snippet = navigator.render_herdr_config(arrows=True)
        for key in ("ctrl+left", "ctrl+down", "ctrl+up", "ctrl+right"):
            self.assertIn(f'key = "{key}"', snippet)

    def test_custom_helper_name_is_used_in_commands(self):
        snippet = navigator.render_herdr_config(helper="/opt/bin/hvn")
        self.assertIn("/opt/bin/hvn dispatch left", snippet)

    def test_splits_flag_adds_commented_examples(self):
        snippet = navigator.render_herdr_config(splits=True)
        self.assertIn("# command = \"herdr-vim-navigator split right\"", snippet)


if __name__ == "__main__":
    unittest.main()
