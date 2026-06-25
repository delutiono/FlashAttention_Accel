# FlashAttention 高性能硬件加速器 IP 项目计划书

> **项目名称**：基于大模型推理的 FlashAttention 高性能硬件加速器 IP 设计  
> **工程代号**：FA-Accel-IP  
> **计划版本**：v1.0  
> **计划起始日期**：2026-05-29  
> **作品提交截止日期**：2026-07-07  
> **计划原则**：Baseline 必过优先，Bonus 后置；7 月初冻结工程，预留 3~4 天应急余量。  
> **团队规模**：2 人  
> **角色划分**：算法负责人 1 人 + RTL/验证/综合负责人 1 人  

---

## 1. 项目背景与目标

本项目面向中国大陆集成电路领域学科竞赛赛题“基于大模型推理的 FlashAttention 高性能硬件加速器 IP 设计”。

项目目标是实现一个可综合、可验证、可评估 PPA 的 FlashAttention-style attention 硬件 IP。该 IP 面向 Transformer 推理中的 Scaled Dot-Product Attention，采用定点计算、online softmax、K/V tiling 和 DMA 数据搬运方式，在固定 Baseline 规模下完成端到端 attention 计算。

本项目不是单纯算法验证，也不是纯 RTL demo，而是以工程产品为目标，完成从算法建模、定点化、RTL 实现、接口集成、验证、综合、报告到最终打包提交的完整流程。

---

## 2. Baseline 项目目标

### 2.1 功能目标

Baseline 必须支持：

| 项目 | 要求 |
|---|---|
| Batch | 1 |
| Head | 1 |
| Sequence Length | `S = 256` |
| Head Dimension | `d = 64` |
| Q/K/V Shape | `[256, 64]` |
| O Shape | `[256, 64]` |
| 输入格式 | signed Q8.8，16-bit |
| 输出格式 | signed Q8.8，16-bit |
| Mask | 必须支持 causal mask |
| 数据流 | FlashAttention-style |
| Softmax | online softmax |
| K/V 处理 | tiling |
| 控制接口 | AXI4-Lite |
| 数据接口 | AXI4 Master + DMA |

### 2.2 性能与资源目标

| 指标 | Baseline 必须满足 | 内部冲刺目标 |
|---|---:|---:|
| 单次 causal attention cycles | `< 300k cycles` | `< 250k cycles`，若时间允许冲刺 `< 150k cycles` |
| 等效逻辑门数 | `<= 2,000,000 gates` | 留出 20% 以上面积余量 |
| Fmax | 越高越好 | 优先保证时序收敛，再追求更高频率 |
| 带宽统计 | 必须给出 RD_BYTES / WR_BYTES | 给出 tile 复用分析与朴素实现对比 |
| 正确性误差 | `mean_abs_error <= 0.03`，`max_abs_error <= 0.10` | 尽量降低误差并解释来源 |

### 2.3 工程交付目标

项目最终应提交：

1. 完整 RTL 代码。
2. AXI4-Lite 控制寄存器实现。
3. AXI4 Master DMA 读写实现。
4. FlashAttention compute core。
5. Python FP32 golden model。
6. Python fixed-point golden model。
7. cocotb 或 SystemVerilog/UVM 验证环境。
8. 随机测试与 corner case 测试。
9. 仿真脚本、测试向量、结果日志。
10. Cadence Genus 综合脚本。
11. SDC 约束文件。
12. 面积、时序、功耗报告。
13. cycles、带宽、误差统计报告。
14. 最终项目报告。
15. README 与提交打包说明。

---

## 3. 项目范围

### 3.1 Baseline 必做范围

Baseline 是整个项目的第一优先级。未完成 Baseline 前，不开展 Bonus 开发。

Baseline 必做内容：

1. 固定 `S=256, d=64`。
2. 单 batch、单 head。
3. 支持 causal 与 non-causal 配置。
4. Q/K/V/O 使用 Q8.8 定点格式。
5. 实现 online softmax。
6. 实现 K/V tiling。
7. 禁止存储完整 score 矩阵。
8. 禁止存储完整 softmax probability 矩阵。
9. 实现 AXI4-Lite register file。
10. 实现 AXI4 Master DMA 读写。
11. 实现 CYCLES 计数器。
12. 实现 RD_BYTES / WR_BYTES 统计或至少在报告中可量化统计。
13. 通过随机端到端测试。
14. 通过 causal mask corner case 测试。
15. 通过 Genus 综合并生成报告。

### 3.2 Baseline 不做范围

Baseline 阶段暂不做：

1. 多 batch。
2. 多 head。
3. `S=512`。
4. BF16 / FP16。
5. INT8 / FP8。
6. dropout。
7. 任务队列。
8. 完整 Transformer block。
9. 复杂多 outstanding AXI 优化。
10. 完整高覆盖率 UVM 验证平台。

### 3.3 Bonus 条件触发范围

只有当以下条件全部满足后，才允许进入 Bonus：

1. Baseline RTL 功能通过。
2. 随机测试误差达标。
3. causal mask corner case 通过。
4. cycles 初步小于 300k。
5. Genus 综合可运行。
6. 工程目录与报告主框架已建立。

建议 Bonus 优先级：

1. Padding mask。
2. 其他定点格式 Q6.10 / Q4.12。
3. AXI4-Stream 接口。
4. 多 head。

不建议优先选择 BF16/FP16、INT8/FP8 或 dropout，因为这些会显著增加数值设计、验证和报告风险。

---

## 4. 总体技术路线

### 4.1 算法路线

算法侧采用三层模型：

1. **FP32 golden model**
   - 完整 SDPA 公式。
   - causal mask。
   - 作为最终误差评价基准。

2. **Fixed-point golden model**
   - 模拟 RTL 定点位宽。
   - 模拟 dot-product 截断、缩放、exp 近似、reciprocal 近似、输出饱和。
   - 作为 RTL 对齐模型。

