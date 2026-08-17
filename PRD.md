# Churn360 — Power BI Solution PRD

**Version:** 2.0
**Author:** Himanshu Upadhyay
**Data source:** `Customer_Analysis` database · `gold` schema (SQL Server, Import mode)
**Build:** Power BI Desktop 2026 · Snapshot analytics

---

## 1. Scope & Design Principles

1. **No time intelligence.** The source dataset contains **no business date columns** (verified across bronze/silver/gold — only `silver.customer.dwh_create_date`, an ETL metadata timestamp, exists). Therefore no Date table, no previous-year / YoY / MoM comparisons, and no `SAMEPERIODLASTYEAR`-style measures. All analysis is **point-in-time snapshot** of the current gold layer.
2. **Star schema only.** One fact (per-customer snapshot) + one factless fact (service subscription matrix) + dimension tables. All relationships are verified and active.
3. **Naming convention: snake_case.** Every measure, calculated column, folder, and page name is lowercase `snake_case` (e.g., `total_customers`, folder `revenue`).
4. **Dashboard-aligned measure folders.** Measures live in folders named after the report page that owns them: `overview`, `churn`, `services`, `revenue`, `geography`.
5. **5 report pages**, mirroring the existing web dashboard, giving 100% coverage of the dataset's analytical surface.

---

## 2. Data Foundation (Gold Layer)

### 2.1 Tables

| Table | Grain | Columns | Role |
|---|---|---|---|
| `gold fact_churn` | 1 row per customer snapshot | ChurnKey, CustomerKey, ContractKey, TenureMonths, MonthlyCharges, TotalCharges, ChurnScore, CLTV, ChurnValue, ChurnLabel, ChurnReason, TenureBucket, TenureBucketOrder | Central fact (7,043 rows) |
| `gold fact_customer_service` | 1 row per customer-service subscription | CustomerKey, ServiceKey | Factless fact (subscription matrix) |
| `gold dim_customer` | 1 row per customer | CustomerKey, CustomerID, Gender, SeniorCitizen, Partner, Dependents, Country, State, City, ZipCode, Latitude, Longitude | Customer attributes + geo |
| `gold dim_contract` | 1 row per contract type | ContractKey, ContractType, PaperlessBilling, PaymentMethod | Contract + billing |
| `gold dim_service` | 1 row per service | ServiceKey, ServiceName, ServiceCategory | Service catalog |

### 2.2 Star Schema Relationships (verified, all active)

| # | From (many) | To (one) | Filtering |
|---|---|---|---|
| 1 | `gold fact_churn` [ContractKey] | `gold dim_contract` [ContractKey] | One-direction |
| 2 | `gold fact_churn` [CustomerKey] | `gold dim_customer` [CustomerKey] | Both directions (1:1) |
| 3 | `gold fact_customer_service` [CustomerKey] | `gold dim_customer` [CustomerKey] | **Both directions** (enables service → churn filtering) |
| 4 | `gold fact_customer_service` [ServiceKey] | `gold dim_service` [ServiceKey] | One-direction |

**Why relationship #3 is bidirectional:** service filters (e.g., "Online Security") must flow through the factless fact → dim_customer → fact_churn, so per-service churn rates compute correctly.

### 2.3 Calculated Columns (existing)

| Column | Table | Formula (concept) | Purpose |
|---|---|---|---|
| `TenureBucket` | gold fact_churn | 0-12 / 13-24 / 25-36 / 37-48 / 49-60 / 60+ | Tenure banding |
| `TenureBucketOrder` | gold fact_churn | 1..6 | Sorts tenure buckets |

---

## 3. Dashboard Plan — 5 Pages (100% dataset coverage)

| Page | Answers | Key story |
|---|---|---|
| `overview` | How much churn? What is it costing? | Executive pulse |
| `churn` | Why do customers leave? | Root-cause drivers |
| `services` | Which products retain vs leak? | Product retention |
| `revenue` | What revenue/CLTV is lost or at risk? | Monetary impact |
| `geography` | Where is risk concentrated? | Field-level risk map |

Shared slicer bar across all pages (see Section 8).

---

## 4. Page-by-Page Specification

### 4.1 Page `overview`

**KPIs (KPI cards, top row):**

