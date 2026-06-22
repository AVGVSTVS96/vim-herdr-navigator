import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "herdr-vim-navigator"

navigator = SourceFileLoader("navigator", str(SCRIPT)).load_module()


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


if __name__ == "__main__":
    unittest.main()
