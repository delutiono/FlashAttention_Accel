<div align="center">

<div style="font-size: 38px; font-weight: 700; line-height: 1.65; margin-top: 24px;">
2026 第九届中国研究生<br>
创“芯”大赛
</div>

<div style="font-size: 28px; font-weight: 700; margin-top: 46px;">
Cadence 企业命题 - 赛题____
</div>

<p style="margin: 52px 0 54px;">
  <img src="./contest_logo.png" alt="中国研究生创芯大赛" width="360">
</p>

<div style="width: 82%; margin: 0 auto; font-size: 26px; font-weight: 700; line-height: 1.9;">
题目名称________________________
</div>

</div>

<table style="width: 82%; margin: 110px auto 28px; border-collapse: collapse; table-layout: fixed; font-size: 20px; font-weight: 700;">
  <tr>
    <td style="width: 150px; padding: 12px 0; letter-spacing: 0.18em;">队伍名称</td>
    <td style="width: 18px; padding: 12px 0; text-align: center;">：</td>
    <td style="padding: 12px 0; text-align: center;"><span style="display: inline-block; width: 280px; padding-bottom: 4px; border-bottom: 1.5px solid #000; text-align: center;">________</span></td>
  </tr>
  <tr>
    <td style="width: 150px; padding: 12px 0; letter-spacing: 0.18em;">参赛队员</td>
    <td style="width: 18px; padding: 12px 0; text-align: center;">：</td>
    <td style="padding: 12px 0; text-align: center;"><span style="display: inline-block; width: 280px; padding-bottom: 4px; border-bottom: 1.5px solid #000; text-align: center;">________</span></td>
  </tr>
  <tr>
    <td style="width: 150px; padding: 12px 0; letter-spacing: 0.18em;">指导教师</td>
    <td style="width: 18px; padding: 12px 0; text-align: center;">：</td>
    <td style="padding: 12px 0; text-align: center;"><span style="display: inline-block; width: 280px; padding-bottom: 4px; border-bottom: 1.5px solid #000; text-align: center;">________</span></td>
  </tr>
  <tr>
    <td style="width: 150px; padding: 12px 0; letter-spacing: 0.18em;">参赛单位</td>
    <td style="width: 18px; padding: 12px 0; text-align: center;">：</td>
    <td style="padding: 12px 0; text-align: center;"><span style="display: inline-block; width: 280px; padding-bottom: 4px; border-bottom: 1.5px solid #000; text-align: center;">________</span></td>
  </tr>
  <tr>
    <td style="width: 150px; padding: 12px 0; letter-spacing: 0.18em;">日期</td>
    <td style="width: 18px; padding: 12px 0; text-align: center;">：</td>
    <td style="padding: 12px 0; text-align: center;"><span style="display: inline-block; width: 280px; padding-bottom: 4px; border-bottom: 1.5px solid #000; text-align: center;">________</span></td>
  </tr>
</table>

<div style="page-break-after: always;"></div>

---

# 摘要

本项目面向 FlashAttention/Scaled Dot-Product Attention 的硬件加速实现，完成了 baseline RTL、综合、门级仿真、SDF 回标仿真以及基于 Joules Xreplay 的功耗计算流程。baseline 设计规格为 S=256、D=64、batch=1、head=1、Q8.8 定点输入输出、causal mask，顶层模块为 `fa_top`，通过 AXI4-Lite 完成寄存器配置，通过 128-bit AXI4 Master DMA 读写 Q/K/V/O 数据，并在片上 SRAM 中采用 tile K/V、每行 m/l/acc 状态更新的 FlashAttention-style online softmax 方案，避免显式存储 S×S attention score 矩阵。后端使用 Genus 25.12 与 SKY130 HS 标准单元库完成 baseline 综合网表生成，200 MHz 目标时钟下报告 WNS 约 0.4 ps、无 violating paths；Xcelium 24.09 完成 zero-delay 门级功能仿真与 SDF 回标功能仿真；Joules Xreplay 基于 RTL SHM activity、Genus RTL-to-gate mapping、综合网表和 Liberty 完成 baseline zero-delay 功耗评估，总功耗为 288.462 mW。Bonus 分支中实现了 padding mask、Q6.10/Q4.12 格式、S=512、DMA 任务队列、AXI4-Stream、Dropout 和多 Head 等扩展，并探索 INT8 block quantization 低精度路径。

关键词：FlashAttention；AXI4；SKY130；Xcelium；Genus；Joules Xreplay；SDF；功耗评估

## 团队介绍

### 团队成员与分工

| 成员 | 单位/专业 | 主要分工 |
|---|---|---|
| 队长姓名 | ________ | ________ |
| 成员姓名 | ________ | ________ |
| 成员姓名 | ________ | ________ |