| KPI card | Measure | Conditional formatting |
|---|---|---|
| Total Customers | `total_customers` | neutral |
| Active Customers | `active_customers` | neutral |
| Churned Customers | `churned_customers` | red when > 0 |
| Churn Rate | `churn_rate` | color scale: <15% green · 15–30% amber · >30% red |
| Monthly Revenue | `monthly_revenue` | color scale (white→green) |
| Avg CLTV | `avg_cltv` | neutral |
| High-Risk Active | `high_risk_active_customers` | amber/red by threshold |
| Revenue at Risk | `revenue_at_risk` | always red tint |

**Charts:**
1. Churned vs Active — donut (`churn_rate` in center)
2. Customers by Contract Type — donut with churn % legend
3. Churn Rate by Contract Type — column
4. Churn Rate by Tenure Bucket — combo (count columns + rate line)
5. Top 10 Churn Reasons — horizontal bar
6. High-Risk by Score Band — column (ChurnScore binned)
7. Monthly Revenue by Payment Method — bar

**Slicers:** all shared slicers (Section 8).

### 4.2 Page `churn`

**KPIs:**
| KPI card | Measure | Conditional formatting |
|---|---|---|
| Churn Rate (current filter) | `churn_rate` | color scale |
| Churned Customers | `churned_customers` | red |
| Avg Tenure | `avg_tenure_months` | neutral |
| Churned Avg Tenure | `churned_avg_tenure` | neutral |
| Top Churn Reason | `top_churn_reason` + `top_churn_reason_count` | red accent |

**Charts:**
1. Churn by Contract Type — column (`month_to_month_churn_rate`, `one_year_churn_rate`, `two_year_churn_rate` as target cards or grouped bar)
2. Churn by Tenure Bucket — combo
3. Churn by Gender / Senior Citizen / Partner / Dependents — clustered columns
4. Payment Method × Paperless Billing churn — 100% stacked
5. Decomposition Tree — Contract → Payment Method → Service Category
6. Churn Reasons by Contract Type — bar

**Slicers:** all shared + `ChurnReason`.

### 4.3 Page `services`

**KPIs:**
| KPI card | Measure | Conditional formatting |
|---|---|---|
| Best Retaining Service | `best_retention_service` | green |
| Worst Retaining Service | `worst_retention_service` | red |
| Avg Premium Add-Ons | `avg_addons` | neutral |
| Service Churn Rate (in context) | `service_churn_rate` | color scale |

**Charts:**
1. Churn Rate by Service Name — bar (via `service_churn_rate` through the factless bridge)
2. Churn Rate by Service Category — bar
3. Service Adoption — donut (subscriptions per service)
4. Matrix: Service × Contract — color-scale on churn rate
5. Add-On Count distribution — histogram
6. Internet Service dependency vs add-ons — scatter (ServiceName color)

**Slicers:** `ServiceCategory`, `ServiceName`, Contract.

### 4.4 Page `revenue`

**KPIs:**
| KPI card | Measure | Conditional formatting |
|---|---|---|
| Monthly Revenue | `monthly_revenue` | color scale |
| Lifetime Revenue | `lifetime_revenue` | color scale |
| Avg Monthly Charge | `avg_monthly_charge` | neutral |
| Avg CLTV | `avg_cltv` | neutral |
| Revenue at Risk | `revenue_at_risk` | red |
| High-Risk Exposure | `high_risk_revenue_exposure` | amber |
| CLTV Lost | `cltv_lost` | red |

**Charts:**
1. Monthly Revenue by Contract Type — bar
2. Monthly Revenue by Payment Method — donut + bar
3. CLTV by Contract Type — column
4. Revenue at Risk by Churn Reason — bar
5. Churn Score vs CLTV — scatter (bubble = MonthlyCharges)
6. Top 10 Zips by Revenue — bar

**Slicers:** all shared.

### 4.5 Page `geography`

**KPIs:**
| KPI card | Measure | Conditional formatting |
|---|---|---|
| Customers (map context) | `geo_customers` | neutral |
| Churn Rate (map context) | `geo_churn_rate` | color scale |
| High-Risk in view | `geo_high_risk` | amber |
| Revenue at Risk in view | `geo_revenue_at_risk` | red |
| Top Churn City | `top_city_churn_rate` (La Puente 70%) | red |
| Top Churn Zip | `top_zip_churn_rate` | red |

**Charts:**
1. Zip-code map — bubble sized by customers, colored by churn rate (ArcGIS/Shape/Filled map)
2. City churn table — color scale on churn rate
3. Top 10 Cities by Churn Count — bar
4. Top 10 Zips by Churn Rate (min base 3) — bar

