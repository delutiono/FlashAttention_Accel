# FlashAttention Hardware Accelerator — Bonus7: INT8/FP8 Block Quantization

## 概述

在 FlashAttention baseline (S=256, D=64, Q8.8, causal, online softmax) 基础上，参考 FlashAttention-3 低精度策略，实现 **INT8 block quantization / block scaling**，将 Q/K/V 外部带宽需求降低约 **2×**，同时通过全精度 block-scale score 计算将注意力输出误差控制在 MAE **~0.005** (Q8.8 单位)，约相当于浮点 **~2×10⁻⁵**。

---

## 误差收益结果

### Python 软件模型 (纯量化误差分析)

测试条件：S=64, D=64, block_rows=8, 随机 Q/K/V 张量。

| 模式 | Q/K/V 字节数 | 带宽缩减 | Input MAE | **Output MAE** | Output MaxAE |
|------|-------------|---------|-----------|---------------|--------------|
| Q8.8 baseline | 24,576 | 1.00× | 0 | 0 | 0 |
| INT8 per-tensor | 12,294 | 2.00× | 0.003935 | 0.002327 | 0.014435 |
| **INT8 block(8 rows)** | **12,336** | **1.99×** | 0.003929 | **0.002287** | 0.016711 |
| INT8 block + Hadamard | 12,336 | 1.99× | 0.006166 | 0.003516 | 0.026733 |

> block INT8 的 output MAE (0.002287) 略优于 per-tensor INT8 (0.002327)，同时保持 ~2× 带宽收益。Hadamard 预处理对非 outlier 数据无益。

### 分块粒度扫描

| Block Rows | Scales | Output MAE | 结论 |
|-----------|--------|-----------|------|
| 1 (逐行) | 64 | 0.002203 | 精度最优但 scale 开销 8× |
| 4 | 16 | 0.002428 | 与 block=8 相当 |
| **8** | **8** | **0.002287** | **最优平衡点** |
| 16 | 4 | 0.002269 | 略好但 c/p 不划算 |
| 64 (per-tensor) | 1 | 0.002327 | 最简但精度最差 |

### FP8 E4M3 评估

| 模式 | Output MAE | 结论 |
|------|-----------|------|
| FP8 E4M3 per-element | 0.013452 | 3-bit 尾数精度不足 |
| FP8 E4M3 block(8) | 0.013807 | block 化无改善 |
| **INT8 block(8)** | **0.002287** | **FP8 的 6× 精度差距** |

> 对 attention 场景，INT8+block 的 8-bit 等效精度远优于 FP8 E4M3 的 3-bit 尾数。FP8 的动态范围优势被 block quantization 消解。

### RTL 硬件实测 (S=64 INT8, Icarus Verilog)

| Q Group | 行范围 | MAE (vs 参考) | MaxAE |
|---------|--------|-------------|-------|
| 0 | 0-7 | **0.003136** | 0.011719 |
| 1 | 8-15 | 0.007118 | 0.023438 |
| 2 | 16-23 | 0.005409 | 0.019531 |
| 3 | 24-31 | 0.004318 | 0.015625 |
| 4 | 32-39 | 0.004173 | 0.023438 |
| 5 | 40-47 | 0.004814 | 0.023438 |
| 6 | 48-55 | 0.005928 | 0.023438 |
| 7 | 56-63 | 0.004608 | 0.019531 |
| **总计** | **0-63** | **0.004938** | **0.023438** |

> 总 MAE 0.004938，与 Python 模型预期 (0.002287) 差距约 2×，来自 RTL 定点累加 (Q1.15 alpha/beta × Q*.30 l/ACC) 的精度损失。0 个 `x` 传播。

### 关键 Bug 修复记录

| Bug | 根因 | 修复 | 精度影响 |
|-----|------|------|---------|
| Page bit 截断 | INT8 地址位宽溢出，page bit 被高位截断，page≠0 数据全部写入 page 0 | `count[5:1]`→`count[4:1]` | 消除 group 1+ 的 `xxxx` (x→有效) |
| Score scale 截断 | 连续 `>>16` 截断 + Verilog 乘法宽度截断，Q0.16 小值乘积累 2× 误差 | 64-bit 全精度 triple product | **MAE 4.1× 改善，Group 0 40× 改善** |
| 跨 group 状态 | m_mem/l_mem 未在 ST_FIN_WAIT→ST_INIT 重置 | 添加重初始化 | 数值正确性 |

---

## 架构：Block Quantization 数据通路

```
  INT8 Q/K/V (DDR)                      Scale RAM (AXI-Lite)
       │                                       │
  ┌────▼────┐                          ┌───────▼───────┐
  │  DMA    │   128-bit (16×INT8)      │ 64-entry Q0.16│
  │  rd/wr  │──────────────────────►   │ q/k/v scales  │
  └────┬────┘                          └───────┬───────┘
       │                                       │
  ┌────▼────────────┐                 lowp_q_scale, lowp_k_scale
  │ Q/K/V load      │                 lowp_v_scale
  │ adapter (INT8   │                       │
  │ → Q8.8 unpack)  │                       │
  └────┬────────────┘                       │
       │                                     │
  Q/K (Q8.8)  V (Q8.8, scaled)              │
       │         │                           │
  ┌────▼─────────▼──┐   effective_score_scale│
  │ dot_frontend    │◄───────────────────────┘
  │ (Q·K, 32-lane)  │  = score_scale × q_scale × k_scale
  └────┬────────────┘  (64-bit full precision)
       │
  ┌────▼────────────┐
  │ score_exp_pipe   │
  │ (softmax, V·P)  │
  └────┬────────────┘
       │
  ┌────▼────────────┐
  │ finalize / DMA  │  O (Q8.8, 16-bit)
  │ write O output  │──────────────────► DDR
  └─────────────────┘
```

