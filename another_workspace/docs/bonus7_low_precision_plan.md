# Bonus7 Low Precision Implementation Plan

Goal: implement an executable INT8 block-quantization path and error report for the FlashAttention accelerator, following the FlashAttention-3 low-precision strategy of block quantization and optional incoherent processing.

Architecture:
- Keep the existing Q8.8 RTL datapath as the verified baseline.
- Add INT8 block-quantization metadata and tooling first, with a software golden evaluator that reports per-tensor INT8, block INT8, and block INT8 plus Hadamard preconditioning.
- Add RTL configuration hooks and safe groundwork for the later hardware datapath: Makefile integration, token-width fix, wider valid_len, and low-precision register map.

Tasks:
- Create a pure-Python low-precision evaluator in `sim/low_precision_eval.py`.
- Add a unit test in `sim/test_low_precision_eval.py` that proves block quantization reduces reconstruction error on an outlier-heavy tensor and emits attention/bandwidth metrics.
- Fix build integration by adding `axi_stream_data_adapter.v` to `Makefile`.
- Fix the 18-bit token packing truncation in `packed_compute_core.v`.
- Widen `valid_len` to 10 bits so padding mask can represent S=512.
- Add low-precision registers for mode, block size, and Q/K/V scale bases.
- Update README with the bonus7 strategy, register additions, and measured evaluator output.

Validation:
- `python sim/test_low_precision_eval.py`
- `python sim/low_precision_eval.py --seq 64 --block 8 --hadamard`
- `D:\iverilog\bin\iverilog.exe -g2012 -o sim\tb_fa_top.vvp ...`

