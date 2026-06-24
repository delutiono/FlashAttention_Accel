from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BackendFlowContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_genus_flow_is_location_independent_and_configures_library(self) -> None:
        script = self.read("synth/run_genus.tcl")
        self.assertIn("REPO_ROOT", script)
        self.assertIn("STD_CELL_LIB", script)
        self.assertIn("set_db init_lib_search_path", script)
        self.assertIn("set_db library", script)
        self.assertIn("file mkdir", script)
        self.assertIn("write_hdl", script)
        self.assertNotIn("sky130_fd_sc_hs__tt_025C_1v80_slim.lib", script)

    def test_synthesis_constraints_exclude_clock_and_reset_from_io_delays(self) -> None:
        sdc = self.read("synth/constraints.sdc")
        self.assertIn("[get_ports {clk rst_n}]", sdc)
        self.assertIn("set_false_path -from [get_ports rst_n]", sdc)

    def test_backend_documentation_lists_genus_library_input(self) -> None:
        doc = self.read("backend_flow.md")
        self.assertIn("STD_CELL_LIB", doc)
        self.assertIn("Genus Logic Synthesis", doc)


if __name__ == "__main__":
    unittest.main()
