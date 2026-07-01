# FlashAttention Hardware Accelerator — Bonus Easy Implementation

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

### Bonus（已实现 4 项）

| # | Bonus | 官方编号 | 关键改动 |
|---|-------|---------|---------|
| 1 | **Padding Mask** | #4 | `valid_len` 寄存器 + score 路径 mask 管道，无效位置 exp=0 |
| 2 | **Q6.10 / Q4.12 定点格式** | #5 | CFG[2:1] FORMAT 选择，output_norm_pipe 动态移位 |
| 3 | **S=512 可配置序列长度** | #3 | `seq_len` 寄存器，所有计数器 5→6 bit，TOKEN_WIDTH 16→18 |
| 4 | **DMA 任务队列** | #9 | 8-entry 任务参数 RAM + FIFO 队列 + 链式自动执行 |

---

## 寄存器地址映射

| Offset | 名称 | 访问 | 说明 |
|--------|------|------|------|
| 0x00 | CTRL | R/W | [0] START, [1] SOFT_RESET, [2] IRQ_EN |
| 0x04 | STATUS | R | [0] BUSY, [1] DONE(W1C), [2] ERROR(W1C) |
| 0x08 | CFG | R/W | [0] CAUSAL_EN, [2:1] FORMAT (00=Q8.8, 01=Q6.10, 10=Q4.12), [3] TASK_CHAIN |
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
│   ├── fa_top.v                  # 顶层集成
│   ├── axi_lite_regs.v           # AXI4-Lite 寄存器 + 任务队列
│   ├── page_manager.v            # Page/Group 管理器（双缓冲 + 任务链）
│   ├── score_scheduler.v         # 记分板调度器（可配置 S）
│   ├── task_ctrl.v               # Task 控制器（链式执行）
│   ├── dma_engine.v              # DMA 引擎
│   ├── dma_read_master.v         # AXI4 读 Master
│   ├── dma_write_master.v        # AXI4 写 Master
│   ├── dma_cmd_queue.v           # DMA 命令队列
│   ├── packed_compute_core.v     # 计算核顶层（含 padding mask）
│   ├── dot_frontend.v            # Dot-product 前端（32 lane × 2 phase）
│   ├── score_exp_pipe.v          # Score + Exp 流水线（含 mask 管道）
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

1. 单 head, 单 batch（多 head 需通过任务队列顺序执行）
2. simulaton 无 dropout / BF16 / INT8 / AXI4-Stream 支持
3. 需 iverilog 解释执行，仿真速度较慢
