###############################################################################
## MICAS Unmet-Need Analysis — full analytical pipeline in R
## -----------------------------------------------------------------------------
## Reproduces the demand (NAS Protocol 37) analysis, the MICAS activity
## reconciliation, the historical supply-saturation trend, the hospital
## crosswalk corridor/distance work, and the PREDICTION MODELS:
##    (A) demand/activity forecast        (forecast::ets / auto.arima)
##    (B) job-duration model              (lm + mgcv::gam on distance)
##    (C) decline-risk model              (logistic glm)
##    (D) national rota capacity sim      (discrete-event)
##    (E) East two-tier expansion sim     (discrete-event, MICAS Acute vs hospital)
##
## All figures are written to OUTPUT_DIR as high-resolution PNGs, and key
## tables to a results workbook.
##
## ---------------------------------------------------------------------------
## REQUIRED INPUT FILES  (place in DATA_DIR; rename to these or edit paths)
##   p37_file   : anon_analys.xlsx              sheet "All transfers to date 2026"
##   micas_csv  : MICAS_anon.csv                actual MICAS retrieval log
##   hist_file  : MICAS_Activity_2024.xlsx      sheets "2016-2024","Monthly","Staff restrictions"
##   east_file  : MICAS_East_data_2025.xlsx     sheet "Data "
##   south_file : MICAS_SOUTH.xlsx              sheet "Data Input"
##   west_file  : MICAS_Westdata_June2025.xlsx  sheet "Data Input"
##   xwalk_file : Hospital_Reference.xlsx        code -> name + lat/long
##
## OPTIONAL (improve the maps — see notes at the MAP section):
##   * Internet access on first run so {rnaturalearth} can fetch the coastline,
##     OR an Ireland boundary shapefile/GeoJSON placed at BOUNDARY_FILE.
##   * An Ireland RHA / county boundary file (GeoJSON) for a demand choropleth.
##   * (nice-to-have) CSO population by county/RHA for per-capita demand rates;
##     a hospital "Model 2/3/4" lookup to colour spokes vs hubs.
###############################################################################

## ----------------------------- 0. SETUP ------------------------------------
## (tidyverse components listed individually so a partial install doesn't force
##  a heavy meta-package build; `library(tidyverse)` would also work.)
needed <- c("dplyr","tidyr","readr","purrr","stringr","tibble","ggplot2",
            "readxl","lubridate","scales","patchwork","ggrepel","viridis",
            "forecast","mgcv","broom","writexl")
to_install <- setdiff(needed, rownames(installed.packages()))
if (length(to_install)) install.packages(to_install, repos = "https://cloud.r-project.org")
invisible(lapply(needed, require, character.only = TRUE))

## spatial packages are optional (need system GDAL/GEOS/PROJ). The script
## degrades gracefully to a coordinate-only map if they are unavailable.
HAVE_SF <- requireNamespace("sf", quietly = TRUE) &&
           requireNamespace("rnaturalearth", quietly = TRUE)

set.seed(42)

DATA_DIR    <- "data"        # <-- folder holding the input files
OUTPUT_DIR  <- "outputs"     # figures + results land here
BOUNDARY_FILE <- file.path(DATA_DIR, "ireland_boundary.geojson")  # optional
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

paths <- list(
  p37   = file.path(DATA_DIR, "anon_analys.xlsx"),
  micas = file.path(DATA_DIR, "MICAS_anon.csv"),
  hist  = file.path(DATA_DIR, "MICAS_Activity_2024.xlsx"),
  east  = file.path(DATA_DIR, "MICAS_East_data_2025.xlsx"),
  south = file.path(DATA_DIR, "MICAS_SOUTH.xlsx"),
  west  = file.path(DATA_DIR, "MICAS_Westdata_June2025.xlsx"),
  xwalk = file.path(DATA_DIR, "Hospital_Reference.xlsx")
)
ANNUALISE <- 52 / 17   # P37 sample is 17 weeks of 2026

## ---- house style ----
theme_micas <- function(base = 12) {
  theme_minimal(base_size = base) +
    theme(plot.title    = element_text(face = "bold"),
          plot.subtitle = element_text(colour = "grey30"),
          panel.grid.minor = element_blank(),
          legend.position = "top")
}
pal_team <- c(East = "#1f6f8b", West = "#e0a030", South = "#c0392b")
save_fig <- function(p, file, w = 10, h = 6, dpi = 160)
  ggsave(file.path(OUTPUT_DIR, file), p, width = w, height = h, dpi = dpi, bg = "white")

