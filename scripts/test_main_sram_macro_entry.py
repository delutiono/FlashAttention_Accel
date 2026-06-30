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
        self.assertNotIn("sky130_sram_0kbytes_1rw1r_64x32_8 ", text)
        self.assertNotIn("sky130_sram_0kbytes_1rw1r_64x64_8 ", text)
        self.assertNotIn("sky130_sram_0kbytes_1rw1r_128x16_16 ", text)

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
        self.assertIn("../sky130_sram_macros/verilog/sky130_sram_0kbytes_1rw1r_32x64_8.v", macro_files)
        self.assertIn("../sky130_sram_macros/verilog/sky130_sram_0kbytes_1rw1r_48x16_8.v", macro_files)


if __name__ == "__main__":
    unittest.main()