3. **Cycle / dataflow model**
   - 模拟 `BQ`、`BK`、PE 并行度。
   - 估算 cycles。
   - 估算 RD_BYTES / WR_BYTES。
   - 为 RTL 架构参数选择提供依据。

### 4.2 RTL 路线

RTL 采用分阶段实现：

1. 先做纯 compute core 的简化 SRAM 接口版本。
2. 再加入 AXI4-Lite register file。
3. 再加入 DMA memory model。
4. 最后集成 AXI4 Master read/write。
5. 先实现 `BQ=1` 功能版本。
6. 再扩展到 `BQ=4` 或 `BQ=8` 性能版本。
7. 先保证正确性，再插入流水线优化时序。

### 4.3 验证路线

验证采用“Python golden + cocotb 主线，轻量 UVM/ SV testbench 辅助”的策略。

主线：

1. Python 生成 Q/K/V 测试向量。
2. RTL 仿真读取或通过 AXI memory model 访问测试向量。
3. 仿真完成后 dump O。
4. Python scoreboard 对比 RTL O 与 golden O。
5. 输出 MAE、MaxAE、失败位置和失败上下文。

辅助：

1. AXI4-Lite register smoke test。
2. START / BUSY / DONE / ERROR 状态测试。
3. SOFT_RESET 测试。
4. IRQ_EN 测试。
5. causal mask corner case 单独测试。

### 4.4 综合路线

综合采用 Cadence Genus 工具链：

1. 建立初始 `run_genus.tcl`。
2. 建立 `constraints.sdc`。
3. 对 compute core 单独综合。
4. 对完整 top 综合。
5. 分析面积、时序、功耗。
6. 对关键路径插入 pipeline。
7. 输出最终 PPA 报告。

---

## 5. 推荐微架构方案

### 5.1 顶层模块

建议模块划分：

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

### 5.2 推荐参数

| 参数 | 初始功能版本 | 性能优化版本 | 说明 |
|---|---:|---:|---|
| BQ | 1 | 4 或 8 | Q block 行数 |
| BK | 16 | 16 或 32 | K/V tile 行数 |
| DOT_PE_LANES | 16 | 32 | dot-product 并行度 |
| V_ACC_LANES | 16 | 16 或 32 | V 加权累加并行度 |
| dot acc width | 40-bit | 40/48-bit | 降低溢出风险 |
| exp | LUT/PWL | LUT/PWL 优化 | 由误差 sweep 决定 |
| reciprocal | LUT/PWL 或 Newton | LUT/PWL 或 Newton | 由面积和误差决定 |

### 5.3 数据流

推荐主循环：

```text
for q_block in range(0, S, BQ):
    load Q block
    init m/l/acc for each q row

    for kv_tile in range(0, S, BK):
        load K tile
        load V tile

        for each q row in q_block:
            for each k row in kv_tile:
                if causal and k_idx > q_idx:
                    skip or mask
                else:
                    score = dot(Q[q], K[k]) * scale
                    online_softmax_update(score, V[k])

    finalize O = acc / l
    write O block
```

---

## 6. 关键技术难点

### 6.1 定点 online softmax 误差控制

难点：

1. score 动态范围较大。
2. exp 近似容易引入误差。
3. reciprocal 近似会放大误差。
4. online 更新中的 `alpha`、`beta`、`l`、`acc` 位宽需要谨慎设计。
5. causal mask 的无效位置不能污染 `m/l/acc`。

应对：

1. 算法侧先 sweep 位宽。
2. 固定一套 RTL-friendly Q 格式。
3. exp 输入做范围裁剪。
4. 对极小 exp 允许下溢为 0。
5. 输出使用 round + saturate。
6. Python fixed golden 与 RTL 使用同一套近似规则。

### 6.2 cycles 小于 300k

难点：

1. causal 有效 score 数为 `256 × 257 / 2 = 32896`。
2. 每个 score 需要 64 项 dot-product。
3. 每个 score 还要参与 V 加权累加。
4. 单 MAC 或低并行度设计难以达标。

应对：

1. dot-product 至少使用 16 lane，优先 32 lane。
2. V accumulate 至少使用 16 lane。
3. DMA load 与 compute 尽量重叠。
4. 先建立 cycle model，避免 RTL 写完才发现 cycles 超标。
5. 对 `BQ/BK/PE_LANES` 做参数化，便于权衡面积与性能。

### 6.3 AXI DMA 工程复杂度

难点：

1. AXI4 Master read/write 状态机容易出错。
2. burst 边界、地址递增、stride 处理需要严格验证。
3. DMA 与 compute core 的握手容易造成死锁。
4. 仿真 debug 成本较高。

应对：

1. 先实现简化 memory 接口 compute core。
2. 再接入 AXI memory model。
3. AXI DMA 单独测试。
4. top 集成前做模块级验证。
5. 对每个 DMA transaction 统计 bytes 和地址。

### 6.4 时序收敛

难点：

1. dot-product adder tree 可能形成长组合路径。
2. exp / reciprocal 近似可能形成长组合路径。
3. online softmax 更新涉及多个乘法、加法和比较。
4. 大规模 mux 和 buffer 读写也可能形成关键路径。

应对：

1. adder tree 分级 pipeline。
2. exp / reciprocal 模块内部 pipeline。
3. softmax update 拆分多级流水。
4. 控制路径和数据路径分离。
5. 使用 valid/ready 或固定 latency pipeline 管理数据对齐。

### 6.5 验证复杂度

难点：

1. RTL 和 Python 定点模型可能不一致。
2. online softmax 中间变量定位困难。
3. AXI 集成后 debug 信号多。
4. UVM 从零学习成本较高。

应对：

1. 优先 cocotb 端到端验证。
2. 给 RTL 增加 debug dump 选项。
3. 先比对中间 score，再比对 exp/l/acc，最后比对 O。
4. UVM 只做轻量寄存器和 AXI smoke test，不作为主线阻塞项。