## ---- helpers ----------------------------------------------------------------
# pick a column by regex (robust to readxl's de-duplicating suffixes)
gcol <- function(df, pattern) {
  i <- grep(pattern, names(df))
  if (!length(i)) return(rep(NA, nrow(df)))
  df[[i[1]]]
}
# convert an Excel time-ish value to seconds-of-day (handles POSIXct / hms /
# numeric Excel fraction / "HH:MM[:SS]" strings)
to_secs <- function(x) {
  if (inherits(x, c("hms","difftime"))) return(as.numeric(x, units = "secs"))
  if (inherits(x, "POSIXct")) return(hour(x)*3600 + minute(x)*60 + second(x))
  if (is.numeric(x)) return(ifelse(x <= 1.0001, x*86400, NA_real_))
  x <- as.character(x)
  m3 <- str_match(x, "^(\\d{1,2}):(\\d{2}):(\\d{2})")
  m2 <- str_match(x, "^(\\d{1,2}):(\\d{2})$")
  out <- rep(NA_real_, length(x))
  ok3 <- !is.na(m3[,1]); out[ok3] <- as.numeric(m3[ok3,2])*3600+as.numeric(m3[ok3,3])*60+as.numeric(m3[ok3,4])
  ok2 <- is.na(out) & !is.na(m2[,1]); out[ok2] <- as.numeric(m2[ok2,2])*3600+as.numeric(m2[ok2,3])*60
  out
}
# minutes-of-day from a MICAS time / datetime cell
to_min <- function(x) {
  s <- to_secs(x)
  bad <- is.na(s)
  if (any(bad)) {                       # try dd/mm/YYYY HH:MM
    dt <- suppressWarnings(dmy_hm(as.character(x[bad])))
    s[bad] <- hour(dt)*3600 + minute(dt)*60
  }
  s/60
}
haversine <- function(lat1, lon1, lat2, lon2) {        # km, vectorised
  R <- 6371; tr <- pi/180
  dlat <- (lat2-lat1)*tr; dlon <- (lon2-lon1)*tr
  a <- sin(dlat/2)^2 + cos(lat1*tr)*cos(lat2*tr)*sin(dlon/2)^2
  2*R*asin(pmin(1, sqrt(a)))
}

results <- list()   # collect tables for the results workbook

