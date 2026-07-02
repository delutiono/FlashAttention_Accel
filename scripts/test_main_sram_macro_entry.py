import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class MainSramMacroEntryTest(unittest.TestCase):
    def test_main_sram_wrappers_use_project_module_names(self) -> None:
        text = (REPO_ROOT / "rtl" / "fa_sram_macros.v").read_text(encoding="utf-8")

        self.assertIn("module fa_sram_1rw1r_64x32_sky130", text)
        self.assertIn("module fa_sram_1rw1r_64x64_sky130", text)
        self.assertIn("module fa_sram_1rw1r_128x16_sky130", text)
        self.assertNotIn("module sky130_sram_0kbytes_1rw1r_64x32_8_wrapper", text)
        self.assertNotIn("module sky130_sram_0kbytes_1rw1r_64x64_8_wrapper", text)
        self.assertNotIn("module sky130_sram_0kbytes_1rw1r_128x16_16_timed_wrapper", text)

    def test_main_sram_wrappers_instantiate_only_selected_compliant_macros(self) -> None:
        text = (REPO_ROOT / "rtl" / "fa_sram_macros.v").read_text(encoding="utf-8")

        self.assertIn("sky130_sram_0kbytes_1rw1r_32x64_8", text)
        self.assertIn("sky130_sram_0kbytes_1rw1r_48x16_8", text)
        self.assertIn(".VERBOSE(0)", text)
        self.assertNotIn("sky130_sram_0kbytes_1rw1r_64x32_8 ", text)
        self.assertNotIn("sky130_sram_0kbytes_1rw1r_64x64_8 ", text)
        self.assertNotIn("sky130_sram_0kbytes_1rw1r_128x16_16 ", text)

    def test_main_sram_wrappers_remove_macro_parameter_overrides_for_synthesis(self) -> None:
        text = (REPO_ROOT / "rtl" / "fa_sram_macros.v").read_text(encoding="utf-8")

        self.assertIn("`ifdef SYNTHESIS", text)
        self.assertIn("`else", text)
        self.assertIn("`endif", text)
        self.assertIn(".VERBOSE(0)", text)

        synthesis_insts = re.findall(
            r"`ifdef SYNTHESIS\s+"
            r"(sky130_sram_0kbytes_1rw1r_(?:32x64|48x16)_8\s+\S+\s*\()"
            r"\s+`else\s+"
            r"sky130_sram_0kbytes_1rw1r_(?:32x64|48x16)_8\s+#\(",
            text,
        )
        self.assertGreaterEqual(len(synthesis_insts), 6)
        self.assertTrue(all("#(" not in inst for inst in synthesis_insts))
        self.assertTrue(all(".VERBOSE" not in inst for inst in synthesis_insts))

    def test_q_and_kv_buffers_instantiate_sram_macro_wrappers(self) -> None:
        q_text = (REPO_ROOT / "rtl" / "fa_q_buffer.sv").read_text(encoding="utf-8")
        kv_text = (REPO_ROOT / "rtl" / "fa_kv_buffer.sv").read_text(encoding="utf-8")

        self.assertIn("fa_sram_1rw1r_64x64_sky130", q_text)
        self.assertIn("fa_sram_1rw1r_64x64_sky130", kv_text)
        self.assertIn("genvar bank", q_text)
        self.assertIn("genvar bank", kv_text)
        self.assertIn("bank_read_en", q_text)
        self.assertIn("k_bank_read_en", kv_text)
        self.assertIn("v_bank_read_en", kv_text)
        self.assertNotIn(".rd_en     (1'b1)", q_text)
        self.assertNotIn(".rd_en     (1'b1)", kv_text)
        self.assertNotIn("q_mem [D]", q_text)
        self.assertNotIn("k_mem [TILE_ROWS][D]", kv_text)
        self.assertNotIn("v_mem [TILE_ROWS][D]", kv_text)

    def test_top_waits_for_sram_read_latency_before_row_engine(self) -> None:
        text = (REPO_ROOT / "rtl" / "fa_accel_top.sv").read_text(encoding="utf-8")

        self.assertIn("TOP_ST_COMPUTE_BUFFER_READ_WAIT", text)
        self.assertIn("compute_buffer_wait_q", text)
        self.assertIn("TOP_BUFFER_READ_WAIT_CYCLES", text)

    def test_top_does_not_instantiate_legacy_row_engine(self) -> None:
        text = (REPO_ROOT / "rtl" / "fa_accel_top.sv").read_text(encoding="utf-8")

        self.assertNotIn("u_row_engine", text)
        self.assertNotIn("row_engine_busy", text)
        self.assertNotIn("row_engine_valid_o", text)

    def test_top_does_not_instantiate_dead_legacy_scheduler(self) -> None:
        text = (REPO_ROOT / "rtl" / "fa_accel_top.sv").read_text(encoding="utf-8")

        self.assertNotIn("u_scheduler", text)
        self.assertNotIn("scheduler_q_group", text)
        self.assertNotIn("scheduler_group_done", text)

    def test_main_sram_synth_filelists_do_not_depend_on_sram128_rtl_path(self) -> None:
        for relative_path in (
            "synth/fa_sram_macro_files.list",
            "synth/fa_sram_tt_libs.list",
            "synth/fa_sram_lefs.list",
        ):
            text = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
            self.assertNotIn("rtl/sram128", text)
            self.assertNotIn("synth/sram128", text)

        macro_files = (REPO_ROOT / "synth/fa_sram_macro_files.list").read_text(encoding="utf-8")
        self.assertIn("../rtl/fa_sram_macros.v", macro_files)
        self.assertIn("../sky130A/libs.ref/sky130_sram_macros/verilog/sky130_sram_0kbytes_1rw1r_32x64_8.v", macro_files)
        self.assertNotIn("48x16", macro_files)

        sram_libs = (REPO_ROOT / "synth/fa_sram_tt_libs.list").read_text(encoding="utf-8")
        sram_lefs = (REPO_ROOT / "synth/fa_sram_lefs.list").read_text(encoding="utf-8")
        self.assertIn("../sky130A/libs.ref/sky130_sram_macros/lib/sky130_sram_0kbytes_1rw1r_32x64_8_TT_1p8V_25C.lib", sram_libs)
        self.assertIn("../sky130A/libs.ref/sky130_sram_macros/lef/sky130_sram_0kbytes_1rw1r_32x64_8.lef", sram_lefs)
        self.assertNotIn("48x16", sram_libs)
        self.assertNotIn("48x16", sram_lefs)


if __name__ == "__main__":
    unittest.main()
