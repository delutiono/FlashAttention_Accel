# FlashAttention Accelerator — Backend Flow

## 项目概述

FlashAttention 硬件加速器，基于 SkyWater 130nm HS 标准单元库（TT corner, 25°C, 1.80V）。

**设计参数**: S=256, D=64, ELEM_W=16, BK=32

## 已完成

### 1. RTL 功能仿真 ✅
- 与 Python 参考模型 100% 匹配（0/16384 像素错误）
- 修复 8 个 RTL bug（乘法位宽截断溢出等）
- 测试平台: `sim/tb_fa_top.sv`

### 2. Yosys 逻辑综合 — 叶子模块 ✅
- 10 个叶子模块全部综合完成（D=64 参数）:
  - `fa_exp_approx` (168KB), `fa_recip_approx` (591KB)
  - `fa_dot_pe` (3.4MB), `fa_out_quant` (11.2MB)
  - `fa_regfile` (99KB), `fa_q_buffer` (203KB)
  - `fa_softmax_online` (31MB)
  - `fa_dma_rd` (792B, stub), `fa_dma_wr` (792B, stub)
- `fa_kv_buffer` 网表 136MB，超过 GitHub 100MB 限制，不在此仓库
- 小参数版本 (D=8) 全部综合完成，网表大幅缩小
- 综合脚本: `synth/synth_modules.ys`, `synth/synth_small_params.ys`

### 3. 门级仿真流程验证 ✅
- 小参数 (S=4, D=8, BK=2) 门级仿真通过
- 编译: iverilog + Yosys simlib + 网表 + RTL scheduler
- 运行: 1分28秒，201周期，error=0
- 大参数 (S=256, D=64) 门级仿真因 vvp 性能限制无法运行（网表 31MB，百万门级）

### 4. 后端脚本草案
- 已有 Genus、Yosys 和 Innovus Tcl/SDC 草案。
- 当前 Baseline 主线只要求先完成 Genus 顶层综合与 PPA 报告。
- Innovus 脚本尚未在远程 PDK 环境实跑，不作为当前完成证据。

### 5. RTL 适配 Yosys ✅
- Yosys 兼容 RTL 在 `rtl_yosys/` 目录
- 端口打包、`include "fa_defines.vh"` 替换 `import fa_pkg::*`
- fa_scheduler 已优化：移除 always_comb 大规模解包，改用直接 packed 端口访问

## 当前主要问题

项目目标以 `docs/request.md` 和 `docs/FA_Accel_IP_Product_Spec.md` 为准。Baseline
要求可综合 RTL、AXI4-Lite 控制、AXI4 Master DMA、端到端正确性、周期与带宽统计，
并使用 Cadence Genus 生成面积、时序和功耗报告。Innovus P&R 属于可选增强，不是当前
Baseline 闭环的前置条件。

### P0：产品级 DMA 与顶层接口尚未实现

- `fa_dma_rd.sv` / `fa_dma_wr.sv` 仍为空 stub。
- 顶层 AXI Master 全部 tie-off，Q/K/V/O 仍通过完整 tensor 宽端口传输。
- 当前接口不符合赛题“主机配置 + 加速器 DMA 搬运数据”的要求。
- 完整 tensor 宽端口和单周期大循环也会造成综合 AST、端口切片和寄存器网络膨胀。

### P0：完整 RTL 周期数不达标

- full-size causal 行为仿真已完成，但硬件计数为 `597,761 cycles`。
- Baseline 要求单次 `S=256,D=64` causal attention `<300,000 cycles`。
- 当前主要开销来自 BQ=1、逐 score 串行控制、V 累加分段和状态机空泡。

### P0：独立 FP32 正确性验收尚未闭环

- `sim/o_tb.hex` 与 RTL behavioral model 的 16,384 个元素一致。
- 该结果证明 RTL 与位精确模型一致，但不能替代 RTL 输出对 FP32 SDPA golden 的
  `MAE/MaxAE` 验收。
- Baseline 要求 `MAE <= 0.03`、`MaxAE <= 0.10`。

### P1：尚无正式 Genus 顶层综合与 PPA 报告

