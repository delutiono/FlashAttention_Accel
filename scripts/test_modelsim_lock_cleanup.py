import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class ModelsimLockCleanupTest(unittest.TestCase):
    def test_cleanup_script_repairs_and_removes_stale_locks(self) -> None:
        text = (REPO_ROOT / "scripts" / "cleanup_modelsim_locks.ps1").read_text(encoding="utf-8")

        self.assertIn("param(", text)
        self.assertIn("[string[]]$WorkLib", text)
        self.assertIn("_lock", text)
        self.assertIn("pid = (\\d+)", text)
        self.assertIn("icacls", text)
        self.assertIn("Remove-Item", text)
        self.assertIn("Stop-Process", text)

    def test_top_scoreboard_runners_use_temp_private_modelsim_worklib(self) -> None:
        helper_text = (REPO_ROOT / "scripts" / "modelsim_worklib.ps1").read_text(encoding="utf-8")
        self.assertIn("Remove-PathWithAclRetry", helper_text)
        self.assertIn("UnauthorizedAccessException", helper_text)
        self.assertIn("icacls", helper_text)

        for script_name in (
            "run_top_compute_s4_scoreboard.ps1",
            "run_top_compute_s5_scoreboard.ps1",
            "run_top_compute_s5_stall_scoreboard.ps1",
            "run_top_compute_s16_scoreboard.ps1",
            "run_top_compute_s32_scoreboard.ps1",
            "run_top_compute_s64_scoreboard.ps1",
            "run_top_compute_s256_scoreboard.ps1",
        ):
            with self.subTest(script_name=script_name):
                text = (REPO_ROOT / "scripts" / script_name).read_text(encoding="utf-8")

                self.assertIn("modelsim_worklib.ps1", text)
                self.assertIn("New-ModelSimWorkLib", text)
                self.assertIn('"-modelsimini"', text)
                self.assertIn('"-timescale" "1ns/1ps"', text)
                self.assertIn("Invoke-ModelSimVsim", text)
                self.assertIn("Remove-PathWithAclRetry", text)
                self.assertNotIn("Invoke-Checked vlib", text)
                self.assertNotIn("Remove-Item $dumpPath", text)


if __name__ == "__main__":
    unittest.main()
