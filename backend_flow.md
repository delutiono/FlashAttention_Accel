# 后端物理综合流程

## 要拷贝到云服务器的文件

```
competition/
├── rtl_yosys/          ← 全部 .sv + .vh 文件
├── synth/
│   └── synth_full.ys   ← Yosys 完整综合脚本
├── innovus/
│   ├── run_phys.tcl    ← Innovus 物理综合主脚本
│   ├── mmmc.tcl        ← MMMC 视图定义
│   └── constraints.sdc ← 时序约束 (200MHz 目标)
├── sky130_fd_sc_hs.lef
├── sky130_fd_sc_hs__tt_025C_1v80_slim.lib
└── sky130_fd_sc_hs.v
```

## Step 1: 安装 Yosys（如果没有）

```bash
conda install -c conda-forge yosys
```

## Step 2: 完整逻辑综合 → 顶层网表

```bash
cd competition
yosys synth/synth_full.ys
# 输出: synth/fa_accel_top_netlist_full.v
```

预计时间: 10-30 分钟，峰值内存 ~20-30GB

## Step 3: Innovus 物理综合

```bash
cd competition
/apps/DDI251/25.12.000/bin/innovus -batch -file innovus/run_phys.tcl
```

会自动完成: Floorplan → Place → CTS → Route → 报告

预计时间: 30 分钟 ~ 2 小时

## 输出结果

所有报告在 `reports/` 目录:
- `timing_top5.rpt` — 关键路径时序
- `area.rpt` — 面积报告
- `power.rpt` — 功耗报告
- `gate_count.rpt` — 门数统计
- `drc.rpt` — DRC 检查
- `summary.rpt` — 总览

## 可能的问题

1. **综合 OOM**: 如果 64GB 不够，把 synth_full.ys 里 fa_kv_buffer 的参数 BK 改小
2. **Innovus RC corner**: 如果没有 cap_table 文件，可能需要在 mmmc.tcl 里注释掉 RC corner
3. **频率达不到 200MHz**: 把 constraints.sdc 里的 period 改大（比如 10.0），重跑 Step 3
