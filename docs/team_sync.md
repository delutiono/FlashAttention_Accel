# 团队对齐与进度同步

> 用途：快速同步项目进度、接口颗粒度、缺失材料和阻塞项。本文档只保留“当前仍有用的信息”，详细设计放独立文档。

## 1. 维护规则

1. 每次有实质推进，只更新相关状态、开放请求和最近记录。
2. 信息要短：写清“传递什么、对齐到什么颗粒度、谁下一步做什么”即可。
3. 已补齐、已失效或不再需要的请求要及时删除，不长期保留历史包袱。
4. 同一信息只保留一处；详细位宽表、格式表、测试列表放到独立文档，在这里给路径。
5. 最近记录只保留最近 5 条；更早历史看 git log。
6. 状态统一使用：未开始 / 进行中 / 待对接 / 阻塞 / 已完成 / 已冻结。

## 2. 当前快照

| 项目 | 状态 | 关键信息 |
|---|---|---|
| Baseline 范围 | 已冻结 | `S=256, d=64, batch=1, head=1, Q8.8 I/O, causal` |
| Golden model | 进行中 | 已有 FP32 / FlashAttention / Q8.8 simulated 初版；仍缺严格 RTL-friendly 定点口径 |
| 测试向量 | 进行中 | 已有 10 组 full-size causal random vectors |
| RTL 骨架 | 进行中 | `fa_regfile` 与 `fa_scheduler` 已有 smoke test 覆盖 |
| 语法检查 | 已完成 | `vlog -lint -sv -work work_green_lint -f rtl/filelist.f`：0 errors，0 warnings |
| 综合脚本 | 进行中 | 已有最小 `synth/run_genus.tcl` 与 `constraints.sdc`，未在 Cadence 环境验证 |

## 3. 分工焦点

| 成员 | 当前焦点 | 下一步 |
|---|---|---|
| A：RTL / 验证 / 综合 | RTL 骨架、寄存器、scheduler、验证框架 | 下一步做简化 memory/compute core dot 对齐 |
| B：算法 / 定点建模 | golden、定点规格、测试向量、误差分析 | 补齐 fixed-point spec、vector format、debug dump |

## 4. 开放对接请求

| ID | 负责人 | 状态 | 需要补齐/冻结 | 对齐颗粒度 | 产物 |
|---|---|---|---|---|---|
| REQ-001 | B+A | 待对接 | fixed-point spec | 明确 score、exp、m/l/acc、reciprocal、O quant 的 Q 格式、位宽、舍入、饱和、mask 处理 | `docs/fixed_point_spec.md` |
| REQ-002 | B+A | 待对接 | test vector format | 明确文件命名、row-major 顺序、4-digit hex、signed int16、Q8.8 解释、`O_ref/O_q88` 含义、AXI memory byte order | `docs/test_vector_format.md` |
| REQ-003 | B | 待对接 | 中间变量 dump 格式 | 至少支持 `score_tile`、`mask_valid`、`m/l_after_tile`、`acc_after_tile`、`recip_l`、`O_q88`；每项必须标注 Q 格式 | `test_vectors/debug/<case>/` + 说明 |
| REQ-004 | B | 待对接 | corner case vectors | zero、小幅随机、causal `i=0/i=255`、tile 跨边界、non-causal | `test_vectors/cases/` |
| REQ-005 | B | 待对接 | 修复 golden 保存 hex 的环境兼容问题 | 当前 bundled Python/numpy 下保存向量会报错，需可复现生成 | `golden_model.py` |

## 5. 当前阻塞/风险

| 风险 | 影响 | 处理 |
|---|---|---|
| fixed-point spec 未冻结 | softmax/exp/recip RTL 容易返工 | A 只搭骨架，B 先出 v0.1 后再固化数值模块 |
| debug dump 未定义 | RTL 错误只能看最终 O，定位慢 | B 先给最小 dump 集合 |
| corner case 不足 | causal/tile 边界 bug 不易暴露 | B 补 cases，A 后续接入 scoreboard |
| AXI/DMA 过早接入 | debug 维度过多 | 先用简化接口跑 compute core |

## 6. 最近推进记录

### 2026-06-01 A

- 完成前三项：补实 `fa_regfile` 基础行为、添加 `sim/tb_regfile.sv`、扩展 `fa_scheduler` 阶段骨架并添加 `sim/tb_scheduler.sv`。
- 验证通过：`tb_regfile PASS`、`tb_scheduler PASS`、全 RTL filelist lint 0 errors/0 warnings。

### 2026-06-01 A

- 按“精简、及时清理”的原则重整本文档，并把该原则写入维护规则。
- 保留当前仍需对接的 5 个请求；压缩 fixed/vector/dump 的详细清单为验收颗粒度。

### 2026-06-01 A

- 创建 RTL 骨架：`rtl/ sim/ cocotb/ synth/ model/`、`rtl/filelist.f`、`synth/filelist.f`、最小 SDC/Genus 脚本。
- 首批 RTL 骨架：`fa_pkg`、`fa_accel_top`、`fa_regfile`、`fa_scheduler`、`fa_dot_pe`、`fa_exp_approx`、`fa_recip_approx`、`fa_softmax_online`、`fa_out_quant`、`fa_dma_rd/wr`、`fa_q_buffer`、`fa_kv_buffer`。
- ModelSim lint 通过：0 errors，0 compile warnings。

### 2026-06-01 B

- 提交 `golden_model.py` 初版和 10 组 full-size causal random vectors。
- 已有 FP32 SDPA、FP32 FlashAttention online/tile、Q8.8 simulated model、exp LUT、reciprocal LUT 与误差统计。

## 7. 下一步

| 成员 | 下一步 |
|---|---|
| A | 开始简化 memory/compute core；先对齐 `fa_dot_pe`，等待 REQ-001/002 后继续 softmax 数值模块 |
| B | 优先交付 REQ-001、REQ-002、REQ-003；同时修复 REQ-005 |

## 8. 文档索引

| 文档 | 状态 | 路径 |
|---|---|---|
| 赛题原始要求 | 已有 | `request.md` |
| 产品需求文档 | 已有 | `FA_Accel_IP_Product_Spec.md` |
| 项目计划书 | 已有 | `FA_Accel_IP_Project_Plan.md` |
| 团队同步 | 已有 | `docs/team_sync.md` |
| 定点规格 | 待创建 | `docs/fixed_point_spec.md` |
| 测试向量格式 | 待创建 | `docs/test_vector_format.md` |
| 架构规格 | 待创建 | `docs/architecture_spec.md` |
| 验证计划 | 待创建 | `docs/verification_plan.md` |
