# FlashAttention 高性能硬件加速器 IP 产品需求文档

> **产品名称**：FA-Accel-IP  
> **文档版本**：Baseline v1.0  
> **适用项目**：基于大模型推理的 FlashAttention 高性能硬件加速器 IP 设计  
> **建议存放路径**：`doc/product_spec.md` 或 `docs/product_spec.md`  
> **文档用途**：作为项目需求冻结、架构设计、RTL 开发、算法建模、验证计划、综合评估和最终报告撰写的工程指导文档。

---

## 1. 文档信息

| 项目 | 内容 |
|---|---|
| 产品名称 | FA-Accel-IP |
| 版本 | Baseline v1.0 |
| 目标场景 | 面向 Transformer 推理中 Scaled Dot-Product Attention 的可综合硬件加速器 IP |
| 目标用户 | SoC / AI 加速器系统集成方、竞赛评测平台、RTL 验证与综合评估流程 |
| 设计目标 | 在固定输入规模下实现 FlashAttention-style attention，满足正确性、性能、面积、带宽与可综合性要求 |
| Baseline 范围 | 单 batch、单 head、固定 `S=256, d=64` |

---

## 2. 产品定位

FA-Accel-IP 是一个独立的 attention 算子级硬件 IP。

该 IP 通过 AXI4-Lite 接收主机配置，通过 AXI4 Master DMA 从外部内存读取 Q、K、V，完成定点 FlashAttention-style attention 计算，并将输出 O 写回外部内存。

该产品不是完整 Transformer 加速器，也不是通用矩阵乘法 IP。Baseline 版本聚焦于单 batch、单 head、固定 `S=256, d=64` 的 causal / non-causal attention 计算。

---

## 3. 设计目标

### 3.1 必须达成目标

1. 实现可综合 RTL IP。
2. 支持 `S=256, d=64, batch=1, head=1`。
3. 输入 Q/K/V 为 16-bit signed Q8.8 定点格式。
4. 输出 O 为 16-bit signed Q8.8 定点格式。
5. 支持 causal mask。
6. 不显式存储完整 score 矩阵。
7. 不显式存储完整 softmax probability 矩阵。
8. 使用 online softmax。
9. 分块处理 K/V。
10. 支持 AXI4-Lite 控制寄存器访问。
11. 支持 AXI4 Master DMA 读 Q/K/V、写 O。
12. 单次 causal attention 执行周期数小于 `300k cycles`。
13. 等效逻辑门数小于或等于 `2,000,000 gates`。
14. 提供 RD_BYTES / WR_BYTES 或等效带宽统计。
15. 提供仿真验证、测试向量、golden 对比、综合脚本与综合报告。

### 3.2 优先优化目标

1. 降低 cycles。
2. 提高 Fmax。
3. 控制面积和片上 buffer。
4. 降低外部内存访问量。
5. 降低 mean_abs_error 和 max_abs_error。
6. 提高设计报告的工程完整性和可解释性。

### 3.3 非目标

Baseline v1.0 不强制支持以下功能：

1. 多 batch。
2. 多 head。
3. `S=512` 或可变序列长度。
4. BF16 / FP16。
5. INT8 / FP8。
6. dropout。
7. padding mask。
8. AXI4-Stream 接口。
9. 多任务队列。
10. 完整 Transformer block。

这些功能可作为 Bonus 版本独立开发，不应影响 Baseline 版本的代码、验证与综合结果。

---

## 4. 功能规格

### 4.1 计算功能

对于每个 query 位置 `i`，IP 需要计算：

```text
score(i,j) = dot(Q[i], K[j]) * SCALE + mask(i,j)
P(i,:)     = softmax(score(i,:))
O[i]       = Σ_j P(i,j) * V[j]
```

其中：

- `Q[i]` 为第 `i` 行 query 向量，长度为 64。
- `K[j]` 为第 `j` 行 key 向量，长度为 64。
- `V[j]` 为第 `j` 行 value 向量，长度为 64。
- `O[i]` 为第 `i` 行输出向量，长度为 64。
- 当 `CAUSAL_EN=1` 时，若 `j > i`，则该位置 score 应被 mask 为 `NEG_LARGE` 或等效负无穷近似值。
- 当 `CAUSAL_EN=0` 时，所有 `j ∈ [0, S-1]` 均参与计算。

