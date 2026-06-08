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

---

## Reassessment with actual MICAS activity data

A second anonymised dataset — the **actual MICAS retrieval log** (Jan 2025–Jun 2026) — was
supplied and reconciled against the P37 demand. It materially refines the picture. (Note: the
raw MICAS file still contains referring-consultant names and patient DOB/age/gender — it is
**not** committed here; only aggregate figures are.)

**What MICAS actually does (12 months, Jun 2025–May 2026):**

- **~405 retrievals delivered/yr** from 459 referrals; **11.6% declined**.
- By team: **East ~67%** (270), West 78, South 57 — confirms East is the busiest.
- Genuine ICU-level work: **86% referred from ICU**, 84% arterial line, 70% CVC,
  **51% on vasopressors, 47% sedated/ventilated**; occasional ECMO/IABP; SOFA-scored.
- **Each retrieval commits a team ~4.3 h** (median 4.0; 90th pct 7 h; some 9–15 h) — roughly
  2× a NAS P37 job, due to ~1 h hands-on stabilisation + long distance + ICU handover.
- **99% of referrals arrive in-hours** (08:00–20:00); weekend delivery ~0.45/day vs
  1.4/weekday. The service is structurally invisible at night.

**Implication for the first-pass model:** the broad "additional personnel / special
equipment" P37 proxy (~5,500/yr) was **too wide**. Real MICAS work sits at the very top of
the acuity pyramid, so the demand denominator must be re-anchored.

**Unmet need — now evidenced, not just modelled.** Three supply constraints:

1. **No out-of-hours service (largest gap).** 99% of referrals are in-hours because referrers
   know there is no night team; every night-time critical-care transfer therefore goes to a
   frontline NAS crew and never appears as a MICAS referral. P37 data shows ~half of
   high-acuity transfer demand is 20:00–08:00.
2. **Peak capacity saturation.** Of declines, **~54%+ are supply-side** ("no team available",
   "both teams out", "superseded by a more acute call") — only ~11% are correct clinical
   gatekeeping; 8 explicitly note fallback to "P37 / local / private ambulance". Matches the
   P37 concurrency peak of 9 simultaneous high-acuity jobs vs 3 teams.
3. **Thin weekend cover.** One team (East) nationally at weekends.

**Re-sized reconciliation (annualised):**

| Cohort | Volume |
|---|---|
| MICAS delivered (actual) | ~410–470 |
| MICAS declined for capacity/hours (measured floor) | ~30–55 |
| P37 `37D03` "inappropriate for NAS" (narrowest high-acuity) | ~800 |
| P37 Delta + special equipment (broad ICU proxy) | ~3,700 |
| First-pass "enhanced need" (now considered too wide) | ~5,500 |

MICAS delivers ~**51% of the narrowest** high-acuity band, ~11% of the Delta+equipment proxy,
and ~7% of the broad proxy. **Defensible unmet-need range ≈ 400–1,100 critical-care
transfers/yr** — i.e. MICAS currently meets roughly **one-third to one-half** of genuine
high-acuity demand, constrained by hours (no nights), weekend cover (1 team) and peak capacity
(long jobs + simultaneous referrals). A precise figure needs a clinical inclusion rule applied
to the P37 cohort; the range reflects that the anonymised P37 data cannot see
ventilation/vasopressor status directly.

See workbook tabs **10_MICAS_actual**, **11_Declines_categorised**, **12_Reconciliation**.

---

## Out-of-hours / extra-team recovery model

**Question:** how many additional retrievals would each rota change recover?

**Method.** A discrete-event simulation drives MICAS-appropriate demand (the adult high-acuity
P37 cohort, whose **temporal shape is stable across proxy definitions** — ~47% weekday-day,
~12% weekday-evening, ~14% weekday-night, ~16% weekend-day, ~11% weekend evening/night) through
each rota. Job durations are **resampled from the actual MICAS log (~4.3 h mean)**, teams are
modelled as shift-lines that can overrun, and the result is **calibrated so the current rota
reproduces the actual ~405 retrievals/yr**. Total MICAS-appropriate demand is taken as
~900/yr central, with sensitivity 700–1,100; conclusions are robust across that range.