###############################################################################
## 1. NAS PROTOCOL 37 DEMAND  --------------------------------------------------
###############################################################################
if (file.exists(paths$p37)) {
  p37 <- read_excel(paths$p37, sheet = "All transfers to date 2026",
                    .name_repair = "unique")

  d <- tibble(
    code     = as.character(gcol(p37, "^Despatch Code/Disposition$")),
    desc     = as.character(gcol(p37, "^Despatch Code/Disposition Description")),
    prompt   = as.character(gcol(p37, "Despatch Prompt")),
    letter   = as.character(gcol(p37, "^Despatch Code Letter")),
    pickup   = as.character(gcol(p37, "^Pickup Hospital")),
    dest     = as.character(gcol(p37, "^Hospital Attended by Resource")),
    ward_d   = as.character(gcol(p37, "^Clinic/Ward Attended by Resource")),
    ward_p   = as.character(gcol(p37, "^Pickup Clinic/Ward")),
    division = as.character(gcol(p37, "^Despatch Point Division")),
    rha      = as.character(gcol(p37, "REGIONAL HEALTH AREA")),
    hour     = suppressWarnings(as.numeric(gcol(p37, "^Hour Call Taking Commenced"))),
    dow      = as.character(gcol(p37, "^Day of Week when Call Taking")),
    date     = as.Date(gcol(p37, "^Date Call Taking Commenced")),
    oop      = as.character(gcol(p37, "^Out of Performance: Reason")),
    clock    = to_secs(gcol(p37, "Time of Call for Performance")),
    clear    = to_secs(gcol(p37, "^Time Resource Clear or Stood Down"))
  ) |>
    filter(str_starts(replace_na(code,""), "37")) |>            # true Protocol 37
    mutate(
      needs_pers = str_detect(replace_na(desc,""), regex("Additional personnel", TRUE)),
      needs_equip= str_detect(replace_na(desc,""), regex("Special equipment", TRUE)),
      enhanced   = needs_pers | needs_equip,
      resource_need = case_when(needs_pers & needs_equip ~ "Both pers. & equip.",
                                needs_pers ~ "Additional personnel",
                                needs_equip ~ "Special equipment",
                                TRUE ~ "None (base)"),
      paed = str_detect(toupper(paste(dest,pickup,ward_d,ward_p)),
                        "CRUMLIN|TEMPLE ST|CHILDREN|PAEDIATR|NICU|NEONAT|SCBU"),
      mat  = str_detect(toupper(paste(dest,pickup,ward_d,ward_p)),
                        "HOLLES STREET|ROTUNDA|COOMBE|MATERNITY|OBSTETRIC|LABOUR"),
      patient = case_when(paed ~ "Paediatric/Neonatal", mat ~ "Maternity", TRUE ~ "Adult"),
      adult   = patient == "Adult",
      cycle_min = ifelse((clear-clock) >= 0, (clear-clock)/60, NA_real_),
      tod_bin = case_when(hour >= 8 & hour < 20 ~ "Day 08-20",
                          hour >= 20 ~ "Evening 20-24", TRUE ~ "Night 00-08"),
      weekend = dow %in% c("Sat","Sun"),
      rha_lab = recode(rha,
        "AREA A"="A: Dublin & NE","AREA B"="B: Dublin & Mid","AREA C"="C: Dublin & SE",
        "AREA D"="D: South West","AREA E"="E: Mid-West","AREA F"="F: West & NW")
    )

  ## --- demand funnel
  funnel <- tibble(
    Cohort = c("All Protocol 37","Delta acuity","IMMEDIATE from TOC","Enhanced need",
               "Adult","Adult + enhanced (MICAS-ish)","Adult + enhanced + Delta"),
    n = c(nrow(d), sum(d$letter=="D",na.rm=TRUE),
          sum(str_detect(replace_na(d$prompt,""),"IMMEDIATE")),
          sum(d$enhanced), sum(d$adult), sum(d$adult & d$enhanced),
          sum(d$adult & d$enhanced & d$letter=="D", na.rm=TRUE))) |>
    mutate(annualised = round(n*ANNUALISE))
  results$p37_funnel <- funnel

  ## --- FIGURE: acuity x resource need heatmap
  hx <- d |> filter(!is.na(letter)) |> count(letter, resource_need)
  p_heat <- ggplot(hx, aes(resource_need, letter, fill = n)) +
    geom_tile(colour = "white") +
    geom_text(aes(label = n), colour = "white", fontface = "bold") +
    scale_fill_viridis_c(option = "rocket", direction = -1) +
    labs(title = "Protocol 37 demand: acuity x clinical complexity",
         subtitle = "Delta (D) + special equipment/personnel = the MICAS-appropriate quadrant",
         x = "AMPDS resource qualifier", y = "Determinant (D>C>B)", fill = "transfers") +
    theme_micas()
  save_fig(p_heat, "01_p37_acuity_need.png", 9, 5)

  ## --- FIGURE: demand by day x hour heatmap (adult + enhanced)
  dh <- d |> filter(adult, enhanced, !is.na(hour)) |>
    mutate(dow = factor(dow, levels = c("Mon","Tue","Wed","Thu","Fri","Sat","Sun"))) |>
    count(dow, hour)
  p_dh <- ggplot(dh, aes(hour, dow, fill = n)) +
    geom_tile() +
    annotate("rect", xmin = 7.5, xmax = 19.5, ymin = 0.5, ymax = 7.5,
             fill = NA, colour = "black", linewidth = .7) +
    scale_fill_viridis_c(option = "mako", direction = -1) +
    scale_x_continuous(breaks = seq(0,23,2)) +
    labs(title = "Adult high-acuity P37 demand by day & hour",
         subtitle = "Box = current 08:00-20:00 MICAS window; heavy demand spills into evening/night",
         x = "Hour of call", y = NULL, fill = "transfers (17 wk)") +
    theme_micas()
  save_fig(p_dh, "02_p37_day_hour.png", 11, 4.5)

  ## --- FIGURE: out-of-hours split + ambulance-hours headline
  oohs <- d |> count(tod_bin) |> mutate(pct = n/sum(n))
  amb_hours <- sum(d$cycle_min, na.rm = TRUE)/60
  p_ooh <- ggplot(oohs, aes(reorder(tod_bin, -n), n, fill = tod_bin)) +
    geom_col(show.legend = FALSE) +
    geom_text(aes(label = percent(pct, 1)), vjust = -0.4) +
    scale_fill_manual(values = c("Day 08-20"="#1f6f8b","Evening 20-24"="#e0a030","Night 00-08"="#c0392b")) +
    labs(title = "When P37 transfers happen",
         subtitle = sprintf("~%s emergency ambulance-hours consumed over 17 wks (~%s/yr). ~49%% are out-of-hours.",
                            comma(round(amb_hours)), comma(round(amb_hours*ANNUALISE))),
         x = NULL, y = "transfers (17 wk)") +
    theme_micas()
  save_fig(p_ooh, "03_p37_out_of_hours.png", 8, 5)

  message("P37 demand: ", nrow(d), " records; ambulance-hours ~", round(amb_hours))
} else message("** P37 file not found - skipping demand section **")

