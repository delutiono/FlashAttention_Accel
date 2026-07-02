import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class MainGenusSramFlowTest(unittest.TestCase):
    def test_run_genus_accepts_mainline_sram_filelists_without_sram128_path(self) -> None:
        text = (REPO_ROOT / "synth" / "run_genus.tcl").read_text(encoding="utf-8")

        self.assertIn("proc read_path_list", text)
        self.assertIn("proc optional_file", text)
        self.assertIn("sky130A libs.ref sky130_fd_sc_hs lib sky130_fd_sc_hs__tt_025C_1v80.lib", text)
        self.assertIn("sky130A libs.ref sky130_fd_sc_hs lef sky130_fd_sc_hs.lef", text)
        self.assertIn("SRAM_WRAPPER_FILELIST", text)
        self.assertIn("SRAM_LIB_FILELIST", text)
        self.assertIn("SRAM_LEF_FILELIST", text)
        self.assertIn("STD_CELL_LIB", text)
        self.assertIn("STD_CELL_LEF_FILELIST", text)
        self.assertIn("synth fa_sram_macro_files.list", text)
        self.assertIn("synth fa_sram_tt_libs.list", text)
        self.assertIn("synth fa_sram_lefs.list", text)
        self.assertIn("read_hdl -sv -define SYNTHESIS {*}$wrapper_files", text)
        self.assertIn("set rtl_filelist [file join $script_dir filelist.f]", text)
        self.assertIn("read_hdl -define SYNTHESIS -f $rtl_filelist", text)
        self.assertIn("set sdc_file [file join $script_dir constraints.sdc]", text)
        self.assertIn("read_sdc $sdc_file", text)
        self.assertIn("foreach lib_file $lib_files", text)
        self.assertIn("read_libs $lib_file", text)
        self.assertIn("read_physical -lefs $lef_arg", text)
        self.assertNotIn("eval read_libs", text)
        self.assertNotIn("sram128", text)

    def test_packaged_genus_flow_defaults_to_project_root_layout(self) -> None:
        tcl_text = (REPO_ROOT / "synth" / "run_fa_accel_sky130_sram.tcl").read_text(encoding="utf-8")
        pack_text = (REPO_ROOT / "scripts" / "make_genus_bundle.ps1").read_text(encoding="utf-8")

        self.assertIn("GENUS_PROJECT_ROOT", tcl_text)
        self.assertIn("Genus project root", tcl_text)
        self.assertIn("PROJECT_ROOT=$bundle_root", tcl_text)
        self.assertIn("read_physical -lefs $lef_arg", tcl_text)
        self.assertIn('project_root="${GENUS_PROJECT_ROOT:-$script_dir}"', pack_text)
        self.assertIn('workspace_dir="${GENUS_WORKSPACE_DIR:-$project_root/workspace}"', pack_text)
        self.assertIn('"$genus_bin" -batch -files "$syn_script"', pack_text)
        self.assertIn('cd /home/liuqisong/Desktop/genus_bs1', pack_text)

    def test_genus_patch_carries_sram_wrapper_and_unparameterized_blackboxes(self) -> None:
        patch_text = (REPO_ROOT / "scripts" / "make_genus_patch.ps1").read_text(encoding="utf-8")

        self.assertIn('"rtl/fa_sram_macros.v"', patch_text)
        self.assertIn('"workspace/RTL/fa_sram_macros.v"', patch_text)
        self.assertIn("module sky130_sram_0kbytes_1rw1r_32x64_8 (", patch_text)
        self.assertIn("module sky130_sram_0kbytes_1rw1r_48x16_8 (", patch_text)
        self.assertNotIn("'  parameter VERBOSE = 1,'", patch_text)
        self.assertNotIn("'  parameter DATA_WIDTH = 33,'", patch_text)

    def test_synthesis_runbook_documents_mainline_sram_environment(self) -> None:
        text = (REPO_ROOT / "docs" / "synthesis_runbook.md").read_text(encoding="utf-8")

        self.assertIn("SRAM_WRAPPER_FILELIST", text)
        self.assertIn("SRAM_LIB_FILELIST", text)
        self.assertIn("SRAM_LEF_FILELIST", text)
        self.assertIn("synth/fa_sram_macro_files.list", text)
        self.assertIn("synth/fa_sram_tt_libs.list", text)
        self.assertIn("synth/fa_sram_lefs.list", text)
        self.assertIn("synth/fa_stdcell_lefs.list", text)
        self.assertIn("sky130_fd_sc_hs__nom.tlef", text)


if __name__ == "__main__":
    unittest.main()
