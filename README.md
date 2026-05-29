# FA-Accel-IP

FA-Accel-IP 是一个面向 Transformer 推理中 Scaled Dot-Product Attention 的可综合硬件加速器 IP。

该 IP 聚焦固定 Baseline 规模：`S=256`、`d=64`、单 batch、单 head。系统通过 AXI4-Lite 接收主机配置，通过 AXI4 Master DMA 从外部内存读取 Q/K/V，采用 K/V tiling 与 online softmax 完成 FlashAttention-style attention 计算，并将输出 O 写回外部内存。

FA-Accel-IP 不是完整 Transformer 加速器，也不是通用矩阵乘法 IP。它的产品边界是一个 attention 算子级硬件 IP，重点覆盖数据搬运、控制寄存器、定点计算、RTL 实现、验证闭环与 PPA 分析。

## 产品目标

FA-Accel-IP 的 Baseline 版本目标包括：

- 提供可综合 RTL IP。
- 支持 `batch=1`、`head=1`、`S=256`、`d=64`。
- 输入 Q/K/V 使用 16-bit signed Q8.8 定点格式。
- 输出 O 使用 16-bit signed Q8.8 定点格式。
- 支持 causal 与 non-causal attention 配置。
- 使用 online softmax，不显式存储完整 score 矩阵。
- 使用 K/V tiling，不显式存储完整 softmax probability 矩阵。
- 通过 AXI4-Lite 暴露控制、状态与统计寄存器。
- 通过 AXI4 Master DMA 读取 Q/K/V 并写回 O。
- 提供 cycles、读写字节数、误差、面积、时序与功耗等分析入口。
- 配套 Python golden model、测试向量、仿真验证、综合脚本与报告流程。

## Baseline 范围

Baseline 配置有意保持收敛，目标是在明确输入规模下完成端到端硬件闭环。

| 项目 | Baseline |
|---|---:|
| Batch | 1 |
| Head | 1 |
| Sequence length | `S = 256` |
| Head dimension | `d = 64` |
| Q/K/V shape | `[256, 64]` |
| O shape | `[256, 64]` |
| 输入格式 | signed Q8.8, 16-bit |
| 输出格式 | signed Q8.8, 16-bit |
| 控制接口 | AXI4-Lite slave |
| 数据接口 | AXI4 Master read/write |
| Mask | causal mask |
| 数据流 | online softmax + K/V tiling |

Baseline 不强制支持多 batch、多 head、可变序列长度、BF16/FP16、INT8/FP8、dropout、padding mask、AXI4-Stream、多任务队列或完整 Transformer block。

## Attention 数据流

对于每个 query 位置 `i`，IP 计算：

```text
score(i,j) = dot(Q[i], K[j]) * SCALE + mask(i,j)
P(i,:)     = softmax(score(i,:))
O[i]       = sum_j P(i,j) * V[j]
```

设计不生成完整 `S x S` score 矩阵，也不生成完整 `S x S` probability 矩阵。K/V 以 tile 为单位进入片上 buffer，每个 query 行或 query block 维护 online softmax 状态：

- `m`：当前行最大值。
- `l`：当前归一化分母。
- `acc[64]`：当前加权累加向量。

推荐的 online softmax 更新形式为：

```text
m_new   = max(m_old, score)
alpha   = exp(m_old - m_new)
beta    = exp(score - m_new)
l_new   = l_old * alpha + beta
acc_new = acc_old * alpha + beta * V[j]
```

遍历所有 K/V tile 后，IP 将 `acc / l` 量化为 Q8.8 输出。

## 数据规格

Q、K、V、O 默认采用 row-major 内存布局：

```text
addr(tensor[i][k]) = BASE + i * STRIDE_BYTES + k * 2
```

Baseline 默认约束：

- `i` 范围为 `0..255`。
- `k` 范围为 `0..63`。
- 每个元素为 16-bit signed Q8.8。
- 默认 `STRIDE_BYTES = 128`。
- 每个 tensor 大小为 `32 KB`。

## 接口概览

顶层 IP 包含：

- `clk` 与 `rst_n`。
- AXI4-Lite slave 控制接口。
- AXI4 Master read 接口，用于读取 Q/K/V。
- AXI4 Master write 接口，用于写回 O。
- `irq` 完成中断输出。

核心寄存器包括：

| Offset | Name | Purpose |
|---:|---|---|
| `0x00` | `CTRL` | START, SOFT_RESET, IRQ_EN |
| `0x04` | `STATUS` | BUSY, DONE, ERROR |
| `0x08` | `CFG` | CAUSAL_EN |
| `0x14` - `0x30` | Base address registers | Q/K/V/O base addresses |
| `0x34` | `STRIDE_BYTES` | Tensor row stride |
| `0x38` | `NEG_LARGE` | Mask value for invalid scores |
| `0x3C` | `SCALE` | Attention scale constant |
| `0x40` | `CYCLES` | Execution cycle count |