---

## 7. 团队分工

### 7.1 角色 A：RTL / 验证 / 综合负责人

角色 A 即你本人，主要负责数字电路 RTL 工程、接口集成、验证落地和综合报告。

#### 主要职责

1. RTL 顶层架构设计。
2. AXI4-Lite register file。
3. AXI4 Master DMA read/write。
4. scheduler 状态机。
5. Q/K/V tile buffer。
6. dot-product PE。
7. online softmax 硬件模块。
8. exp / reciprocal 近似模块硬件化。
9. output quantization。
10. cocotb / SV testbench 集成。
11. waveform debug。
12. Cadence Genus 综合脚本。
13. SDC 约束。
14. 面积、时序、功耗报告。
15. 最终代码整理与提交打包。

#### 能力成长目标

1. 掌握 AXI4-Lite 和 AXI4 Master 基础工程实现。
2. 掌握定点数值模块 RTL 化。
3. 建立从 RTL 到 Genus 综合报告的闭环。
4. UVM 从寄存器读写与启动流程开始学习，不作为主线阻塞项。

### 7.2 角色 B：算法 / 定点建模 / 误差分析负责人

角色 B 即团队同伴，主要负责算法建模、数值近似、定点策略和测试向量生成。

#### 主要职责

1. FP32 SDPA golden model。
2. FlashAttention online softmax model。
3. fixed-point golden model。
4. exp 近似方案评估。
5. reciprocal 近似方案评估。
6. Q 格式和位宽 sweep。
7. 误差统计脚本。
8. 随机测试向量生成。
9. corner case 测试向量生成。
10. cycle model / bandwidth model。
11. 与 RTL 对齐中间变量格式。
12. 算法说明文档。
13. 误差来源分析文档。
14. 协助最终报告中的算法与结果分析章节。

### 7.3 双人协作接口

两人必须共同维护以下接口文档：

| 文档 | 负责人 | 协作方 | 用途 |
|---|---|---|---|
| `product_spec.md` | A | B | 项目需求冻结 |
| `fixed_point_spec.md` | B | A | 定点位宽、缩放、舍入、饱和规则 |
| `architecture_spec.md` | A | B | RTL 架构、模块接口、数据流 |
| `verification_plan.md` | A | B | 验证用例、golden 对比、scoreboard |
| `test_vector_format.md` | B | A | Q/K/V/O 文件格式 |
| `ppa_report.md` | A | B | cycles、area、timing、power、bandwidth |
| `final_report.md` | A+B | A+B | 最终提交报告 |

---

## 8. 工作量估算

### 8.1 总体工作量

从 2026-05-29 到 2026-07-07，共约 40 个自然日。

考虑到需要预留最终打包与应急时间，实际开发冻结日期建议定为：

- **Baseline 功能冻结**：2026-06-28
- **Baseline PPA 冻结**：2026-07-01
- **最终提交包冻结**：2026-07-04
- **应急修复窗口**：2026-07-05 至 2026-07-06
- **提交日**：2026-07-07

按两人协作估算，有效工程量约为：

| 阶段 | A：RTL/验证/综合 | B：算法/模型/误差 | 合计 |
|---|---:|---:|---:|
| 需求冻结与架构 | 2.0 人日 | 1.5 人日 | 3.5 人日 |
| 算法与定点模型 | 2.0 人日 | 7.0 人日 | 9.0 人日 |
| RTL functional | 8.0 人日 | 2.0 人日 | 10.0 人日 |
| softmax/定点对齐 | 5.0 人日 | 5.0 人日 | 10.0 人日 |
| AXI/DMA 集成 | 6.0 人日 | 1.0 人日 | 7.0 人日 |
| 验证与 debug | 7.0 人日 | 4.0 人日 | 11.0 人日 |
| 性能优化 | 5.0 人日 | 2.0 人日 | 7.0 人日 |
| 综合与 PPA | 5.0 人日 | 1.0 人日 | 6.0 人日 |
| 报告与提交 | 3.0 人日 | 3.0 人日 | 6.0 人日 |
| 余量与返工 | 4.0 人日 | 3.0 人日 | 7.0 人日 |
| **合计** | **47.0 人日** | **29.5 人日** | **76.5 人日** |

> 注：RTL/验证/综合工作量显著大于算法建模工作量，因此角色 A 的任务更重。应尽早让角色 B 提供稳定 fixed-point golden，减少 RTL 后期返工。

---

## 9. 时间线计划

### 9.1 总体阶段安排

| 阶段 | 日期 | 目标 | 状态门槛 |
|---|---|---|---|
| M0：需求冻结与工程初始化 | 05-29 ~ 05-31 | 冻结 Baseline 范围、建立 repo、建立文档框架 | PRD/plan/目录结构完成 |
| M1：算法 golden 与定点方案 | 06-01 ~ 06-05 | FP32/fixed golden、误差 sweep、初版位宽 | Python 模型可生成 golden |
| M2：RTL functional core | 06-06 ~ 06-12 | compute core 简化接口跑通 | 小规模 case 仿真通过 |
| M3：online softmax RTL 对齐 | 06-13 ~ 06-18 | 定点 softmax 与 golden 对齐 | 随机小规模误差达标 |
| M4：AXI/DMA 与端到端集成 | 06-19 ~ 06-24 | AXI4-Lite + DMA + full S=256 | full case 可跑通 |
| M5：性能优化与验证收敛 | 06-25 ~ 06-28 | cycles < 300k，corner case 通过 | Baseline 功能冻结 |
| M6：综合与 PPA 收敛 | 06-29 ~ 07-01 | Genus 综合，面积/时序/功耗报告 | PPA 冻结 |
| M7：最终报告与提交包 | 07-02 ~ 07-04 | 报告、README、脚本、结果整理 | 提交包冻结 |
| M8：应急缓冲 | 07-05 ~ 07-06 | 修复阻塞问题，不新增功能 | 只允许 bug fix |
| M9：正式提交 | 07-07 | 上传最终作品 | 不做代码修改 |

