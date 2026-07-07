# FlashAttention Hardware Accelerator — Bonus Medium Implementation (7/9 Bonuses)

## 已实现功能总览

### Baseline（必选）

| # | 要求 | 实现 |
|---|------|------|
| (1) | SDPA 计算：S=256, D=64, causal mask | `packed_compute_core` + `score_scheduler` |
| (2) | FlashAttention-style：禁止显存 S×S 矩阵 + online softmax + tiling | `update_state_cluster` 在线 softmax，`page_manager` tile K/V，双缓冲 |
| (3) | Q8.8 有符号定点（16-bit） | 输入 Q/K/V 均为 Q8.8，累加 48-bit |
| (4) | AXI4-Lite 控制接口 | `axi_lite_regs.v` |
| (5) | AXI4 Master + DMA（128-bit 数据宽度） | `dma_engine.v` 含读/写 Master |
| (6) | 寄存器 map（W1C STATUS） | 见下方寄存器表 |
| (7) | 片上存储约束：无 S×S 矩阵，仅 tile K/V + 每行 m/l/acc | 8-entry token FIFO + tile 双缓冲 + per-row online softmax state |
| (8) | Causal mask corner case 正确 | i=0 只能关注 j=0 |

### Bonus（已实现 7/9 项）

| # | Bonus | 官方编号 | 难度 | 关键改动 |
|---|-------|---------|------|---------|
| 1 | **Padding Mask** | #4 | Easy | `valid_len` 寄存器 + score 路径 mask 管道，无效位置 exp=0 |
| 2 | **Q6.10 / Q4.12 定点格式** | #5 | Easy | CFG[2:1] FORMAT 选择，output_norm_pipe 动态移位 |
| 3 | **S=512 可配置序列长度** | #3 | Easy | `seq_len` 寄存器，所有计数器 5→6 bit，TOKEN_WIDTH 16→18 |
| 4 | **DMA 任务队列** | #9 | Easy | 8-entry 任务参数 RAM + FIFO 队列 + 链式自动执行 |
| 5 | **AXI4-Stream 数据接口** | #8 | Medium | `axi_stream_data_adapter.v` 旁路 DMA，CFG[4] STREAM_EN |
| 6 | **Dropout 训练模式** | #6 | Medium | 32-bit LFSR + dropout 管道复用 padding mask 路径 |
| 7 | **多 Head 支持** | #2 | Medium | `page_manager` 最外层 head 循环 + head_stride 地址偏移 |

