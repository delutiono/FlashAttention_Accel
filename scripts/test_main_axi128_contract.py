import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class MainAxi128ContractTest(unittest.TestCase):
    def test_project_top_uses_128_bit_axi_width(self) -> None:
        pkg = (REPO_ROOT / "rtl" / "fa_pkg.sv").read_text(encoding="utf-8")
        top = (REPO_ROOT / "rtl" / "fa_accel_top.sv").read_text(encoding="utf-8")

        self.assertIn("FA_AXI_DATA_W = 128", pkg)
        self.assertIn("localparam int unsigned TOP_AXI_LANES = FA_AXI_DATA_W / FA_ELEM_W", top)
        self.assertIn(".DATA_W        (FA_AXI_DATA_W)", top)
        self.assertIn("9'(TOP_ROW_BEATS)", top)

    def test_main_rtl_filelist_stays_on_fa_namespace(self) -> None:
        filelist = (REPO_ROOT / "rtl" / "filelist.f").read_text(encoding="utf-8")

        self.assertIn("rtl/fa_accel_top.sv", filelist)
        self.assertNotIn("rtl/sram128", filelist)
        self.assertNotIn("fa_top_sram128", filelist)

    def test_top_scoreboard_runners_use_128_bit_packed_vectors(self) -> None:
        for script_name in (
            "run_top_compute_s32_scoreboard.ps1",
            "run_top_compute_s64_scoreboard.ps1",
            "run_top_compute_s256_scoreboard.ps1",
            "run_top_compute_s4_scoreboard.ps1",
            "run_top_compute_s5_scoreboard.ps1",
            "run_top_compute_s5_stall_scoreboard.ps1",
            "run_top_compute_s16_scoreboard.ps1",
        ):
            with self.subTest(script_name=script_name):
                script = (REPO_ROOT / "scripts" / script_name).read_text(encoding="utf-8")

                self.assertIn("scripts/pack_vectors_128.py", script)
                self.assertIn("+Q_BEATS128=$qPath128", script)
                self.assertIn("+K_BEATS128=$kPath128", script)
                self.assertIn("+V_BEATS128=$vPath128", script)
                self.assertIn("+O_GOLDEN_BEATS128=$oGoldenPath128", script)
                self.assertIn("+DUMP_O_BEATS128=$dumpPath", script)
                self.assertIn('"--format" "beats128"', script)
                self.assertNotIn("+Q_BEATS64=$qPath", script)
                self.assertNotIn("+DUMP_O_BEATS64=$dumpPath", script)
                self.assertNotIn('"--format" "beats64"', script)

    def test_generic_top_smoke_exposes_axi_memory_stall_parameters(self) -> None:
        tb = (REPO_ROOT / "sim" / "tb_top_compute_s32_smoke.sv").read_text(encoding="utf-8")

        for name in (
            "AXI_MEM_AR_READY_STALL_CYCLES",
            "AXI_MEM_AW_READY_STALL_CYCLES",
            "AXI_MEM_W_READY_STALL_CYCLES",
            "AXI_MEM_R_VALID_DELAY_CYCLES",
            "AXI_MEM_B_VALID_DELAY_CYCLES",
        ):
            with self.subTest(name=name):
                self.assertIn(f"parameter int unsigned {name}", tb)
                self.assertIn(f".{name.replace('AXI_MEM_', '')} ({name})", tb)


if __name__ == "__main__":
    unittest.main()