**Slicers:** `State`, `City`, `ZipCode`, Churn Status.

---

## 5. Master Measure Catalog (37 measures, snake_case)

### Folder `overview`
| Measure | DAX |
|---|---|
| `total_customers` | `COUNTROWS('gold fact_churn')` |
| `active_customers` | `CALCULATE(COUNTROWS('gold fact_churn'), ChurnLabel = "No")` |
| `churned_customers` | `CALCULATE(COUNTROWS('gold fact_churn'), ChurnLabel = "Yes")` |
| `churn_rate` | `DIVIDE([churned_customers], [total_customers], 0)` |
| `retention_rate` | `DIVIDE([active_customers], [total_customers], 0)` |
| `avg_churn_score` | `AVERAGE(ChurnScore)` |
| `high_risk_active_customers` | `CALCULATE(COUNTROWS(...), ChurnScore >= 70, ChurnLabel = "No")` |
| `active_high_risk_share` | `DIVIDE([high_risk_active_customers], [active_customers], 0)` |

### Folder `revenue`
| Measure | DAX |
|---|---|
| `monthly_revenue` | `SUM(MonthlyCharges)` |
| `lifetime_revenue` | `SUM(TotalCharges)` |
| `avg_monthly_charge` | `AVERAGE(MonthlyCharges)` |
| `avg_cltv` | `AVERAGE(CLTV)` |
| `revenue_at_risk` | `CALCULATE([monthly_revenue], ChurnLabel = "Yes")` |
| `high_risk_revenue_exposure` | `CALCULATE([monthly_revenue], ChurnScore >= 70, ChurnLabel = "No")` |
| `lost_lifetime_revenue` | `CALCULATE([lifetime_revenue], ChurnLabel = "Yes")` |
| `cltv_lost` | `CALCULATE(SUM(CLTV), ChurnLabel = "Yes")` |

### Folder `churn`
| Measure | DAX |
|---|---|
| `avg_tenure_months` | `AVERAGE(TenureMonths)` |
| `churned_avg_tenure` | `CALCULATE(AVERAGE(TenureMonths), ChurnLabel = "Yes")` |
| `month_to_month_churn_rate` | `CALCULATE([churn_rate], dim_contract[ContractType] = "Month-to-month")` |
| `one_year_churn_rate` | `CALCULATE([churn_rate], dim_contract[ContractType] = "One year")` |
| `two_year_churn_rate` | `CALCULATE([churn_rate], dim_contract[ContractType] = "Two year")` |
| `top_churn_reason` | `MAXX(TOPN(1, SUMMARIZE(...ChurnReason, churned count...), DESC), ChurnReason)` |
| `top_churn_reason_count` | count for `top_churn_reason` |

### Folder `services`
| Measure | DAX |
|---|---|
| `service_customers` | `COUNTROWS('gold fact_churn')` (context-driven via bridge) |
| `service_churned` | `CALCULATE(COUNTROWS(...), ChurnLabel = "Yes")` |
| `service_churn_rate` | `DIVIDE([service_churned], [service_customers], 0)` |
| `avg_addons` | `AVERAGEX(dim_customer, CALCULATE(COUNTROWS(fact_customer_service), ServiceName IN {Online Security, Online Backup, Device Protection, Tech Support}))` |
| `best_retention_service` | `MAXX(TOPN(1, SUMMARIZE(dim_service, ...churn rate ASC), ServiceName)` |
| `worst_retention_service` | same, DESC |

### Folder `geography`
| Measure | DAX |
|---|---|
| `geo_customers` | `COUNTROWS('gold fact_churn')` (context-driven) |
| `geo_churn_rate` | `[churn_rate]` (context-driven) |
| `geo_high_risk` | `CALCULATE(COUNTROWS(...), ChurnScore >= 70, ChurnLabel = "No")` |
| `geo_revenue_at_risk` | `CALCULATE([monthly_revenue], ChurnLabel = "Yes")` |
| `top_city_churn_rate` / `_value` | top churn-rate city with **min 10 customers** |
| `top_zip_churn_rate` / `_value` | top churn-rate zip with **min 3 customers** |

**Verified values:** churn 26.54% · M2M 42.7% · One year 11.3% · Two year 2.8% · top reason "Attitude of support person" (192) · best retention Online Security 14.61% · worst Internet Service · top city La Puente 70% · high-risk active 950 · revenue at risk $139,131 · CLTV lost $7.76M.

