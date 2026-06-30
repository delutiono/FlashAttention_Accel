import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class MainGenusSramFlowTest(unittest.TestCase):
    def test_run_genus_accepts_mainline_sram_filelists_without_sram128_path(self) -> None:
        text = (REPO_ROOT / "synth" / "run_genus.tcl").read_text(encoding="utf-8")

        self.assertIn("proc read_path_list", text)
        self.assertIn("SRAM_WRAPPER_FILELIST", text)
        self.assertIn("SRAM_LIB_FILELIST", text)
        self.assertIn("SRAM_LEF_FILELIST", text)
        self.assertIn("synth fa_sram_macro_files.list", text)
        self.assertIn("synth fa_sram_tt_libs.list", text)
        self.assertIn("synth fa_sram_lefs.list", text)
        self.assertIn("read_hdl -sv {*}$wrapper_files", text)
        self.assertIn("set rtl_filelist [file join $script_dir filelist.f]", text)
        self.assertIn("read_hdl -f $rtl_filelist", text)
        self.assertIn("set sdc_file [file join $script_dir constraints.sdc]", text)
        self.assertIn("read_sdc $sdc_file", text)
        self.assertIn("foreach lib_file $lib_files", text)
        self.assertIn("read_libs $lib_file", text)
        self.assertIn("read_physical -lef {*}$lef_files", text)
        self.assertNotIn("eval read_libs", text)
        self.assertNotIn("sram128", text)

    def test_synthesis_runbook_documents_mainline_sram_environment(self) -> None:
        text = (REPO_ROOT / "docs" / "synthesis_runbook.md").read_text(encoding="utf-8")

        self.assertIn("SRAM_WRAPPER_FILELIST", text)
        self.assertIn("SRAM_LIB_FILELIST", text)
        self.assertIn("SRAM_LEF_FILELIST", text)
        self.assertIn("synth/fa_sram_macro_files.list", text)
        self.assertIn("synth/fa_sram_tt_libs.list", text)
        self.assertIn("synth/fa_sram_lefs.list", text)
        self.assertIn("sky130_fd_sc_hs__nom.tlef", text)


if __name__ == "__main__":
    unittest.main()