###############################################################################
## 2. MICAS ACTIVITY (anon log) + CROSSWALK + DISTANCES ------------------------
###############################################################################
if (file.exists(paths$micas) && file.exists(paths$xwalk)) {

  xw_raw <- read_excel(paths$xwalk)
  xw <- tibble(code = str_trim(as.character(xw_raw[[grep("Code", names(xw_raw))[1]]])),
               name = as.character(xw_raw[[grep("Name", names(xw_raw))[1]]]),
               lat  = as.numeric(xw_raw[[grep("Lat",  names(xw_raw))[1]]]),
               lon  = as.numeric(xw_raw[[grep("Lon",  names(xw_raw))[1]]]))
  coord <- xw |> select(code, lat, lon)

  m <- suppressWarnings(read_csv(paths$micas, show_col_types = FALSE,
                                 name_repair = "unique"))   # repairs empty/dup headers
  names(m) <- str_replace_all(names(m), "\\ufeff", "")      # strip BOM (base assign)
  # tolerant column getters (names vary slightly across exports)
  getc <- function(df, pat) df[[ grep(pat, names(df), ignore.case = TRUE)[1] ]]
  mic <- tibble(
    dt    = dmy_hm(getc(m, "^Date and Time")),
    team  = str_trim(getc(m, "Assigned MICAS Team")),
    decision = str_trim(getc(m, "^Accept/Decline")),
    decl_reason = str_trim(getc(m, "If Declined")),
    ref_dep = getc(m, "Referring department"),
    rec_dep = getc(m, "Receiving Department"),
    vaso  = toupper(str_trim(getc(m, "^Vasopressors"))),
    sed   = toupper(str_trim(getc(m, "Sedated/Paralysed"))),
    aline = toupper(str_trim(getc(m, "Arterial Line"))),
    rf    = str_trim(getc(m, "Referring Hospital")),
    rc    = str_trim(getc(m, "Receiving Hospital")),
    t_call = to_min(getc(m, "Ambulance Called")),
    t_depbase = to_min(getc(m, "Ambulance Departed Hospital")),
    t_deprec  = to_min(getc(m, "Departed Receiving Hospital"))
  ) |>
    mutate(
      accepted = str_detect(replace_na(decision,""), regex("^accept", TRUE)),
      declined = str_detect(replace_na(decision,""), regex("^decline", TRUE)),
      hour = hour(dt), wkday = wday(dt, week_start = 1),
      weekend = wkday %in% c(6,7),
      mobilise_min = { x <- t_depbase - t_call; ifelse(x < 0, x + 1440, x) },
      job_min      = { x <- t_deprec  - t_call; ifelse(x < 0, x + 1440, x) },
      job_h = ifelse(job_min >= 30 & job_min <= 900, job_min/60, NA_real_)
    ) |>
    left_join(coord |> rename(rf=code, rf_lat=lat, rf_lon=lon), by="rf") |>
    left_join(coord |> rename(rc=code, rc_lat=lat, rc_lon=lon), by="rc") |>
    mutate(dist_km = haversine(rf_lat, rf_lon, rc_lat, rc_lon))

  acc <- filter(mic, accepted)

  ## --- reconciliation / clinical profile / decline split
  decline_rate <- mean(mic$declined[mic$accepted|mic$declined], na.rm=TRUE)
  clin <- tibble(metric = c("Delivered (rows)","Decline rate",
                            "From ICU %","Vasopressors %","Sedated/ventilated %","Art line %",
                            "Mean job (h)","Mean mobilise (min)"),
                 value = c(sum(mic$accepted),
                           round(decline_rate*100,1),
                           round(mean(str_detect(toupper(replace_na(acc$ref_dep,"")),"INTENSIVE"))*100),
                           round(mean(acc$vaso=="TRUE",na.rm=TRUE)*100),
                           round(mean(acc$sed=="TRUE",na.rm=TRUE)*100),
                           round(mean(acc$aline=="TRUE",na.rm=TRUE)*100),
                           round(mean(acc$job_h,na.rm=TRUE),1),
                           round(median(acc$mobilise_min,na.rm=TRUE))))
  results$micas_profile <- clin

  ## --- FIGURE: mobilisation bimodality by team (the two-tier signal)
  p_mob <- acc |> filter(!is.na(mobilise_min), mobilise_min <= 150,
                         team %in% c("East","West","South")) |>
    ggplot(aes(mobilise_min, fill = team)) +
    geom_histogram(binwidth = 5, colour = "white") +
    geom_vline(xintercept = 25, linetype = 2, colour = "grey40") +
    facet_wrap(~team, ncol = 1, scales = "free_y") +
    scale_fill_manual(values = pal_team, guide = "none") +
    labs(title = "Mobilisation time confirms the East two-tier model",
         subtitle = "East is bimodal (co-located MICAS Acute ~<=25 min vs hospital-composite ~>=45 min); South fast, West slow",
         x = "Mobilisation: call -> depart base (min)", y = "retrievals") +
    theme_micas()
  save_fig(p_mob, "04_micas_mobilisation.png", 8, 7)

  ## --- FIGURE: decline reasons categorised
  cat_decl <- mic |> filter(declined) |>
    mutate(cat = case_when(
      str_detect(tolower(replace_na(decl_reason,"")),
                 "no team|already|simultaneous|superseded|both out|no south|no micas|en route|stacked") ~ "No team available (capacity)",
      str_detect(tolower(replace_na(decl_reason,"")),
                 "out of hours|overrun|past midnight|too late|finish|operating hours|service hours") ~ "Out-of-hours / overrun",
      str_detect(tolower(replace_na(decl_reason,"")),
                 "no critical care|not need|wardable|not an icu|stable") ~ "Clinically not appropriate",
      replace_na(decl_reason,"")=="" ~ "No reason recorded",
      TRUE ~ "Other")) |>
    count(cat) |> arrange(n)
  p_decl <- ggplot(cat_decl, aes(reorder(cat,n), n, fill = cat)) +
    geom_col(show.legend = FALSE) + coord_flip() +
    scale_fill_viridis_d(option="turbo", end=.85) +
    labs(title = "Why MICAS declines (≈ measured unmet need)",
         subtitle = "Capacity/hours dominate; clinical gatekeeping is the minority",
         x = NULL, y = "declined referrals") +
    theme_micas()
  save_fig(p_decl, "05_micas_declines.png", 8, 4.5)

  ## --- FIGURE: distance by team
  p_dist <- acc |> filter(!is.na(dist_km), team %in% c("East","West","South")) |>
    ggplot(aes(team, dist_km, fill = team)) +
    geom_boxplot(alpha=.85, outlier.alpha=.3) +
    scale_fill_manual(values = pal_team, guide="none") +
    labs(title = "Transfer distance by team",
         subtitle = "West runs far longer legs (median ~118 km) -> longer jobs, more overrun declines",
         x = NULL, y = "one-way distance (km)") +
    theme_micas()
  save_fig(p_dist, "06_distance_by_team.png", 7, 5)

  message("MICAS: ", sum(mic$accepted), " accepted, decline rate ",
          round(decline_rate*100,1), "%")
} else message("** MICAS log or crosswalk missing - skipping MICAS/crosswalk section **")

