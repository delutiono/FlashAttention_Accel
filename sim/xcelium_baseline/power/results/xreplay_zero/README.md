# fa_top zero-delay Xreplay power result

This directory archives the completed Joules Xreplay baseline power result for
`fa_top`.

## Flow

- Tool flow: RTL SHM activity -> Genus RTL-to-gate mapping -> Joules Xreplay.
- Delay mode: zero delay.
- Power report frame: `/stim#0/frame#0`.
- Replay input waveform: `../../rtl_wave/fa_top_power_s256_rtl.shm`.
- Mapping file: `../../mapping/fa_top_genus_mapping.rpt`.

## Result

Power unit: mW.

| Category | Leakage | Internal | Switching | Total | Row% |
| --- | ---: | ---: | ---: | ---: | ---: |
| memory | 0.115 | 130.156 | 0.346 | 130.618 | 45.28% |
| register | 0.007 | 137.683 | 1.270 | 138.959 | 48.17% |
| logic | 0.011 | 13.453 | 5.421 | 18.885 | 6.55% |
| subtotal | 0.133 | 281.292 | 7.038 | 288.462 | 100.00% |

Hierarchical highlights:

| Instance | Total power |
| --- | ---: |
| `/fa_top` | 288.462 mW |
| `/fa_top/u_core_u_update` | 129.120 mW |
| `/fa_top/u_finalize` | 16.071 mW |

## Activity annotation

From `stim_annotation_report.rpt`:

- Primary inputs asserted: 205 / 205, 100.00%.
- Sequential memory outputs asserted: 4864 / 4864, 100.00%.
- Sequential flop outputs asserted: 8315 / 16068, 51.74%.
- Driver nets asserted: 13384 / 136733, 9.78%.

This is a reproducible baseline power result, not a signoff power number. The
full gate replay VCD is intentionally not committed because it is a large
intermediate artifact.