---

## 10. 详细周计划

### Week 0：2026-05-29 ~ 2026-05-31

主题：需求冻结、工程骨架、技术路线确定。

#### A：RTL/验证/综合负责人

1. 建立项目 repo 目录。
2. 放置 `product_spec.md`。
3. 放置本 `project_plan.md`。
4. 创建 `rtl/ sim/ cocotb/ model/ synth/ doc/ vectors/` 目录。
5. 初步定义 top module 端口。
6. 初步定义 register map。
7. 写 `architecture_spec.md` 初稿。
8. 写 `verification_plan.md` 初稿。

#### B：算法/模型负责人

1. 阅读赛题要求和产品 spec。
2. 建立 FP32 SDPA baseline 脚本。
3. 明确输入随机分布范围。
4. 明确 causal mask golden 行为。
5. 准备 `fixed_point_spec.md` 初稿目录。
6. 与 A 确认 tensor memory layout。

#### 本阶段交付物

- repo 目录结构。
- `product_spec.md`
- `project_plan.md`
- `architecture_spec.md` 初稿。
- `verification_plan.md` 初稿。
- FP32 golden model 初版。

#### 阶段验收

- 两人确认 Baseline 范围不再随意扩大。
- 确认 7 月 4 日前冻结提交包。
- 确认 Bonus 不进入主线。

---

### Week 1：2026-06-01 ~ 2026-06-05

主题：算法 golden、定点建模、cycle model。

#### A：RTL/验证/综合负责人

1. 实现 `fa_regfile` 初版。
2. 实现寄存器读写 testbench。
3. 实现 `fa_scheduler` 初版状态机框架。
4. 实现简化 SRAM 接口定义。
5. 与 B 对齐 Q/K/V/O 文件格式。
6. 编写 basic cocotb 工程骨架。
7. 准备 Genus 最小综合脚本框架。

#### B：算法/模型负责人

1. 完成 FP32 golden。
2. 完成 online softmax Python 版本。
3. 完成 Q8.8 量化/反量化函数。
4. 完成 fixed-point golden 初版。
5. sweep dot acc width、score width、exp width、l width、acc width。
6. 评估 exp LUT/PWL 方案。
7. 评估 reciprocal LUT/PWL/Newton 方案。
8. 输出第一版 `fixed_point_spec.md`。
9. 输出第一批测试向量：
   - 全零输入。
   - 小幅随机输入。
   - 正负混合输入。
   - causal corner case。

#### 本阶段交付物

- `golden_fp32.py`
- `golden_fixed.py`
- `quant.py`
- `gen_vectors.py`
- `fixed_point_spec.md` v0.1
- `fa_regfile.sv` v0.1
- cocotb skeleton
- Genus script skeleton

#### 阶段验收

- FP32 golden 可跑通 `S=256,d=64`。
- fixed-point golden 初步误差接近要求。
- 产生 RTL 可读取的测试向量。

---

### Week 2：2026-06-06 ~ 2026-06-12

主题：RTL compute core functional 版本。

#### A：RTL/验证/综合负责人

1. 实现 `fa_q_buffer`。
2. 实现 `fa_kv_buffer`。
3. 实现 `fa_dot_pe` 初版。
4. 实现 dot-product adder tree。
5. 实现 `fa_out_quant` 初版。
6. 实现 `BQ=1, BK=16` 简化 compute 流程。
7. 暂时使用理想 exp/recip 或 B 提供的组合近似模块。
8. 跑通小规模仿真：
   - `S=8,d=8` 或参数化小 case。
   - 再扩展到 `S=256,d=64`。
9. 添加核心 debug 信号 dump：
   - score
   - valid mask
   - m/l
   - acc
   - O

#### B：算法/模型负责人

1. 根据 RTL 小规模参数生成测试向量。
2. 输出中间变量 golden：
   - score
   - m
   - l
   - acc
3. 协助 A 定位 dot-product 差异。
4. 固化 exp/reciprocal 近似方案。
5. 更新 `fixed_point_spec.md` v0.2。
6. 建立 cycle model 初版。
7. 初步估计 `BQ/BK/PE_LANES` 对 cycles 的影响。

#### 本阶段交付物

- `fa_dot_pe.sv`
- `fa_q_buffer.sv`
- `fa_kv_buffer.sv`
- `fa_out_quant.sv`
- compute core functional 仿真日志。
- 中间变量对齐脚本。
- cycle model v0.1。

#### 阶段验收

- 小规模 compute core 仿真通过。
- dot-product 与 fixed golden 对齐。
- causal mask 基础逻辑正确。
- 明确性能版需要的 PE 并行度。

---

### Week 3：2026-06-13 ~ 2026-06-18

主题：online softmax RTL 化与定点对齐。

#### A：RTL/验证/综合负责人

1. 实现 `fa_exp_approx`。
2. 实现 `fa_recip_approx`。
3. 实现 `fa_softmax_online`。
4. 将 softmax update 插入 compute pipeline。
5. 处理 fixed latency pipeline 对齐。
6. 处理 mask 无效 score 不污染 m/l/acc。
7. 跑通：
   - 全零输入。
   - 单行 causal。
   - 小幅随机。
   - 正负混合。
8. 开始 full `S=256,d=64` 仿真。

#### B：算法/模型负责人

1. 固化 exp 近似查表或 PWL 参数。
2. 固化 reciprocal 近似参数。
3. 生成 RTL LUT 初始化文件。
4. 生成更多随机测试。
5. 统计 MAE/MaxAE。
6. 对误差超标 case 做分类：
   - exp 误差。
   - reciprocal 误差。
   - dot 截断误差。
   - 输出饱和误差。
7. 更新 `fixed_point_spec.md` v1.0。

