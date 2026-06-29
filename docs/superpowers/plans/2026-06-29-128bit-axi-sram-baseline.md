# 128-bit AXI SRAM Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the minimum-engineering final baseline path around a 128-bit AXI master and compliant SKY130 SRAM macro wrappers, reusing the working `genus/` example architecture wherever practical.

**Architecture:** Keep the current 64-bit RTL as fallback and add a separate `fa_top_sram128` path that imports the example's 128-bit DMA/control/scheduler/compute organization. Replace only the non-compliant SRAM macro layer and verification/synthesis packaging needed to satisfy the project baseline.

**Tech Stack:** SystemVerilog/Verilog RTL, ModelSim locally, Xcelium and Genus on the remote EDA server, Python vector/comparator scripts, PowerShell local runners, Tcl synthesis scripts.

---

## File Structure

Create or modify these project-owned files. Do not modify files inside `genus/`; treat that directory as an upstream reference.

- Create: `rtl/sram128/`
  - Imported and lightly adapted 128-bit RTL modules copied from `genus/workspace/RTL/`.
  - Top module name for this branch: `fa_top_sram128`.
- Create: `rtl/sram128/filelist.f`
  - Project-owned RTL filelist for local lint/sim and remote synthesis.
- Create: `sim/sram128/`
  - 128-bit AXI memory model wrappers, SRAM behavioral models, and S256 testbenches.
- Create: `scripts/pack_vectors_128.py`
  - Project-owned Q/K/V `words16` to 128-bit AXI beat packer, derived from `genus_exzample_sim/pack_vectors_128.py`.
- Modify: `scripts/compare_vector_output.py`
  - Add `beats128` DUT input support.
- Modify: `scripts/test_compare_vector_output.py`
  - Add coverage for `beats128` lane unpacking.
- Create: `scripts/test_pack_vectors_128.py`
  - Unit tests for project-owned 128-bit vector packing.
- Create: `scripts/run_sram128_axi_lite_smoke.ps1`
  - Local RTL AXI-Lite smoke runner.
- Create: `scripts/run_sram128_zero_s256.ps1`
  - Local RTL all-zero S256 runner.
- Create: `scripts/run_sram128_s256_scoreboard.ps1`
  - Local RTL random S256 runner and comparator gate.
- Create: `synth/run_sram128_genus.tcl`
  - Remote Genus script template driven by environment variables.
- Create: `synth/sram128_filelist.f`
  - Synthesis filelist for the `fa_top_sram128` branch.
- Create: `docs/sram128_remote_runbook.md`
  - Exact remote path inputs, Genus commands, Xcelium commands, and returned artifact contract.

The selected compliant SRAM macro cannot be fully wrapped until the user provides the remote macro `.v` port list. The plan therefore separates local behavioral simulation from final macro-wrapper binding.

---

### Task 1: Add `beats128` Comparator Support

**Files:**
- Modify: `scripts/compare_vector_output.py`
- Modify: `scripts/test_compare_vector_output.py`

- [ ] **Step 1: Write failing unit tests for 128-bit beat unpack**

Add these tests to `scripts/test_compare_vector_output.py`:

```python
def test_load_dut_words_accepts_beats128(tmp_path):
    dut = tmp_path / "dut_beats128.hex"
    # Lanes are little-endian int16: 0001, ffff, 0002, fffe, 0003, fffd, 0004, fffc.
    dut.write_text("fffc0004fffd0003fffe0002ffff0001\n", encoding="ascii")

    words = compare_vector_output.load_dut_words(
        dut,
        dut_format="beats128",
        dimension=8,
        rows=1,
        beats_per_row=1,
    )

    assert words == [1, -1, 2, -2, 3, -3, 4, -4]


def test_load_dut_words_beats128_discards_stride_padding(tmp_path):
    dut = tmp_path / "dut_beats128.hex"
    dut.write_text(
        "00080007000600050004000300020001\n"
        "0010000f000e000d000c000b000a0009\n",
        encoding="ascii",
    )

    words = compare_vector_output.load_dut_words(
        dut,
        dut_format="beats128",
        dimension=10,
        rows=1,
        beats_per_row=2,
    )

    assert words == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:

```powershell
python -B -m pytest scripts/test_compare_vector_output.py -k beats128 -q
```

Expected: failures showing `beats128` is not an accepted DUT format.

- [ ] **Step 3: Implement `beats128` parsing**

In `scripts/compare_vector_output.py`, change the type alias and add the parser:

```python
DutFormat = Literal["words16", "beats64", "beats128"]
```

Add:

```python
def _parse_beat128_line(line: str, *, path: Path, line_number: int) -> list[int]:
    if len(line) != 32:
        raise ValueError(f"{path}:{line_number}: expected a 32-digit 128-bit beat hex word")
    try:
        beat = int(line, 16)
    except ValueError as exc:
        raise ValueError(f"{path}:{line_number}: invalid 128-bit beat hex word {line!r}") from exc
    return [_int16_from_word((beat >> (16 * lane)) & 0xFFFF) for lane in range(8)]
