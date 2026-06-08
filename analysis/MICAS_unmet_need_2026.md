# MICAS Unmet-Need Analysis — Protocol 37 Transfers, 2026

Analysis of National Ambulance Service (NAS) AMPDS **Protocol 37 (inter-hospital /
interfacility transfer)** activity, sizing the unmet need for the Mobile Intensive
Care Ambulance Service (MICAS).

## Source & scope

- **Input:** anonymised NAS extract (`anon_analys.xlsx`, 5 sheets). Source not committed
  (contains patient-transfer records, even if de-identified).
- **Period:** Week 1–17 of 2026 (29 Dec 2025 – 26 Apr 2026), 17 weeks.
- **True Protocol 37 records** (despatch code starts `37`): **3,472 resources /
  2,864 incidents**. (The file also holds 502 non-P37 `33C00T` palliative/override rows,
  excluded here.)
- **Annualisation:** ×3.06 (52 ÷ 17).

## Remit applied

- **National** service; **adult critical-care** cohort (paediatric/neonatal & maternity
  excluded — handled by IPATS/NNTP and maternity pathways).
- **Operating model:** national pool of **3 teams** (Dublin, Cork, Galway), preferentially
  dispatched to nearer calls but no hard geographic boundaries; **08:00–20:00**, Mon–Fri all
  three teams, Sat–Sun **Dublin only**.

## Method

- **Acuity & clinical complexity** read from the AMPDS despatch code: determinant letter
  (D/C/B) and qualifier suffix (`A` = additional personnel, `S` = special equipment,
  `B` = both). "Critical-care core" = adult records flagged for additional personnel and/or
  special equipment (the dispatch system's own marker that a standard crew is insufficient).
- **Patient cohort** inferred from origin/destination hospital and ward (age anonymised) —
  treat as a close estimate.
- **Coverage / unmet need** computed with a discrete-event simulation: teams reset each day
  at 08:00; a call is "met" only if a team is genuinely free when it lands; nights have zero
  teams. Cross-checked against a daily demand-vs-capacity calculation (they converge).

## Headline results

**Calls MICAS could clinically do (national, adult critical-care): ~5,500/yr.**
Current 3-team rota services only **~41% (~2,300/yr)** → **unmet need ≈ 3,240/yr (59%)**.

| Adult critical-care core (~5,500/yr addressable) | 17 wk | Annualised | Share |
|---|---:|---:|---:|
| Served within current model | 750 | ~2,300 | 41% |
| Unmet — nights (20:00–08:00, no team rostered) | 668 | ~2,040 | 37% |
| Unmet — daytime capacity (all teams busy) | 391 | ~1,200 | 22% |
| **Total unmet** | 1,059 | **~3,240** | **59%** |

Broadest definition (all adult P37, ~8,700/yr addressable): unmet ≈ **5,800/yr (66%)**.
Defensible unmet-need range: **~3,200–5,800 transfers/year**.

## Key drivers

1. **Out-of-hours is the biggest gap (~2,000/yr, 37%)** — ~half of demand lands 20:00–08:00
   with no team rostered; 37% of those are Delta/IMMEDIATE (cannot wait).
2. **Thin weekend cover** — one team (Dublin) for the whole country at weekends.
3. **In-hours capacity exceeded (~1,200/yr, 22%)** — peak simultaneous adult critical-care
   demand reaches **9 concurrent transfers** vs 3 teams (weekday) / 1 (weekend).

## Supporting context

- **57%** of all P37 transfers carry an additional-personnel / special-equipment qualifier.
- **839** transfers (~2,570/yr) are Delta **and** need both escort and equipment.
- **~800/yr** are `37D03` (airway/peri-arrest), system-tagged *"inappropriate for NAS
  Protocol 37"*.
- P37 absorbs **~21,000 emergency ambulance-hours/yr** (≈ 2.4 ambulances 24/7); **85%** of
  transfers already breach the NAS transfer time standard (distance & volume).

## Files

- `MICAS_unmet_need_analysis.xlsx` — 10 tabs. **Tab 8 = coverage/unmet model** (headline);
  Tab 1 clinical funnel; Tab 2 acuity×need; Tab 3 by region; Tabs 4–6 hospitals/corridors;
  Tab 7 out-of-performance; Tab 9 day×hour matrix.
- `MICAS_demand_heatmap.png` — adult critical-care demand by day & hour vs the 08:00–20:00
  operating window (solid box = Mon–Fri 3 teams; dashed = weekend, 1 team).

## Caveats

Cohort and "critical-care" are proxies (age anonymised; complexity inferred from dispatch
code). The simulation ignores return-to-base travel, so it is mildly optimistic on capacity.
Annualisation is a flat ×3.06 (no seasonality adjustment).