---

## 6. Conditional Formatting Specification

Since no time comparisons exist, conditional formatting is **threshold/goal-based**:

| Field / Measure | Type | Rule |
|---|---|---|
| `churn_rate` (any visual) | Color scale | 0–15% green · 15–30% amber · >30% red |
| `churn_rate` cards | Data bars / icons | ▼ arrow when below 15% target (green), ▲ arrow when above (red) |
| `ChurnScore` | Color scale | 0–49 green · 50–69 amber · 70–84 orange · 85+ red |
| `ChurnLabel` = "Yes" rows | Rules | red background |
| `revenue_at_risk`, `cltv_lost` | Rules | red text / background |
| `monthly_revenue`, `lifetime_revenue` | Color scale | white → green |
| `avg_cltv` | Color scale | white → green |
| Service matrix churn | Color scale | green (low) → red (high) |
| Geography map bubbles | Color scale | green (low churn) → amber → red (high) |
| KPI progress | Icons | ▲/▼/➖ arrows for over/under target |

**Icon rules** use native Power BI conditional-formatting icons (arrows) on KPI cards to show over/under target.

---

## 7. Slicers Strategy (shared)

| Slicer | Field | Type |
|---|---|---|
| Gender | `dim_customer.Gender` | chip/single-select |
| Contract | `dim_contract.ContractType` | dropdown |
| Payment Method | `dim_contract.PaymentMethod` | dropdown |
| Tenure | `TenureBucket` | horizontal |
| Churn Status | `ChurnLabel` | toggle (All/Active/Churned) |
| Score Threshold | Parameter (default 70) | numeric field parameter |
| Service Category | `dim_service.ServiceCategory` | page-specific (services) |
| Service Name | `dim_service.ServiceName` | page-specific (services) |
| City / Zip | `dim_customer.City`, `ZipCode` | page-specific (geography) |

All slicers cross-filter every visual on the page. Use a slicer bar on each page; `Churn Status` drives the red/active framing.

---

## 8. Premium Theme Customization

Two branded Power BI theme `.json` files (mirror the web dashboard):

**Holographic Dark** (`theme_dark.json`)
- Background: `#0B0E14` · Card: `#12151E`
- Accent (primary): `#2BFF9E` · Secondary: `#4CC9F0`
- Warning: `#FFC24B` · Danger: `#FF5A5F`
- Text: `#EAFFF2` · Gridlines: `rgba(234,255,242,0.06)`
- `dataColors`: custom 8-color neon palette
- No borders, flat cards, rounded corners, hidden axes where possible

**Apple Light** (`theme_light.json`)
- Background: `#F5F7FB` · Card: `#FFFFFF`
- Accent: `#047857` · Text: `#1D1D1F` · Gridlines: `#E5E7EB`

**Global theme settings:** Segoe UI Variable font, KPI card style (value + unit + icon chip), no default gridlines, subtle 6px radius, consistent data-label colors, tooltips dark-mode-aware. Apply via View → Themes → Browse for themes.

---

## 9. Interactivity & Navigation

- **Cross-filtering** across all visuals per page.
- **Bookmarks:** theme toggle (dark/light), drill page states.
- **Drill-through:** `geography` city/zip → `overview`; table rows on `churn` → filter context.
- **Report page tooltips:** contract/service/churn-reason tooltip pages.
- **Field parameter:** score threshold slider (default 70) redefines `high_risk_*` measures.
- **Rename page tabs** in snake_case: `overview`, `churn`, `services`, `revenue`, `geography`.

---

## 10. Governance & Scalability (Enterprise)

- **Refresh:** Import mode + Power BI Gateway (Personal) → scheduled refresh (15 min) as CRM/ERP land.
- **Incremental refresh** on `gold fact_churn` when volume grows (roadmap item).
- **RLS:** Role `Executive` (all data), Role `Regional` (by `State`).
- **Deployment:** PBIP folder source control → Dev/Test/Prod workspace pipeline.
- **Data certification** + sensitivity label.
- **QA checklist:** verify 37 measures compute (values in Section 5), relationship filter propagation (services), no blank measures, conditional formatting on all score/rate fields, theme applied consistently.

---

*Prepared for the Churn360 project. Model implemented in `Customer_Churn360_Analysis.pbix` — save in Power BI Desktop to persist.*