### 指导教师

________

---

# 1 赛题理解与需求分解

## 1.1 赛题理解与需求目标

### 1.1.1 赛题理解

赛题目标是设计面向 Attention 计算的硬件加速器，重点覆盖 SDPA/FlashAttention 的计算正确性、片上存储组织、可综合 RTL、接口协议、后端实现与 PPA 评估。baseline 关注固定规模 S=256、D=64、batch=1、head=1、causal attention，并要求输入输出使用定点格式。由于标准 attention 需要 S×S score 矩阵，直接存储会带来较高片上 SRAM 或外部存储访问需求，因此本设计采用 FlashAttention 的分块思想：只分块加载 K/V，逐行维护在线 softmax 所需的 m、l 和 acc 状态，不在片上或外部显式保存完整 S×S score 矩阵。

项目验证范围包括 RTL 功能验证、Genus 综合、baseline 门级网表功能仿真、SDF 回标仿真和 Joules 功耗计算。其中 SDF 仿真用于验证回标延迟和标准单元 specify 模型下的门级功能行为，不作为 timing signoff 的唯一依据；功耗评估采用 zero-delay Xreplay 路线，用 RTL activity 映射到门级网表，以避免直接生成超大 gate-level VCD。

### 1.1.2 设计目标

- 功能目标：完成 S=256、D=64、Q8.8、causal SDPA/FlashAttention baseline 计算，AXI4-Lite 可配置，AXI4 Master 可搬运 Q/K/V/O。
- 性能目标：baseline RTL 仿真周期数低于 300,000 cycles；后端综合目标时钟 200 MHz。
- 面积目标：在 SKY130 HS 标准单元库下获得可综合、可门级仿真的 `fa_top_mapped.v`，并输出面积报告。
- 功耗目标：建立可复现的 Joules Xreplay 功耗评估流程，给出 baseline zero-delay 功耗结果。
- 可验证性目标：形成 RTL、门级 zero-delay、SDF 回标、memory model sanity、Xreplay power 的脚本化验证环境。

## 1.2 需求分解与方案映射

| 需求项 | 设计/验证映射 | 项目文件或结果 |
|---|---|---|
| SDPA/FlashAttention baseline | `fa_top` 集成 DMA、page manager、score scheduler、compute core、online softmax update、finalize | `workspace/RTL/fa_top.v` |
| AXI4-Lite 控制 | 控制/状态/地址/scale/stride 寄存器 | `workspace/RTL/axi_lite_regs.v` |
| AXI4 Master 数据搬运 | 128-bit AXI read/write master 与 DMA engine | `workspace/RTL/dma_engine.v` 等 |
| 片上 SRAM tile | Q/K/V/ACC/meta SRAM cluster 和 load/store adapter | `workspace/RTL/*sram_cluster.v` |
| RTL 正确性 | Python/golden testbench 对比 | `sim/tb_fa_top.sv`，bonus 分支 README 记录 |
| 逻辑综合 | Genus + SKY130 HS Liberty | `results/reports/fa_top/*.rpt` |
| 门级功能仿真 | Xcelium zero-delay `smoke`、`zero` | `sim/xcelium_baseline/run_xcelium.sh` |
| SDF 回标仿真 | Xcelium `sdf_smoke`、`sdf_s256` | `sim/xcelium_baseline/timing/fa_top_mapped.sdf` |
| 功耗计算 | Joules Xreplay，RTL SHM + mapping + netlist | `sim/xcelium_baseline/power/results/xreplay_zero/` |
| Bonus 扩展 | padding mask、S=512、stream、dropout、multi-head 等 | `bonus_medium` 分支 |

## 1.3 指标约束与达成路径

### 1.3.1 面积

baseline 使用 SKY130 HS 标准单元库进行 Genus 综合。`results/reports/fa_top/area.rpt` 显示顶层 `fa_top` cell count 为 126,308，cell area 为 6,424,406.642 um²，net area 为 2,541,452.196 um²，total area 为 8,965,858.838 um²。主要面积集中在 `u_core_u_update`，其 total area 为 4,867,785.043 um²，反映在线 softmax 状态更新、累加和乘法相关逻辑是面积主体。

### 1.3.2 速度与时序

综合约束目标为 200 MHz，即 5 ns 时钟周期。`results/reports/fa_top/qor_final.rpt` 显示 clock period 为 5000 ps，critical path slack 约 0.4 ps，violating paths 为 0。`results/reports/fa_top/timing.rpt` 中关键路径位于 `u_core_u_update` 内部乘法/累加相关路径，说明后续若继续优化时序，应优先关注 update state cluster 中的乘法树、加法树和状态寄存器间路径。