- 仓库中没有可验收的 Genus `area/timing/power/qor` 报告。
- 本地没有 Genus 和完整 PDK；实际综合在远程 Cadence 服务器执行。
- checked-in `sky130_ff.lib` 不含 Liberty `cell()`，不能用于综合或 STA。
- Yosys 叶模块网表和小参数门级仿真只能作为辅助证据，不能替代 Genus 顶层报告。

### P1：控制与回归环境仍不完整

- AXI4-Lite AW/W 独立握手、STATUS W1C、重复 START、soft reset、IRQ 和错误响应需要
  完整测试。
- testbench 在 DONE 后仍会进入 timeout 分支，自动回归缺少唯一的 PASS/FAIL 结束条件。
- 尚未提供真实 DMA `RD_BYTES/WR_BYTES` 统计。

## 待完成工作

### 1. 远程运行首次 Genus 探路综合

目的：先取得真实 elaboration、面积和关键路径信息，不把首次运行误当成最终验收。

1. 将当前项目同步到远程 Cadence 服务器。
2. 找到完整 Sky130 HS TT Liberty，并设置：

   ```bash
   export STD_CELL_LIB=/absolute/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib
   ```

3. 在项目根目录执行：

   ```bash
   genus -batch -files synth/run_genus.tcl 2>&1 | tee synth/genus_run.log
   ```

4. 保存 `genus_run.log`、`check_design` 信息、峰值内存、运行时间和所有生成报告。
5. 若卡在 elaboration 或内存展开，停止硬顶当前宽端口结构，转入 DMA/有界 buffer 重构。

完成判据：至少明确 Genus 能否 elaborate 当前顶层，并获得可定位的错误或首轮 PPA 数据。

### 2. 实现 AXI DMA 与有界 buffer 数据流

1. `fa_dma_rd` 实现 Q row、K/V tile 的 AXI burst read、stride 地址计算、backpressure、
   response error 和读字节统计。
2. `fa_dma_wr` 实现 O row/block burst write、AW/W/B 通道握手、WLAST、BRESP 和写字节统计。
3. scheduler 改为通过固定宽度 ready/valid 接口访问 Q/K/V/O buffer。
4. 将 `ST_LOAD_Q/ST_LOAD_KV` 的整块单周期搬运改成多周期装载。
5. 产品顶层移除完整 tensor 宽端口，仅保留 AXI4-Lite、AXI4 Master、时钟复位和 IRQ。

完成判据：AXI memory model 中能够从非零基地址读取 Q/K/V，并把完整 O 写回指定地址。

### 3. 建立端到端 AXI 验证与 FP32 scoreboard

验证流程：

```text
AXI-Lite 配置 base/stride/scale
-> START
-> DMA 读取 Q/K/V
-> online-softmax attention
-> DMA 写回 O
-> DONE/IRQ
-> scoreboard 从 memory model 读取 O
```

必须覆盖随机 full-size causal、`i=0`、`i=255`、tile 跨 causal 边界、非零 base、
非默认 stride、AXI backpressure、错误响应、soft reset 和重复 START。

scoreboard 至少输出：

```text
RESULT
MAE
MAX_AE
WORST_INDEX
CYCLES
RD_BYTES
WR_BYTES
```

完成判据：随机和 corner case 全部通过，且 `MAE <= 0.03`、`MaxAE <= 0.10`。

### 4. 将周期数压到 300k 以下

按风险从低到高依次执行：

1. 用 softmax `ready` 握手替代固定等待周期。
2. 合并 `NEXT_K/NEXT_TILE` 等纯控制空泡。
3. 将 `V_ACC_LANES` 从 16 提高到 32，并用 Genus 比较面积和时序代价。
4. 缓存 K/V tile 并在多个 query 间复用。
5. 从 BQ=1 升级到 BQ=2/4，使多个 query 共享一次 K/V tile 装载。
6. 为状态机增加 cycle breakdown，量化 load/dot/softmax/VACC/finalize/write 各阶段开销。

完成判据：RTL full-size causal 报告 `CYCLES < 300000`，同时正确性仍达标。

### 5. 执行正式 Genus 验收

在 DMA、正确性和周期闭环后重新运行 `synth/run_genus.tcl`，提交：

- `qor.rpt`
- `area.rpt`
- `timing.rpt`
- `power.rpt`
- mapped netlist
- mapped SDC
- 完整 Genus 日志

