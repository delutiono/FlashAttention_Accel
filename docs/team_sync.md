# 团队对齐与进度同步

> 用途：快速同步项目进度、接口颗粒度、缺失材料和阻塞项。本文档只保留“当前仍有用的信息”，详细设计放独立文档。

## 1. 维护规则

1. 每次有实质推进，只更新相关状态、开放请求和最近记录。
2. 信息要短：写清“传递什么、对齐到什么颗粒度、谁下一步做什么”即可。
3. 已补齐、已失效或不再需要的请求要及时删除，不长期保留历史包袱。
4. 同一信息只保留一处；详细位宽表、格式表、测试列表放到独立文档，在这里给路径。
5. 最近记录只保留最近 5 条；更早历史看 git log。
6. 状态统一使用：未开始 / 进行中 / 待对接 / 阻塞 / 已完成 / 已冻结。

## 2. 当前快照

| 项目 | 状态 | 关键信息 |
|---|---|---|
| Baseline 范围 | 已冻结 | `S=256, d=64, batch=1, head=1, Q8.8 I/O, causal` |
| Golden model | 已冻结 | fixed golden 默认 finalize 已切到 `32-entry + 1NR`；`exact` 仅作 CLI 对照；exp/score 契约未变 |
| 数值回归 | 已完成 | S64/S256、seeds 100-104 均通过 `MAE<=0.03`、`MaxAE<=0.10`、candidate-vs-exact `<=1 LSB` |
| RTL 骨架 | 进行中 | reciprocal 已替换为 `U9.23 -> U1.31` 32x1 NR，zero 同延迟返回错误标志；下一步接 DMA/top |
| 语法检查 | 已完成 | `vlog -lint -sv -work <work> -f rtl/filelist.f`：0 errors，0 warnings |
| 综合脚本 | 进行中 | `run_genus.tcl`/`run_leaf_genus.tcl` 支持 `STD_CELL_LIB`、`TOP`、report 与 mapped netlist/SDC 输出；未在 Cadence 环境验证 |

## 3. 分工焦点

| 成员 | 当前焦点 | 下一步 |
|---|---|---|
| A：RTL / 验证 / 综合 | reciprocal/finalize/softmax 联合路径已通 | 接 DMA/top，补 AXI memory smoke 与 leaf Genus 远程验证 |
| B：算法 / 验证 | 默认 NR finalize、S64/S256 回归、可复现向量导出、cycle/bandwidth model 与 committed S4/D64 fixture 已闭环 | 支持 A 将 fixture 接入 top compute S4 smoke，并准备后续 S=256 scoreboard 材料 |

## 4. 开放对接请求

| ID | 负责人 | 状态 | 需要补齐/冻结 | 对齐颗粒度 | 产物 |
|---|---|---|---|---|---|
| REQ-005 | B | 已完成 | 可复现 golden/vector 导出 | 不依赖 NumPy；输出 16-bit word hex、64-bit beat hex、metadata JSON；默认对齐 fixed golden 32-entry + 1NR | `scripts/generate_test_vectors.py`, `docs/test_vector_format.md` |
| REQ-006 | A | 已完成 | reciprocal RTL | 已对齐 32-entry ROM、1 次 NR、trace checkpoint、zero flag、固定 4 拍 valid | `rtl/fa_recip_approx.sv` |
| REQ-007 | B | 已完成 | committed RTL end-to-end smoke fixture 与 top smoke loader | `S=4,D=64,seed=100,stride=128`；Q/K/V/O_golden 同时提供 16-bit word hex、64-bit beat hex、SVH localparam/path include；比较工具支持 words16/beats64 DUT 输出与阈值退出 | `test_vectors/generated/s4_d64_seed100/`, `scripts/dump_fixture_sv.py`, `sim/include/s4_d64_seed100_vectors.svh`, `scripts/compare_vector_output.py` |

## 5. 当前阻塞/风险

| 风险 | 影响 | 处理 |
|---|---|---|
| AXI DMA/top 未通 | 无法满足接口验收 | 先 DMA smoke，再接 top；暂不做多 outstanding 优化 |
| committed smoke 尚未接 RTL | row_engine/top 端到端仍缺自动验收 | A 后续接入 `sim/include/s4_d64_seed100_vectors.svh` 或 fixture `*_beats64.hex`；B 提供 comparator/scoreboard 支持 |
| corner case 不足 | causal/tile 边界 bug 不易暴露 | 后续按 scoreboard 覆盖缺口补 cases |
| score/memory 测试仍是零延迟 | 接 buffer/DMA 后 valid 对齐可能出 bug | 后续 TB 加 memory latency/backpressure |

## 6. 最近推进记录

### 2026-06-26 Round 5 B