```

Add:

```python
def _read_beats128(
    path: Path,
    *,
    dimension: int,
    rows: int,
    beats_per_row: int,
) -> list[int]:
    lines = _parse_hex_lines(path)
    expected_beats = rows * beats_per_row
    if len(lines) != expected_beats:
        raise ValueError(f"{path}: expected {expected_beats} beats, found {len(lines)}")

    words: list[int] = []
    for row in range(rows):
        row_words: list[int] = []
        for beat_index in range(beats_per_row):
            line_index = row * beats_per_row + beat_index
            row_words.extend(
                _parse_beat128_line(
                    lines[line_index],
                    path=path,
                    line_number=line_index + 1,
                )
            )
        words.extend(row_words[:dimension])
    return words
```

Extend `load_dut_words()`:

```python
    if dut_format == "beats128":
        return _read_beats128(
            path,
            dimension=dimension,
            rows=rows,
            beats_per_row=beats_per_row,
        )
```

Extend CLI choices:

```python
    parser.add_argument("--format", choices=("words16", "beats64", "beats128"), default="words16")
```

- [ ] **Step 4: Run the focused tests and confirm they pass**

Run:

```powershell
python -B -m pytest scripts/test_compare_vector_output.py -k beats128 -q
```

Expected: `2 passed`.

- [ ] **Step 5: Run all comparator tests**

Run:

```powershell
python -B -m pytest scripts/test_compare_vector_output.py -q
```

Expected: all tests in that file pass.

- [ ] **Step 6: Commit**

```powershell
git add scripts/compare_vector_output.py scripts/test_compare_vector_output.py
git commit -m "Add beats128 comparator support"
```

---

### Task 2: Add Project-Owned 128-bit Vector Packer

**Files:**
- Create: `scripts/pack_vectors_128.py`
- Create: `scripts/test_pack_vectors_128.py`

- [ ] **Step 1: Write failing packer tests**

Create `scripts/test_pack_vectors_128.py`:

```python
from pathlib import Path

import pytest

import scripts.pack_vectors_128 as pack_vectors_128


def test_pack_tensor_packs_little_endian_128_bit_beats(tmp_path: Path):
    words = tmp_path / "q.hex"
    words.write_text(
        "\n".join(f"{value:04x}" for value in range(1, 17)) + "\n",
        encoding="ascii",
    )
    out = tmp_path / "q_beats128.hex"

    count = pack_vectors_128.pack_tensor(
        input_words=words,
        output_beats=out,
        rows=1,
        dimension=16,
        stride_bytes=32,
    )

    assert count == 2
    assert out.read_text(encoding="ascii").splitlines() == [
        "00080007000600050004000300020001",
        "0010000F000E000D000C000B000A0009",
    ]


def test_pack_tensor_adds_stride_padding(tmp_path: Path):
    words = tmp_path / "q.hex"
    words.write_text("\n".join(f"{value:04x}" for value in range(1, 11)) + "\n", encoding="ascii")
    out = tmp_path / "q_beats128.hex"

    count = pack_vectors_128.pack_tensor(
        input_words=words,
        output_beats=out,
        rows=1,
        dimension=10,
        stride_bytes=32,
    )

    assert count == 2
    assert out.read_text(encoding="ascii").splitlines() == [
        "00080007000600050004000300020001",
        "000000000000000000000000000A0009",
    ]


def test_pack_tensor_rejects_wrong_word_count(tmp_path: Path):
    words = tmp_path / "q.hex"
    words.write_text("0001\n", encoding="ascii")

    with pytest.raises(ValueError, match="expected 2 words"):
        pack_vectors_128.pack_tensor(
            input_words=words,
            output_beats=tmp_path / "out.hex",
            rows=1,
            dimension=2,
            stride_bytes=16,
        )
