# FlashAttention Hardware Accelerator — Baseline Implementation

## 基本功能要求（Baseline）

| # | 要求 | 实现 |
|---|------|------|
| (1) | SDPA 计算：S=256, D=64, causal mask | `packed_compute_core` + `score_scheduler` |
| (2) | FlashAttention-style：禁止显存 S×S 矩阵 + online softmax + tiling | `update_state_cluster` 在线 softmax，`page_manager` tile K/V，双缓冲 |
| (3) | Q8.8 有符号定点（16-bit） | 输入 Q/K/V 均为 Q8.8，累加 48-bit |
| (4) | AXI4-Lite 控制接口 | `axi_lite_regs.v`：CTRL/STATUS/CFG/基地址/STRIDE/NEG_LARGE/SCALE/CYCLES |
| (5) | AXI4 Master + DMA（128-bit 数据宽度） | `dma_engine.v` 含读/写 Master，INCR burst（max 16 beats），4KB 边界安全 |
| (6) | 寄存器 map（W1C STATUS） | 见下方寄存器表 |
| (7) | 片上存储约束：无 S×S 矩阵，仅 tile K/V + 每行 m/l/acc | 8-entry token FIFO + tile 双缓冲 + per-row online softmax state |
| (8) | Causal mask corner case 正确 | i=0 只能关注 j=0 |

### 寄存器地址映射

| Offset | 名称 | 访问 | 说明 |
|--------|------|------|------|
| 0x00 | CTRL | R/W | [0] START, [1] SOFT_RESET, [2] IRQ_EN |
| 0x04 | STATUS | R | [0] BUSY, [1] DONE(W1C), [2] ERROR(W1C) |
| 0x08 | CFG | R/W | [0] CAUSAL_EN |
| 0x14 | Q_BASE_L | R/W | Q 基地址低 32 位 |
| 0x18 | Q_BASE_H | R/W | Q 基地址高 32 位 |
| 0x1C | K_BASE_L | R/W | K 基地址低 32 位 |
| 0x20 | K_BASE_H | R/W | K 基地址高 32 位 |
| 0x24 | V_BASE_L | R/W | V 基地址低 32 位 |
| 0x28 | V_BASE_H | R/W | V 基地址高 32 位 |
| 0x2C | O_BASE_L | R/W | O 基地址低 32 位 |
| 0x30 | O_BASE_H | R/W | O 基地址高 32 位 |
| 0x34 | STRIDE_BYTES | R/W | 行 stride（默认 128） |
| 0x38 | NEG_LARGE | R/W | -inf 近似值（Q8.8） |
| 0x3C | SCALE | R/W | 缩放常数 |
| 0x40 | CYCLES | R | 执行周期数（perf counter） |

### 架构概览

```
AXI4-Lite (Control)                AXI4 Master (Data)
     │                                    │
  axi_lite_regs                       dma_engine
  (寄存器 + START)                  (读Q/K/V, 写O)
     │                                    │
  task_ctrl ──► page_manager ──► dma_read_master  (Q/K/V load)
     │              │               dma_write_master (O store)
     │              │                    │
  score_scheduler  │              q_load_store_adapter
     │              │              o_store_adapter
     │              │              k/v_load_adapter
     └──────┬───────┘                    │
            │                    packed_compute_core
     finalize_cluster             (dot + softmax + update)
            │
     Q SRAM ←→ O store DMA
```

## 性能结果 (2026-06-30)

### 正确性

| 对比 | MAE | Max AE | 阈值 | 结果 |
|------|-----|--------|------|------|
| Verilog vs Python 行为模型 | 0.000613 | 0.007812 | 0.03/0.10 | **PASS** |
| Verilog vs FP32 黄金参考 | 0.001129 | 0.008569 | 0.03/0.10 | **PASS** |

- S=256, D=64, causal, Q8.8
- 2547/16384 像素有 ±1-2 LSB 量化噪声（15.5%）
- 所有误差在竞赛阈值内

### 延迟

| 指标 | 值 | 阈值 |
|------|-----|------|
| 执行周期数 | **145,219** | < 300,000 ✅ |
| 仿真时间 @ iverilog | ~15 min wall time | — |

### 带宽统计

| 操作 | 字节数 |
|------|--------|
| DMA 读 Q | 32 KB (256×64×2B) |
| DMA 读 K | 32 KB (×32 tiles) |
| DMA 读 V | 32 KB (×32 tiles) |
| DMA 写 O | 32 KB |
| 总 RD_BYTES | 96 KB |
| 总 WR_BYTES | 32 KB |

## 编译与仿真

### 依赖

- Icarus Verilog (iverilog) >= 11.0
- Python 3 + numpy (用于 golden model 对比)

### 运行仿真

```bash
# 编译并运行
make sim

# 仅编译
make compile

# 清理
make clean
```

### 手动编译