###############################################################################
## 3. HISTORICAL TREND (supply saturation) ------------------------------------
###############################################################################
if (file.exists(paths$hist)) {
  tr <- read_excel(paths$hist, sheet = "2016-2024", col_names = FALSE)
  yr_row <- which(apply(tr, 1, function(r) sum(grepl("^(199|200|201|202)\\d", r)) > 5))[1]
  yrs <- suppressWarnings(as.integer(unlist(tr[yr_row, -1])))
  vals<- suppressWarnings(as.numeric(unlist(tr[yr_row+1, -1])))
  annual <- tibble(year = yrs, transfers = vals) |> filter(!is.na(year), !is.na(transfers))
  annual <- bind_rows(annual, tibble(year = 2025, transfers = 356)) |>
            distinct(year, .keep_all = TRUE) |> arrange(year)
  results$annual_trend <- annual

  p_trend <- ggplot(annual, aes(year, transfers)) +
    geom_col(aes(fill = case_when(year==2021~"covid",
                                  year>=2022~"plateau", TRUE~"growth"))) +
    scale_fill_manual(values=c(covid="#c0392b",plateau="#e0a030",growth="#1f6f8b"), guide="none") +
    annotate("text", x=2021, y=max(annual$transfers)+18, label="COVID surge (469)",
             colour="#c0392b", fontface="bold", size=3.3) +
    annotate("text", x=2023.5, y=210,
             label="4-yr plateau ~356/yr\n(supply ceiling; ~23% declined)",
             colour="#9a6a00", fontface="bold", size=3.3) +
    scale_x_continuous(breaks=seq(1996,2026,2)) +
    labs(title="MICAS national activity 1996-2025: growth -> COVID peak -> plateau",
         subtitle="A 4-year flat ceiling while ~23% of referrals are declined = supply-capped, not demand-capped",
         x=NULL, y="transfers / year") +
    theme_micas() + theme(axis.text.x = element_text(angle=45, hjust=1))
  save_fig(p_trend, "07_historical_trend.png", 11, 5.2)

  ## team split 2023 vs 2024 (from the Monthly summary, hard-coded from sheet)
  split <- tibble(team=c("East","West","South"),
                  `2023`=c(197,75,84), `2024`=c(214,83,63)) |>
    pivot_longer(-team, names_to="year", values_to="n")
  p_split <- ggplot(split, aes(team, n, fill=year)) +
    geom_col(position="dodge") +
    scale_fill_manual(values=c(`2023`="#9bbfc9", `2024`="#1f6f8b")) +
    labs(title="MICAS by team, 2023 -> 2024",
         subtitle="South -25% from repeated 'no consultant' no-service days (small-team fragility)",
         x=NULL, y="transfers / year") + theme_micas()
  save_fig(p_split, "08_team_split.png", 7.5, 5)
  message("Historical trend loaded: ", nrow(annual), " years")
} else message("** Historical file missing - skipping trend section **")

###############################################################################
## 4. PREDICTION MODELS --------------------------------------------------------
###############################################################################

