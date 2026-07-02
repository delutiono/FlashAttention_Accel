# accel_code branch

## Genus synthesis snapshot

This `genus` branch records the first complete Sky130/Genus synthesis
environment and output snapshot under `genus_bs1/`.

Run summary:

- Tool flow reached `Normal exit`; RTL was loaded successfully.
- The design used the 128-bit AXI mainline and real SRAM macro wrappers.
- Genus reported `SRAM_COUNT sky130_sram_0kbytes_1rw1r_32x64_8 = 96`.
- Reports were generated under `genus_bs1/results/reports/fa_accel_top/`.
- Large local-only artifacts are intentionally not tracked on GitHub because of
  repository file size limits: the mapped netlist, Genus `.db`, and the full
  Sky130 HS standard-cell Liberty file.
- Final timing was not closed at 5 ns: WNS was about `-0.528 ns`, with TNS
  about `-350.98 ns`.
- Area was dominated by compute datapath logic, especially row/softmax/finalize
  logic; vectorless power was around `5.57 W`.

Known limitations and follow-up work:

- This run is primarily a logical synthesis snapshot. The attempted physical
  options did not become a clean physical-aware flow because no floorplan DEF,
  macro placement, and complete extraction/QRC setup were provided.
- Clock tree is not built in Genus, so clock power and timing are not signoff
  quality.
- Power is vectorless and should be rerun with SAIF/VCD activity from functional
  simulation.
- The immediate RTL PPA priority is pipelining the dot-product/score path and
  then reducing or pipelining softmax/finalize logic.
- A later physical-aware run should add floorplan/macro placement constraints
  for the 96 SRAM macros and use the Sky130 Cadence QRC technology files.

该分支主要目标是完善RTL与综合验证。