```bash
iverilog -g2012 -o sim/tb_fa_top.vvp \
  rtl/fa_top.v rtl/axi_lite_regs.v rtl/task_ctrl.v rtl/perf_counters.v \
  rtl/page_manager.v rtl/score_scheduler.v rtl/dma_engine.v \
  rtl/dma_read_master.v rtl/dma_write_master.v rtl/q_load_store_adapter.v \
  rtl/o_store_adapter.v rtl/k_load_adapter.v rtl/v_load_adapter.v \
  rtl/packed_compute_core.v rtl/dot_frontend.v rtl/qk_sram_cluster.v \
  rtl/v_sram_cluster.v rtl/acc_sram_cluster.v rtl/meta_sram_cluster.v \
  rtl/score_exp_pipe.v rtl/score_exp_banked_rom.v \
  rtl/update_token_fifo.v rtl/update_state_cluster.v \
  rtl/finalize_cluster.v rtl/reciprocal_approx.v rtl/output_norm_pipe.v \
  rtl/sky130_sram_0kbytes_1rw1r_128x16_16_timed_wrapper.v \
  rtl/sky130_sram_0kbytes_1rw1r_128x16_16.v \
  rtl/sky130_sram_0kbytes_1rw1r_64x32_8_wrapper.v \
  rtl/sky130_sram_0kbytes_1rw1r_64x32_8.v \
  rtl/sky130_sram_0kbytes_1rw1r_64x64_8_wrapper.v \
  rtl/sky130_sram_0kbytes_1rw1r_64x64_8.v \
  sim/tb_fa_top.sv

# 运行仿真
vvp sim/tb_fa_top.vvp
```

### Golden 模型对比

```bash
# 生成 golden 参考输出（在 competition/ 目录下执行）
python3 sim/gen_ref.py

# 对比 RTL 输出与 golden
python3 -c "
import numpy as np
ref = np.loadtxt('sim/o_ref_tb.hex', dtype=np.int16)
tb  = np.loadtxt('sim/o_tb.hex', dtype=np.int16)
diff = ref.astype(np.int32) - tb.astype(np.int32)
print(f'MAE: {np.abs(diff).mean()/256:.6f}')
print(f'MaxAE: {np.abs(diff).max()/256:.6f}')
print(f'Errors: {(diff!=0).sum()}/{len(diff)}')
"
```

## 已知限制

1. 仅支持 S=256, D=64（固定参数）
2. 单 head, 单 batch
3. 仅 Q8.8 定点格式
4. 无 padding mask / dropout / 多 head 支持
5. 仿真速度较慢（iverilog 解释执行，~10us 仿真时间/秒 wall time）

## 文件结构

```
another_workspace/
├── rtl/           # 所有 RTL 设计源文件
│   ├── fa_top.v                # 顶层集成
│   ├── axi_lite_regs.v         # AXI4-Lite 寄存器
│   ├── page_manager.v          # Page/Group 管理器（双缓冲）
│   ├── score_scheduler.v       # 记分板调度器
│   ├── dma_engine.v            # DMA 引擎
│   ├── dma_read_master.v       # AXI4 读 Master
│   ├── dma_write_master.v      # AXI4 写 Master
│   ├── packed_compute_core.v   # 计算核顶层
│   ├── dot_frontend.v          # Dot-product 前端（32 lane × 2 phase）
│   ├── score_exp_pipe.v        # Score + Exp 流水线
│   ├── update_state_cluster.v  # Online Softmax + 累加更新
│   ├── finalize_cluster.v      # 最终归一化 + O 输出
│   ├── reciprocal_approx.v     # 倒数近似
│   ├── output_norm_pipe.v      # 输出归一化流水线
│   ├── q_load_store_adapter.v  # Q 加载 / O 存储 适配器
│   ├── o_store_adapter.v       # O 存储 SRAM 读适配器
│   ├── k_load_adapter.v        # K 加载适配器
│   ├── v_load_adapter.v        # V 加载适配器
│   ├── qk_sram_cluster.v       # Q/K SRAM bank 集群
│   ├── v_sram_cluster.v        # V SRAM bank 集群
│   ├── acc_sram_cluster.v      # ACC SRAM bank 集群
│   ├── meta_sram_cluster.v     # Meta SRAM bank 集群
│   ├── update_token_fifo.v     # Token FIFO
│   ├── task_ctrl.v             # Task 控制器
│   ├── perf_counters.v         # 性能计数器
│   └── sky130_sram_*.v         # SRAM 行为模型 + wrapper
├── sim/
│   ├── tb_fa_top.sv            # SystemVerilog testbench
│   ├── q_tb.hex                # Q 测试输入 (Q8.8)
│   ├── k_tb.hex                # K 测试输入 (Q8.8)
│   ├── v_tb.hex                # V 测试输入 (Q8.8)
│   └── o_ref_tb.hex            # Golden 参考输出
├── Makefile                    # 编译/仿真脚本
└── README.md                   # 本文件
```