### 1.3.3 功耗

功耗评估采用 Joules Xreplay zero-delay flow：先通过 Xcelium 生成 RTL activity SHM，再通过 Genus mapping 文件将 RTL activity 映射到门级网表，最后在 Joules 中结合 Liberty 进行功耗计算。当前归档结果为 total power 288.462 mW，其中 leakage 0.133 mW、internal 281.292 mW、switching 7.038 mW。该结果为 baseline zero-delay 估算结果，不是后布局 signoff power。

### 1.3.4 安全性与鲁棒性

本赛题主要面向算子加速，不涉及安全协议或加密防护。鲁棒性设计主要体现在配置寄存器默认值、W1C 状态位、AXI handshake 检查、DMA response error 传播、`fin_error_zero_l` 等异常标志，以及 testbench 中对 AXI response、unknown value、写回 beat/burst 数的检查。

### 1.3.5 验证与覆盖率目标

验证目标包括：RTL 输出与 golden model 对齐；AXI4-Lite 寄存器读写正确；AXI4 Master 读写 burst 行为正确；门级 zero-delay 仿真通过；SDF 回标仿真可完成；Xreplay power flow 可复现。当前未生成代码覆盖率数据库，因此报告中不声称代码覆盖率数值；功能覆盖以 directed testcase、scoreboard、trace 和工具日志通过为依据。

---

# 2 算法/协议与模式支持

## 2.1 算法/协议定义与 Golden 模型

### 2.1.1 算法/协议定义与处理流程

baseline 实现 causal SDPA：

```text
score(i,j) = Q_i dot K_j / sqrt(D)
P(i,j) = softmax(score(i,0..i))
O_i = sum_j P(i,j) * V_j
```

硬件实现不保存完整 score 矩阵，而是按 Q group 与 K/V tile 遍历。对每行维护 online softmax 状态：当前最大值 m、归一化分母 l 和累加向量 acc。每处理一个 tile，更新 m/l/acc，最后通过 reciprocal/normalize 输出 O。causal mask 在 score scheduler/compute path 中限制 j > i 的位置不参与 softmax。

### 2.1.2 软件参考模型

项目中包含 Python 行为模型与参考生成脚本，用于生成 Q/K/V/O 参考向量和误差对比。`bonus_medium` 分支 README 记录 S=256、Q8.8、causal 下 Verilog 与 Python 行为模型 MAE 为 0.000613、Max AE 为 0.007812；Verilog 与 FP32 golden reference MAE 为 0.001129、Max AE 为 0.008569，均满足 0.03/0.10 阈值。

### 2.1.3 输入输出与数据范围分析

baseline 输入 Q/K/V 为 signed Q8.8，16-bit 定点；输出 O 同样以 Q8.8 写回。score path 使用更宽的中间表示，update state cluster 中累加宽度为 48-bit，避免点积和 V 加权累加时过早溢出。寄存器 `SCALE` 默认 `0x00002000`，对应 baseline 缩放常数；`NEG_LARGE` 默认 `0xfff00000`，用于近似 mask 后的负无穷 score。

## 2.2 数值格式与关键算子设计

### 2.2.1 数据格式选择

baseline 采用 Q8.8 有符号定点格式，兼顾实现复杂度和误差。输入/输出使用 16-bit，AXI4 Master 数据宽度为 128-bit，因此每 beat 可搬运 8 个 16-bit 元素。Bonus 中增加 Q6.10 和 Q4.12 输出格式，通过 `CFG[2:1]` 选择，内部保持 Q16.16 相关中间表示，并通过 finalize/output normalize 的动态 shift 适配不同输出小数位。

### 2.2.2 误差与溢出控制

误差来源包括定点量化、score 缩放近似、exp/reciprocal 近似、online softmax 分块更新舍入等。设计采用较宽中间累加位宽、饱和/截断、负大数 mask 和查表/近似单元控制误差。测试结果显示 baseline S=256 相对 FP32 golden 的 MAE/MaxAE 均低于阈值。Bonus INT8 block quantization 探索通过 per-block scale 降低 outlier 对 INT8 量化误差的影响。

### 2.2.3 关键算子设计方案

关键算子包括 dot product、score/exp、online softmax update、reciprocal 和 output normalize。`dot_frontend` 负责组织 Q/K 数据和点积前端，`score_exp_pipe` 负责 score 处理、mask 和指数近似，`update_state_cluster` 负责 m/l/acc 更新，`finalize_cluster` 与 `output_norm_pipe` 完成最终归一化和输出打包。update state cluster 是面积和时序关键模块。