报告必须说明等效门数是否 `<=2,000,000`、目标时钟、WNS/TNS、关键路径、功耗、
buffer/memory 折算方式及 exp/reciprocal/MAC 的面积贡献。

完成判据：Genus 顶层综合通过，面积达标，并形成可解释的时序和功耗结论。

### 6. 综合后门级验证

- 对 mapped netlist 运行寄存器/启动流程和小规模计算 smoke test。
- 若仿真性能允许，再运行完整端到端用例。
- 门级仿真是推荐的回归增强，不替代 RTL 端到端验证和 Genus PPA 报告。

### 7. Innovus 暂缓

当前不需要以 Innovus place/CTS/route 作为 Baseline 前置工作。只有在 RTL、DMA、精度、
周期和 Genus PPA 全部闭环后，且时间允许时，再进行 P&R 时序收敛和版图报告。

## 已知问题与处理原则

### 宽端口与综合内存

- **根因**：完整 tensor 宽端口、组合位切片和单周期大循环共同形成巨大 AST/网表。
- **处理**：改为 AXI DMA + 有界 buffer + 多周期固定宽度握手。
- **原则**：Genus 可以提供真实诊断，但商业工具不能替代架构修正。

### 网表与片上存储规模

- `fa_kv_buffer_netlist.v` 约 136MB，当前 buffer 会被大量展开为触发器。
- `fa_softmax_online_netlist.v` 约 31MB，大参数 vvp 门级仿真非常缓慢。
- 正式报告需要区分寄存器实现和 SRAM macro 实现，并折算存储面积。

### 数值量化风险

- scheduler 当前最终量化路径没有完整复用饱和量化模块。
- 大幅输入可能出现截断或 int16 回绕，需要通过大幅随机和饱和 corner case 验证。

### 工具与工艺库

- 本地环境仅用于 RTL、测试和脚本静态检查。
- Genus 和完整 PDK views 位于远程 Cadence 服务器。
- Genus 逻辑综合只需要完整 Liberty；Innovus 才需要 technology LEF、cell LEF 和 QRC。
- 远程运行产生的正式报告应复制回 `synth/reports/` 并纳入最终提交。

## 目录结构

```
competition/
├── rtl/                    # 原始 RTL（使用 fa_pkg）
├── rtl_yosys/              # Yosys 兼容 RTL
├── synth/                  # Yosys 综合脚本和网表
│   ├── synth_full.ys       # 完整顶层综合
│   ├── synth_modules.ys    # 叶子模块综合
│   └── *_netlist.v         # 综合网表
├── sim/                    # 仿真
│   ├── tb_fa_top.sv        # RTL testbench
│   ├── tb_scheduler_gate*.sv  # 门级 testbench
│   └── run_gate_sim*.sh    # 门级仿真脚本
├── innovus/                # Innovus 物理综合
│   ├── run_phys.tcl
│   ├── mmmc.tcl
│   └── constraints.sdc
├── test_vectors/           # Python 测试向量
├── cocotb/                 # Cocotb 验证
├── docs/                   # 赛题要求、产品规格、项目计划和团队同步
├── backend_flow.md         # 后端流程操作说明
└── *.lef, *.v              # SkyWater 130nm HS PDK
```

## 需求文档索引

- `docs/request.md`：赛题原始要求，决定强制接口、正确性、性能与提交材料。
- `docs/FA_Accel_IP_Product_Spec.md`：Baseline 产品规格和成功判据。
- `docs/FA_Accel_IP_Project_Plan.md`：任务拆解、协作与里程碑。
- `docs/team_sync.md`：当前进度、阻塞项和近期协作记录。

当 README、实现和需求文档存在冲突时，先以赛题 `request.md` 为最高依据，再更新产品规格、
项目计划和 README，避免实现目标漂移。

## 快速开始

**RTL lint**:

```bash
vlib work_lint
vlog -lint -sv -work work_lint -f rtl/filelist.f
```

**门级仿真（小参数，仅辅助验证）**:

```bash
yosys synth/synth_small_params.ys
bash sim/run_gate_sim_small.sh
```

**远程 Genus 探路/正式综合**:

```bash
export STD_CELL_LIB=/absolute/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib
genus -batch -files synth/run_genus.tcl 2>&1 | tee synth/genus_run.log
```

详细环境与产物说明见 `backend_flow.md`。
