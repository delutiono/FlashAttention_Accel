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
        self.assertIn("proc configure_physical_context", tcl_text)
        self.assertIn("GENUS_DEF_FILE", tcl_text)
        self.assertIn("GENUS_PREDICT_FLOORPLAN", tcl_text)
        self.assertIn("predict_floorplan", tcl_text)
        self.assertIn("GENUS_ALLOW_PHYSICAL_FALLBACK", tcl_text)
        self.assertIn("proc configure_multicpu", tcl_text)
        self.assertIn("GENUS_THREADS", tcl_text)
        self.assertIn("set_db max_cpus_per_server", tcl_text)
        self.assertIn("set_db auto_super_thread true", tcl_text)
        self.assertIn("run_physical_command {syn_generic -physical}", tcl_text)
        self.assertIn('project_root="${GENUS_PROJECT_ROOT:-$script_dir}"', pack_text)
        self.assertIn('workspace_dir="${GENUS_WORKSPACE_DIR:-$project_root/workspace}"', pack_text)
        self.assertIn('export GENUS_THREADS="${GENUS_THREADS:-8}"', pack_text)
        self.assertIn('"$genus_bin" -batch -files "$syn_script"', pack_text)
        self.assertIn("GENUS_PREDICT_FLOORPLAN", pack_text)
        self.assertIn('cd /home/liuqisong/Desktop/genus_bs1', pack_text)

    def test_genus_patch_carries_sram_wrapper_and_unparameterized_blackboxes(self) -> None:
        patch_text = (REPO_ROOT / "scripts" / "make_genus_patch.ps1").read_text(encoding="utf-8")

        self.assertIn('"fa_pkg.sv"', patch_text)
        self.assertIn('"fa_sram_macros.v"', patch_text)
        self.assertIn('"fa_accel_top.sv"', patch_text)
        self.assertIn('"fa_q_buffer.sv"', patch_text)
        self.assertIn('"fa_kv_buffer.sv"', patch_text)
        self.assertIn('"fa_group_engine.sv"', patch_text)
        self.assertIn('"fa_o_group_store.sv"', patch_text)
        self.assertIn('"workspace/filelists"', patch_text)
        self.assertIn('"rtl.f"', patch_text)
        self.assertIn("../RTL/fa_sram_macros.v", patch_text)
        self.assertIn("../RTL/sky130_sram_macro_blackboxes.v", patch_text)
        self.assertIn("module sky130_sram_0kbytes_1rw1r_32x64_8 (", patch_text)
        self.assertIn("module sky130_sram_0kbytes_1rw1r_48x16_8 (", patch_text)
        self.assertNotIn("'  parameter VERBOSE = 1,'", patch_text)
        self.assertNotIn("'  parameter DATA_WIDTH = 33,'", patch_text)

    def test_constraints_capture_baseline_clock_and_io_environment(self) -> None:
        text = (REPO_ROOT / "synth" / "constraints.sdc").read_text(encoding="utf-8")

        self.assertIn("set CLK_PERIOD_NS", text)
        self.assertIn("5.000", text)
        self.assertIn("create_clock -name clk -period $CLK_PERIOD_NS", text)
        self.assertIn("set_clock_uncertainty", text)
        self.assertIn("set_clock_transition", text)
        self.assertIn("set_false_path -from [get_ports rst_n]", text)
        self.assertIn("set_driving_cell -lib_cell sky130_fd_sc_hs__buf_4", text)
        self.assertIn("set_load", text)

    def test_genus_patch_carries_timing_constraints(self) -> None:
        patch_text = (REPO_ROOT / "scripts" / "make_genus_patch.ps1").read_text(encoding="utf-8")

        self.assertIn('$constraintDir = Join-Path $patchDir "workspace/constraints"', patch_text)
        self.assertIn("synth/constraints.sdc", patch_text)
        self.assertIn("timing_300m.sdc", patch_text)
        self.assertIn("- `workspace/constraints/timing_300m.sdc`", patch_text)
        self.assertIn("GENUS_DEF_FILE", patch_text)
        self.assertIn("GENUS_PREDICT_FLOORPLAN", patch_text)
        self.assertIn("GENUS_ALLOW_PHYSICAL_FALLBACK", patch_text)
        self.assertIn("GENUS_THREADS=8", patch_text)

    def test_main_synthesis_filelist_includes_group_reuse_modules(self) -> None:
        text = (REPO_ROOT / "synth" / "filelist.f").read_text(encoding="utf-8")

        self.assertIn("../rtl/fa_pkg.sv", text)
        self.assertIn("../rtl/fa_q_buffer.sv", text)
        self.assertIn("../rtl/fa_kv_buffer.sv", text)
        self.assertIn("../rtl/fa_group_engine.sv", text)
        self.assertIn("../rtl/fa_o_group_store.sv", text)
        self.assertLess(text.index("../rtl/fa_pkg.sv"), text.index("../rtl/fa_accel_top.sv"))
        self.assertLess(text.index("../rtl/fa_q_buffer.sv"), text.index("../rtl/fa_accel_top.sv"))
        self.assertLess(text.index("../rtl/fa_kv_buffer.sv"), text.index("../rtl/fa_accel_top.sv"))
        self.assertLess(text.index("../rtl/fa_group_engine.sv"), text.index("../rtl/fa_accel_top.sv"))
        self.assertLess(text.index("../rtl/fa_o_group_store.sv"), text.index("../rtl/fa_accel_top.sv"))

    def test_genus_physical_flow_requires_floorplan_or_predict_floorplan(self) -> None:
        text = (REPO_ROOT / "synth" / "run_fa_accel_sky130_sram.tcl").read_text(encoding="utf-8")

        self.assertIn("set allow_physical_fallback [env_flag GENUS_ALLOW_PHYSICAL_FALLBACK 0]", text)
        self.assertIn("set physical_floorplan_ready [configure_physical_context $output_dir $top]", text)
        self.assertIn("GENUS_PHYSICAL=1 requires GENUS_DEF_FILE or a successful predict_floorplan result", text)
        self.assertIn("try_write_def [file join $output_dir ${top}_predict_floorplan.def]", text)
        self.assertIn("create_rc_corner -name sky130_pre_route_rc -cap_table $cap_table", text)
        self.assertNotIn("WARNING: syn_generic -physical failed; retrying syn_generic", text)

    def test_genus_multicpu_flow_is_parameterized(self) -> None:
        text = (REPO_ROOT / "synth" / "run_fa_accel_sky130_sram.tcl").read_text(encoding="utf-8")

        self.assertIn("set threads [env_value GENUS_THREADS 8]", text)
        self.assertIn("set_db max_cpus_per_server $threads", text)
        self.assertIn("set_db auto_super_thread true", text)
        self.assertIn("set_db super_thread_servers [list localhost $threads]", text)
        self.assertIn("set_multi_cpu_usage -local_cpu $threads", text)
        self.assertIn("configure_multicpu", text)

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