**未实现（2 项 Hard）**：BF16/FP16 (#1)、INT8/FP8 低精度 (#7)

---

## 寄存器地址映射

| Offset | 名称 | 访问 | 说明 |
|--------|------|------|------|
| 0x00 | CTRL | R/W | [0] START, [1] SOFT_RESET, [2] IRQ_EN |
| 0x04 | STATUS | R | [0] BUSY, [1] DONE(W1C), [2] ERROR(W1C) |
| 0x08 | CFG | R/W | [0] CAUSAL_EN, [2:1] FORMAT (00=Q8.8, 01=Q6.10, 10=Q4.12), [3] TASK_CHAIN, [4] STREAM_EN, [5] DROPOUT_EN |
| 0x0C | SEQ_LEN | R/W | S/8 = num_groups（默认 32→S=256, 最大 64→S=512） |
| 0x10 | VALID_LEN | R/W | 有效 KV 位置数（≤S），0=禁用 padding mask |
| 0x14 | Q_BASE_L | R/W | Q 基地址低 32 位 |
| 0x18 | Q_BASE_H | R/W | Q 基地址高 32 位 |
| 0x1C | K_BASE_L | R/W | K 基地址低 32 位 |
| 0x20 | K_BASE_H | R/W | K 基地址高 32 位 |
| 0x24 | V_BASE_L | R/W | V 基地址低 32 位 |
| 0x28 | V_BASE_H | R/W | V 基地址高 32 位 |
| 0x2C | O_BASE_L | R/W | O 基地址低 32 位 |
| 0x30 | O_BASE_H | R/W | O 基地址高 32 位 |
| 0x34 | STRIDE_BYTES | R/W | 行 stride（默认 128） |
| 0x38 | NEG_LARGE | R/W | -inf 近似值（Q16.16） |
| 0x3C | SCALE | R/W | 缩放常数（软件根据 FORMAT 写入） |
| 0x40 | CYCLES | R | 执行周期数 |
| 0x44 | TASK_PARAM_ADDR | W | 任务参数 RAM 索引（[2:0]=entry, [5:3]=word） |
| 0x48 | TASK_PARAM_DATA | R/W | 任务参数数据（写入后自动递增 word 地址） |
| 0x4C | TASK_QUEUE_CTRL | W | [0]=入队, [1]=清队列；R 返回 queue_count[3:0] |
| 0x50 | DROPOUT_SEED | R/W | 32-bit LFSR 种子（写操作重新播种） |
| 0x54 | DROPOUT_PROB | R/W | Q0.16 概率阈值（默认 0x0000，禁用 dropout） |
| 0x58 | NUM_HEADS | R/W | Head 数量（1-8，默认 1→单 head） |
| 0x5C | HEAD_STRIDE | R/W | 每个 head 的字节偏移（含 Q/K/V/O 所有矩阵） |

---

## Bonus 实现细节

### 1. Padding Mask（官方 #4）

**原理**：当输入序列有效长度 L < S 时，将 KV 位置 ≥ L 的 score 置为 -inf（exp→0），使无效 token 不影响 softmax 结果。

**数据流**：
```
axi_lite_regs.VALID_LEN → fa_top → packed_compute_core → score_exp_pipe
```

**关键修改**：
- `rtl/axi_lite_regs.v`: 寄存器 `VALID_LEN`（0x010），默认 0 禁用
- `rtl/packed_compute_core.v`: 提取 `score_user_token`，与 `valid_len` 比较生成 `pad_mask`
- `rtl/score_exp_pipe.v`: 3-stage mask 延迟管道，mask=1 时 score 强制置 -inf（`32'h80000000`）

### 2. 可配置定点格式（官方 #5）

**原理**：内部数据通路保持 Q16.16，通过改变 OUTPUT_SHIFT 实现不同格式输出：
- Q8.8: shift=52（16+16+20，默认）
- Q6.10: shift=50
- Q4.12: shift=48

**关键修改**：
- `rtl/axi_lite_regs.v`: CFG[2:1] → `format_sel`，默认 00 (Q8.8)
- `rtl/finalize_cluster.v`: `format_sel` → `output_shift` 译码
- `rtl/output_norm_pipe.v`: 将硬编码移位量改为动态 `output_shift`

**软件配合**：不同格式下软件需写入对应 SCALE 值：

| FORMAT | SCALE | 说明 |
|--------|-------|------|
| Q8.8 (00) | 0x2000 | 0.125 / 1 |
| Q6.10 (01) | 0x0200 | 0.125 / 16 |
| Q4.12 (10) | 0x0020 | 0.125 / 256 |

### 3. 可配置序列长度 S=512（官方 #3）

**原理**：将 S 存储为 `num_groups = S/8`，默认 32（S=256），最大 64（S=512）。所有相关计数器从 5-bit 扩展到 6-bit，TOKEN_WIDTH 从 16 扩展到 18。

**关键修改**：
- `rtl/axi_lite_regs.v`: 寄存器 `SEQ_LEN`（0x00C），默认 32
- `rtl/page_manager.v`: `active_q_group/kv_tile` 5→6 bit，`5'd31` → `num_groups - 1`
- `rtl/score_scheduler.v`: 分组/瓦片计数器扩展，`token_counter_reg` 8→10 bit
- `rtl/packed_compute_core.v`: TOKEN_WIDTH 16→18，`score_user_token` 8→10 bit
- 级联影响: `dot_frontend`, `score_exp_pipe`, `update_token_fifo`, `update_state_cluster`, `finalize_cluster`, `output_norm_pipe`

**TOKEN_WIDTH 位域**（18-bit）：
```
[2:0] = context (3-bit)
[5:3] = v_row (3-bit)
[6]   = v_page (1-bit)
[7]   = last (1-bit)
[17:8]= user_token (10-bit)
```

### 4. DMA 任务队列（官方 #9）

**原理**：在 `axi_lite_regs` 中实现 8-entry 任务参数 RAM + 队列 FIFO，支持链式自动执行多个 attention 任务，减少主机交互。

**关键修改**：
- `rtl/axi_lite_regs.v`: 64×32 task RAM, 8-deep 队列 FIFO, task_active mux
- `rtl/task_ctrl.v`: ST_DONE 时若 `task_chain_enable && queue_not_empty` 则跳回 ST_INIT
- `rtl/page_manager.v`: ST_DONE 时自动 dequeue 下一个任务，跳回 ST_Q_CMD

**软件使用流程**：
```c
// 1. 写入任务参数到 RAM
for (i = 0; i < num_tasks; i++) {
    write(TASK_PARAM_ADDR, (0 << 3) | i);   // entry=i, word=0
    write(TASK_PARAM_DATA, task[i].q_lo);     // 自动递增 word
    write(TASK_PARAM_DATA, task[i].q_hi);
    write(TASK_PARAM_DATA, task[i].k_lo);
    write(TASK_PARAM_DATA, task[i].k_hi);
    write(TASK_PARAM_DATA, task[i].v_lo);
    write(TASK_PARAM_DATA, task[i].v_hi);
    write(TASK_PARAM_DATA, task[i].o_lo);
    write(TASK_PARAM_DATA, task[i].o_hi);
}

// 2. 使能链式执行
write(CFG, (1 << 3) | FORMAT | CAUSAL);

// 3. 入队所有任务
for (i = 0; i < num_tasks; i++) {
    write(TASK_PARAM_ADDR, i);
    write(TASK_QUEUE_CTRL, 0x1);  // ENQUEUE
}

// 4. 启动（后续任务自动执行）
write(CTRL, 0x1);  // START
```

---

### 5. AXI4-Stream 数据接口（官方 #8）

**原理**：在 AXI4 Memory-Mapped DMA 通路之外，额外提供 AXI4-Stream 从/主接口，便于与其他 IP 级联。CFG[4]=1 时，`axi_stream_data_adapter` 将 Stream 信号直通到内部 DMA rd/wr 接口，旁路 DMA engine。

**数据通路**：
```
Stream 模式 (CFG[4]=1):
  s_axis_t* → stream_adapter → dma_rd_* → load adapters (K/V/Q) → compute core
  compute core → o_store_adapter → dma_wr_* → stream_adapter → m_axis_t*

DMA 模式 (CFG[4]=0):
  现有通路不变，DMA engine 正常工作
```

**AXI4-Stream 端口**：
- Slave (输入 Q/K/V): `s_axis_tvalid/tready/tdata[127:0]/tkeep[15:0]/tuser[1:0]/tlast`，tuser=0/1/2 区分 Q/K/V
- Master (输出 O): `m_axis_tvalid/tready/tdata[127:0]/tkeep[15:0]/tlast`

**关键修改**：
- `rtl/axi_stream_data_adapter.v`: **新文件**，~134 行，Stream↔DMA 桥接
- `rtl/fa_top.v`: 新增 stream 端口 + MUX 旁路逻辑（~60 行）
- `rtl/axi_lite_regs.v`: CFG[4] → stream_en

### 6. Dropout 训练模式（官方 #6）

**原理**：在 softmax 后的 score 路径上加入 dropout，使用 32-bit Fibonacci LFSR（多项式 x^32 + x^22 + x^2 + x + 1）生成伪随机数。`dropout_prob`（Q0.16）控制 mask 概率：`lfsr[15:0] < dropout_prob` 时该 token 被 mask（alpha=0, beta=0）。

**管道设计**：完全复用 padding mask 的 5 级延迟管道（mask_v0→v1→v2→side_s0→side_s1），dropout mask 与 padding mask 在输出阶段 OR 合并：
```
in_valid → lfsr_advance + dropout_v0 → ... → dropout_side_s1
effective_mask = mask_side_s1 || (dropout_en && dropout_side_s1)
alpha = effective_mask ? 0x8000 : normal_alpha
beta  = effective_mask ? 0      : normal_beta
```

**关键修改**：
- `rtl/score_exp_pipe.v`: +32-bit LFSR reg + dropout_v0/v1/v2/s0/s1 管道 + 输出 OR 合并（~100 行）
- `rtl/packed_compute_core.v`: 端口透传 dropout_en/seed/prob
- `rtl/axi_lite_regs.v`: DROPOUT_SEED (0x050), DROPOUT_PROB (0x054)

### 7. 多 Head 支持（官方 #2）

**原理**：在 `page_manager` 最外层添加 head 循环，对每个 head 通过 `head_idx * head_stride` 偏移 Q/K/V/O 基地址。计算核心完全不变，每个 head 顺序执行。

**循环结构**：
```
for head_idx in 0..num_heads-1:
    cur_*_base = *_base + head_idx * head_stride
    for group in 0..num_groups-1:   ← 现有逻辑，改用 cur_*_base
        ...
```

**关键修改**：
- `rtl/page_manager.v`: +head_idx_reg, head_offset_reg, cur_*_base 寄存器，ST_O_WAIT 中判断 head 是否完成（~80 行）
- `rtl/axi_lite_regs.v`: NUM_HEADS (0x058, 默认 1), HEAD_STRIDE (0x05C)
- `rtl/fa_top.v`: wires + 连线

**配置示例**（head=4, S=256, D=64, 每个 head 矩阵连续存储）：
- HEAD_STRIDE = 4 × S × D × 2 = 4 × 256 × 64 × 2 = 131072 bytes
- 物理内存布局: `[Q_head0][K_head0][V_head0][O_head0][Q_head1][K_head1][V_head1][O_head1]...`

---

## 性能结果

### 正确性（S=256, Q8.8, causal）

| 对比 | MAE | Max AE | 阈值 | 结果 |
|------|-----|--------|------|------|
| Verilog vs Python 行为模型 | 0.000613 | 0.007812 | 0.03/0.10 | **PASS** |
| Verilog vs FP32 黄金参考 | 0.001129 | 0.008569 | 0.03/0.10 | **PASS** |

### 正确性（S=512, Q8.8, causal）

| 对比 | MAE | Max AE | 阈值 | 结果 |
|------|-----|--------|------|------|
| Verilog vs FP32 黄金参考 | 0.000530 | 0.007812 | 0.03/0.10 | **PASS** |

### 延迟

| 配置 | 周期数 | 基线阈值 |
|------|--------|---------|
| S=256 | **145,219** | < 300,000 |
| S=512 | **514,600** | N/A（bonus） |

### 带宽统计（S=256）

| 操作 | 字节数 |
|------|--------|
| DMA 读 Q | 32 KB |
| DMA 读 K | 32 KB (×32 tiles) |
| DMA 读 V | 32 KB (×32 tiles) |
| DMA 写 O | 32 KB |
| 总 RD_BYTES | 96 KB |
| 总 WR_BYTES | 32 KB |

---

## 编译与仿真

### 依赖

- Icarus Verilog (iverilog) >= 11.0
- Python 3 + numpy（用于 golden 模型对比）

### S=256 仿真

```bash
make sim
```

### S=512 仿真

```bash
make sim_512
```

### Golden 模型对比

```bash
# S=256
python3 -c "
import numpy as np
ref = np.loadtxt('sim/o_ref_tb.hex', dtype=np.int16)
tb  = np.loadtxt('sim/o_tb.hex', dtype=np.int16)
diff = ref.astype(np.int32) - tb.astype(np.int32)
print(f'MAE: {np.abs(diff).mean()/256:.6f}')
print(f'MaxAE: {np.abs(diff).max()/256:.6f}')
print(f'Errors: {(diff!=0).sum()}/{len(diff)}')
"

# S=512
python3 -c "
import numpy as np
ref = np.loadtxt('sim/o_ref_tb_512.hex', dtype=np.int16)
tb  = np.loadtxt('sim/o_tb_512.hex', dtype=np.int16)
diff = ref.astype(np.int32) - tb.astype(np.int32)
print(f'MAE: {np.abs(diff).mean()/256:.6f}')
print(f'MaxAE: {np.abs(diff).max()/256:.6f}')
print(f'Errors: {(diff!=0).sum()}/{len(diff)}')
"
```

---

## 文件结构

```
another_workspace/
├── rtl/                          # 所有 RTL 设计源文件
│   ├── fa_top.v                  # 顶层集成（Stream + Dropout + Multi-head 端口）
│   ├── axi_lite_regs.v           # AXI4-Lite 寄存器 + 任务队列
│   ├── page_manager.v            # Page/Group 管理器（双缓冲 + 任务链 + head 循环）
│   ├── score_scheduler.v         # 记分板调度器（可配置 S）
│   ├── task_ctrl.v               # Task 控制器（链式执行）
│   ├── dma_engine.v              # DMA 引擎
│   ├── dma_read_master.v         # AXI4 读 Master
│   ├── dma_write_master.v        # AXI4 写 Master
│   ├── axi_stream_data_adapter.v   # AXI4-Stream ↔ DMA 桥接（新）
│   ├── dma_cmd_queue.v           # DMA 命令队列
│   ├── packed_compute_core.v     # 计算核顶层（含 padding mask）
│   ├── dot_frontend.v            # Dot-product 前端（32 lane × 2 phase）
│   ├── score_exp_pipe.v          # Score + Exp 流水线（mask 管道 + LFSR dropout）
│   ├── update_state_cluster.v    # Online Softmax + 累加更新
│   ├── finalize_cluster.v        # 最终归一化（含 format 译码）
│   ├── reciprocal_approx.v       # 倒数近似
│   ├── output_norm_pipe.v        # 输出归一化（动态 shift）
│   ├── q_load_store_adapter.v    # Q 加载 / O 存储适配器
│   ├── o_store_adapter.v         # O 存储 SRAM 读适配器
│   ├── k_load_adapter.v          # K 加载适配器
│   ├── v_load_adapter.v          # V 加载适配器
│   ├── qk_sram_cluster.v         # Q/K SRAM bank 集群
│   ├── v_sram_cluster.v          # V SRAM bank 集群
│   ├── acc_sram_cluster.v        # ACC SRAM bank 集群
│   ├── meta_sram_cluster.v       # Meta SRAM bank 集群
│   ├── update_token_fifo.v       # Token FIFO (18-bit)
│   ├── perf_counters.v           # 性能计数器
│   └── sky130_sram_*.v           # SRAM 行为模型 + wrapper
├── sim/
│   ├── tb_fa_top.sv              # S=256 testbench
│   ├── tb_fa_top_512.sv          # S=512 testbench
│   ├── q_tb.hex / k_tb.hex       # S=256 测试输入
│   ├── v_tb.hex / o_ref_tb.hex   # S=256 参考输出
│   ├── q_tb_512.hex / k_tb_512.hex  # S=512 测试输入
│   ├── v_tb_512.hex / o_ref_tb_512.hex  # S=512 参考输出
│   └── gen_ref.py                # Golden 参考生成脚本（父目录）
├── Makefile                      # 编译/仿真脚本（含 S=512 target）
└── README.md                     # 本文件
```

## 已知限制

1. 单 batch（batch=1），不支持多 batch 并行
2. Dropout 使用 LFSR 伪随机数，非真随机，需软件写 DROPOUT_SEED 保证可复现
3. AXI4-Stream 模式下 tuser 仅区分 Q/K/V（0/1/2），不支持带内配置参数
4. 多 head 为顺序执行（非并行），head 数增加时延迟线性增长
5. 未实现 BF16/FP16 (#1) 和 INT8/FP8 低精度 (#7)