### 4.2 FlashAttention-style 数据流要求

设计必须满足以下数据流要求：

1. 不生成完整 `S × S` score 矩阵。
2. 不生成完整 `S × S` probability 矩阵。
3. K/V 以 tile 为单位载入片上 buffer。
4. 每个 query 行或 query block 维护 online softmax 状态。
5. 对每个 query 行维护：
   - 当前最大值 `m`
   - 当前归一化分母 `l`
   - 当前加权累加向量 `acc[64]`
6. 在遍历 K/V tile 时持续更新 `m/l/acc`。
7. 所有 K/V tile 遍历结束后，将 `acc / l` 转换为 Q8.8 输出。

推荐 online softmax 更新形式：

```text
m_new   = max(m_old, score)
alpha   = exp(m_old - m_new)
beta    = exp(score - m_new)
l_new   = l_old * alpha + beta
acc_new = acc_old * alpha + beta * V[j]
```

对于 tile 内多 score 的实现，可使用逐元素 online 更新，也可先求 tile 局部最大值后进行 tile-level 更新。但无论采用哪种方式，都不得存储完整 attention 矩阵。

---

## 5. 输入输出数据规格

### 5.1 Tensor 规模

| Tensor | Shape | Data Type | Size |
|---|---:|---:|---:|
| Q | `[256, 64]` | signed Q8.8 | 32 KB |
| K | `[256, 64]` | signed Q8.8 | 32 KB |
| V | `[256, 64]` | signed Q8.8 | 32 KB |
| O | `[256, 64]` | signed Q8.8 | 32 KB |

### 5.2 内存排布

Baseline 默认采用 row-major 排布：

```text
addr(tensor[i][k]) = BASE + i * STRIDE_BYTES + k * 2
```

其中：

- `i ∈ [0, 255]`
- `k ∈ [0, 63]`
- 每个元素为 16-bit signed Q8.8
- 默认 `STRIDE_BYTES = 128`

### 5.3 定点格式

| 数据 | 格式 | 位宽 | 说明 |
|---|---:|---:|---|
| Q/K/V | Q8.8 signed | 16-bit | 输入 |
| dot-product 乘法结果 | Q16.16 signed | 32-bit | 单项乘法 |
| dot-product 累加 | signed fixed-point | ≥40-bit 推荐 | 64 项累加 |
| score after scale | signed fixed-point | 算法确定 | 进入 softmax 前 |
| exp 输出 | unsigned fixed-point | 算法确定 | 近似指数 |
| l | unsigned fixed-point | 算法确定 | softmax 分母 |
| acc | signed fixed-point | 算法确定 | 64 维输出累加 |
| O | Q8.8 signed | 16-bit | 输出 |

所有定点路径必须定义：

1. 小数位数。
2. 右移策略。
3. 舍入策略。
4. 饱和策略。
5. 溢出处理。
6. 误差来源。

---

## 6. 接口规格

### 6.1 顶层接口

FA-Accel-IP 顶层应包含：

1. 时钟与复位接口：
   - `clk`
   - `rst_n`

2. AXI4-Lite slave 控制接口：
   - 用于寄存器读写、启动、状态查询。

3. AXI4 Master read/write 接口：
   - 用于 DMA 读取 Q/K/V。
   - 用于 DMA 写回 O。

4. 中断接口：
   - `irq`
   - 当 `IRQ_EN=1` 且计算完成时拉高。

---

## 7. 寄存器规格

### 7.1 必需寄存器

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x00 | CTRL | R/W | bit0 START；bit1 SOFT_RESET；bit2 IRQ_EN |
| 0x04 | STATUS | R / W1C | bit0 BUSY；bit1 DONE；bit2 ERROR |
| 0x08 | CFG | R/W | bit0 CAUSAL_EN |
| 0x14 | Q_BASE_L | R/W | Q base address low 32-bit |
| 0x18 | Q_BASE_H | R/W | Q base address high 32-bit |
| 0x1C | K_BASE_L | R/W | K base address low 32-bit |
| 0x20 | K_BASE_H | R/W | K base address high 32-bit |
| 0x24 | V_BASE_L | R/W | V base address low 32-bit |
| 0x28 | V_BASE_H | R/W | V base address high 32-bit |
| 0x2C | O_BASE_L | R/W | O base address low 32-bit |
| 0x30 | O_BASE_H | R/W | O base address high 32-bit |
| 0x34 | STRIDE_BYTES | R/W | 默认 128 bytes |
| 0x38 | NEG_LARGE | R/W | mask 负无穷近似值 |
| 0x3C | SCALE | R/W | `1/sqrt(d)` 缩放常数 |
| 0x40 | CYCLES | R | 本次执行周期数 |

