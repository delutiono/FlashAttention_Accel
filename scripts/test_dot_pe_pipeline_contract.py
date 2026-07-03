import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_rtl(name: str) -> str:
    return (ROOT / "rtl" / name).read_text(encoding="utf-8")


class DotPePipelineContractTest(unittest.TestCase):
    def test_dot_pe_uses_registered_pipeline(self) -> None:
        rtl = read_rtl("fa_dot_pe.sv")
        self.assertIn("DOT_LATENCY_CYCLES", rtl)
        self.assertIn("DOT_LANES", rtl)
        self.assertIn("ready_o", rtl)
        self.assertIn("prod_s1_q", rtl)
        self.assertIn("chunk_idx_q", rtl)
        self.assertIn("dot_acc_q", rtl)
        self.assertNotRegex(rtl, r"\bdot_o\s*<=\s*valid_i\s*\?\s*dot_sum\(\)")

    def test_score_pipe_delays_indices_to_match_dot_latency(self) -> None:
        rtl = read_rtl("fa_score_pipe.sv")
        self.assertIn("DOT_LATENCY_CYCLES", rtl)
        self.assertIn("DOT_LANES", rtl)
        self.assertIn("ready_o", rtl)
        self.assertIn("q_index_pipe_q", rtl)
        self.assertIn("k_index_pipe_q", rtl)
        self.assertIn("dot_ready", rtl)
        self.assertRegex(rtl, re.compile(r"assign\s+q_index_o\s*=\s*dot_valid\s*\?", re.S))
        self.assertRegex(rtl, re.compile(r"assign\s+k_index_o\s*=\s*dot_valid\s*\?", re.S))

    def test_row_engine_delays_score_metadata(self) -> None:
        rtl = read_rtl("fa_row_engine.sv")
        self.assertIn("SCORE_PIPE_LATENCY", rtl)
        self.assertIn("score_row_start_pipe_q", rtl)
        self.assertIn("score_last_pipe_q", rtl)
        self.assertIn("score_v_pipe_q", rtl)

    def test_group_engine_delays_score_metadata(self) -> None:
        rtl = read_rtl("fa_group_engine.sv")
        self.assertIn("SCORE_PIPE_LATENCY", rtl)
        self.assertIn("score_context_pipe_q", rtl)
        self.assertIn("score_last_pipe_q", rtl)
        self.assertIn("score_v_pipe_q", rtl)
        self.assertIn("score_pipe_ready", rtl)


if __name__ == "__main__":
    unittest.main()
