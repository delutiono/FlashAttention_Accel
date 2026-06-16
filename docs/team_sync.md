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
| Golden model | 进行中 | 已有 FP32 / FlashAttention / Q8.8 simulated 初版；定点规格 v0.1 已交付，待 sweep 冻结 |
| 测试向量 | 进行中 | 已有 q0/q1 final、exp LUT v0.2、scheduler -0.5/-2/-4 final expected、`row_scoreboard_s4_det` Q/K/V/O；仍需可复现随机/full-row |
| RTL 骨架 | 进行中 | `row_scoreboard_s4_det` 64-lane row scoreboard 已通；下一步转 generic exp/recip 与随机/full-row |
| 语法检查 | 已完成 | `vlog -lint -sv -work <work> -f rtl/filelist.f`：0 errors，0 warnings |
| 综合脚本 | 进行中 | 已有最小 `synth/run_genus.tcl` 与 `constraints.sdc`，未在 Cadence 环境验证 |

## 3. 分工焦点

| 成员 | 当前焦点 | 下一步 |
|---|---|---|
| A：RTL / 验证 / 综合 | deterministic row scoreboard 已通 | 替换 exact-point exp/recip 为最小 generic 实现 |
| B：算法 / 定点建模 | `row_scoreboard_s4_det` Q/K/V/O 已补 | 冻结 exp/recip v0.2 参数，补可复现随机/full-row expected |

## 4. 开放对接请求

| ID | 负责人 | 状态 | 需要补齐/冻结 | 对齐颗粒度 | 产物 |
|---|---|---|---|---|---|
| REQ-004 | B | 进行中 | random/full-row final vectors | 已有 `row_scoreboard_s4_det` Q/K/V/O；待补可复现随机 fixed `O_q88` 与误差统计 | `test_vectors/cases/` |
| REQ-005 | B | 待对接 | 修复 golden 保存 hex 的环境兼容问题 | 当前 bundled Python/numpy 下保存向量会报错，需可复现生成 | `golden_model.py` |
| REQ-006 | B+A | 待冻结 | fixed-point v1.0 | exp LUT v0.2 仅覆盖少数点；仍需冻结通用 LUT/PWL、recip、rounding tie、`REG_SCALE=32` | `docs/fixed_point_spec.md` |

## 5. 当前阻塞/风险

| 风险 | 影响 | 处理 |
|---|---|---|
| fixed-point spec 未冻结 | softmax/exp/recip RTL 容易返工 | v0.1 已有；B 做 sweep，A 按 v0.1 先实现可替换模块 |
| exp/recip 仍是 exact-point bring-up | 随机 score 会大量落到 unsupported path | B 冻结最小 LUT/PWL/NR 规则，A 替换硬编码点表 |
| row scoreboard 仍是 deterministic sentinel | 不能代表随机/full-row baseline 正确性 | B 补可复现随机 expected；A 接 scoreboard 阈值/误差统计 |
| AXI DMA/top 未通 | 无法满足接口验收 | 先 DMA smoke，再接 top；暂不做多 outstanding 优化 |
| corner case 不足 | causal/tile 边界 bug 不易暴露 | B 补 cases，A 后续接入 scoreboard |
| score/memory 测试仍是零延迟 | 接 buffer/DMA 后 valid 对齐可能出 bug | 后续 TB 加 memory latency/backpressure |

## 6. 最近推进记录

### 2026-06-16 Round 16 A/B/C

- RTL：`fa_exp_approx` 扩到 bring-up LUT v0.2，覆盖 `0/-0.5/-1/-2/-4/<=-16` exact points，接口不变。
- 算法/文档：新增 `exp_lut_v02/expected.txt`，并在 fixed-point/debug 文档中标明这不是最终 LUT/PWL。
- 验证：`tb_exp_approx PASS`；脚本测试 13 项 OK；RTL/synth filelist lint 0 errors/0 warnings。

### 2026-06-17 Round 19 A/B/C

