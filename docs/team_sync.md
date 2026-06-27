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
| RTL 骨架 | 进行中 | Round7 已补 Q row buffer 与 K/V tile buffer leaf；下一步接入 top DMA/compute tile-loop 并扩 S256 回归 |
| 语法检查 | 已完成 | `vlog -lint -sv -work <work> -f rtl/filelist.f`：0 errors，0 warnings |
| 综合/PPA | 进行中 | Genus scripts 已支持 `STD_CELL_LIB`、`TOP`、report 与 mapped netlist/SDC 输出；B 已补远程 runbook 与 report parser；仍需远程 Genus 真实报告 |

## 3. 分工焦点

| 成员 | 当前焦点 | 下一步 |
|---|---|---|
| A：RTL / 验证 / 综合 | top compute S4 smoke、tile-loop、Q row buffer 与 K/V tile buffer leaf 已通 | 将 buffer 接入 DMA read stream 与 top compute tile-loop，补 valid/backpressure 覆盖 |
| B：算法 / 验证 / 综合脚本 | cycle/bandwidth model 已具备 tile-aware 参数；本轮补 Genus report parser 与远程 PPA runbook | 等远程 Genus artifacts 回传后汇总 area/timing/power/qor，并配合 S256 scoreboard 材料 |

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
| buffer 尚未接 top | leaf buffer 已通，但 top 仍直接顺序读 Q/K/V | 下一轮把 Q/K/V buffer 接入 DMA read stream 与 compute tile-loop |
| corner case 不足 | causal/tile 边界 bug 不易暴露 | 后续按 scoreboard 覆盖缺口补 cases |
| score/memory 测试仍是零延迟 | 接 buffer/DMA 后 valid 对齐可能出 bug | 后续 TB 加 memory latency/backpressure |
| 远程 PPA 尚未闭环 | 无法给出真实 area/timing/power/qor 结论 | 远程设置 `STD_CELL_LIB` 后跑 leaf/top Genus，回传 `synth/reports/<top>` 与 `synth/outputs/<top>`，再用 parser 生成 summary |

## 6. 最近推进记录

### 2026-06-27 Round 7 B

- 新增 `scripts/parse_genus_reports.py`：解析 `area.rpt`、`timing.rpt`、`power.rpt`、`qor.rpt`、`check_design.rpt`，支持文本摘要、`--json` 与 `--require-clean-check-design`；缺失报告标记为 missing，不假装远程 Genus 已完成。
- 新增 `scripts/test_parse_genus_reports.py`：fake report 临时目录覆盖 missing、area/timing/power/qor 字段解析，以及 dirty `check_design.rpt` 非零退出策略；不依赖 Cadence。
- 新增 `docs/synthesis_runbook.md`：记录远程 `STD_CELL_LIB` 设置、leaf/top Genus 命令、reports/outputs 收集清单和 parser 汇总命令；当前阶段不需要 Innovus。
- 当前 PPA 状态：本地只完成 parser 与流程材料准备；真实 area/timing/power/qor 仍等待远程 Genus artifacts。

### 2026-06-27 Round 7 A

- `fa_q_buffer` 从空壳升级为可综合 Q row buffer：64-bit beat 流写入、4x int16 little-endian lane unpack、`load_done_o` sticky 完成标志与 `clear_i` 重新装载。
- `fa_kv_buffer` 从空壳升级为可综合 K/V tile buffer：独立 K/V 写通道、`TILE_ROWS x D` 寄存器阵列、按 `row_index_i` 组合输出 K/V 行。
- 新增 `tb_q_kv_buffer` 覆盖 `TILE_ROWS=2`、lane endian、row indexing、done/ready/clear 行为；作为后续 top DMA read stream 接入前的 leaf 证据。
- 本轮 buffer 尚未接入 `fa_accel_top`，下一步连接到 compute tile-loop 后再跑 S4/S256 端到端回归。

### 2026-06-27 Round 6

- top compute S4 smoke 已完成，tile-loop 参数化已接入，cycle/bandwidth model 已更新为 tile-aware 估算。
- 下一步聚焦 buffer 接入、S256 回归 artifact/scoreboard 扩展，以及远程 Genus 真实报告闭环。

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


## 7. 下一步

| 成员 | 下一步 |
|---|---|
| A | 将 Q/K/V buffer 接入 top DMA read stream 与 compute tile-loop；补 TB memory latency/backpressure 覆盖 |
| B | S256 regression/scoreboard 材料扩展；远程 Genus artifacts 回传后用 parser 生成 PPA summary |

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
| 综合运行手册 | v0.1 已有 | `docs/synthesis_runbook.md` |
| 架构规格 | 待创建 | `docs/architecture_spec.md` |
| 验证计划 | 待创建 | `docs/verification_plan.md` |