## ---- (A) Activity forecast (delivered activity is supply-capped) ----
if (exists("annual")) {
  fit_ets <- ets(ts(annual$transfers, start = min(annual$year)))
  fc <- forecast(fit_ets, h = 3)
  fc_df <- tibble(year = max(annual$year) + 1:3,
                  mean = as.numeric(fc$mean),
                  lo = as.numeric(fc$lower[,2]), hi = as.numeric(fc$upper[,2]))
  results$forecast <- fc_df
  p_fc <- ggplot() +
    geom_col(data=annual, aes(year, transfers), fill="#1f6f8b") +
    geom_ribbon(data=fc_df, aes(year, ymin=lo, ymax=hi), fill="#e0a030", alpha=.3) +
    geom_line(data=fc_df, aes(year, mean), colour="#9a6a00", linewidth=1) +
    geom_point(data=fc_df, aes(year, mean), colour="#9a6a00") +
    labs(title="Forecast of DELIVERED MICAS activity (ETS)",
         subtitle="Flat at the supply ceiling absent capacity change - the scenario models below show what expansion unlocks",
         x=NULL, y="transfers / year") + theme_micas()
  save_fig(p_fc, "09_forecast.png", 9, 5)
}

## ---- (B) Job-duration model: duration ~ distance (+ team) ----
if (exists("acc")) {
  dd <- acc |> filter(!is.na(job_h), !is.na(dist_km))
  lm_dur <- lm(job_h ~ dist_km, data = dd)
  gam_dur <- mgcv::gam(job_h ~ s(dist_km, k = 6), data = dd)
  results$duration_model <- broom::glance(lm_dur) |> mutate(model="lm job_h~dist")
  grid <- tibble(dist_km = seq(0, max(dd$dist_km, na.rm=TRUE), length.out = 100))
  grid$pred <- predict(gam_dur, grid)
  p_dur <- ggplot(dd, aes(dist_km, job_h)) +
    geom_point(alpha=.35, colour="#1f6f8b") +
    geom_line(data=grid, aes(dist_km, pred), colour="#c0392b", linewidth=1.1) +
    labs(title="Job-duration prediction model",
         subtitle=sprintf("Distance explains job length (lm R2 = %.2f). 0-50km ~3.3h; 150km+ ~6.4h - the overrun driver.",
                          summary(lm_dur)$r.squared),
         x="one-way distance (km)", y="team commitment (h)") + theme_micas()
  save_fig(p_dur, "10_duration_model.png", 8.5, 5)
  # empirical duration sample used by the simulations below
  dur_sample <- pmin(dd$job_h, 9)
} else dur_sample <- rgamma(500, shape = 4, rate = 1)  # fallback ~4h jobs

## ---- (C) Decline-risk model: logistic ----
if (exists("mic")) {
  md <- mic |> filter(accepted | declined) |>
    transmute(declined = as.integer(declined),
              hour, weekend = as.integer(weekend),
              team = factor(team), dist_km) |>
    filter(!is.na(hour))
  glm_decl <- glm(declined ~ hour + weekend + team, family = binomial, data = md)
  results$decline_model <- broom::tidy(glm_decl, exponentiate = TRUE) |>
    mutate(across(where(is.numeric), ~round(.x, 3)))
  newd <- expand_grid(hour = 8:20, weekend = 0, team = "East") |> mutate(team=factor(team, levels=levels(md$team)))
  newd$p <- predict(glm_decl, newd, type = "response")
  p_glm <- ggplot(newd, aes(hour, p)) + geom_line(colour="#c0392b", linewidth=1) +
    scale_y_continuous(labels = percent) +
    labs(title="Decline-risk model (logistic): P(decline) by hour, East weekday",
         subtitle="Risk climbs through the day as teams get committed - quantifies the capacity squeeze",
         x="hour of referral", y="predicted P(decline)") + theme_micas()
  save_fig(p_glm, "11_decline_model.png", 8, 5)
}

## ---- discrete-event capacity simulator (shared by D & E) ----
## teams: list of list(days=<ints 1=Mon..7=Sun>, h0, h1, tier)
## tiers: Acute / Comp / Plain (mobilisation, overrun tolerance, base decline)
TIERS <- list(Acute=list(mob=0.37,tol=2.0,pdec=0.03),
              Comp =list(mob=0.90,tol=1.0,pdec=0.12),
              Plain=list(mob=0.50,tol=1.5,pdec=0.05))
