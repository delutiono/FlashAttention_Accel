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

### 4. Innovus 物理综合脚本 ✅
- 完整 Tcl 脚本: `innovus/run_phys.tcl`
- MMMC 时序视图: `innovus/mmmc.tcl`
- SDC 时序约束 (200MHz): `innovus/constraints.sdc`
- 已针对 Innovus v25.12 适配

### 5. RTL 适配 Yosys ✅
- Yosys 兼容 RTL 在 `rtl_yosys/` 目录
- 端口打包、`include "fa_defines.vh"` 替换 `import fa_pkg::*`
- fa_scheduler 已优化：移除 always_comb 大规模解包，改用直接 packed 端口访问

## 待完成

### 1. 顶层完整综合（高优先级）
- **问题**: `fa_scheduler` 在 Yosys 中 read_verilog 阶段极慢（单线程，262K-bit 宽端口位切片 AST 展开）
- **现状**: WSL 23GB 爆 OOM；512GB Windows 机器上 Yosys 单核跑极慢
- **可能方案**:
  - 分层综合：叶子模块先综合，scheduler 单独综合，顶层黑盒连线
  - 将 ST_LOAD_Q/KV 大循环拆成多周期串行
  - 换用商业综合工具（Design Compiler / Genus）
- **脚本**: `synth/synth_full.ys`

### 2. 物理综合（高优先级）
- 需要完整顶层网表后才能跑 Innovus
- 云服务器: `/apps/DDI251/25.12.000/bin/innovus -batch -file innovus/run_phys.tcl`
- 输出: 面积、功耗、时序报告

### 3. DMA 实现（中优先级）
- `fa_dma_rd.sv` / `fa_dma_wr.sv` 目前是空 stub
- AXI Master 接口全部 tie-off，当前数据通路走 SRAM 宽并行端口

## 已知问题

### Yosys 内存/性能
- **根因**: Yosys 单线程开源工具，处理 >100K-bit 宽端口上的位切片展开成巨大 AST
- **影响**: fa_scheduler（S=256, D=64）综合缓慢，23GB 机器 OOM
- **规避**: 商业工具（DC/Genus）无此问题；或将大循环拆成多周期

### 网表尺寸
- `fa_kv_buffer_netlist.v`: 136MB（BK=32, D=64 → 2048 个 16-bit 寄存器展开为触发器）
- `fa_softmax_online_netlist.v`: 31MB
- 门级仿真器 vvp 无法处理此规模

### DMA / Top-Level
- fa_dma_rd / fa_dma_wr 为空 stub（792B 网表）
- 顶层 AXI Master 全部 tie-off
- 当前芯片接口是宽并行 SRAM 端口（非标准 AXI）

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
├── backend_flow.md         # 后端流程操作说明
└── *.lef, *.v              # SkyWater 130nm HS PDK
```

## 快速开始

**门级仿真（小参数）**:
```bash
yosys synth/synth_small_params.ys
bash sim/run_gate_sim_small.sh
```

**物理综合**（需完整顶层网表）:
```bash
/apps/DDI251/25.12.000/bin/innovus -batch -file innovus/run_phys.tcl
```
