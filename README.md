# baseline_200mhz_genuspass — LANES=16 Baseline Genus Synthesis

FlashAttention 加速器纯净 baseline（0 bonus），MAC 通道数从 32 降至 16，
在 SkyWater 130nm 工艺下以 200MHz 完成 Genus 综合。

## 设计参数

| 参数 | 值 |
|------|-----|
| 序列长度 S | 256 |
| 特征维度 D | 64 |
| Block 大小 BK | 32 |
| MAC 通道 LANES | 16（原 32） |
| 定点格式 | Q8.8 |
| Bonus 功能 | 无 |

## 综合结果

### 时序

| 项目 | 数值 |
|------|------|
| 时钟周期 | 5000 ps（200 MHz） |
| Critical Slack | **+0.4 ps**（MET，无违规） |
| TNS | 0.0 |
| Violating Paths | 0 |

### 面积

| 项目 | 数值 |
|------|------|
| Leaf Instance Count | 126,308 |
| Cell Area | 6,424,407 µm² |
| Net Area | 2,541,452 µm² |
| Total Area | 8,965,859 µm² |
| **等效门数** | **~1.36M gates** |

等效门数基于 NAND2_1 物理面积（~4.8 µm²）计算，**远低于 2M gate 竞赛限制**。

### 面积分解（标准单元）

| 类型 | 实例数 | 面积 (µm²) | 占比 |
|------|--------|------------|------|
| Combinational | 111,597 | ~1.68M | 68.6% |
| Sequential | 14,711 | ~0.53M | 21.4% |
| Buffer/Inverter | — | ~0.24M | 10.0% |
| **标准单元合计** | **126,308** | **~2.45M** | **100%** |
| SRAM Macro (87 个) | 87 | ~7.85M | — |

### 模块层次面积

| 模块 | 实例数 | 总面积 (µm²) | 占比 |
|------|--------|-------------|------|
| update_state_cluster | 69,528 | 4,867,785 | 54.3% |
| finalize_cluster | 11,144 | 270,479 | 3.0% |
| 其余模块 | 45,636 | ~3,827,595 | 42.7% |

### 物理信息

| 项目 | 数值 |
|------|------|
| Floorplan Utilization | 27.31% |
| Total Net Length | 11,552,055 µm |
| Avg Net Length | 79.18 µm |
| Routing Congestion | H: 19.03%, V: 7.24% |
| Max Fanout | 14,785 (clk) |

## 与原始 32-Lane Baseline 对比

| 指标 | LANES=32 (原) | LANES=16 (本) | 变化 |
|------|---------------|---------------|------|
| Leaf Instances | 192,032 | 126,308 | **-34.2%** |
| Cell Area | 10,390,892 | 6,424,407 | **-38.2%** |
| Total Area | 14,537,809 | 8,965,859 | **-38.3%** |
| 等效门数 | ~2.2M | ~1.36M | **-38.2%** |
| RTL 仿真周期 | 145K | 178K | +22.8% |

面积减少约 38%，仿真周期增加 23%，仍在 300K 限制内。

## 目录结构

```
baseline_200mhz_genuspass/
├── results/outputs/fa_top/
│   ├── fa_top_mapped.v          # 综合后网表（映射到标准单元 + SRAM 宏）
│   └── fa_top_mapped.sdc        # 时序约束（Genus 输出）
├── results/reports/fa_top/      # 综合报告（面积/时序/功耗/gate 列表）
├── workspace/RTL/               # 综合使用的 RTL 源码
├── workspace/VERILOG/           # sky130 标准单元 + primitive 行为模型
├── workspace/LIBS/              # SRAM Liberty 文件
├── workspace/LEFS/              # LEF 物理库
├── workspace/constraints/       # 时序约束输入（timing_200m.sdc）
├── workspace/filelists/         # Genus 文件列表
├── genus.log18 / genus.log19    # Genus 综合日志
└── run_genus.sh                 # 综合运行脚本
```

## 综合环境

- **工具**: Cadence Genus 25.12-s067_1
- **工艺**: SkyWater 130nm sky130_fd_sc_hs
- **SRAM**: OpenRAM compiled macros（32x64_8 ×48, 48x16_8 ×39）
- **主机**: sh02lo01
- **运行时间**: ~1.6 小时（Elapsed 5767 秒）