simulate_service <- function(starts, teams, n_target, durations, n_runs = 25,
                             weeks = 17, two_tier = FALSE) {
  N <- length(starts); ann <- 52/weeks
  served <- evening <- numeric(n_runs)
  for (r in seq_len(n_runs)) {
    idx <- sort(sample.int(N, min(n_target, N)))
    ev  <- starts[idx]
    free <- rep(min(ev) - 3*3600, length(teams))   # numeric seconds
    s <- 0; se <- 0
    evn <- as.numeric(ev)
    wd  <- wday(ev, week_start = 1); hh <- hour(ev) + minute(ev)/60
    dnum<- as.numeric(as.Date(ev))                 # day index for shift-end
    for (i in seq_along(evn)) {
      t <- evn[i]; cand <- NA_integer_; cand_free <- Inf
      dh <- sample(durations, 1)
      for (k in seq_along(teams)) {
        T <- teams[[k]]
        if (!(wd[i] %in% T$days)) next
        if (!(hh[i] >= T$h0 && hh[i] < T$h1)) next
        if (free[k] > t) next
        if (two_tier) {
          p <- TIERS[[T$tier]]
          finish <- t + (p$mob + dh + 0.4)*3600
          shift_end <- dnum[i]*86400 + T$h1*3600
          if (finish > shift_end + p$tol*3600) next
          if (runif(1) < p$pdec) next
        }
        if (free[k] < cand_free) { cand <- k; cand_free <- free[k] }
      }
      if (!is.na(cand)) {
        free[cand] <- t + dh*3600; s <- s + 1
        if (hh[i] >= 20 && hh[i] < 24) se <- se + 1
      }
    }
    served[r] <- s * ann; evening[r] <- se * ann
  }
  list(served = mean(served), evening = mean(evening))
}

## ---- (D) National rota recovery model ----
if (exists("d")) {
  ev_nat <- d |> filter(adult, enhanced, !is.na(date), !is.na(clock)) |>
    mutate(start = as.POSIXct(date) + clock) |> pull(start)
  ALL <- 1:7; WD <- 1:5; WE <- 6:7
  cfg <- list(
    `C0 Current (3 wkdy/1 wkend, 08-20)` = c(rep(list(list(days=WD,h0=8,h1=20)),3), list(list(days=WE,h0=8,h1=20))),
    `C1 +Weekend (3 teams 7d, 08-20)`    = rep(list(list(days=ALL,h0=8,h1=20)),3),
    `C2 +Evenings (3 teams, 08-24)`      = rep(list(list(days=ALL,h0=8,h1=24)),3),
    `C3 24/7 (3 teams)`                  = rep(list(list(days=ALL,h0=0,h1=24)),3),
    `C4 24/7 + 4th team`                 = rep(list(list(days=ALL,h0=0,h1=24)),4))
  D_NAT <- 900                                   # central addressable demand/yr
  nat <- imap_dfr(cfg, ~{
    r <- simulate_service(ev_nat, .x, round(D_NAT*17/52), dur_sample, n_runs = 25)
    tibble(scenario = .y, served = round(r$served))
  }) |> mutate(recovered = served - served[1])
  results$national_recovery <- nat
  p_nat <- ggplot(nat, aes(reorder(scenario, served), served)) +
    geom_col(fill = "#1f6f8b") +
    geom_text(aes(label = ifelse(recovered>0, paste0("+",recovered), "baseline")),
              hjust = -0.1) +
    coord_flip(clip="off") + expand_limits(y = max(nat$served)*1.15) +
    labs(title="National rota recovery model (discrete-event)",
         subtitle="Served retrievals/yr by configuration (demand ~900/yr; calibrate to local figures)",
         x=NULL, y="served / year") + theme_micas()
  save_fig(p_nat, "12_national_recovery.png", 9.5, 5)
}