### 7.2 建议扩展寄存器

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x44 | RD_BYTES_L | R | DMA read bytes low 32-bit |
| 0x48 | RD_BYTES_H | R | DMA read bytes high 32-bit |
| 0x4C | WR_BYTES_L | R | DMA write bytes low 32-bit |
| 0x50 | WR_BYTES_H | R | DMA write bytes high 32-bit |
| 0x54 | ERR_CODE | R | 错误码 |
| 0x58 | VERSION | R | IP version |
| 0x5C | IMPL_CFG | R | BQ/BK/PE 配置信息 |

### 7.3 CTRL 行为

- 写 `CTRL.START=1` 时，如果 `STATUS.BUSY=0`，IP 开始一次 attention 任务。
- 如果 `STATUS.BUSY=1` 时再次写 START，IP 应忽略该请求或置 `STATUS.ERROR=1`。
- 写 `CTRL.SOFT_RESET=1` 时，IP 清除内部状态机、计数器和错误状态。
- `CTRL.IRQ_EN=1` 时，任务完成后产生中断。

### 7.4 STATUS 行为

- `BUSY=1` 表示 IP 正在执行任务。
- `DONE=1` 表示本次任务完成。
- `DONE` 建议采用 write-one-clear。
- `ERROR=1` 表示配置非法、AXI 访问错误或状态机异常。

---

## 8. 微架构建议

### 8.1 顶层模块划分

建议 RTL 采用以下模块层次：

1. `fa_accel_top`
   - 顶层封装。
   - 连接 AXI4-Lite、AXI4 Master、irq。

2. `fa_regfile`
   - 控制寄存器。
   - 状态寄存器。
   - 计数器寄存器。

3. `fa_dma_rd`
   - Q/K/V 读取 DMA。
   - 支持 burst read。

4. `fa_dma_wr`
   - O 写回 DMA。
   - 支持 burst write。

5. `fa_scheduler`
   - 控制 Q block、K/V tile 遍历。
   - 生成 tile 地址。
   - 管理 causal mask 边界。

6. `fa_kv_buffer`
   - K tile buffer。
   - V tile buffer。

7. `fa_q_buffer`
   - Q block buffer。

8. `fa_dot_pe`
   - Q/K dot-product 计算阵列。
   - 推荐 16 或 32 lane MAC。

9. `fa_softmax_online`
   - online softmax 状态更新。
   - 包含 max、exp、l 更新、acc 缩放。

10. `fa_exp_approx`
    - exp 近似模块。
    - 可采用 LUT、PWL 或 LUT+插值。

11. `fa_recip_approx`
    - reciprocal 近似模块。
    - 用于最终 `acc / l`。

12. `fa_out_quant`
    - 输出量化。
    - Q8.8 舍入、饱和。

---

## 9. 推荐 Baseline 参数

建议 Baseline v1.0 采用以下参数作为初始工程目标：

| 参数 | 建议值 | 说明 |
|---|---:|---|
| S | 256 | 固定 |
| d | 64 | 固定 |
| BQ | 4 或 8 | Q block 行数 |
| BK | 16 或 32 | K/V tile 行数 |
| DOT_PE_LANES | 32 | dot-product 并行乘加数量 |
| V_ACC_LANES | 16 或 32 | V 加权累加并行度 |
| dot acc width | 40 或 48 bit | 降低溢出风险 |
| exp implementation | LUT 或 PWL | 由算法误差评估决定 |
| reciprocal implementation | LUT+Newton 或 PWL | 由算法误差评估决定 |
| output mode | round + saturate | 输出 Q8.8 |

如果时间紧张，优先保证：

1. `BQ=1` 的功能正确版本。
2. `BQ=4/8` 的性能优化版本。
3. `DOT_PE_LANES=32` 的综合版本。

---

## 10. 状态机流程

一次任务的推荐流程如下：