## 2.3 模式支持与扩展能力

### 2.3.1 性能优化

baseline 通过 tile K/V、双缓冲 SRAM page、DMA burst、online softmax 状态复用减少外部访问和片上存储压力。S=256 配置下，bonus 分支记录 RTL 仿真周期数为 145,219 cycles，低于 300,000 cycles 阈值。

### 2.3.2 模式支持与可配置性

baseline 支持 causal enable、Q/K/V/O base address、stride、scale、negative large value 等寄存器配置。Bonus 分支扩展了 padding mask、S=512、Q6.10/Q4.12、task chain、AXI4-Stream、dropout 和 multi-head 配置。

### 2.3.3 其他亮点

主要亮点包括：不保存 S×S 矩阵的 FlashAttention-style online softmax；AXI4-Lite + AXI4 Master 完整系统接口；Xcelium zero-delay/SDF 双门级仿真流程；Joules Xreplay 功耗路径；bonus 分支中对训练/部署场景的多项扩展。

---

# 3 数字模块硬件实现方案

## 3.1 总体架构与接口设计

### 3.1.1 总体实现架构

顶层 `fa_top` 包含以下主要模块：

- `axi_lite_regs`：控制寄存器、状态寄存器、地址寄存器、scale/stride 配置。
- `task_ctrl`：任务启动、运行、完成和错误状态控制。
- `page_manager`：Q group、K/V tile、page 切换、DMA command 调度。
- `dma_engine`、`dma_read_master`、`dma_write_master`：AXI4 Master 读写搬运。
- `q_load_store_adapter`、`k_load_adapter`、`v_load_adapter`、`o_store_adapter`：DMA 与 SRAM cluster 间的数据适配。
- `qk_sram_cluster`、`v_sram_cluster`、`acc_sram_cluster`、`meta_sram_cluster`：片上 SRAM 存储。
- `packed_compute_core`：score、online softmax update 和 finalize 的计算核心。

数据流为：AXI4-Lite 配置寄存器 -> page manager 发起 DMA 读 Q/K/V -> load adapter 写入 SRAM -> compute core 读取 Q/K/V SRAM 并更新 m/l/acc -> finalize 生成 O -> DMA write master 写回 O。

### 3.1.2 接口协议与总线功能

控制接口为 AXI4-Lite，地址宽度 12-bit，数据宽度 32-bit，负责配置控制寄存器和读取状态/性能计数。数据接口为 128-bit AXI4 Master，读通道用于搬运 Q/K/V，写通道用于写回 O。AXI memory model test 和门级仿真 testbench 均检查 AXI response、burst 类型、beat 数和写回范围。

### 3.1.3 外部寄存器描述

| Offset | 名称 | 访问属性 | 说明 |
|---:|---|:---:|---|
| 0x000 | CTRL | R/W | [0] START, [1] SOFT_RESET, [2] IRQ_EN |
| 0x004 | STATUS | R/W1C | [0] BUSY, [1] DONE, [2] ERROR |
| 0x008 | CFG | R/W | [0] CAUSAL_EN，baseline 默认开启 |
| 0x014 | Q_BASE_L | R/W | Q 基地址低 32 位 |
| 0x018 | Q_BASE_H | R/W | Q 基地址高 32 位 |
| 0x01C | K_BASE_L | R/W | K 基地址低 32 位 |
| 0x020 | K_BASE_H | R/W | K 基地址高 32 位 |
| 0x024 | V_BASE_L | R/W | V 基地址低 32 位 |
| 0x028 | V_BASE_H | R/W | V 基地址高 32 位 |
| 0x02C | O_BASE_L | R/W | O 基地址低 32 位 |
| 0x030 | O_BASE_H | R/W | O 基地址高 32 位 |
| 0x034 | STRIDE_BYTES | R/W | 行 stride，默认 128 bytes |
| 0x038 | NEG_LARGE | R/W | mask 用负大数，默认 `0xfff00000` |
| 0x03C | SCALE | R/W | score scale，默认 `0x00002000` |
| 0x040 | CYCLES | R | 性能计数器读数 |

## 3.2 关键模块实现与优化

### 3.2.1 关键架构与调度策略

调度围绕 Q group 和 K/V tile 展开。page manager 控制 Q/K/V load、score scheduler、update 和 finalize 的顺序，并通过 page 标志实现双缓冲。score scheduler 在每个 tile 内产生 Q row、K row、V row 和 token 信息，update token FIFO 传递上下文和 last 标志，保证 online softmax 状态更新与 V 累加同步。

### 3.2.2 关键计算单元实现