## ---- (E) East two-tier expansion model ----
if (exists("d")) {
  ev_east <- d |> filter(division=="NORTH LEINSTER", adult, enhanced, !is.na(date), !is.na(clock)) |>
    mutate(start = as.POSIXct(date) + clock) |> pull(start)
  WD <- 1:5; WE <- 6:7
  acute_wd <- function(n_acute) {  # T1 weekday tiers: n_acute Acute days, rest Comp
    days <- sample(WD); set_names(ifelse(seq_len(5) <= n_acute, "Acute","Comp"), days)
  }
  mk_east <- function(second = NULL) {              # build a team list
    t1 <- lapply(WD, function(w) list(days=w, h0=8, h1=20, tier="Acute")) # P1: Acute all wkdy
    t1 <- c(t1, list(list(days=6, h0=8, h1=20, tier="Comp")),
                list(list(days=7, h0=8, h1=20, tier="Comp")))
    if (!is.null(second)) t1 <- c(t1, second)
    t1
  }
  t2 <- function(h0,h1,tier="Acute") lapply(WD, function(w) list(days=w,h0=h0,h1=h1,tier=tier))
  east_cfg <- list(
    `P0 Baseline`            = c(lapply(1:3,function(w) list(days=w,h0=8,h1=20,tier="Acute")),
                                 lapply(4:5,function(w) list(days=w,h0=8,h1=20,tier="Comp")),
                                 list(list(days=6,h0=8,h1=20,tier="Comp")),
                                 list(list(days=7,h0=8,h1=20,tier="Comp"))),
    `P1 Acute all weekday`   = mk_east(),
    `P2 +2nd team 08-20`     = mk_east(t2(8,20)),
    `P3 +2nd team 10-22`     = mk_east(t2(10,22)),
    `P4 +2nd team 12-00`     = mk_east(t2(12,24)))
  ## D_EAST is a CALIBRATION KNOB. The absolute baseline is model-sensitive
  ## (the P37 proxy is burstier than true MICAS demand, so a lone team under-
  ## serves) -> interpret the RECOVERED deltas and the evening column, not the
  ## absolute 'served'. Raise n_runs and tune D_EAST to reproduce your local
  ## delivered East baseline before quoting absolute numbers.
  D_EAST <- 520
  east <- imap_dfr(east_cfg, ~{
    r <- simulate_service(ev_east, .x, round(D_EAST*17/52), dur_sample, n_runs = 30, two_tier = TRUE)
    tibble(scenario = .y, served = round(r$served), evening = round(r$evening))
  }) |> mutate(recovered = served - served[1])
  results$east_permutations <- east
  p_east <- ggplot(east, aes(scenario, served)) +
    geom_col(fill = "#155f7a") +
    geom_text(aes(label = ifelse(recovered>0, paste0("+",recovered," (eve ",evening,")"), "baseline")), vjust=-0.4) +
    labs(title="East two-tier expansion permutations",
         subtitle="A 2nd team on a 12:00-00:00 shift recovers most AND uniquely covers the evening peak",
         x=NULL, y="East served / year") +
    theme_micas() + theme(axis.text.x = element_text(angle=20, hjust=1))
  save_fig(p_east, "13_east_permutations.png", 10, 5.5)
}

###############################################################################
## 5. THE FLOW MAP (most useful visual) ---------------------------------------
###############################################################################
if (exists("acc")) {
  flows <- acc |> filter(!is.na(rf_lat), !is.na(rc_lat)) |>
    count(rf, rc, rf_lat, rf_lon, rc_lat, rc_lon, name = "n") |>
    mutate(dist_km = haversine(rf_lat, rf_lon, rc_lat, rc_lon)) |>
    arrange(desc(n))
  hubs <- acc |> count(rc, rc_lat, rc_lon, name="vol") |> arrange(desc(vol)) |>
    left_join(xw |> select(rc=code, name), by="rc")

  base_layer <- NULL
  if (HAVE_SF) {
    library(sf)
    ie <- tryCatch(
      rnaturalearth::ne_countries(country = c("Ireland","United Kingdom"),
                                  scale = "large", returnclass = "sf"),
      error = function(e) NULL)
    if (is.null(ie) && file.exists(BOUNDARY_FILE)) ie <- st_read(BOUNDARY_FILE, quiet = TRUE)
    if (!is.null(ie)) base_layer <- geom_sf(data = ie, fill = "grey96", colour = "grey75", inherit.aes = FALSE)
  }

  p_map <- ggplot() +
    { if (!is.null(base_layer)) base_layer } +
    geom_curve(data = head(flows, 40),
               aes(x = rf_lon, y = rf_lat, xend = rc_lon, yend = rc_lat,
                   linewidth = n, colour = dist_km),
               curvature = 0.18, alpha = 0.75, lineend = "round") +
    geom_point(data = hubs, aes(rc_lon, rc_lat, size = vol), colour = "grey20") +
    ggrepel::geom_text_repel(data = head(hubs, 12),
               aes(rc_lon, rc_lat, label = str_replace(name, " Hospital","")),
               size = 3, max.overlaps = 20) +
    scale_colour_viridis_c(option = "inferno", direction = -1, end = .9, name = "distance (km)") +
    scale_linewidth(range = c(.3, 3.5), name = "transfers") +
    scale_size(range = c(1, 7), guide = "none") +
    coord_sf(xlim = c(-10.6, -5.8), ylim = c(51.4, 55.4), expand = FALSE) +
    labs(title = "MICAS retrieval corridors",
         subtitle = "Line width ∝ volume, colour = distance. Long bright lines (Galway/Cork/Kerry -> Dublin) are the shift-breakers.",
         x = NULL, y = NULL) +
    theme_micas() +
    theme(legend.position = "right", panel.grid = element_line(colour = "grey92"))
  save_fig(p_map, "14_corridor_map.png", 8.5, 10)
  message("Flow map written (basemap: ", ifelse(is.null(base_layer),"NO - coordinate-only","YES"), ")")
}

###############################################################################
## 6. SAVE RESULTS WORKBOOK ----------------------------------------------------
###############################################################################
if (length(results)) {
  writexl::write_xlsx(results, file.path(OUTPUT_DIR, "MICAS_results_tables.xlsx"))
  message("Wrote ", length(results), " result tables to outputs/MICAS_results_tables.xlsx")
}
message("DONE. Figures + tables in: ", normalizePath(OUTPUT_DIR))