```

- [ ] **Step 2: Run tests and confirm import failure**

Run:

```powershell
python -B -m pytest scripts/test_pack_vectors_128.py -q
```

Expected: failure because `scripts.pack_vectors_128` does not exist.

- [ ] **Step 3: Create the packer**

Create `scripts/pack_vectors_128.py` with this content:

```python
#!/usr/bin/env python3
"""Pack generated int16 Q/K/V vectors into 128-bit AXI beat hex files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _parse_word16(path: Path) -> list[int]:
    words: list[int] = []
    for line_no, raw in enumerate(path.read_text(encoding="ascii").splitlines(), start=1):
        text = raw.strip()
        if not text:
            continue
        if len(text) != 4:
            raise ValueError(f"{path}:{line_no}: expected 4 hex digits")
        words.append(int(text, 16) & 0xFFFF)
    return words


def _pack_beat128(lanes: list[int]) -> str:
    if len(lanes) > 8:
        raise ValueError("128-bit beat can contain at most eight int16 lanes")
    padded = lanes + [0] * (8 - len(lanes))
    beat = 0
    for index, value in enumerate(padded):
        beat |= (value & 0xFFFF) << (16 * index)
    return f"{beat:032X}"


def pack_tensor(
    *,
    input_words: Path,
    output_beats: Path,
    rows: int,
    dimension: int,
    stride_bytes: int,
) -> int:
    words = _parse_word16(input_words)
    expected = rows * dimension
    if len(words) != expected:
        raise ValueError(f"{input_words}: expected {expected} words, found {len(words)}")

    if stride_bytes % 16 != 0:
        raise ValueError(f"stride_bytes must be a multiple of 16 for 128-bit beats, got {stride_bytes}")
    if stride_bytes < dimension * 2:
        raise ValueError(f"stride_bytes {stride_bytes} is smaller than packed row bytes {dimension * 2}")

    elements_per_row = stride_bytes // 2
    beats_per_row = stride_bytes // 16
    lines: list[str] = []
    for row in range(rows):
        row_words = words[row * dimension : (row + 1) * dimension]
        padded = row_words + [0] * (elements_per_row - dimension)
        for beat_idx in range(beats_per_row):
            start = beat_idx * 8
            lines.append(_pack_beat128(padded[start : start + 8]))

    output_beats.parent.mkdir(parents=True, exist_ok=True)
    output_beats.write_text("".join(f"{line}\n" for line in lines), encoding="ascii")
    return len(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    case_name = metadata["case_name"]
    rows = int(metadata["sequence_length"])
    dimension = int(metadata["dimension"])
    stride_bytes = int(metadata["stride_bytes"])

    outputs: dict[str, str] = {}
    for tensor in ("Q", "K", "V"):
        input_words = args.metadata.parent / metadata["files"][f"{tensor}_16b_hex"]["path"]
        output_beats = args.output_dir / f"{case_name}_{tensor}_beats128.hex"
        pack_tensor(
            input_words=input_words,
            output_beats=output_beats,
            rows=rows,
            dimension=dimension,
            stride_bytes=stride_bytes,
        )
        outputs[tensor] = str(output_beats)

    print(json.dumps({"case_name": case_name, "beats128": outputs}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run packer tests**

Run:

```powershell
python -B -m pytest scripts/test_pack_vectors_128.py -q
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add scripts/pack_vectors_128.py scripts/test_pack_vectors_128.py
git commit -m "Add 128-bit vector packer"
```

---

### Task 3: Import the Minimal Example RTL into a Project-Owned Branch Path

**Files:**
- Create: `rtl/sram128/*.v`
- Create: `rtl/sram128/filelist.f`

- [ ] **Step 1: Create the target directory**

Run:

```powershell
New-Item -ItemType Directory -Force -Path rtl\sram128 | Out-Null
```

Expected: `rtl\sram128` exists.

- [ ] **Step 2: Copy reusable RTL modules**

Run:

```powershell
$src = "genus\workspace\RTL"
$dst = "rtl\sram128"
$files = @(
  "axi_lite_regs.v",
  "task_ctrl.v",
  "perf_counters.v",
  "dma_cmd_queue.v",
  "dma_read_master.v",
  "dma_write_master.v",
  "dma_engine.v",
  "page_manager.v",
  "q_load_store_adapter.v",
  "k_load_adapter.v",
  "v_load_adapter.v",
  "o_store_adapter.v",
  "dot_frontend.v",
  "score_exp_banked_rom.v",
  "score_exp_pipe.v",
  "update_token_fifo.v",
  "update_state_cluster.v",
  "packed_compute_core.v",
  "score_scheduler.v",
  "reciprocal_approx.v",
  "output_norm_pipe.v",
  "finalize_cluster.v"
)
foreach ($file in $files) {
  Copy-Item -Force (Join-Path $src $file) (Join-Path $dst $file)
}
Copy-Item -Force (Join-Path $src "fa_top.v") (Join-Path $dst "fa_top_sram128.v")
```

Expected: each copied file exists under `rtl\sram128`.

- [ ] **Step 3: Rename top module**

Edit `rtl/sram128/fa_top_sram128.v`:

```verilog
module fa_top_sram128 (
```

The rest of the port list stays identical to the example top for the first import.

- [ ] **Step 4: Create an initial filelist**

Create `rtl/sram128/filelist.f`:

```text
rtl/sram128/sram128_behav_models.v
rtl/sram128/axi_lite_regs.v
rtl/sram128/task_ctrl.v
rtl/sram128/perf_counters.v
rtl/sram128/dma_cmd_queue.v
rtl/sram128/dma_read_master.v
rtl/sram128/dma_write_master.v
rtl/sram128/dma_engine.v
rtl/sram128/page_manager.v
rtl/sram128/q_load_store_adapter.v
rtl/sram128/k_load_adapter.v
rtl/sram128/v_load_adapter.v
rtl/sram128/o_store_adapter.v
rtl/sram128/dot_frontend.v
rtl/sram128/score_exp_banked_rom.v
rtl/sram128/score_exp_pipe.v
rtl/sram128/update_token_fifo.v
rtl/sram128/update_state_cluster.v
rtl/sram128/packed_compute_core.v
rtl/sram128/score_scheduler.v
rtl/sram128/reciprocal_approx.v
rtl/sram128/output_norm_pipe.v
rtl/sram128/finalize_cluster.v
rtl/sram128/fa_top_sram128.v
```

- [ ] **Step 5: Copy local behavioral SRAM model for bring-up**

Run:

```powershell
Copy-Item -Force genus_exzample_sim\sram_behav_models.v rtl\sram128\sram128_behav_models.v
```

Expected: local behavioral simulation can still resolve the example SRAM wrapper module names. This is temporary for local bring-up only; compliant macro replacement happens in Task 6.

- [ ] **Step 6: Compile imported branch**

Run:

```powershell
vlib work_sram128_import
vlog -sv -work work_sram128_import -f rtl/sram128/filelist.f
```

Expected: `Errors: 0`. Warnings are acceptable if they match the original example warnings.

- [ ] **Step 7: Commit**

```powershell
git add rtl/sram128
git commit -m "Import 128-bit SRAM baseline RTL skeleton"
```

---

### Task 4: Create Project-Owned 128-bit Simulation Harness

**Files:**
- Create: `sim/sram128/axi_mem_model_128.sv`
- Create: `sim/sram128/tb_fa_top_sram128_axi_lite_smoke.sv`
- Create: `sim/sram128/tb_fa_top_sram128_zero_s256.sv`
- Create: `sim/sram128/tb_fa_top_sram128_s256_scoreboard.sv`

- [ ] **Step 1: Copy existing 128-bit simulation assets**

Run:

```powershell
New-Item -ItemType Directory -Force -Path sim\sram128 | Out-Null
Copy-Item -Force genus_exzample_sim\axi_mem_model_128.sv sim\sram128\axi_mem_model_128.sv
Copy-Item -Force genus_exzample_sim\tb_fa_top_axi_lite_smoke.sv sim\sram128\tb_fa_top_sram128_axi_lite_smoke.sv
Copy-Item -Force genus_exzample_sim\tb_fa_top_zero_s256.sv sim\sram128\tb_fa_top_sram128_zero_s256.sv
Copy-Item -Force genus_exzample_sim\tb_fa_top_s256_scoreboard.sv sim\sram128\tb_fa_top_sram128_s256_scoreboard.sv
```

- [ ] **Step 2: Rename DUT modules in copied testbenches**

In the three copied testbenches, replace:

```verilog
fa_top dut (
```

with:

```verilog
fa_top_sram128 dut (
```

Also rename each testbench module:

```verilog
module tb_fa_top_sram128_axi_lite_smoke;
module tb_fa_top_sram128_zero_s256;
module tb_fa_top_sram128_s256_scoreboard;
```

- [ ] **Step 3: Compile AXI-Lite smoke test**

Run:

```powershell
vlib work_sram128_axi
vlog -sv -work work_sram128_axi -f rtl/sram128/filelist.f sim/sram128/axi_mem_model_128.sv sim/sram128/tb_fa_top_sram128_axi_lite_smoke.sv
```

Expected: `Errors: 0`.

- [ ] **Step 4: Run AXI-Lite smoke**

Run:

```powershell
vsim -c -lib work_sram128_axi tb_fa_top_sram128_axi_lite_smoke -do "run -all; quit -f"
```

Expected output includes:

```text
PASS: fa_top AXI-Lite register smoke
```

- [ ] **Step 5: Commit**

```powershell
git add sim/sram128
git commit -m "Add sram128 simulation harness"
```

---

### Task 5: Add Local Runner Scripts for SRAM128 Gates

**Files:**
- Create: `scripts/run_sram128_axi_lite_smoke.ps1`
- Create: `scripts/run_sram128_zero_s256.ps1`
- Create: `scripts/run_sram128_s256_scoreboard.ps1`

- [ ] **Step 1: Create AXI-Lite runner**

Create `scripts/run_sram128_axi_lite_smoke.ps1`:

```powershell
param(
  [string]$WorkLib = "work_sram128_axi_lite"
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Exe,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
  )
  Write-Host ">> $Exe $($Args -join ' ')"
  & $Exe @Args
  if ($LASTEXITCODE -ne 0) {
    throw "$Exe failed with exit code $LASTEXITCODE"
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

Invoke-Checked vlib $WorkLib
Invoke-Checked vlog "-sv" "-work" $WorkLib "-f" "rtl/sram128/filelist.f" "sim/sram128/axi_mem_model_128.sv" "sim/sram128/tb_fa_top_sram128_axi_lite_smoke.sv"
Invoke-Checked vsim "-c" "-lib" $WorkLib "tb_fa_top_sram128_axi_lite_smoke" "-do" "run -all; quit -f"
```

- [ ] **Step 2: Create zero S256 runner**

Use `genus_exzample_sim/run_zero_s256.ps1` as the source, with these required substitutions:

```text
WorkLib default: work_sram128_zero_s256
RTL filelist: rtl/sram128/filelist.f
AXI model: sim/sram128/axi_mem_model_128.sv
Testbench: sim/sram128/tb_fa_top_sram128_zero_s256.sv
Top module: tb_fa_top_sram128_zero_s256
```

- [ ] **Step 3: Create random S256 scoreboard runner**

Use `genus_exzample_sim/run_s256_scoreboard.ps1` as the source, with these required substitutions:

```text
WorkLib default: work_sram128_s256_scoreboard
CaseName default: sram128_s256_d64_seed100
VectorDir default: artifacts/vectors/sram128_s256_d64_seed100
RunDir default: artifacts/runs/sram128_s256_d64_seed100
Packer: scripts/pack_vectors_128.py
RTL filelist: rtl/sram128/filelist.f
AXI model: sim/sram128/axi_mem_model_128.sv
Testbench: sim/sram128/tb_fa_top_sram128_s256_scoreboard.sv
Top module: tb_fa_top_sram128_s256_scoreboard
Comparator threshold: --require-mae 0.03 --require-maxae 0.10
```

- [ ] **Step 4: Run AXI-Lite runner**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_sram128_axi_lite_smoke.ps1
```

Expected: output includes `PASS: fa_top AXI-Lite register smoke`.

- [ ] **Step 5: Run zero S256 runner**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_sram128_zero_s256.ps1
```

Expected: output includes `PASS: fa_top S256 zero run` and `o_write_beats=2048`.

- [ ] **Step 6: Run random S256 scoreboard runner**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_sram128_s256_scoreboard.ps1
```

Expected: output includes `PASS` from `compare_vector_output.py` with `mae <= 0.03` and `maxae <= 0.10`.

- [ ] **Step 7: Commit**

```powershell
git add scripts/run_sram128_axi_lite_smoke.ps1 scripts/run_sram128_zero_s256.ps1 scripts/run_sram128_s256_scoreboard.ps1
git commit -m "Add sram128 local regression runners"
```

---

### Task 6: Collect Remote SRAM Macro Port and Library Inputs

**Files:**
- Create: `docs/sram128_remote_runbook.md`

- [ ] **Step 1: Ask the user for exact remote inputs**

Ask the user to provide the following paths copied from the remote EDA server:

```text
STD_CELL_LIB_TT=
TECH_LEF=
STD_CELL_LEF=
SRAM_128x128_LIB_TT=
SRAM_128x128_LEF=
SRAM_128x128_VERILOG=
SRAM_128x128_BEHAV_VERILOG=
GENUS_COMMAND=
XCELIUM_ANALYZE_COMMAND=
XCELIUM_ELAB_COMMAND=
XCELIUM_RUN_COMMAND=
```

Use `sky130_sram_2kbytes_1rw1r_128x128_16` as the first-choice macro. If the user reports that it is unavailable, ask for the same four SRAM paths for one of these listed alternatives:

```text
sky130_sram_4kbytes_1rw1r_128x256_8
sky130_sram_8kbytes_1rw1r_128x512_8
sky130_sram_0kbytes_1rw1r_32x128_8
```

- [ ] **Step 2: Create the remote runbook with required path format**

Create `docs/sram128_remote_runbook.md`:

```markdown
# SRAM128 Remote EDA Runbook

## Required Remote Inputs

The implementation uses environment variables rather than hard-coded remote paths. On the remote server, create `sram128_env.sh` with real `export` commands for these variable names, then source it before running Genus or Xcelium:

```sh
test -n "$STD_CELL_LIB_TT" || { echo "STD_CELL_LIB_TT is unset"; exit 2; }
test -n "$TECH_LEF" || { echo "TECH_LEF is unset"; exit 2; }
test -n "$STD_CELL_LEF" || { echo "STD_CELL_LEF is unset"; exit 2; }
test -n "$SRAM_128x128_LIB_TT" || { echo "SRAM_128x128_LIB_TT is unset"; exit 2; }
test -n "$SRAM_128x128_LEF" || { echo "SRAM_128x128_LEF is unset"; exit 2; }
test -n "$SRAM_128x128_VERILOG" || { echo "SRAM_128x128_VERILOG is unset"; exit 2; }
test -n "$SRAM_128x128_BEHAV_VERILOG" || { echo "SRAM_128x128_BEHAV_VERILOG is unset"; exit 2; }
```

The selected SRAM must be listed in `docs/SKY130_readme.txt`.

## Local Pre-Remote Gates

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_sram128_axi_lite_smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_sram128_zero_s256.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_sram128_s256_scoreboard.ps1
```

## Remote Genus Gate

```sh
cd synth
genus -batch -files run_sram128_genus.tcl
```

Return these directories:

```text
synth/reports/fa_top_sram128/
synth/outputs/fa_top_sram128/
```

## Remote Simulation Gate

Run the mapped or gate-level simulation with the same Q/K/V seed100 vectors used by the RTL scoreboard. Return:

```text
artifacts/runs/sram128_s256_d64_seed100/
```
```

- [ ] **Step 3: Commit**

```powershell
git add docs/sram128_remote_runbook.md
git commit -m "Document sram128 remote EDA inputs"
```

---

### Task 7: Replace Example SRAM Layer with Compliant Macro Wrappers

**Files:**
- Create: `rtl/sram128/sram128_macro_wrappers.v`
- Modify: copied SRAM cluster files under `rtl/sram128/`
- Modify: `rtl/sram128/filelist.f`

- [ ] **Step 1: Inspect selected SRAM blackbox ports**

After the user provides `SRAM_128x128_VERILOG`, run on the remote server:

```sh
grep -n "module sky130_sram_2kbytes_1rw1r_128x128_16" "$SRAM_128x128_VERILOG"
sed -n '/module sky130_sram_2kbytes_1rw1r_128x128_16/,/endmodule/p' "$SRAM_128x128_VERILOG"
```

Expected: a readable module declaration with clock, chip-select, write-enable, address, data-in, data-out, and mask pins. Copy the exact port declaration into the task notes before editing wrappers.

- [ ] **Step 2: Create a compliant wrapper module**

Create `rtl/sram128/sram128_macro_wrappers.v`. Use the exact port names from Step 1 for the selected macro instance. The wrapper must expose this project-side interface:

```verilog
module sram128_1rw1r_128x128_wrapper (
    input  wire          clk,
    input  wire          rw_csb,
    input  wire          rw_web,
    input  wire [6:0]    rw_addr,
    input  wire [15:0]   rw_wmask,
    input  wire [127:0]  rw_wdata,
    output wire [127:0]  rw_rdata,
    input  wire          r_csb,
    input  wire [6:0]    r_addr,
    output wire [127:0]  r_rdata
);
    // Add a Chinese comment here explaining that this wrapper normalizes
    // the project SRAM interface while instantiating only contest-allowed macros.
    // Instantiate the selected compliant SRAM macro here using the exact
    // blackbox ports copied from SRAM_128x128_VERILOG in Step 1.
endmodule
```

Do not commit a comment-only wrapper. The implementation step is complete only when every macro port from the selected SRAM blackbox is connected to the wrapper interface above.

- [ ] **Step 3: Patch SRAM clusters to instantiate compliant wrappers**

Search:

```powershell
rg "sky130_sram_0kbytes|sky130_sram_1kbytes|sky130_sram_2kbytes" rtl/sram128
```

For every old example SRAM macro instance, replace the direct macro instance with `sram128_1rw1r_128x128_wrapper` or a narrower adapter that feeds it. Add a Chinese comment at each cluster boundary:

```verilog
// Add a Chinese comment here explaining that the logical bank keeps the
// example dataflow while the physical SRAM macro is contest-compliant.
```

- [ ] **Step 4: Remove temporary behavioral model from synthesis filelist**

Modify `rtl/sram128/filelist.f` for local RTL simulation to keep behavioral models. Create a separate synthesis filelist in Task 8 so synthesis uses blackbox macro Verilog and wrapper files instead of behavioral arrays.

- [ ] **Step 5: Compile local RTL with behavioral macro models**

Run:

```powershell
vlib work_sram128_macro
vlog -sv -work work_sram128_macro -f rtl/sram128/filelist.f sim/sram128/axi_mem_model_128.sv sim/sram128/tb_fa_top_sram128_axi_lite_smoke.sv
```

Expected: `Errors: 0`.

- [ ] **Step 6: Run local scoreboard**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_sram128_s256_scoreboard.ps1
```

Expected: comparator `PASS` with `MAE<=0.03` and `MaxAE<=0.10`.

- [ ] **Step 7: Commit**

```powershell
git add rtl/sram128 sim/sram128 scripts/run_sram128_s256_scoreboard.ps1
git commit -m "Replace sram128 branch with compliant SRAM wrappers"
```

---

### Task 8: Add Remote Genus Script Template

**Files:**
- Create: `synth/sram128_filelist.f`
- Create: `synth/run_sram128_genus.tcl`

- [ ] **Step 1: Create synthesis filelist**

Create `synth/sram128_filelist.f`:

```text
../rtl/sram128/sram128_macro_wrappers.v
../rtl/sram128/axi_lite_regs.v
../rtl/sram128/task_ctrl.v
../rtl/sram128/perf_counters.v
../rtl/sram128/dma_cmd_queue.v
../rtl/sram128/dma_read_master.v
../rtl/sram128/dma_write_master.v
../rtl/sram128/dma_engine.v
../rtl/sram128/page_manager.v
../rtl/sram128/q_load_store_adapter.v
../rtl/sram128/k_load_adapter.v
../rtl/sram128/v_load_adapter.v
../rtl/sram128/o_store_adapter.v
../rtl/sram128/dot_frontend.v
../rtl/sram128/score_exp_banked_rom.v
../rtl/sram128/score_exp_pipe.v
../rtl/sram128/update_token_fifo.v
../rtl/sram128/update_state_cluster.v
../rtl/sram128/packed_compute_core.v
../rtl/sram128/score_scheduler.v
../rtl/sram128/reciprocal_approx.v
../rtl/sram128/output_norm_pipe.v
../rtl/sram128/finalize_cluster.v
../rtl/sram128/fa_top_sram128.v
```

- [ ] **Step 2: Create Genus Tcl**

Create `synth/run_sram128_genus.tcl`:

```tcl
proc require_env_file {name label} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "$name must name a readable $label"
  }
  set path [file normalize $::env($name)]
  if {![file isfile $path] || ![file readable $path]} {
    error "$name is not a readable file: $path"
  }
  return $path
}

set top fa_top_sram128
set report_dir [file join reports $top]
set output_dir [file join outputs $top]
file mkdir $report_dir
file mkdir $output_dir

set std_lib [require_env_file STD_CELL_LIB_TT "standard-cell Liberty"]
set sram_lib [require_env_file SRAM_128x128_LIB_TT "SRAM Liberty"]
set sram_v   [require_env_file SRAM_128x128_VERILOG "SRAM blackbox Verilog"]

set lib_files [list $std_lib $sram_lib]
set_db init_lib_search_path [lsort -unique [list [file dirname $std_lib] [file dirname $sram_lib]]]
read_libs {*}$lib_files

set_db init_hdl_search_path [list ../rtl/sram128]
set_db hdl_language sv
read_hdl $sram_v
read_hdl -f sram128_filelist.f
elaborate $top

if {[file exists constraints.sdc]} {
  read_sdc constraints.sdc
}

redirect [file join $report_dir check_design.rpt] {check_design}
redirect [file join $report_dir hierarchy_pre.rpt] {report hierarchy}
redirect [file join $report_dir gates_pre.rpt] {report gates}

syn_generic
redirect [file join $report_dir qor_generic.rpt] {report qor}

syn_map
redirect [file join $report_dir qor_mapped.rpt] {report qor}
redirect [file join $report_dir hierarchy_mapped.rpt] {report hierarchy}

syn_opt

redirect [file join $report_dir timing.rpt] {report timing}
redirect [file join $report_dir area.rpt] {report area}
redirect [file join $report_dir gates.rpt] {report gates}
redirect [file join $report_dir power.rpt] {report power}
redirect [file join $report_dir qor.rpt] {report qor}
redirect [file join $report_dir check_design_post.rpt] {check_design}
redirect [file join $report_dir hierarchy_final.rpt] {report hierarchy}

write_hdl > [file join $output_dir ${top}_mapped.v]
write_sdc > [file join $output_dir ${top}_mapped.sdc]

puts "GENUS_DONE $top"
exit
```

- [ ] **Step 3: Run parser unit tests**

Run:

```powershell
python -B -m pytest scripts/test_parse_genus_reports.py -q
```

Expected: parser tests pass.

- [ ] **Step 4: Commit**

```powershell
git add synth/sram128_filelist.f synth/run_sram128_genus.tcl
git commit -m "Add sram128 Genus flow"
```

---

### Task 9: Add Returned Artifact Checker for SRAM128 Branch

**Files:**
- Modify: `scripts/check_baseline_artifacts.py`
- Modify: `scripts/test_check_baseline_artifacts.py`

- [ ] **Step 1: Add tests for SRAM128 artifact mode**

In `scripts/test_check_baseline_artifacts.py`, add a test that invokes the checker with `--profile sram128` and expects these required paths:

```text
artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_compare.json
artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_top_sim.log
synth/reports/fa_top_sram128/
synth/outputs/fa_top_sram128/
synth/reports/fa_top_sram128/ppa_summary.json
```

Use the existing test style in that file; create temporary files/directories and assert `baseline_ready` is `True` only when all required paths exist.

- [ ] **Step 2: Run checker tests and confirm failure**

Run:

```powershell
python -B -m pytest scripts/test_check_baseline_artifacts.py -q
```

Expected: failure because `--profile sram128` is not implemented.

- [ ] **Step 3: Implement `--profile sram128`**

Modify `scripts/check_baseline_artifacts.py` so `argparse` accepts:

```python
parser.add_argument("--profile", choices=("main64", "sram128"), default="main64")
```

For `sram128`, use:

```python
case_name = "sram128_s256_d64_seed100"
required = [
    Artifact("file", "artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_compare.json", True),
    Artifact("file", "artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_top_sim.log", True),
    Artifact("directory", "synth/reports/fa_top_sram128", True),
    Artifact("directory", "synth/outputs/fa_top_sram128", True),
    Artifact("file", "synth/reports/fa_top_sram128/ppa_summary.json", True),
]
```

Keep existing default behavior unchanged.

- [ ] **Step 4: Run checker tests**

Run:

```powershell
python -B -m pytest scripts/test_check_baseline_artifacts.py -q
```

Expected: all checker tests pass.

- [ ] **Step 5: Commit**

```powershell
git add scripts/check_baseline_artifacts.py scripts/test_check_baseline_artifacts.py
git commit -m "Add sram128 artifact checker profile"
```

---

### Task 10: Remote Genus and Xcelium Closure

**Files:**
- Modify: `docs/sram128_remote_runbook.md`
- Generated remotely, copied back: `synth/reports/fa_top_sram128/`
- Generated remotely, copied back: `synth/outputs/fa_top_sram128/`
- Generated remotely, copied back: `artifacts/runs/sram128_s256_d64_seed100/`

- [ ] **Step 1: Package source for remote server**

From repo root, create a source package excluding generated simulator work libraries:

```powershell
git archive --format=tar HEAD -o fa_accel_sram128_source.tar
```

Expected: `fa_accel_sram128_source.tar` exists.

- [ ] **Step 2: Run remote Genus**

On the remote server, after setting the environment variables in `docs/sram128_remote_runbook.md`, run:

```sh
cd synth
genus -batch -files run_sram128_genus.tcl | tee ../logs/sram128_genus.log
```

Expected: log contains:

```text
GENUS_DONE fa_top_sram128
```

- [ ] **Step 3: Parse returned reports locally**

After copying reports back, run:

```powershell
python -B scripts/parse_genus_reports.py synth/reports/fa_top_sram128 --json > synth/reports/fa_top_sram128/ppa_summary.json
python -B scripts/parse_genus_reports.py synth/reports/fa_top_sram128 --require-clean-check-design
```

Expected: first command writes JSON; second command exits 0 or reports specific check-design warnings that must be documented.

- [ ] **Step 4: Run remote mapped or gate-level simulation**

Use the same generated vectors as the local S256 scoreboard. The remote test must produce:

```text
artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_O_dut_words16.hex
artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_compare.json
artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_top_sim.log
```

Run the comparator:

```sh
python -B scripts/compare_vector_output.py \
  --metadata artifacts/vectors/sram128_s256_d64_seed100/sram128_s256_d64_seed100_metadata.json \
  --dut-hex artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_O_dut_words16.hex \
  --format words16 \
  --require-mae 0.03 \
  --require-maxae 0.10 \
  --dump-summary-json artifacts/runs/sram128_s256_d64_seed100/sram128_s256_d64_seed100_compare.json
```

Expected: comparator prints `PASS`.

- [ ] **Step 5: Run artifact checker**

Run:

```powershell
python -B scripts/check_baseline_artifacts.py --profile sram128 --require-complete
```

Expected: exits 0 and reports `baseline_ready=true`.

- [ ] **Step 6: Commit returned lightweight summaries**

Commit only lightweight report summaries and run logs selected for final delivery. Do not commit large waveforms or full simulator work directories.

```powershell
git add synth/reports/fa_top_sram128/ppa_summary.json docs/sram128_remote_runbook.md
git commit -m "Add sram128 remote closure summaries"
```

---

## Self-Review Notes

Spec coverage:

- 128-bit AXI path: Tasks 1 through 5.
- Reuse of `genus/` example: Tasks 3 through 5.
- Compliant SRAM macro replacement: Tasks 6 and 7.
- Remote Genus/Xcelium flow: Tasks 6, 8, and 10.
- Existing golden/vector/comparator reuse: Tasks 1, 2, 5, and 10.
- Artifact closure: Task 9 and Task 10.

Known blocking input:

- Task 7 requires the exact selected compliant SRAM macro Verilog port list from the remote server before final wrapper code can be completed.