| Rota option | Served/yr | **Recovered vs now** |
|---|---:|---:|
| **C0 Current** — 3 wkdy / 1 wkend team, 08:00–20:00 | ~405 | — |
| **C1 +Weekend teams** — 3 teams 7 days, 08:00–20:00 | ~440 | **+35** |
| **C2 +Evenings** — 3 teams 7 days, 08:00–24:00 | ~565 | **+161** |
| **C3 24/7** — 3 teams round-the-clock | ~695 | **+291** |
| **C4 24/7 + 4th team** | ~710 | **+303** |

**Findings:**

- **Evenings (C2) are the best value lever: ~+160 retrievals/yr (~40% uplift)** from extending
  the existing three crews' finish to ~midnight — covering the 20:00–24:00 evening peak with
  no new daytime teams.
- **Full 24/7 (C3) ~doubles delivered activity to ~695/yr (+291)**, closing most of the gap;
  the incremental deep-night (00:00–08:00) volume is lower but needs a full night roster.
- **A 4th team adds little volume at current demand (~+12 over C3)** — three round-the-clock
  teams already absorb most concurrent demand. Justify a 4th team on **peak resilience /
  guaranteeing the sickest time-critical cases**, evidenced by the "both teams out" declines —
  and revisit if true demand exceeds ~1,100/yr.
- **Weekend-only uplift (C1) is modest (+35)** because East already covers weekend days; the
  weekend prize is captured within the 24/7 option.

**Priority ladder for a business case:** evenings → full 24/7 → 4th team for resilience.

**Caveats.** Demand denominator is calibrated/estimated (sensitivity shown). Assumes referrers
would refer out-of-hours if a service existed (supported: those transfers currently happen via
NAS at night). Excludes cost, crew fatigue/rest rules, and repatriation logistics. See workbook
tab **13_Recovery_scenarios** and `MICAS_recovery_scenarios.png`.

---

## East expansion — two-tier permutations

The national-pool assumption was refined: **Cork and Galway are effectively regional** (they
decline long-distance calls to avoid shift overruns) and **will not expand** (uneconomic at
their volumes). The realistic expansion is in the **East**, which runs a **two-tier** model:

- **MICAS Acute** (whole team co-located at the NASCCRS base) — runs 2–3 days/week; **fast
  mobilisation and few declines**.
- **Hospital-composite** (EMT ± nurse at base + a doctor ± nurse pulled from a hospital ICU —
  SVUH/BH/MMUH) on the other days — **slower to activate and more likely to decline**.

This two-tier structure is **confirmed in the data**: East mobilisation is bimodal — **52%
≤25 min (Acute) vs 32% ≥45 min (composite; 90th pct 90 min)**, and the "Team Ready <30 min"
KPI is FALSE on ~42% of East jobs. South is uniformly fast (median 20 min), West slower —
consistent with no expansion there.

**Model.** East-only discrete-event simulation; demand = North Leinster adult high-acuity P37;
job durations from the actual MICAS log; two tiers parameterised with different mobilisation,
overrun tolerance and decline propensity. **The absolute baseline is model-sensitive** (the
broad P37 stream is burstier than true ICU-retrieval demand, so a lone team under-serves vs the
real ~270), therefore the **recovery deltas** are reported (robust across parameterisations),
with a ±30% demand range. Cork & Galway are held constant.

| Permutation (on top of current ~270/yr) | **Recovered/yr** | of which evening 20–24 |
|---|---:|---:|
| **P1** Acute every weekday (1 team, 08–20) | **+~24** (19–28) | 0 |
| **P2** P1 + 2nd team **08–20** | +~79 | 0 |
| **P3** P1 + 2nd team **10–22** | +~110 (76–141) | ~9 |
| **P4** P1 + 2nd team **12–00** | **+~130 (92–166)** | ~24 |
| **P5** P1 + 2nd team **12–00, Acute all 5 days** | +~155 (120–180) | ~37 |

**Findings:**

- **Upgrading the first team to Acute every weekday (P1) is a small volume gain (~+24/yr)** but
  its real value is *quality*: faster activation for time-critical cases and fewer declines. It
  is also the foundation for the two-team base model.