1. `IDLE`
   - 等待 `START=1`。

2. `CHECK_CFG`
   - 检查 base address、stride、cfg 是否合法。
   - 清零 CYCLES、RD_BYTES、WR_BYTES。

3. `LOAD_Q_BLOCK`
   - 从 Q_BASE 读取一个 Q block。

4. `INIT_ROW_STATE`
   - 对 Q block 内每一行初始化：
     - `m = NEG_LARGE`
     - `l = 0`
     - `acc[0:63] = 0`

5. `LOAD_KV_TILE`
   - 从 K_BASE/V_BASE 读取当前 K/V tile。

6. `COMPUTE_TILE`
   - 对 Q block 与 K/V tile 做 score 计算。
   - 根据 causal mask 判断是否有效。
   - 有效 score 进入 online softmax 更新。
   - 无效 score 跳过或作为 NEG_LARGE 处理。

7. `NEXT_KV_TILE`
   - 若 K/V tile 未遍历完，返回 `LOAD_KV_TILE`。
   - 否则进入输出阶段。

8. `FINALIZE_O`
   - 对每行执行 `O = acc / l`。
   - 量化为 Q8.8。

9. `WRITE_O_BLOCK`
   - 将 O block 写回 O_BASE。

10. `NEXT_Q_BLOCK`
    - 若 Q block 未遍历完，返回 `LOAD_Q_BLOCK`。
    - 否则任务完成。

11. `DONE`
    - `BUSY=0`
    - `DONE=1`
    - 若 `IRQ_EN=1`，拉高 `irq`。

12. `ERROR`
    - 停止任务。
    - `ERROR=1`
    - 写 soft reset 后恢复。

---

## 11. Causal Mask 规格

当 `CAUSAL_EN=1` 时：

- 对于 query 行 `i` 和 key 行 `j`：
  - 若 `j <= i`，score 有效。
  - 若 `j > i`，score 无效。
- 无效 score 不应影响 `m/l/acc`。
- 也可以将无效 score 视为 `NEG_LARGE`，但必须保证不会导致 exp 路径异常。
- 必测 corner case：
  - `i=0` 时只能访问 `j=0`。
  - `i=255` 时可访问全部 `j=0..255`。
  - tile 跨越 causal 边界时，部分元素有效、部分无效。

---

## 12. 正确性要求

### 12.1 Golden Model

必须提供 Python golden model，包含：

1. FP32 SDPA golden。
2. 定点近似 golden。
3. causal mask 逻辑。
4. Q8.8 输入生成。
5. Q8.8 输出量化。
6. mean_abs_error 统计。
7. max_abs_error 统计。

### 12.2 误差门限

RTL 输出与 FP32 golden 对比，应满足：

- `mean_abs_error <= 0.03`
- `max_abs_error <= 0.10`

若无法直接满足，应分析：

1. exp 近似误差。
2. reciprocal 近似误差。
3. dot-product 截断误差。
4. acc 缩放误差。
5. 输出 Q8.8 量化误差。

---

## 13. 验证需求

### 13.1 验证策略

Baseline 推荐采用：

- Python golden model；
- cocotb 端到端验证；
- SystemVerilog testbench 或轻量 UVM 作为补充。

### 13.2 必测用例

1. AXI4-Lite 寄存器读写。
2. START / BUSY / DONE / ERROR 流程。
3. SOFT_RESET 流程。
4. IRQ_EN 中断流程。
5. 随机 Q/K/V 端到端测试。
6. causal mask 测试。
7. `i=0` corner case。
8. `i=255` corner case。
9. 全零输入。
10. 小幅随机输入。
11. 大幅随机输入。
12. 正负混合输入。
13. stride 默认值测试。
14. stride 非默认值测试。
15. base address 非零测试。

### 13.3 Scoreboard

scoreboard 应完成：

1. 从仿真 memory model 中读取 RTL 输出 O。
2. 与 Python golden 输出逐元素对比。
3. 输出 MAE、MaxAE。
4. 输出失败元素位置。
5. 输出对应 Q/K/V 行列索引，便于 debug。

---

## 14. 性能与 PPA 需求

### 14.1 周期数

Baseline 必须满足：

- causal attention 单次执行 `< 300k cycles`

内部目标建议：