- 新增 `scripts/dump_fixture_sv.py`：读取 v1 metadata，校验 Q/K/V/O 的 16-bit words 与 64-bit beats 数量、stride、little-endian lane packing，并生成 include-friendly SVH。
- 新增 `sim/include/s4_d64_seed100_vectors.svh`：提供 S4/D64 shape 常量、Q/K/V/O `$readmemh` path 常量、64-bit beat localparam arrays，以及 `S4_D64_SEED100_o_golden_word(row,col)`，供 top compute S4 smoke 快速加载 AXI memory 和比较 O。
- 扩展 `scripts/test_compare_vector_output.py`：覆盖 committed SVH 可再生、O_golden `4*16` beats、自比 words16/beats64 均可用、DUT failure CLI 输出 `row/col/expected/got`。
- `docs/test_vector_format.md` 记录 top smoke 接入方式：按 `row*STRIDE_BYTES + beat*8` 预加载 Q/K/V，dump O 为 words16 或 beats64 后调用 comparator；S=256 扩展复用同一 metadata/comparator，但默认不提交大型生成目录。

### 2026-06-26 Round 4 B

- 新增 committed fixture `test_vectors/generated/s4_d64_seed100/`：`S=4,D=64,seed=100,stride=128,causal=1`，包含 Q/K/V/O_golden 的 16-bit word hex、64-bit AXI beat hex 与 metadata JSON。
- 新增 `scripts/compare_vector_output.py`：读取 metadata 与 golden O，比较 words16 或 beats64 DUT 输出，报告 MAE/MaxAE、最大 LSB 误差和首个失败 row/col，阈值失败非零退出。
- 新增 `scripts/test_compare_vector_output.py`：覆盖 fixture 存在性、golden 自比、单点扰动失败与 beats64 little-endian lane unpack。
- `docs/test_vector_format.md` 标明该 fixture 是 RTL `row_engine`/top AXI memory/cocotb 端到端验收基准，不是临时文件。

### 2026-06-26 Round 3 B

- 新增 `scripts/generate_test_vectors.py`：复用 `generate_qkv` 与 `model.golden_fixed.attention_fixed`，支持 baseline `S=256,D=64`、small smoke、`max_rows`、单 seed / 多 seed 导出。
- 向量格式升级为持久 v1 契约：`*_Q/K/V/O_golden.hex` 16-bit row-major word 文件、`*_beats64.hex` stride-padded 64-bit AXI beat 文件、`*_metadata.json` 记录 endian/stride/reciprocal/source。
- 新增 `scripts/cycle_bandwidth_model.py`：估算 baseline read/write bytes、DMA beats、compute/DMA/total cycles，并给出 current functional 与 target parallel 两组参数的 `<300k` 判断。
- 新增 unittest 覆盖向量可复现、hex/beat packing、metadata、bytes/beats 和 cycle budget；产物用于后续 RTL end-to-end、cocotb scoreboard 与 AXI memory model，不是临时 dump。

### 2026-06-26 Round 2 B

- fixed golden 默认 finalize 正式切到 `32-entry + 1NR`，exact 保留为 `--recip-mode exact` 对照；exp/score 契约未改。
- 新增默认路径 bit-exact checkpoint、zero/container corners、S64 与 S256 seeds 100-104 门限；回归记录 mode/LUT/iterations/latency。
- S64：`MAE=0.00394442`、`MaxAE=0.03223060`；S256：`MAE=0.00236523`、`MaxAE=0.03811298`；candidate-vs-exact 最大 `1 LSB`。
- 给 A 的 RTL 接口：`l_u9_23 + in_valid -> recip_u1_31 + divide_by_zero + out_valid`，固定 4 拍，包括 zero。

### 2026-06-26 Round 2 A

- `fa_recip_approx` 替换 exact-point 表和变量除法，采用 32-entry seed ROM + 1 次 NR；`tb_recip_approx` 覆盖 zero、container corners、LUT 边界与 checkpoint。
- `fa_finalize_vec` 对齐 reciprocal 固定延迟，新增 `div_zero_o`，`tb_finalize_vec` 和 `tb_softmax_finalize_vec` 已迁移。
- `tb_scheduler_softmax_finalize_row_scoreboard` 接入 `ready_o`/`div_zero_o`，代表性路径 0 warning 通过。
- Genus 脚本新增 leaf top 入口，并输出 `check_design/area/timing/power/qor` report 以及 mapped Verilog/SDC。

## 7. 下一步

| 成员 | 下一步 |
|---|---|
| A | 将 `sim/include/s4_d64_seed100_vectors.svh` 或 fixture `*_beats64.hex` 接入 top compute S4 AXI memory smoke，逐步替换零延迟 testbench 假设 |
| B | 继续配合 scoreboard 阈值/格式对齐；S4 top smoke 稳定后按同一 v1 contract 扩到 S=256 regression artifact，不默认提交大型目录 |

## 8. 文档索引

| 文档 | 状态 | 路径 |
|---|---|---|
| 赛题原始要求 | 已有 | `docs/request.md` |
| 产品需求文档 | 已有 | `docs/FA_Accel_IP_Product_Spec.md` |
| 项目计划书 | 已有 | `docs/FA_Accel_IP_Project_Plan.md` |
| 团队同步 | 已有 | `docs/team_sync.md` |
| 定点规格 | v0.5 reciprocal 默认路径已冻结 | `docs/fixed_point_spec.md` |
| 测试向量格式 | v1 导出契约已补齐 | `docs/test_vector_format.md` |
| Debug dump 格式 | v0.1 已有 | `docs/debug_dump_format.md` |
| 架构规格 | 待创建 | `docs/architecture_spec.md` |
| 验证计划 | 待创建 | `docs/verification_plan.md` |