- **The second weekday East team is the major lever (~+80–160/yr).**
- **Shift timing is the key decision, and a later shift wins.** An 08–20 second team only adds
  daytime concurrency (no new hours); **10–22 covers the front of the evening (20–22); 12:00–00:00
  covers the whole evening peak (20:00–24:00)** — which is **entirely uncovered today**. Evening
  20:00–24:00 is one of the busiest demand bands (see `MICAS_east_shift_choice.png`), so
  **12:00–00:00 recovers the most and is recommended**; 10–22 is the fallback if a midnight
  finish is impractical, at the cost of the 22:00–24:00 tail. Starting at 12:00 sacrifices little,
  because the first team already covers the 08:00–12:00 morning.

**Recommendation:** (1) make the first East team Acute every weekday; (2) add a second weekday
East team on a **12:00–00:00** shift; (3) staff it as Acute on as many weekdays as feasible —
the "2× Acute base 2–3 days + Acute-plus-hospital-secondary on other days" plan is a sound
phased start. See workbook tab **14_East_permutations** and `MICAS_east_permutations.png`.

**Caveats.** Illustrative *relative* model: absolute volumes carry ±30% demand uncertainty plus
the burstiness caveat above. Tier decline/mobilisation propensities are assumptions anchored to
the observed bimodal mobilisation. Excludes cost and crew-rest rules.

---

## Historical MICAS data (1996–2025) — supply saturation

Four additional historical workbooks (2024 national activity; East/South/West 2025 logs) were
analysed. They **strongly corroborate the supply-constrained thesis** and validate the model
parameters. (These files also retain DOB/age/gender — kept aggregate; not committed.)

**Long-run trend.** National MICAS activity grew from ~23 (1996) and 104 (2016) to a **COVID-19
peak of 469 (2021)**, then **plateaued at ~346–360/yr for four straight years (2022–2025)**. A
flat ceiling for four years — while **~23% of referrals are declined** and "no-service" days are
logged — is the signature of a service capped by *supply*, not demand. See
`MICAS_longrun_trend.png`.

**2024 detail (national):**

| Outcome 2024 | Count |
|---|---:|
| Transferred (delivered) | **360** |
| **Declined** | **107 (~23% of referrals)** |
| Deferred / Stood down / Not transferred | ~21 |

| Team 2024 | Transfers | Share | YoY |
|---|---:|---:|---:|
| East (Dublin) | 214 | 59% | +8.6% |
| West (Galway) | 83 | 23% | +10.7% |
| South (Cork) | 63 | 18% | **−25%** |

**Small-team fragility.** The Staff-restrictions log shows repeated **whole-day "no service"**
events from single absences — South "no consultant" (≈8 days), West "nurse ill" / "no doctor" /
"ambulance breakdown". This explains South's −25% (a *supply* contraction, not falling demand)
and confirms that thin single-team regional cover is fragile — reinforcing **no South/West
expansion** and favouring **resilience/redundancy in the East** (the second-team plan).

**Parameter validation (2025 team logs).** Confirms the modelling assumptions:

- **100% of retrievals ventilated** — MICAS is unambiguously top-of-pyramid critical care.
- **Job commitment** medians: East 3.3 h, South 4.4 h, **West 5.6 h** (rural/long-distance) —
  brackets the ~4.3 h used in the recovery models.
- **Mobilisation** confirms the two-tier East structure: East **bimodal** (median 30 min, long
  tail), South fast (15 min, co-located), West slow (38 min). South/West are single-tier.

**Reconciliation.** The canonical *delivered* figure is **~356–360/yr (calendar)**; the earlier
~405 (from the rolling 12-month anonymised export) was a window/counting artefact. The headline
unmet-need picture is unchanged — if anything strengthened: with **107 declines/yr measured in
2024 alone** (mostly capacity/overrun, same pattern as the 2026 log) *before* counting the
invisible out-of-hours demand, the recovery estimates (e.g. ~+130/yr from a second East team)
are well within the demonstrated gap. Workbook tabs **15_Historical_trend**,
**16_Team_split_decline**; charts `MICAS_longrun_trend.png`, `MICAS_team_split.png`.