- v1 functional：先跑通，不强制周期。
- v2 optimized：`< 250k cycles`
- v3 competition：尽量靠近或低于 `150k cycles`

### 14.2 面积

Baseline 必须满足：

- 等效逻辑门数 `<= 2,000,000 gates`

面积报告应包含：

1. 总面积。
2. 组合逻辑面积。
3. 时序逻辑面积。
4. buffer / memory 折算面积。
5. MAC 阵列面积。
6. exp / reciprocal 近似模块面积。

### 14.3 频率

主频越高越好。至少应提供：

1. Genus 逻辑综合时序报告。
2. 目标时钟周期。
3. WNS/TNS。
4. 关键路径分析。
5. 若可完成 P&R，应提供进一步时序收敛结果。

### 14.4 带宽统计

IP 应统计或报告：

1. Q read bytes。
2. K read bytes。
3. V read bytes。
4. O write bytes。
5. total RD_BYTES。
6. total WR_BYTES。
7. tile 复用策略。
8. 与朴素实现的带宽对比。
9. 若缓存完整 K/V，应报告 SRAM 成本与带宽收益。

---

## 15. 工程交付物

Baseline 项目应至少包含：

```text
fa_accel_baseline/
├── rtl/
│   ├── fa_accel_top.sv
│   ├── fa_regfile.sv
│   ├── fa_dma_rd.sv
│   ├── fa_dma_wr.sv
│   ├── fa_scheduler.sv
│   ├── fa_q_buffer.sv
│   ├── fa_kv_buffer.sv
│   ├── fa_dot_pe.sv
│   ├── fa_softmax_online.sv
│   ├── fa_exp_approx.sv
│   ├── fa_recip_approx.sv
│   └── fa_out_quant.sv
│
├── sim/
│   ├── tb_top.sv
│   ├── axi_mem_model.sv
│   └── run_sim.sh
│
├── cocotb/
│   ├── test_fa_accel.py
│   ├── axi_lite_driver.py
│   ├── axi_mem_model.py
│   └── scoreboard.py
│
├── model/
│   ├── golden_fp32.py
│   ├── golden_fixed.py
│   ├── quant.py
│   ├── exp_approx.py
│   └── gen_vectors.py
│
├── vectors/
│   ├── q.hex
│   ├── k.hex
│   ├── v.hex
│   └── golden_o.hex
│
├── synth/
│   ├── run_genus.tcl
│   ├── constraints.sdc
│   └── reports/
│
├── doc/
│   ├── architecture_spec.md
│   ├── fixed_point_spec.md
│   ├── verification_plan.md
│   ├── ppa_report.md
│   └── final_report.md
│
└── README.md
```

---

## 16. 两人协作接口

### 16.1 算法负责人交付给 RTL 负责人

1. `golden_fp32.py`
2. `golden_fixed.py`
3. `fixed_point_spec.md`
4. `exp_approx.py`
5. `recip_approx.py`
6. 随机测试向量
7. corner case 测试向量
8. 误差分析报告

### 16.2 RTL 负责人交付给算法负责人

1. RTL 输出 dump 文件格式。
2. 每个中间变量的硬件位宽。
3. tile 顺序。
4. mask 处理方式。
5. 舍入和饱和实现。
6. 仿真失败日志。
7. 波形定位信息。

### 16.3 联合验收标准

1. Python fixed golden 与 RTL 中间行为一致。
2. RTL 输出与 FP32 golden 误差达标。
3. AXI4-Lite 控制流程正确。
4. DMA 读写地址正确。
5. causal mask corner case 正确。
6. Genus 综合通过。
7. cycles 小于 300k。
8. 面积小于 200 万门。
9. 最终报告解释清楚算法、架构、误差、性能、面积与带宽。

---

## 17. 开发里程碑

### Milestone 0：需求冻结

目标：

- 冻结 Baseline scope。
- 冻结 tensor shape。
- 冻结 memory layout。
- 冻结寄存器表。
- 冻结验证方案。

交付：

- PRD v1.0
- architecture draft
- fixed-point draft

### Milestone 1：算法 golden 完成

目标：

- FP32 golden 完成。
- fixed-point golden 完成。
- causal mask 完成。
- 误差初步达标。

交付：

- Python model
- 测试向量
- 初版误差报告

### Milestone 2：RTL functional 版本

