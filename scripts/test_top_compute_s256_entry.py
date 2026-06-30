import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class TopComputeS256EntryTest(unittest.TestCase):
    def test_wrapper_uses_non_overlapping_s256_memory_map(self):
        wrapper = REPO_ROOT / "sim" / "tb_top_compute_s256_smoke.sv"
        text = wrapper.read_text(encoding="utf-8")

        self.assertIn(".ROWS         (256)", text)
        self.assertIn(".KV_TILE_ROWS (16)", text)
        self.assertIn(".MEM_WORDS    (32768)", text)
        self.assertIn(".Q_BASE       (64'h0000_0000_0000_1000)", text)
        self.assertIn(".K_BASE       (64'h0000_0000_0000_9000)", text)
        self.assertIn(".V_BASE       (64'h0000_0000_0001_1000)", text)
        self.assertIn(".O_BASE       (64'h0000_0000_0001_9000)", text)

    def test_runner_defaults_to_prepare_only_paths(self):
        runner = REPO_ROOT / "scripts" / "run_top_compute_s256_scoreboard.ps1"
        text = runner.read_text(encoding="utf-8")

        self.assertIn('[switch]$RunSimulation', text)
        self.assertIn('"artifacts/vectors/s256_d64_seed100"', text)
        self.assertIn('"artifacts/runs/s256_d64_seed100"', text)
        self.assertIn('"--sequence-length" "256"', text)
        self.assertIn("scripts/pack_vectors_128.py", text)
        self.assertIn("+Q_BEATS128=$qPath128", text)
        self.assertIn("+DUMP_O_BEATS128=$dumpPath", text)
        self.assertIn('"--format" "beats128"', text)
        self.assertIn("tb_top_compute_s256_smoke", text)
        self.assertIn("S256 prepare-only mode", text)


if __name__ == "__main__":
    unittest.main()