`packed_compute_core` 集成 dot-product 前端、score/exp pipeline、update state cluster 和 finalize cluster。dot-product 负责 Q/K 乘加，score/exp pipeline 处理 causal mask、score clamp 和指数近似，update state cluster 根据 alpha/beta 更新 m/l/acc，finalize cluster 读取 acc 和 l，调用 reciprocal 近似并归一化输出。

### 3.2.3 存储与数据搬运设计

设计使用 Q/K SRAM cluster、V SRAM cluster、ACC SRAM cluster 和 meta SRAM cluster。Q/K/V 数据通过 128-bit AXI burst 进入片上 SRAM；O 输出由 finalize 结果经 O store adapter 组包后写回。该结构避免 S×S score 存储，仅保留 tile 和每行 softmax 状态，符合 FlashAttention 的存储约束。

### 3.2.4 控制通路与状态机

`task_ctrl` 管理 IDLE/INIT/RUN/DRAIN/DONE/ERROR 等任务状态；`page_manager` 管理 Q/K/V load、tile 切换、score scheduling 和 O store；各 load/store adapter 使用 valid/ready handshake 与 DMA 和 SRAM 交互。错误路径包括 DMA response error、K/V load error、finalize zero-l error，并通过 STATUS.ERROR 反映。

### 3.2.5 接口信号列表