建议扩展寄存器用于报告 RD_BYTES、WR_BYTES、错误码、版本号和实现参数。

## 微架构

推荐 RTL 层次如下：

```text
fa_accel_top
├── fa_regfile
├── fa_dma_rd
├── fa_dma_wr
├── fa_scheduler
├── fa_q_buffer
├── fa_kv_buffer
├── fa_dot_pe
├── fa_softmax_online
├── fa_exp_approx
├── fa_recip_approx
└── fa_out_quant
```

模块职责：

- `fa_regfile` 管理控制寄存器、状态寄存器和统计计数器。
- `fa_dma_rd` 负责 Q/K/V DMA 读取。
- `fa_dma_wr` 负责 O DMA 写回。
- `fa_scheduler` 管理 Q block、K/V tile、causal 边界和任务状态。
- `fa_q_buffer` 与 `fa_kv_buffer` 缓存当前计算窗口所需数据。
- `fa_dot_pe` 执行 Q/K dot-product，可采用 16 或 32 lane MAC。
- `fa_softmax_online` 更新 `m/l/acc` 状态。
- `fa_exp_approx` 与 `fa_recip_approx` 提供硬件友好的数值近似。
- `fa_out_quant` 完成 Q8.8 输出舍入与饱和。

推荐 Baseline 参数包括 `BQ=4/8`、`BK=16/32`、`DOT_PE_LANES=32`、`V_ACC_LANES=16/32`。最终参数需要根据误差、面积、频率、周期数和带宽权衡确定。

## 正确性与 PPA 目标

| 指标 | 目标 |
|---|---:|
| mean_abs_error | `<= 0.03` |
| max_abs_error | `<= 0.10` |
| 单次 causal attention cycles | `< 300k cycles` |
| 等效逻辑门数 | `<= 2,000,000 gates` |
| 带宽统计 | RD_BYTES / WR_BYTES |

正确性以 FP32 golden model 为最终参考，fixed-point golden model 用于对齐 RTL 定点行为，并解释 dot-product 截断、缩放、exp 近似、reciprocal 近似、累加缩放和输出量化带来的误差。

## 验证策略

验证流程以 golden 对比为核心：

- Python FP32 SDPA golden model。
- Python fixed-point golden model。
- Q8.8 量化与反量化工具。
- 随机测试向量与 corner case 测试向量生成。
- cocotb 端到端验证。
- SystemVerilog testbench 或轻量 UVM smoke test 作为补充。
- scoreboard 逐元素对比 RTL 输出与 golden 输出，并统计 MAE、MaxAE 和失败位置。

必测内容包括 AXI4-Lite 寄存器读写、START/BUSY/DONE/ERROR 流程、SOFT_RESET、IRQ、DMA read/write、随机 Q/K/V、causal mask、`i=0`、`i=255`、tile 跨 causal 边界、默认 stride、非默认 stride、非零 base address 和 full-size `S=256,d=64` 回归。

## 计划目录结构

```text
.
├── rtl/
├── sim/
├── cocotb/
├── model/
├── vectors/
├── synth/
├── doc/
└── README.md
```

目录用途：

- `rtl/`：SystemVerilog RTL 源码与 filelist。
- `sim/`：SystemVerilog testbench、memory model 和仿真脚本。
- `cocotb/`：Python 端到端验证环境。
- `model/`：FP32 golden、fixed-point golden、量化、近似、cycle 和 bandwidth model。
- `vectors/`：Q/K/V 输入和 golden O 输出。
- `synth/`：Genus 脚本、约束、日志和报告。
- `doc/`：架构、定点、验证、误差、PPA 和最终设计文档。

## 当前状态

仓库当前处于产品定义与工程初始化阶段。已建立基础版本控制和产品导向 README。后续将逐步加入 RTL、模型、验证环境、综合脚本、测试向量和分析报告。

## Roadmap

1. 建立 FP32 与 fixed-point golden model。
2. 实现简化 memory 接口的 functional compute core。
3. 实现并对齐 online softmax RTL。
4. 集成 AXI4-Lite 控制接口与 AXI4 Master DMA。
5. 跑通 full-size 端到端回归与误差分析。
6. 优化 PE 并行度、tiling、流水线、cycles 和带宽。
7. 完成综合并生成面积、时序、功耗和 QoR 报告。
8. 固化 Baseline IP 包、脚本和文档。

后续扩展方向可包括 padding mask、更多定点格式、AXI4-Stream 接口和 multi-head 执行。