目标：

- 不追求最佳性能，先跑通端到端。
- 支持寄存器配置。
- 支持 DMA memory model。
- 支持完整 Q/K/V/O 流程。

交付：

- RTL v0.1
- 基础 testbench
- 首个端到端仿真 pass

### Milestone 3：online softmax RTL 对齐

目标：

- RTL softmax 与 fixed golden 对齐。
- 支持 exp/reciprocal 近似。
- 支持 Q8.8 输出。

交付：

- RTL v0.2
- MAE/MaxAE 统计
- corner case pass

### Milestone 4：性能优化

目标：

- 引入 PE 并行。
- 优化 tile 调度。
- 优化 DMA burst。
- cycles 小于 300k。

交付：

- RTL v0.5
- cycles report
- bandwidth report

### Milestone 5：综合与时序收敛

目标：

- Genus 综合通过。
- 面积小于 200 万门。
- 完成时序分析。
- 输出功耗报告。

交付：

- Genus scripts
- SDC
- area report
- timing report
- power report

### Milestone 6：最终提交

目标：

- 整理代码。
- 整理验证环境。
- 整理报告。
- 固化 Baseline 版本。

交付：

- RTL source
- verification source
- test vectors
- simulation report
- waveform
- synthesis report
- final design report
- README

---

## 18. Bonus 规划建议

Baseline 完成后，可优先考虑以下 Bonus：

### Priority 1：Padding mask

原因：

- 与 causal mask 逻辑相似。
- RTL 改动较小。
- 算法风险较低。

### Priority 2：其他定点格式 Q6.10 / Q4.12

原因：

- 可复用大部分 RTL。
- 主要改量化参数。
- 适合展示误差与性能对比。

### Priority 3：AXI4-Stream 接口

原因：

- 接口类 Bonus 更适合 RTL 工程发挥。
- 相比 FP16/BF16，数值风险小。

### Priority 4：多 head

原因：

- 工程量中等。
- 地址管理和调度复杂度增加。
- 适合作为后续增强。

不建议过早选择 BF16/FP16、INT8/FP8 或 dropout，因为这些会显著增加 softmax、数值近似、验证和报告复杂度。

---

## 19. 风险清单

| 风险 | 严重性 | 应对策略 |
|---|---:|---|
| fixed-point softmax 误差超标 | 高 | 先用 Python sweep 位宽和近似方式，再 RTL 固化 |
| cycles 超过 300k | 高 | 尽早建立 cycle model，至少使用 16/32 lane PE |
| AXI DMA debug 耗时 | 中高 | 先用简化 SRAM 接口跑通 compute core，再接 AXI |
| UVM 学习成本过高 | 中 | Baseline 主线使用 cocotb，UVM 做寄存器/AXI smoke test |
| Genus 时序不过 | 中高 | PE、exp、reciprocal 插入流水线，避免长组合路径 |
| 面积超标 | 中 | 控制 PE 数量，LUT 表规模参数化 |
| 报告不完整 | 中 | 从第一版开始统计 cycles、bytes、error、area |
| Bonus 影响 Baseline | 高 | Baseline 和 Bonus 分目录、分工程、分报告 |

---

## 20. Baseline 成功判据

当满足以下条件时，Baseline v1.0 可认为达到提交标准：

1. RTL 可综合。
2. AXI4-Lite 寄存器读写正确。
3. DMA 能正确读取 Q/K/V 并写回 O。
4. causal attention 计算正确。
5. 不存储完整 score/p 矩阵。
6. 使用 online softmax。
7. 使用 K/V tiling。
8. 随机测试通过。
9. causal corner case 通过。
10. `mean_abs_error <= 0.03`。
11. `max_abs_error <= 0.10`。
12. `cycles < 300k`。
13. `area <= 2M gates`。
14. 提供 RD_BYTES / WR_BYTES 分析。
15. 提供 Genus 面积、时序、功耗报告。
16. 提供完整代码、验证、脚本和说明文档。

---

## 21. 备注

赛题提交材料中出现了“PQC 加速器源代码（ML-DSA + ML-KEM）”相关表述，该内容与本 FlashAttention 赛题正文不一致，疑似模板残留或误植。项目实际范围应以 FlashAttention 赛题正文、接口、性能、验证和 PPA 要求为准。