#### 本阶段交付物

- `fa_exp_approx.sv`
- `fa_recip_approx.sv`
- `fa_softmax_online.sv`
- LUT 初始化文件。
- fixed-point spec v1.0。
- 随机测试误差报告 v0.1。

#### 阶段验收

- 小规模 online softmax RTL 与 fixed golden 对齐。
- 至少 10 组随机 case 误差接近或满足要求。
- full size 仿真可以运行到结束。

---

### Week 4：2026-06-19 ~ 2026-06-24

主题：AXI/DMA 集成与端到端 full case。

#### A：RTL/验证/综合负责人

1. 实现 `fa_dma_rd`。
2. 实现 `fa_dma_wr`。
3. 接入 AXI memory model。
4. 集成 `fa_accel_top`。
5. 实现 Q/K/V/O base address。
6. 实现 stride。
7. 实现 CYCLES。
8. 实现 RD_BYTES/WR_BYTES。
9. 实现 START/BUSY/DONE/ERROR。
10. 实现 SOFT_RESET。
11. 实现 IRQ_EN/irq。
12. 跑通完整 AXI4-Lite 配置流程。
13. 跑通 full `S=256,d=64` 端到端仿真。

#### B：算法/模型负责人

1. 生成 full-size 回归测试向量。
2. 完成 scoreboard 脚本。
3. 根据 RTL dump 自动输出误差报告。
4. 协助检查 DMA 地址、stride 和 row-major 排布。
5. 补充 bandwidth model。
6. 对比 RTL RD_BYTES/WR_BYTES 统计。

#### 本阶段交付物

- `fa_dma_rd.sv`
- `fa_dma_wr.sv`
- `fa_accel_top.sv`
- AXI4-Lite register test。
- AXI memory model test。
- full-size end-to-end 仿真日志。
- bandwidth report v0.1。

#### 阶段验收

- 主机配置寄存器后可启动 IP。
- IP 可从 memory model 读取 Q/K/V。
- IP 可写回 O。
- DONE 正确置位。
- full-size 输出可被 scoreboard 读取。
- 随机 full-size case 初步通过误差门限。

---

### Week 5：2026-06-25 ~ 2026-06-28

主题：性能优化、验证收敛、Baseline 功能冻结。

#### A：RTL/验证/综合负责人

1. 优化 `DOT_PE_LANES`。
2. 优化 `V_ACC_LANES`。
3. 调整 `BQ/BK`。
4. 插入必要 pipeline。
5. 优化 DMA burst。
6. 减少 compute idle cycles。
7. 固化 CYCLES 统计。
8. 跑完整回归测试。
9. 跑 causal corner case：
   - `i=0`
   - `i=1`
   - `i=255`
   - tile 跨 causal 边界
10. 生成 Baseline v0.9 tag。

#### B：算法/模型负责人

1. 基于最终参数更新 cycle model。
2. 更新 bandwidth model。
3. 输出误差统计表。
4. 输出 corner case 说明。
5. 协助判断是否需要改 exp/recip 参数。
6. 准备最终报告中的算法章节初稿。

#### 本阶段交付物

- Baseline RTL v0.9。
- cycles report v0.1。
- full regression report。
- error report v0.2。
- bandwidth report v0.2。
- algorithm section draft。

#### 阶段验收

- Baseline 功能冻结。
- `cycles < 300k`。
- `mean_abs_error <= 0.03`。
- `max_abs_error <= 0.10`。
- 之后原则上不再大改架构。

---

### Week 6 前半：2026-06-29 ~ 2026-07-01

主题：Genus 综合与 PPA 收敛。

#### A：RTL/验证/综合负责人

1. 整理 RTL filelist。
2. 完善 `run_genus.tcl`。
3. 完善 `constraints.sdc`。
4. 跑 compute core 综合。
5. 跑 full top 综合。
6. 生成 area report。
7. 生成 timing report。
8. 生成 power report。
9. 分析 WNS/TNS。
10. 对关键路径做小规模 pipeline 修复。
11. 确认面积小于 2M gates。

#### B：算法/模型负责人

1. 协助解释性能/带宽收益。
2. 整理与朴素 SDPA 的对比。
3. 整理误差来源分析。
4. 检查最终 RTL 参数与 fixed golden 参数一致。
5. 更新最终图表和表格。

#### 本阶段交付物

- Genus 综合脚本。
- SDC 文件。
- area report。
- timing report。
- power report。
- PPA report v0.9。

#### 阶段验收

- Genus 综合通过。
- 面积达标。
- 时序报告可解释。
- PPA 数据可写入最终报告。

---

### Week 6 后半：2026-07-02 ~ 2026-07-04

主题：最终报告、代码整理、提交包冻结。

#### A：RTL/验证/综合负责人

1. 清理 RTL warning。
2. 清理仿真 warning。
3. 固化 Baseline tag。
4. 整理 README。
5. 整理 run scripts。
6. 整理 waveform 示例。
7. 整理综合报告。
8. 撰写架构、RTL、接口、验证、综合章节。
9. 打包提交目录。

#### B：算法/模型负责人

1. 整理 Python model。
2. 整理测试向量生成脚本。
3. 整理误差统计结果。
4. 撰写算法、定点、误差、带宽分析章节。
5. 校对最终报告中的公式、表格和图。
6. 协助检查提交包完整性。

#### 本阶段交付物

- Baseline v1.0 tag。
- final report v1.0。
- README。
- 提交包 v1.0。
- 所有脚本可复现说明。
- 最终仿真与综合结果汇总表。

#### 阶段验收

- 提交包冻结。
- 不再新增功能。
- 不再重构代码。
- 后续只允许修复阻塞性 bug。

---

### Buffer：2026-07-05 ~ 2026-07-06

主题：应急修复与最终检查。

允许做：

