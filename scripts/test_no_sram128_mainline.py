import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class NoSram128MainlineTest(unittest.TestCase):
    def test_sram128_reference_trees_are_removed_from_main_workspace(self) -> None:
        for relative_path in (
            "rtl/sram128",
            "sim/sram128",
            "synth/sram128",
            "docs/sram128_remote_runbook.md",
            "scripts/run_sram128_axi_lite_smoke.ps1",
            "scripts/run_sram128_compliant_wrapper_smoke.ps1",
            "scripts/run_sram128_o_store_backpressure.ps1",
            "scripts/run_sram128_s256_scoreboard.ps1",
            "scripts/run_sram128_zero_s256.ps1",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertFalse((REPO_ROOT / relative_path).exists())

    def test_active_sources_do_not_reference_sram128_path(self) -> None:
        active_roots = ("rtl", "sim", "synth", "scripts")
        forbidden = ("rtl/sram128", "sim/sram128", "synth/sram128", "fa_top_sram128")
        for root_name in active_roots:
            for path in (REPO_ROOT / root_name).rglob("*"):
                if not path.is_file():
                    continue
                if root_name == "scripts" and path.name.startswith("test_"):
                    continue
                text = path.read_text(encoding="utf-8", errors="ignore")
                normalized = text.replace("\\", "/")
                for pattern in forbidden:
                    with self.subTest(path=path.relative_to(REPO_ROOT).as_posix(), pattern=pattern):
                        self.assertNotIn(pattern, normalized)


if __name__ == "__main__":
    unittest.main()