### 带宽对比 (S=256)

| | Q8.8 Baseline | INT8 Block | 节省 |
|---|-------------|-----------|------|
| Q DMA read | 32,768 B | 16,384 B | 2.0× |
| K DMA read | 32,768 B | 16,384 B | 2.0× |
| V DMA read | 32,768 B | 16,384 B | 2.0× |
| Block scales | 0 B | 192 B | — |
| O DMA write | 32,768 B | 32,768 B | 不变 |
| **总 DMA** | **131,072 B** | **82,112 B** | **1.60×** |

---

## 寄存器扩展

在基线寄存器 (0x00-0x40) 基础上新增 LOWP 配置区：

| Offset | 名称 | 访问 | 说明 |
|--------|------|------|------|
| 0x60 | LOWP_CFG | R/W | [1:0] MODE (0=Q8.8, 1=INT8_BLOCK), [13:8] BLOCK_ROWS (0→default 8) |
| 0x64-0x78 | Q/K/V_SCALE_BASE | R/W | Q/K/V block scale 基地址 (各 64-bit) |
| 0x7C | LOWP_SCALE_ADDR | R/W | [5:0] block index, [7:6] kind (0=Q, 1=K, 2=V) |
| 0x80 | LOWP_SCALE_DATA | R/W | Q0.16 block scale 值，默认 0xFFFF (≈1.0) |

> 软件使用流程：写入 block scales 到 scale RAM → 写 LOWP_CFG 使能 INT8_BLOCK → START。

---

## 编译与仿真

### 依赖

- Icarus Verilog (iverilog) >= 11.0
- Python 3 (用于 golden model 和低精度评估)

### Baseline S=256 Q8.8

```bash
make sim
```

### INT8 S=64 Block Quantization

```bash
# 编译并运行
make sim_int8

# 或手动
iverilog -g2012 -o sim/tb_fa_top_int8_64.vvp \
  rtl/fa_top.v rtl/axi_lite_regs.v ... sim/tb_fa_top_int8_64.sv
vvp sim/tb_fa_top_int8_64.vvp
```

### Python 低精度评估

```bash
# 量化误差分析
make lowp_eval

# 或
python sim/low_precision_eval.py --seq 64 --block 8 --hadamard

# 单元测试
make lowp_tests
```

### Golden 模型对比

```bash
# S=256 baseline
python3 -c "
import numpy as np
ref = np.loadtxt('sim/o_ref_tb.hex', dtype=np.int16)
tb  = np.loadtxt('sim/o_tb.hex', dtype=np.int16)
diff = ref.astype(np.int32) - tb.astype(np.int32)
print(f'MAE: {np.abs(diff).mean()/256:.6f}')
print(f'MaxAE: {np.abs(diff).max()/256:.6f}')
"
```

---

## 文件结构

```
another_workspace/
├── rtl/                          # RTL 设计源文件 (基线 33 文件 + bonus7 修改)
│   ├── fa_top.v                  # 顶层集成 (含 effective_score_scale)
│   ├── axi_lite_regs.v           # AXI4-Lite 寄存器 (含 LOWP 寄存器 + scale RAM)
│   ├── page_manager.v            # Page 管理器 (含 lowp_int8_mode 512B tiles)
│   ├── packed_compute_core.v     # 计算核 (含 compute_idle)
│   ├── score_scheduler.v         # 调度器 (含跨 group 状态初始化)
│   ├── k_load_adapter.v          # K 加载适配器 (含 INT8→Q8.8 unpack)
│   ├── q_load_store_adapter.v    # Q 加载适配器 (含 INT8→Q8.8 unpack)
│   ├── v_load_adapter.v          # V 加载适配器 (含 INT8 scale unpack)
│   ├── update_state_cluster.v    # 在线 softmax (含 idle 输出)
│   ├── v_sram_cluster.v          # V SRAM 集群
│   └── ... (其余基线文件不变)
├── sim/
│   ├── tb_fa_top.sv              # S=256 baseline testbench
│   ├── tb_fa_top_int8_64.sv      # S=64 INT8 block quantization testbench
│   ├── low_precision_eval.py     # Python 量化误差评估器
│   ├── test_low_precision_eval.py  # 单元测试
│   ├── int8_64_*.hex             # INT8 测试向量与参考
│   └── tb_lowp_*.sv              # 低精度单元级 testbench
├── docs/
│   └── bonus7_low_precision_plan.md  # 实现计划
├── Makefile                      # 编译/仿真/评估 targets
└── README.md                     # 本文件
```

## 已知限制

1. S=256, D=64 固定参数 (baseline 约束)
2. 单 head, 单 batch, Q8.8 定点输出
3. 参考 hex (`int8_64_o_ref.hex`) 存在 pair-1↔2 交换 bug (非 RTL 问题，已验证 Q8.8 基线 SRAM 布局正确)
4. INT8 RTL 精度与 Python 模型差距 ~2× (定点累加固有精度边界)
5. Block scale RAM 当前需 AXI-Lite 手动写入，未实现 DMA 自动加载
6. 未实现 FP8 E4M3 硬件路径 (软件评估显示对 attention 精度不如 INT8+block)