1. 修复脚本路径。
2. 修复 README 错误。
3. 修复报告笔误。
4. 修复仿真命令问题。
5. 修复不影响架构的小 bug。
6. 重新打包。
7. 检查压缩包能否解压。
8. 检查文件是否缺失。

禁止做：

1. 新增 Bonus。
2. 大改定点格式。
3. 大改 RTL 架构。
4. 大改 AXI/DMA。
5. 更换 exp/reciprocal 方案。
6. 重写验证环境。

---

### Submit：2026-07-07

主题：正式提交。

当天只做：

1. 核对提交要求。
2. 上传最终压缩包。
3. 保存上传回执或截图。
4. 备份最终版本。

不建议当天再修改代码或报告。

---

## 11. 任务分解与责任矩阵

### 11.1 RACI 说明

- R：Responsible，直接负责执行。
- A：Accountable，对结果负责。
- C：Consulted，协助讨论。
- I：Informed，知会即可。

| 工作项 | A：RTL/验证/综合 | B：算法/模型 |
|---|---|---|
| 产品需求冻结 | A/R | C |
| 项目计划 | A/R | C |
| FP32 golden | C | A/R |
| fixed-point golden | C | A/R |
| exp/recip 近似设计 | C | A/R |
| 位宽 sweep | C | A/R |
| 测试向量生成 | C | A/R |
| RTL top | A/R | I |
| AXI4-Lite | A/R | I |
| AXI4 Master DMA | A/R | C |
| scheduler | A/R | C |
| dot PE | A/R | C |
| online softmax RTL | A/R | C |
| output quantization | A/R | C |
| cocotb 验证 | A/R | C |
| scoreboard | C | A/R |
| UVM smoke test | A/R | I |
| cycles 统计 | A/R | C |
| bandwidth 统计 | A/R | C |
| Genus 综合 | A/R | I |
| PPA 分析 | A/R | C |
| 误差分析 | C | A/R |
| 最终报告 | A/R | A/R |
| 提交打包 | A/R | C |

---

## 12. 每日协作机制

### 12.1 每日同步

建议每天进行 15~20 分钟同步，内容固定为：

1. 昨天完成了什么。
2. 今天要完成什么。
3. 当前阻塞是什么。
4. 是否需要对方提供接口、脚本或数据。
5. 是否有影响 deadline 的风险。

### 12.2 每两天一次联调

从 2026-06-06 开始，每两天至少进行一次联调：

1. B 生成最新测试向量。
2. A 跑 RTL 仿真。
3. A 输出失败日志。
4. B 用 Python 分析失败位置。
5. 两人确认是 RTL bug 还是模型/spec 不一致。
6. 更新 `fixed_point_spec.md` 或 RTL。

### 12.3 每周冻结点

每周末必须冻结一个可回退版本：

| 日期 | tag | 内容 |
|---|---|---|
| 2026-05-31 | `spec_freeze_v1` | 需求与计划冻结 |
| 2026-06-05 | `model_v1` | golden 与定点模型初版 |
| 2026-06-12 | `rtl_core_v1` | compute core functional |
| 2026-06-18 | `softmax_v1` | online softmax RTL |
| 2026-06-24 | `e2e_v1` | AXI/DMA 端到端 |
| 2026-06-28 | `baseline_v0.9` | Baseline 功能冻结 |
| 2026-07-01 | `ppa_v1` | 综合报告冻结 |
| 2026-07-04 | `submit_v1.0` | 提交包冻结 |

---

## 13. 验证计划摘要

### 13.1 必须通过的测试

| 测试类别 | 测试内容 | 负责人 |
|---|---|---|
| Register | AXI4-Lite 读写 | A |
| Control | START/BUSY/DONE/ERROR | A |
| Reset | SOFT_RESET | A |
| IRQ | IRQ_EN 与 irq | A |
| DMA Read | Q/K/V 读取 | A |
| DMA Write | O 写回 | A |
| Dot | dot-product 与 golden 对齐 | A+B |
| Softmax | online m/l/acc 对齐 | A+B |
| Causal | `i=0` 只看 `j=0` | A+B |
| Causal | tile 跨越 mask 边界 | A+B |
| Random | 多 seed 随机 Q/K/V | B |
| Full-size | `S=256,d=64` end-to-end | A+B |
| Error | MAE/MaxAE 统计 | B |
| Cycle | CYCLES 统计 | A |
| Bandwidth | RD_BYTES/WR_BYTES | A+B |

### 13.2 回归测试集合

建议最少保留以下 regression set：

1. `test_zero_input`
2. `test_small_random_seed_0`
3. `test_small_random_seed_1`
4. `test_signed_random_seed_0`
5. `test_signed_random_seed_1`
6. `test_causal_i0`
7. `test_causal_boundary_tile`
8. `test_full_s256_seed_0`
9. `test_full_s256_seed_1`
10. `test_noncausal_s256_seed_0`
11. `test_stride_default`
12. `test_stride_nondefault`
13. `test_soft_reset`
14. `test_irq`
15. `test_busy_start_error_or_ignore`

---

## 14. 综合与 PPA 计划

### 14.1 综合对象

建议按以下顺序综合：

1. `fa_dot_pe`
2. `fa_exp_approx`
3. `fa_recip_approx`
4. `fa_softmax_online`
5. `fa_compute_core`
6. `fa_accel_top`

### 14.2 必须输出的报告

| 报告 | 文件建议 | 说明 |
|---|---|---|
| 面积报告 | `reports/area.rpt` | 总面积、模块面积、等效门数 |
| 时序报告 | `reports/timing.rpt` | WNS/TNS、关键路径 |
| 功耗报告 | `reports/power.rpt` | 动态/静态功耗 |
| 综合日志 | `logs/genus.log` | 工具运行日志 |
| 约束报告 | `reports/constraints.rpt` | SDC 约束检查 |
| 层次面积 | `reports/hier_area.rpt` | 定位大面积模块 |
| QoR 报告 | `reports/qor.rpt` | 总体质量评估 |