| 信号名 | 位宽 | 方向 | 说明 |
|---|---:|:---:|---|
| clk | 1 | I | 主时钟 |
| rst_n | 1 | I | 低有效复位 |
| s_axil_awaddr/s_axil_araddr | 12 | I | AXI4-Lite 地址 |
| s_axil_wdata/s_axil_rdata | 32 | I/O | AXI4-Lite 数据 |
| s_axil_*valid/*ready | 1 | I/O | AXI4-Lite handshake |
| irq | 1 | O | 中断请求 |
| m_axi_araddr/m_axi_awaddr | 64 | O | AXI4 Master 读/写地址 |
| m_axi_rdata/m_axi_wdata | 128 | I/O | AXI4 Master 数据 |
| m_axi_arlen/m_axi_awlen | 8 | O | AXI burst 长度 |
| m_axi_*valid/*ready | 1 | I/O | AXI4 Master handshake |

## 3.3 其他子模块设计

### 3.3.1 配置与控制模块

`axi_lite_regs` 实现寄存器读写、byte strobe、start pulse、soft reset pulse、IRQ enable、DONE/ERROR latch 与 W1C 清除。默认配置包括 causal enable、stride 128 bytes、scale `0x2000` 和 negative large `0xfff00000`。

### 3.3.2 数据路径模块

数据路径由 DMA engine、load/store adapter、SRAM cluster 和 compute core 串联。Q/K/V 输入以 16-bit 元素打包在 128-bit beat 内，计算核心内部使用更宽的 score、m/l 和 acc 表示，最后输出 128-bit 写回数据。

### 3.3.3 辅助模块

辅助模块包括 performance counters、update token FIFO、reciprocal approximation、score exp ROM/pipe、SRAM wrapper 和仿真 memory model。门级仿真中使用 `sim/xcelium_baseline/models/` 下的标准单元、SRAM 和 AXI memory 模型。

---

# 4 验证方案与正确性结果

## 4.1 验证目标与通过准则

验证通过准则包括：RTL 输出与 golden reference 误差小于阈值；AXI4-Lite smoke 能正确读写寄存器；S=256 zero testcase 能完成并写回期望 O 区间；门级 zero-delay 仿真无 X/timeout/STATUS.ERROR；SDF 回标仿真可完成；memory model sanity 通过；功耗 activity testcase 产生有效 RTL SHM。

## 4.2 验证环境

### 4.2.1 验证工具与脚本

- RTL/bonus 仿真：Icarus Verilog、Python/numpy golden check。
- 门级仿真：Xcelium 24.09-s006，脚本位于 `sim/xcelium_baseline/run_xcelium.sh`。
- SDF 仿真：Xcelium `$sdf_annotate`，SDF 文件为 `sim/xcelium_baseline/timing/fa_top_mapped.sdf`。
- 功耗：Joules Xreplay，脚本位于 `sim/xcelium_baseline/power/scripts/run_joules_xreplay_zero.sh`。

### 4.2.2 验证平台架构

门级 testbench 实例化 `fa_top_mapped.v`、AXI memory model 和 AXI-Lite driver。测试流程为复位、配置 Q/K/V/O 地址、stride、scale、启动 CTRL.START、轮询 STATUS，监控 AXI read/write handshake、DMA done/error、O 写回 beat/burst 数。power testcase 使用非零 Q/K/V stimulus 生成 RTL activity SHM。

### 4.2.3 测试集设计

| 测试项 | 目的 | 结果 |
|---|---|---|
| `run_mem_model_test.sh` | AXI memory model sanity | 通过 |
| `run_xcelium.sh smoke` | AXI-Lite register smoke | 通过 |
| `run_xcelium.sh zero` | S=256 zero-input zero-delay 门级功能 | 通过，`o_write_beats=2048`，`o_write_bursts=128` |
| `run_xcelium.sh sdf_smoke` | SDF 回标下 AXI-Lite smoke | 通过 |
| `run_xcelium.sh sdf_s256` | SDF 回标下 S=256 功能 | 通过，`o_write_beats=2048`，`o_write_bursts=128` |
| `power_s256` RTL activity | 功耗输入 stimulus | 生成 RTL SHM |

## 4.3 正确性验证结果

### 4.3.1 基本功能验证

bonus 分支 README 记录 baseline S=256、Q8.8、causal 下 Verilog 与 Python 行为模型对比 MAE 为 0.000613，Max AE 为 0.007812；Verilog 与 FP32 golden reference 对比 MAE 为 0.001129，Max AE 为 0.008569，满足 0.03/0.10 阈值。

### 4.3.2 边界与异常场景验证

causal mask 覆盖 i=0 只能关注 j=0 的 corner case。AXI testbench 检查 AXI response 是否 OKAY、O 写回地址是否位于 O 区间、AWSIZE 是否为 128-bit、AWBURST 是否为 INCR、WSTRB 是否全有效，并在 timeout 时输出 DMA、AXI、调度状态诊断信息。STATUS.ERROR 和 finalize zero-l error 用于异常路径观测。

### 4.3.3 随机回归验证

当前报告依据主要为 directed testcase 与 golden vector 对比。仓库中未归档完整随机回归覆盖率数据库，因此不声称随机覆盖率数值。Python model 和 bonus 分支低精度 evaluator 可继续扩展为随机回归入口。

## 4.4 接口验证结果

### 4.4.1 配置接口

`smoke` testcase 验证 AXI4-Lite register write/read 和默认 STATUS 行为。SDF smoke 在回标延迟模型下复验同一寄存器路径，说明标准单元延迟和 specify 模型不会破坏基本控制接口功能。

### 4.4.2 数据接口

`zero` 和 `sdf_s256` testcase 通过 AXI memory model 验证 Q/K/V 读与 O 写回。S=256 输出大小为 256×64×2 bytes = 32768 bytes，对应 2048 个 128-bit write beats；日志记录 `o_write_beats=2048`、`o_write_bursts=128`。

## 4.5 覆盖率与问题闭环

### 4.5.1 代码覆盖率

当前未生成代码覆盖率数据库，故本节不填写百分比。后续可通过 Xcelium coverage 或 Verilator/covered 等工具补充 statement/branch/toggle coverage。

### 4.5.2 功能覆盖率

已覆盖 baseline 寄存器配置、S=256 数据搬运、DMA 读写、O 写回、zero-delay 门级仿真、SDF 回标仿真和 power stimulus。Bonus 分支覆盖 S=256、S=512、padding mask、格式选择、task queue、stream、dropout、multi-head 等 directed 场景。

### 4.5.3 问题分析与修复记录

主要问题闭环包括：早期 Yosys 对大端口/大位宽 RTL 展开性能不足，后端改用 Genus；门级仿真中修正 SRAM/memory model 行为以匹配 AXI burst；SDF 仿真中引入 SKY130 standard-cell specify 模型并修正 SDF annotation；Xreplay 功耗中补充 Genus mapping、SRAM Liberty、标准单元/SRAM Verilog model startup file，并避免归档超大 replay VCD。

---

# 5 PPA 结果与指标达成

## 5.1 工具与环境配置

| 类型 | 工具/库 | 说明 |
|---|---|---|
| 综合 | Genus 25.12-s067_1 | `results/reports/fa_top/*.rpt` |
| 门级仿真 | Xcelium 24.09-s006 | `sim/xcelium_baseline` |
| 功耗 | Joules 25.12 | Xreplay zero-delay power |
| 工艺库 | SkyWater SKY130 HS | `sky130_fd_sc_hs__tt_025C_1v80.lib` |
| SDF 模型 | SKY130 standard-cell specify | 来源于开源 SkyWater PDK standard-cell Verilog 模型 |

## 5.2 面积结果

| 模块 | 面积/门数 | 备注 |
|---|---:|---|
| `fa_top` | cell count 126,308；total area 8,965,858.838 um² | Genus area report |
| `u_core_u_update` | cell count 69,528；total area 4,867,785.043 um² | online softmax/update 主体 |
| `u_finalize` | cell count 11,144；total area 270,479.156 um² | 最终归一化 |

## 5.3 时序结果

| 模式 | 目标频率 | 实际频率/Fmax | Slack | 备注 |
|---|---:|---:|---:|---|
| baseline synthesis | 200 MHz | 约 200 MHz | WNS 0.4 ps | Genus `qor_final.rpt`，violating paths=0 |
| SDF gate simulation | 200 MHz 对应 SDF | 不作为 Fmax signoff | 不作为 pass/fail | 用于回标功能验证 |

## 5.4 功耗结果

| 项目 | 数值 | 备注 |
|---|---:|---|
| 静态功耗 | 0.133 mW | Joules Xreplay zero-delay |
| 动态功耗 | 288.329 mW | internal + switching |
| 其中 internal | 281.292 mW | 占 97.51% |
| 其中 switching | 7.038 mW | 占 2.44% |
| 总功耗 | 288.462 mW | `fa_top_power_s256_xreplay_zero.rpt` |

按 category：

| Category | Leakage | Internal | Switching | Total | Row% |
|---|---:|---:|---:|---:|---:|
| memory | 0.115 | 130.156 | 0.346 | 130.618 | 45.28% |
| register | 0.007 | 137.683 | 1.270 | 138.959 | 48.17% |
| logic | 0.011 | 13.453 | 5.421 | 18.885 | 6.55% |

## 5.5 指标达成与 PPA 权衡分析

baseline 已达成 RTL 正确性、Genus 可综合、200 MHz 综合时序、Xcelium zero-delay 门级功能仿真、SDF 回标功能仿真和 Joules Xreplay 功耗计算。PPA 上，面积和功耗主要集中在 update state cluster 和 SRAM/register 相关部分，说明 online softmax 的 m/l/acc 更新和数据保持是优化重点。当前 power 是 zero-delay baseline estimate，未包含 post-route SPEF，因此后续若进入 signoff，应补充 Innovus 后布局、寄生参数、真实时钟树和 vector-based/signoff power flow。

---

# 6 Bonus / 扩展设计

## 6.1 扩展设计与创新点总结

1. `bonus_medium` 分支实现 7/9 项 bonus，包括 4 项 easy 和 3 项 medium。
2. 扩展均围绕 baseline 架构增量实现，保持 AXI4-Lite 配置模型和 FlashAttention online softmax 主路径。
3. `bonus7_int8/fp8` 分支探索 INT8 block quantization，保留 Q8.8 RTL baseline，同时增加低精度 evaluator、scale metadata 和寄存器规划。

## 6.2 Bonus 项实现情况

| Bonus | 难度 | 实现方式 | 结果/收益 |
|---|---|---|---|
| Padding Mask | Easy | `VALID_LEN` 寄存器，score path mask，无效 token exp=0 | 支持有效长度小于 S |
| Q6.10/Q4.12 | Easy | `CFG[2:1]` 格式选择，finalize/output shift 动态配置 | 支持不同定点精度 |
| S=512 | Easy | `SEQ_LEN` 存储 num_groups，计数器扩展，TOKEN_WIDTH 16->18 | S=512 FP32 对比 MAE 0.000530、Max AE 0.007812 |
| DMA 任务队列 | Easy | 8-entry task RAM + FIFO，task chain 自动执行 | 减少主机逐任务启动开销 |
| AXI4-Stream | Medium | 新增 `axi_stream_data_adapter`，CFG[4] 旁路 DMA | 支持与流式 IP 级联 |
| Dropout | Medium | 32-bit LFSR，dropout mask 复用 padding mask 管道 | 支持训练模式近似 |
| 多 Head | Medium | page manager 外层 head loop，head_stride 地址偏移 | 支持 1-8 heads 顺序执行 |
| INT8 block quantization | Hard 探索 | Python evaluator、block scale、Hadamard preconditioning 选项 | 为低精度路径提供误差/带宽评估 |

Bonus 分支记录 S=256 延迟为 145,219 cycles，S=512 延迟为 514,600 cycles。S=256 DMA 带宽统计为读 Q 32 KB、读 K 32 KB、读 V 32 KB、写 O 32 KB，总读 96 KB、总写 32 KB。

---

# 7 总结

## 7.1 项目总结

本项目完成了 FlashAttention baseline 加速器从 RTL、综合、门级验证到功耗评估的完整路径。baseline 采用 Q8.8 定点、S=256、D=64、causal attention，通过 tile K/V 与 online softmax 避免 S×S score 矩阵存储；后端使用 Genus 生成 `fa_top_mapped.v`，在 200 MHz 目标下综合报告无 violating paths；Xcelium 完成 zero-delay 与 SDF 回标门级仿真；Joules Xreplay 完成 baseline zero-delay 功耗计算，总功耗 288.462 mW。Bonus 分支实现 padding mask、格式扩展、S=512、任务队列、AXI4-Stream、Dropout、多 Head，并探索 INT8 block quantization。后续工作可继续推进 post-route PPA、真实 SPEF power、覆盖率收集、低精度 RTL datapath 和更高并行度 multi-head。

---

# 8 附录

## 8.1 关键寄存器表

| Offset | 名称 | 访问属性 | 说明 |
|---:|---|:---:|---|
| 0x000 | CTRL | R/W | [0] START, [1] SOFT_RESET, [2] IRQ_EN |
| 0x004 | STATUS | R/W1C | [0] BUSY, [1] DONE, [2] ERROR |
| 0x008 | CFG | R/W | baseline [0] CAUSAL_EN；bonus 扩展 FORMAT/TASK_CHAIN/STREAM/DROPOUT |
| 0x00C | SEQ_LEN | R/W | bonus，S/8，默认 32，最大 64 |
| 0x010 | VALID_LEN | R/W | bonus padding mask，有效 KV 长度 |
| 0x014 | Q_BASE_L | R/W | Q 基地址低 32 位 |
| 0x018 | Q_BASE_H | R/W | Q 基地址高 32 位 |
| 0x01C | K_BASE_L | R/W | K 基地址低 32 位 |
| 0x020 | K_BASE_H | R/W | K 基地址高 32 位 |
| 0x024 | V_BASE_L | R/W | V 基地址低 32 位 |
| 0x028 | V_BASE_H | R/W | V 基地址高 32 位 |
| 0x02C | O_BASE_L | R/W | O 基地址低 32 位 |
| 0x030 | O_BASE_H | R/W | O 基地址高 32 位 |
| 0x034 | STRIDE_BYTES | R/W | 行 stride |
| 0x038 | NEG_LARGE | R/W | mask 负大数 |
| 0x03C | SCALE | R/W | score scale |
| 0x040 | CYCLES | R | 性能计数器 |
| 0x044-0x04C | TASK_* | R/W | bonus DMA task queue |
| 0x050-0x054 | DROPOUT_* | R/W | bonus dropout seed/prob |
| 0x058-0x05C | HEAD_* | R/W | bonus multi-head 配置 |

## 8.2 关键接口信号说明

| 信号名 | 位宽 | 方向 | 说明 |
|---|---:|:---:|---|
| `clk` | 1 | I | 主时钟 |
| `rst_n` | 1 | I | 低有效复位 |
| `irq` | 1 | O | 中断请求 |
| `s_axil_awaddr` | 12 | I | AXI4-Lite write address |
| `s_axil_wdata` | 32 | I | AXI4-Lite write data |
| `s_axil_araddr` | 12 | I | AXI4-Lite read address |
| `s_axil_rdata` | 32 | O | AXI4-Lite read data |
| `m_axi_araddr` | 64 | O | AXI4 read address |
| `m_axi_rdata` | 128 | I | AXI4 read data |
| `m_axi_awaddr` | 64 | O | AXI4 write address |
| `m_axi_wdata` | 128 | O | AXI4 write data |
| `m_axi_wstrb` | 16 | O | AXI4 write strobe |
| `m_axi_*valid/*ready` | 1 | I/O | AXI handshake |

## 8.3 补充实验结果

| 实验 | 文件/路径 | 结果 |
|---|---|---|
| Genus 面积 | `results/reports/fa_top/area.rpt` | total area 8,965,858.838 um² |
| Genus QoR | `results/reports/fa_top/qor_final.rpt` | 200 MHz，WNS 0.4 ps，violating paths 0 |
| Xcelium baseline | `sim/xcelium_baseline/README.md` | `zero`、`sdf_smoke`、`sdf_s256` 通过 |
| Joules Xreplay | `sim/xcelium_baseline/power/results/xreplay_zero/` | total power 288.462 mW |
| Bonus S=512 | `bonus_medium:another_workspace/README.md` | MAE 0.000530，Max AE 0.007812 |

---

# 9 参考文献

1. Tri Dao et al., FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness.
2. Tri Dao, FlashAttention-2: Faster Attention with Better Parallelism and Work Partitioning.
3. Google/SkyWater SKY130 PDK: https://github.com/google/skywater-pdk
4. Cadence Genus、Xcelium、Joules 工具用户文档。
5. 本项目仓库与分支资料：`xcelium_baseline`、`bonus_medium`、`bonus7_int8/fp8`。