- RTL：`fa_recip_approx` 新增 `l=009152AB -> recip=70BDF523`，新增 `tb_scheduler_softmax_finalize_q1_neg2_vec`。
- 算法：新增 `q1_delta_neg2/pipeline_final_expected.txt`，冻结 score `FFFFFFFE0000`、exp `001152AB`、acc `0000A2A55600`、final O `011F`。
- C：确认 -2 增加 exp LUT v0.2 exact point 的 scheduler/final 证据；下一步优先 -4，再做 higher generic。
- 验证：`tb_scheduler_softmax_finalize_q1_neg2_vec PASS`；脚本测试 16 项 OK；RTL/synth filelist lint 0 errors/0 warnings。

### 2026-06-17 Round 20 A/B/C

- RTL：`fa_recip_approx` 新增 `l=0082582B -> recip=7DB2A076`，新增 `tb_scheduler_softmax_finalize_q1_neg4_vec`。
- 算法：新增 `q1_delta_neg4/pipeline_final_expected.txt`，冻结 score `FFFFFFFC0000`、exp `0002582B`、acc `000084B05600`、final O `0105`。
- C：确认 -4 仍只是 bring-up exact point；下一轮必须转向 generic exp/recip、random/full-row scoreboard、tile/top/DMA 闭环。
- 验证：`tb_scheduler_softmax_finalize_q1_neg4_vec PASS`；脚本测试 17 项 OK；RTL/synth filelist lint 0 errors/0 warnings。

### 2026-06-17 Round 21 A/B/C

- RTL：新增 64-lane row scoreboard checker 与 `tb_scheduler_softmax_finalize_row_scoreboard`，已复用比较 q0_i0、q1_neg2、q1_neg4。
- 算法：新增 `row_scoreboard_s4_det/expected.txt`，记录 q3、4 个有效 K、64 lane O，补 fixed-point v0.2 待冻结清单。
- C：指出该 expected 尚未闭环到 RTL；连续 lower-exp 与 generic recip 是下一轮主阻塞。
- 验证：row scoreboard 内置 3 case PASS；脚本测试 18 项 OK；RTL/synth filelist lint 0 errors/0 warnings。

### 2026-06-17 Round 22 A/B/C

- RTL：`fa_softmax_online_vec` lower-exp 改为 2-entry FIFO，补 `l=00E14DA2 -> recip=48B842A1`，`row_scoreboard_s4_det` case 接入。
- 算法：新增 `row_scoreboard_s4_det_{Q,K,V}.hex`，每个 16384 行，脚本校验关键 Q/K/V 地址与 expected 对齐。
- C：确认这是 baseline 前正确闭环；跑通后应转 generic exp/recip、可复现随机/full-row、再 tile/DMA/top。
- 验证：`row_scoreboard_s4_det` 64-lane compare PASS；q1_neg4/q1_neg2/q0_i0 与 `tb_softmax_online_vec` 回归 PASS；脚本测试 18 项 OK；RTL/synth lint 0 errors/0 warnings。

## 7. 下一步

| 成员 | 下一步 |
|---|---|
| A | 做最小 generic exp/recip，不再依赖 exact-point 表覆盖随机输入 |
| B | 冻结 exp/recip v0.2 参数并生成可复现随机/full-row `O_q88` |

## 8. 文档索引

| 文档 | 状态 | 路径 |
|---|---|---|
| 赛题原始要求 | 已有 | `docs/request.md` |
| 产品需求文档 | 已有 | `docs/FA_Accel_IP_Product_Spec.md` |
| 项目计划书 | 已有 | `docs/FA_Accel_IP_Project_Plan.md` |
| 团队同步 | 已有 | `docs/team_sync.md` |
| 定点规格 | v0.1 草案 | `docs/fixed_point_spec.md` |
| 测试向量格式 | v0.1 已有 | `docs/test_vector_format.md` |
| Debug dump 格式 | v0.1 已有 | `docs/debug_dump_format.md` |
| 架构规格 | 待创建 | `docs/architecture_spec.md` |
| 验证计划 | 待创建 | `docs/verification_plan.md` |