### 14.3 时序优化优先级

1. dot-product adder tree pipeline。
2. exp/recip 近似模块 pipeline。
3. softmax update pipeline。
4. DMA/control 与 compute 解耦。
5. 避免超大 mux。
6. 避免跨模块长路径。
7. 合理设置 multicycle 或 false path，但必须谨慎，不能掩盖真实数据路径。

---

## 15. 文档与最终报告计划

### 15.1 必须维护的文档

| 文档 | 路径建议 | 负责人 |
|---|---|---|
| 产品需求文档 | `doc/product_spec.md` | A |
| 项目计划书 | `doc/project_plan.md` | A |
| 架构设计文档 | `doc/architecture_spec.md` | A |
| 定点算法文档 | `doc/fixed_point_spec.md` | B |
| 验证计划 | `doc/verification_plan.md` | A |
| 误差分析报告 | `doc/error_analysis.md` | B |
| PPA 报告 | `doc/ppa_report.md` | A |
| 最终报告 | `doc/final_report.md` | A+B |

### 15.2 最终报告建议结构

```text
1. 项目背景
2. 赛题需求理解
3. 总体架构
4. FlashAttention-style 数据流
5. 定点数值设计
6. online softmax 实现
7. RTL 微架构
8. AXI4-Lite 与 DMA 接口
9. 验证方法
10. 正确性与误差结果
11. 性能与带宽结果
12. 综合结果
13. 面积、时序、功耗分析
14. 风险与优化
15. 总结与后续 Bonus 展望
```

---

## 16. 目录结构计划

建议最终工程目录如下：

```text
fa_accel_baseline/
├── README.md
├── rtl/
│   ├── filelist.f
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
│   ├── run_sim.sh
│   └── waves/
│
├── cocotb/
│   ├── Makefile
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
│   ├── recip_approx.py
│   ├── cycle_model.py
│   ├── bandwidth_model.py
│   └── gen_vectors.py
│
├── vectors/
│   ├── README.md
│   ├── q.hex
│   ├── k.hex
│   ├── v.hex
│   ├── golden_o.hex
│   └── cases/
│
├── synth/
│   ├── run_genus.tcl
│   ├── constraints.sdc
│   ├── filelist.f
│   ├── logs/
│   └── reports/
│
├── doc/
│   ├── product_spec.md
│   ├── project_plan.md
│   ├── architecture_spec.md
│   ├── fixed_point_spec.md
│   ├── verification_plan.md
│   ├── error_analysis.md
│   ├── ppa_report.md
│   └── final_report.md
│
└── submit/
    ├── package_manifest.md
    └── final_archive/
```

---

## 17. 风险管理

### 17.1 高风险项

| 风险 | 影响 | 概率 | 预案 |
|---|---|---:|---|
| 定点误差超标 | 无法通过正确性验收 | 高 | 算法先 sweep，RTL 严格对齐 fixed golden |
| cycles 超过 300k | 无法通过性能要求 | 中高 | 早期 cycle model，至少 16/32 lane PE |
| AXI DMA debug 超时 | 端到端不通 | 中高 | 先简化 SRAM 接口，DMA 单独测 |
| Genus 时序不过 | PPA 报告质量差 | 中 | 分阶段综合，提前插 pipeline |
| RTL 与 golden 不一致 | debug 时间不可控 | 高 | 输出中间变量，逐级比对 |
| 报告整理不足 | 影响评审观感 | 中 | 从 Week 1 开始维护文档 |
| Bonus 拖累 Baseline | 主线失败 | 中 | Bonus 后置，未满足条件不做 |

### 17.2 风险触发条件

若出现以下情况，应立即降级目标：

1. 到 2026-06-18 full-size 仿真仍无法跑完。
   - 降级：固定 `BQ=1`，先保证正确性。

2. 到 2026-06-24 AXI/DMA 仍无法端到端跑通。
   - 降级：保留简化 memory 接口作为 debug 备份，同时集中修 DMA。

3. 到 2026-06-28 cycles 仍超过 300k。
   - 降级：优先增加 PE lane 或优化 idle，而不是继续改 softmax 数值。

4. 到 2026-07-01 Genus full top 仍失败。
   - 降级：分模块综合报告 + 尽快修 top 可综合语法和约束问题。

5. 到 2026-07-04 提交包仍不完整。
   - 降级：停止所有优化，只做打包和报告补全。

---

## 18. 阶段性验收清单

### 18.1 2026-06-05 检查点

- [ ] FP32 golden 完成。
- [ ] fixed-point golden 初版完成。
- [ ] 测试向量格式确定。
- [ ] register map 确定。
- [ ] RTL 模块划分确定。
- [ ] Genus 脚本骨架存在。

### 18.2 2026-06-12 检查点

- [ ] dot-product RTL 可运行。
- [ ] buffer RTL 可运行。
- [ ] 小规模 compute core 通过。
- [ ] causal mask 基础逻辑通过。
- [ ] 中间变量可 dump。

### 18.3 2026-06-18 检查点

- [ ] exp/recip 近似 RTL 完成。
- [ ] online softmax RTL 完成。
- [ ] 小规模随机测试通过。
- [ ] full-size 仿真可运行。
- [ ] fixed-point spec v1.0 冻结。

### 18.4 2026-06-24 检查点

- [ ] AXI4-Lite 可配置。
- [ ] DMA read/write 可运行。
- [ ] top 端到端跑通。
- [ ] full-size 输出可被 scoreboard 检查。
- [ ] error report 初版完成。
- [ ] bandwidth report 初版完成。

### 18.5 2026-06-28 检查点

- [ ] cycles < 300k。
- [ ] MAE/MaxAE 达标。
- [ ] causal corner case 通过。
- [ ] Baseline 功能冻结。
- [ ] 回归测试集合通过。

### 18.6 2026-07-01 检查点

