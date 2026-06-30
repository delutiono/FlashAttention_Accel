# sky130A + SRAM 项目配置

本项目使用 sky130A 开源 PDK（commit `e8294524...`）。

---

## 工艺配置

| 项目 | 选择 |
|------|------|
| PDK | **sky130A** |
| 标准单元库 | **sky130_fd_sc_hs**（High Speed） |
| Technology LEF | **nom**（nominal） |
| 物理综合 / PnR corner | **TT**（Typical-Typical，25 °C，1.80 V） |

### 标准单元库三套 corner（`libs.ref/sky130_fd_sc_hs/lib/`）

| Corner | Liberty 文件 |
|--------|-------------|
| TT | `sky130_fd_sc_hs__tt_025C_1v80.lib` 
| FF | `sky130_fd_sc_hs__ff_n40C_1v95.lib` 
| SS | `sky130_fd_sc_hs__ss_100C_1v60.lib` 


### tLEF（`libs.ref/sky130_fd_sc_hs/techlef/`）

- `sky130_fd_sc_hs__nom.tlef` — **物理综合 / PnR 固定用这份**
- `__max.tlef` / `__min.tlef` — RC 多 corner 参数，多用于 STA

---

## SRAM 宏库

共 **29 个** SRAM，覆盖 128 bit – 8 KB 多种尺寸和形状。

### 来自 efabless 原装

| 宏名 | 容量 | 形状 | 端口 | Liberty |
|------|------|------|------|---------|
| `sky130_sram_1kbyte_1rw1r_32x256_8` | 1 KB | 32×256 | 1rw+1r | TT |
| `sky130_sram_1kbyte_1rw1r_8x1024_8` | 1 KB | 8×1024 | 1rw+1r | TT |
| `sky130_sram_2kbyte_1rw1r_32x512_8` | 2 KB | 32×512 | 1rw+1r | TT |
| `sram_1rw1r_32_256_8_sky130` | 1 KB | 32×256 | 1rw+1r | **7** 个（多 V/T）|

### 本地 OpenRAM 生成（DRC clean）

下列 **25 个** SRAM 每个都带 **TT / FF / SS 三个 corner Liberty**：

| 宏名 | 容量 | 形状 | 端口 | Liberty |
|------|------|------|------|---------|
| `sky130_sram_0kbytes_1rw_8x16_2` | 128 b | 8×16 | 1rw | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_8x16_2` | 128 b | 8×16 | 1rw+1r | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_8x32_2` | 256 b | 8×32 | 1rw+1r | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_8x64_2` | 512 b | 8×64 | 1rw+1r | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_48x16_8` | 768 b | 48×16 | 1rw+1r | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_16x64_8` | 1 Kb | 16×64 | 1rw+1r | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_32x64_8` | 2 Kb | 32×64 | 1rw+1r | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_32x128_8` | 4 Kb | 32×128 | 1rw+1r | TT/FF/SS |
| `sky130_sram_0kbytes_1rw1r_48x64_8` | 3 Kb | 48×64 | 1rw+1r | TT/FF/SS |
| `sky130_sram_1kbytes_1rw1r_24x256_8` | 6 Kb | 24×256 | 1rw+1r | TT/FF/SS |
| `sky130_sram_1kbytes_1rw1r_48x128_8` | 6 Kb | 48×128 | 1rw+1r | TT/FF/SS |
| `sky130_sram_1kbytes_1r1w_8x1024_8` | 1 KB | 8×1024 | 1r+1w | TT/FF/SS |
| `sky130_sram_1kbytes_1rw1r_32x256_8` | 1 KB | 32×256 | 1rw+1r | TT/FF/SS |
| `sky130_sram_1kbytes_1rw1r_8x1024_8` | 1 KB | 8×1024 | 1rw+1r | TT/FF/SS |
| `sky130_sram_2kbytes_1rw1r_32x512_8` | 2 KB | 32×512 | 1rw+1r | TT/FF/SS |
| `sky130_sram_2kbytes_1rw1r_128x128_16` | 2 KB | 128×128 | 1rw+1r | TT/FF/SS |
| `sky130_sram_3kbytes_1rw1r_48x512_8` | 3 KB | 48×512 | 1rw+1r | TT/FF/SS |
| `sky130_sram_3kbytes_1rw1r_96x256_8` | 3 KB | 96×256 | 1rw+1r | TT/FF/SS |
| `sky130_sram_4kbytes_1rw1r_32x1024_8` | 4 KB | 32×1024 | 1rw+1r | TT/FF/SS |
| `sky130_sram_4kbytes_1rw1r_64x512_8` | 4 KB | 64×512 | 1rw+1r | TT/FF/SS |
| `sky130_sram_4kbytes_1rw1r_128x256_8` | 4 KB | 128×256 | 1rw+1r | TT/FF/SS |
| `sky130_sram_6kbytes_1rw1r_48x1024_8` | 6 KB | 48×1024 | 1rw+1r | TT/FF/SS |
| `sky130_sram_6kbytes_1rw1r_96x512_8` | 6 KB | 96×512 | 1rw+1r | TT/FF/SS |
| `sky130_sram_8kbytes_1rw1r_64x1024_8` | 8 KB | 64×1024 | 1rw+1r | TT/FF/SS |
| `sky130_sram_8kbytes_1rw1r_128x512_8` | 8 KB | 128×512 | 1rw+1r | TT/FF/SS |

### 每个 SRAM 宏下的文件

```
sky130_sram_macros/
├── gds/<cell>.gds         # 版图
├── lef/<cell>.lef         # 抽象 LEF（PnR 用）
├── verilog/<cell>.v       # 黑盒 Verilog（仿真）
├── spice/<cell>.spice     # Spice netlist
└── lib/<cell>_{TT,FF,SS}_*.lib   # Liberty 时序
```


### 端口缩写

- `1rw` = 单端口读写（一个时钟下可读**或**写）
- `1rw+1r` = 读写口 + 只读口（可同时一读一写）
- `1r+1w` = 独立读口 + 独立写口（完全独立）

---
---
## 其他相关资源

| 位置 | 说明 |
|------|------|
| `libs.tech/magic/` | Magic 的 DRC / 抽寄生 / 版图规则 |
| `libs.tech/netgen/` | Netgen 的 LVS 规则 |
| `libs.tech/ngspice/` | ngspice 的晶体管模型和 corner |
| `libs.tech/klayout/` | KLayout DRC/LVS runset |
| `libs.tech/cadence/` | Cadence Quantus `qrcTechFile`（typ 角寄生抽取）|
| `libs.tech/openlane/` | OpenLane 各 sc 库的默认 PnR 配置 |
| `~/eda/pdk/sky130_fd_bd_sram/` | OpenRAM 用的 SRAM bitcell 库|

---

## 参考

| 资源 | URL |
|------|-----|
| sky130A 源 | https://github.com/RTimothyEdwards/open_pdks |
| skywater-pdk | https://github.com/google/skywater-pdk |
| 开源 QRC（stineje）| https://github.com/stineje/sky130_cds |
| OpenLane | https://github.com/The-OpenROAD-Project/OpenLane |
| OpenRAM | https://github.com/VLSIDA/OpenRAM |