- [ ] Genus 综合通过。
- [ ] area report 完成。
- [ ] timing report 完成。
- [ ] power report 完成。
- [ ] 面积小于 2M gates。
- [ ] PPA report 完成。

### 18.7 2026-07-04 检查点

- [ ] final report 完成。
- [ ] README 完成。
- [ ] 提交包完成。
- [ ] 所有脚本路径检查完成。
- [ ] 压缩包解压检查完成。
- [ ] 备份完成。

---

## 19. Bonus 决策点

建议在 2026-06-28 Baseline 功能冻结后进行一次 Bonus 评估。

### 19.1 可以做 Bonus 的条件

只有满足以下条件才考虑 Bonus：

- [ ] Baseline cycles 已小于 300k。
- [ ] Baseline error 已达标。
- [ ] Genus 初步综合可通过。
- [ ] 最终报告已有 70% 内容。
- [ ] 两人都确认不会影响 Baseline。

### 19.2 Bonus 优先级

| 优先级 | Bonus | 原因 |
|---:|---|---|
| 1 | Padding mask | 与 causal mask 类似，风险较低 |
| 2 | Q6.10 / Q4.12 | 主要是定点参数扩展，利于展示误差对比 |
| 3 | AXI4-Stream | 接口增强，适合 RTL 方向发挥 |
| 4 | 多 head | 工程量中等，地址管理复杂 |
| 5 | BF16/FP16 | 数值硬件复杂，风险较高 |
| 6 | INT8/FP8 | 研究性强，短期风险高 |

### 19.3 Bonus 截止原则

无论 Bonus 进度如何，2026-07-02 后不再合入任何 Bonus 相关改动到提交主包。Bonus 必须独立目录、独立验证、独立报告，不能污染 Baseline。

---

## 20. 最终提交包检查清单

### 20.1 代码文件

- [ ] RTL 源码完整。
- [ ] filelist 完整。
- [ ] 无绝对路径依赖。
- [ ] 无临时 debug 文件污染主目录。
- [ ] 无未解释的大段废弃代码。

### 20.2 验证文件

- [ ] testbench 完整。
- [ ] cocotb 脚本完整。
- [ ] 测试向量完整。
- [ ] scoreboard 完整。
- [ ] 仿真运行说明完整。
- [ ] 关键波形文件或截图保留。

### 20.3 综合文件

- [ ] Genus 脚本完整。
- [ ] SDC 文件完整。
- [ ] filelist 路径正确。
- [ ] area report 存在。
- [ ] timing report 存在。
- [ ] power report 存在。
- [ ] log 文件存在。

### 20.4 文档文件

- [ ] README。
- [ ] product spec。
- [ ] project plan。
- [ ] architecture spec。
- [ ] fixed-point spec。
- [ ] verification plan。
- [ ] error analysis。
- [ ] PPA report。
- [ ] final report。

### 20.5 结果数据

- [ ] cycles 统计。
- [ ] RD_BYTES/WR_BYTES 统计。
- [ ] MAE/MaxAE 统计。
- [ ] causal corner case 结果。
- [ ] random regression 结果。
- [ ] Genus PPA 结果。

---

## 21. 成功标准

本项目按以下优先级判断成功：

### 21.1 最低成功标准

1. RTL 可综合。
2. full-size end-to-end 仿真可跑通。
3. 输出误差达到赛题门限。
4. 支持 causal mask。
5. 不存完整 score/p 矩阵。
6. 使用 online softmax 和 K/V tiling。
7. 提交材料完整。

### 21.2 合格竞争标准

1. cycles 小于 300k。
2. 面积小于 2M gates。
3. AXI4-Lite 与 AXI4 Master DMA 流程完整。
4. Genus 报告完整。
5. 文档解释清楚架构、算法、误差、PPA 和带宽。

### 21.3 优秀竞争标准

1. cycles 明显低于 300k。
2. 面积和 Fmax 表现良好。
3. 带宽分析清晰，有 tile 复用收益说明。
4. 验证用例充分。
5. 报告具有工程产品感。
6. 具备 1 个低风险 Bonus 且不影响 Baseline。

---

## 22. 当前立即行动清单

### A：RTL/验证/综合负责人

从 2026-05-29 开始立即执行：

1. 建立工程目录。
2. 将 `product_spec.md` 和 `project_plan.md` 放入 `doc/`。
3. 创建 RTL filelist。
4. 写 `fa_accel_top.sv` 空壳。
5. 写 `fa_regfile.sv`。
6. 写 AXI4-Lite register smoke test。
7. 写 `architecture_spec.md` 初稿。
8. 写 `verification_plan.md` 初稿。

### B：算法/模型负责人

从 2026-05-29 开始立即执行：

1. 写 FP32 SDPA golden。
2. 写 causal mask golden。
3. 写 Q8.8 quant/dequant。
4. 写 fixed-point online softmax 初版。
5. 生成第一批 Q/K/V/O 测试向量。
6. 开始 exp/reciprocal 近似 sweep。
7. 写 `fixed_point_spec.md` 初稿。

---

## 23. 结论

本项目时间紧、工程链路长、任务类型跨度大。两人团队要优先保证 Baseline 闭环，而不是过早追求 Bonus 或过度复杂架构。

最关键的成功路径是：

```text
FP32 golden
→ fixed-point golden
→ 小规模 RTL compute core
→ online softmax RTL 对齐
→ AXI/DMA 端到端
→ full-size regression
→ cycles/area 优化
→ Genus 综合
→ 报告与提交包冻结
```

项目管理上必须坚持：

1. 需求尽早冻结。
2. 定点 spec 先于 RTL 大规模开发冻结。
3. 每周保留可回退 tag。
4. 7 月 4 日前冻结提交包。
5. 7 月 5 日至 7 月 6 日只做应急修复。
6. 7 月 7 日只提交，不开发。

只要按本计划执行，Baseline 通过和形成完整工程产品展示的概率最高。
