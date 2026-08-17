# Churn360 — Chart-Level Build Specification (Field-Well Blueprint)

**Version:** 1.0
**Author:** Himanshu Upadhyay
**Companion to:** `PRD.md` v2.0 (architecture, measures, theme, governance)
**Scope:** Exact drag-and-drop instructions for every visual on the 5 report pages. Follow this document page-by-page in Power BI Desktop to reproduce the dashboard pixel-for-pixel.

---

## 1. Field-Well Rules — Which Sections Accept What

This is the most common source of build errors. Power BI restricts field wells by field type:

| Well | Accepts | Restriction |
|---|---|---|
| `Values` (pie/donut/table/matrix/cards) | **Measures only** (recommended) | A raw column dragged here forces an implicit SUM/COUNT — never do this |
| `Y-axis` (numeric value axis, bar/column/line/combo) | **Measures only** | Raw column → implicit aggregation |
| `X-axis` / `Axis` (category axis) | **Columns only** | A measure can only appear as a category via Axis → "Groups" (binning) |
| `Legend` | **Columns only** | Cannot group by a measure |
| `Details` (pie/donut/scatter) | **Columns only** | Defines slice / individual points |
| `Tooltips` | Measures preferred (columns get auto-aggregated) | **Not available on Table and Matrix** visuals |
| `Small multiples` | **Columns only** | Facet grid; never a measure |
| `Location` (maps) | **Columns only** | City / State / ZipCode / Country |
| `Latitude` / `Longitude` (bubble map) | **Columns only** | `dim_customer.Latitude` / `Longitude` (numeric geo columns) |
| `Color saturation` (maps, bar) | **Measures only** | Magnitude coloring |
| `Size` (scatter/map) | **Measures only** | |
| Scatter `X-axis` / `Y-axis` | **Measures only** | Numeric value axes |
| `Play axis` (scatter) | **Columns only** | Animation dimension |
| `Rows` / `Columns` (matrix) | **Columns only** | Grouping; `Values` = measures only |
| `Min` / `Max` / `Target` (gauge) | **Measures only** | |
| `Analyze` (decomposition tree) | Exactly ONE measure (or column) | Only one value |
| `Explain by` (decomposition tree) | **Columns only** | Dimensions to drill into |
| `Column series` / `Line series` / `Secondary y-axis` (combo) | **Measures only** | Shared axis = columns only |

**Rule of thumb:** if the well describes "a category, a group, or where something is" → column. If it describes "how much / how many / a rate" → measure.

---

## 2. New Calculated Columns Used by These Charts

Added to the model (validated, values computed):

| Column | Table | Purpose | Values |
|---|---|---|---|
| `ScoreBand` | gold fact_churn | ChurnScore banding for score-distribution charts | 0-39 · 40-59 · 60-69 · 70-84 · 85+ |
| `ScoreBandOrder` | gold fact_churn | Sorts ScoreBand correctly | 1..5 |
| `addon_count` | gold dim_customer | Count of premium add-ons (Online Security, Online Backup, Device Protection, Tech Support) per customer | 0..4 (blank = none) |
| `TenureBucket` | gold fact_churn | Tenure banding (from PRD.md) | 0-12 · 13-24 · 25-36 · 37-48 · 49-60 · 60+ |
| `TenureBucketOrder` | gold fact_churn | Sorts TenureBucket | 1..6 |

**Mandatory sorting setup** (do once, applies to all charts below):
- `TenureBucket` → Column tools → **Sort by column → `TenureBucketOrder`**
- `ScoreBand` → Column tools → **Sort by column → `ScoreBandOrder`**
- `addon_count` is numeric — sorts naturally.

---

## 3. Page `overview` — Executive Pulse

### 3.0 KPI cards (top row, 8 single-value cards)

| # | Card title | Value well (measure) | Formatting |
|---|---|---|---|
| K1 | Total Customers | `total_customers` | neutral, 0 decimals |
| K2 | Active Customers | `active_customers` | neutral |
| K3 | Churned Customers | `churned_customers` | red tint (rule: > 0) |
| K4 | Churn Rate | `churn_rate` | color scale: <15% green · 15–30% amber · >30% red |
| K5 | Monthly Revenue | `monthly_revenue` | color scale white→green |
| K6 | Avg CLTV | `avg_cltv` | neutral |
| K7 | High-Risk Active | `high_risk_active_customers` | amber when > 0 |
| K8 | Revenue at Risk | `revenue_at_risk` | always red tint |

Card = `Visualizations → Card` → `Fields → Value = measure`. Value well is **measure-only**.

### 3.1 Churned vs Active — Donut

| Well | Field | Type |
|---|---|---|
| Legend | `dim_customer` → not needed | — |
| Details | `ChurnLabel` | C |
| Values | `total_customers` | M |
| Tooltips | `churn_rate` | M |

**Why:** shows at a glance that ~1 in 4 customers is churned. **Info gained:** active/churned split + churn % on hover.
**Notes:** `Details` = column (the two slices). Center shows total. Optional: overlay a small Card with `churn_rate` on the donut center.

### 3.2 Customers by Contract Type — Donut

| Well | Field | Type |
|---|---|---|
| Legend | `ContractType` (dim_contract) | C |
| Details | `ContractType` | C |
| Values | `total_customers` | M |
| Tooltips | `churn_rate` | M |

**Why:** contract mix drives churn economics. **Info gained:** share of base per contract; tooltip reveals M2M 42.7% vs one-year 11.3% vs two-year 2.8%.

### 3.3 Churn Rate by Contract Type — Clustered Column

| Well | Field | Type |
|---|---|---|
| X-axis | `ContractType` | C |
| Y-axis | `churn_rate` | M |
| Tooltips | `churned_customers`, `total_customers` | M |
| Sort | by `churn_rate` descending | |

**Why:** ranks contracts by churn to justify M2M penalty. **Info gained:** exact churn rate per contract.
**Notes:** Y-axis = **measure only**. Add conditional formatting: background color scale on `churn_rate`.

### 3.4 Churn by Tenure Bucket — Line and Stacked Column (combo)

| Well | Field | Type |
|---|---|---|
| Shared axis | `TenureBucket` | C |
| Column series (Y-axis) | `total_customers` | M |
| Line series (Y-axis) | `churn_rate` | M |
| Secondary y-axis | `churn_rate` (set via format → Line series → on secondary axis) | M |
| Tooltips | `churned_customers` | M |

**Why:** the single most diagnostic chart — churn rate collapses with tenure. **Info gained:** most churn happens in 0-12 months; columns = base size, line = rate.
**Notes:** combo chart wells are strictly separated: **Shared axis accepts columns only; Column series and Line series accept measures only**. Sort shared axis by `TenureBucketOrder`.

### 3.5 Top 10 Churn Reasons — Clustered Bar

| Well | Field | Type |
|---|---|---|
| Y-axis | `ChurnReason` | C |
| X-axis | `churned_customers` | M |
| Filters | Top N = 10 by `churned_customers` | |
| Sort | descending by value | |

**Why:** surfaces the "attitude of support person" (192) problem. **Info gained:** ranked list of why customers leave.
**Notes:** Y-axis category = **column only**. Filter pane → Top N (a Top-N filter counts as an implicit measure filter).

### 3.6 High-Risk by Score Band — Stacked Column

| Well | Field | Type |
|---|---|---|
| X-axis | `ScoreBand` | C (calc) |
| Legend | `ChurnLabel` | C |
| Y-axis | `total_customers` | M |
| Sort | by `ScoreBandOrder` | |

**Why:** shows risk concentration; 70-84 (1,739) and 85+ (820) are dominated by churned customers. **Info gained:** where to focus retention.
**Notes:** **Legend = column only**. Scores ≤ 69 are mostly active; ≥ 70 mostly churned — proves the 70 threshold.

### 3.7 Monthly Revenue by Payment Method — Clustered Bar

| Well | Field | Type |
|---|---|---|
| Y-axis | `PaymentMethod` (dim_contract) | C |
| X-axis | `monthly_revenue` | M |
| Sort | descending | |

**Why:** revenue is concentrated in electronic check / credit card. **Info gained:** billing method = revenue lever.

---

## 4. Page `churn` — Root-Cause Drivers

### 4.0 KPI cards

| # | Card title | Value well (measure) |
|---|---|---|
| K1 | Churn Rate | `churn_rate` |
| K2 | Churned Customers | `churned_customers` |
| K3 | Avg Tenure (all) | `avg_tenure_months` |
| K4 | Churned Avg Tenure | `churned_avg_tenure` |
| K5 | Top Churn Reason | `top_churn_reason` (text) + `top_churn_reason_count` (subtitle) |

### 4.1 Contract Rates — Multi-row Card (3 target rates)

| Well | Field | Type |
|---|---|---|
| Values | `month_to_month_churn_rate` | M |
| Values | `one_year_churn_rate` | M |
| Values | `two_year_churn_rate` | M |

**Why:** the three contract-level churn rates side by side. **Info gained:** M2M is ~15× worse than two-year.
**Notes:** use a **Multi-row card** (or three Cards). Card Values = **measure only**.

### 4.2 Churn by Tenure Bucket — Combo

Identical field layout to `overview` §3.4 (Shared axis `TenureBucket`; Column series `churned_customers`; Line series `churn_rate` on secondary axis). **Why:** isolates WHERE in the lifecycle churn peaks. **Info gained:** churned volume peaks 0-12 months while rate declines steadily.

### 4.3 Demographics — 4 Clustered Columns (small multiples)

One chart each: `Gender`, `SeniorCitizen`, `Partner`, `Dependents`.

| Well | Field | Type |
|---|---|---|
| X-axis | `dim_customer.<Attribute>` | C |
| Y-axis | `churn_rate` | M |
| Tooltips | `churned_customers`, `total_customers` | M |

**Why:** seniors churn ~2× more; partners/dependents retain. **Info gained:** demographic risk segmentation.
**Notes:** X-axis = **column only**. Alternatively use **Small multiples** on `Gender` — Small multiples = **columns only**.

### 4.4 Payment Method × Paperless Billing — 100% Stacked Column

| Well | Field | Type |
|---|---|---|
| X-axis | `PaymentMethod` | C |
| Legend | `PaperlessBilling` | C |
| Y-axis | `total_customers` | M |
| Tooltips | `churn_rate` | M |

**Why:** paperless + electronic payment cohort is the heaviest churner. **Info gained:** billing-stack composition per payment method.

### 4.5 Decomposition Tree — Population Drill

| Well | Field | Type |
|---|---|---|
| Analyze | `total_customers` | M |
| Explain by | `ContractType` → `PaymentMethod` → `ServiceCategory` | C (columns only) |

**Why:** interactive root-cause drill for the analyst. **Info gained:** find highest-churn sub-segments by clicking through. **Notes:** **Analyze = exactly one measure; Explain by = columns only**. Turn off "Actions" footer if it clutters.

### 4.6 Churn Reasons by Contract Type — Stacked Bar

| Well | Field | Type |
|---|---|---|
| Y-axis | `ChurnReason` | C |
| X-axis | `churned_customers` | M |
| Legend | `ContractType` | C |

**Why:** shows whether "attitude" complaints are a contract-type problem. **Info gained:** reason mix stacked by contract.

---

## 5. Page `services` — Product Retention

### 5.0 KPI cards

| # | Card title | Value well |
|---|---|---|
| K1 | Best Retaining Service | `best_retention_service` (text, green) |
| K2 | Worst Retaining Service | `worst_retention_service` (text, red) |
| K3 | Avg Premium Add-Ons | `avg_addons` (2 decimals) |
| K4 | Service Churn Rate (in context) | `service_churn_rate` |

### 5.1 Churn Rate by Service Name — Clustered Bar

| Well | Field | Type |
|---|---|---|
| Y-axis | `ServiceName` (dim_service) | C |
| X-axis | `service_churn_rate` | M |
| Tooltips | `service_churned`, `service_customers` | M |
| Color saturation | `service_churn_rate` (diverging green→red) | M |
| Sort | ascending (best first) or descending | |

**Why:** Online Security 14.61% vs Internet Service — product-level retention ranking. **Info gained:** which products leak.
**Notes:** relies on the bidirectional `fact_customer_service → dim_customer` bridge so service context flows to churn. **Color saturation = measure only.**

### 5.2 Churn Rate by Service Category — Clustered Column

| Well | Field | Type |
|---|---|---|
| X-axis | `ServiceCategory` | C |
| Y-axis | `service_churn_rate` | M |
| Tooltips | `service_churned`, `service_customers` | M |

### 5.3 Service Adoption — Donut

| Well | Field | Type |
|---|---|---|
| Legend | `ServiceName` | C |
| Details | `ServiceName` | C |
| Values | `service_customers` | M |

**Why:** shows subscription penetration per service. **Info gained:** phone service near-universal; add-on services lower adoption.

### 5.4 Service × Contract Churn Matrix — Matrix

| Well | Field | Type |
|---|---|---|
| Rows | `ServiceName` | C |
| Columns | `ContractType` | C |
| Values | `service_churn_rate` | M |
| Formatting | Background color scale on Values (green→red) | |

**Why:** heat-map of where each service leaks per contract. **Info gained:** M2M + add-on services = worst cell. **Notes:** Matrix **Rows/Columns accept columns only; Values measures only; NO Tooltips well** (use Values tooltips via format → "Values" tooltip option).

### 5.5 Add-On Count Distribution — Column (histogram)

| Well | Field | Type |
|---|---|---|
| X-axis | `addon_count` | C (calc) |
| Y-axis | `total_customers` | M |
| Sort | by `addon_count` ascending | |

**Why:** 2,793 customers have ZERO premium add-ons — the upsell gap. **Info gained:** add-on adoption curve (0:2,793 · 1:1,467 · 2:1,372 · 3:941 · 4:470).

### 5.6 Service Adoption vs Churn — Scatter

| Well | Field | Type |
|---|---|---|
| Details | `ServiceName` | C |
| X-axis | `service_customers` | M |
| Y-axis | `service_churn_rate` | M |
| Legend | `ServiceCategory` | C |
| Size | `service_churned` | M |
| Tooltips | `avg_addons` | M |

**Why:** one bubble per service — adoption on X, churn on Y, color = category, size = churned volume. **Info gained:** services in the top-left quadrant = high churn despite low adoption (focus).
**Notes:** **Details = column (one bubble per service); X/Y/Size = measures only; Legend = column only.**

---

## 6. Page `revenue` — Monetary Impact

### 6.0 KPI cards

| # | Card title | Value well |
|---|---|---|
| K1 | Monthly Revenue | `monthly_revenue` |
| K2 | Lifetime Revenue | `lifetime_revenue` |
| K3 | Avg Monthly Charge | `avg_monthly_charge` |
| K4 | Avg CLTV | `avg_cltv` |
| K5 | Revenue at Risk | `revenue_at_risk` (red) |
| K6 | High-Risk Exposure | `high_risk_revenue_exposure` (amber) |
| K7 | CLTV Lost | `cltv_lost` (red) |

### 6.1 Monthly Revenue by Contract Type — Clustered Column

| Well | Field | Type |
|---|---|---|
| X-axis | `ContractType` | C |
| Y-axis | `monthly_revenue` | M |
| Tooltips | `avg_monthly_charge` | M |

### 6.2 Monthly Revenue by Payment Method — Donut

| Well | Field | Type |
|---|---|---|
| Legend | `PaymentMethod` | C |
| Details | `PaymentMethod` | C |
| Values | `monthly_revenue` | M |

**Why:** revenue share by billing method. **Info gained:** electronic check ~half of revenue.

### 6.3 CLTV by Contract Type — Clustered Column

| Well | Field | Type |
|---|---|---|
| X-axis | `ContractType` | C |
| Y-axis | `avg_cltv` | M |
| Tooltips | `lifetime_revenue` | M |

**Why:** long contracts are worth ~3× more. **Info gained:** CLTV lift from contract migration.

### 6.4 Revenue at Risk by Churn Reason — Clustered Bar (Top 10)

| Well | Field | Type |
|---|---|---|
| Y-axis | `ChurnReason` | C |
| X-axis | `revenue_at_risk` | M |
| Filters | Top N = 10 by `revenue_at_risk` | |
| Formatting | red tint on bars | |

### 6.5 Churn Score vs CLTV — Scatter (per customer)

| Well | Field | Type |
|---|---|---|
| Details | `ChurnKey` | C |
| X-axis | `ChurnScore` | M |
| Y-axis | `avg_cltv` | M |
| Legend | `ChurnLabel` | C |
| Size | `MonthlyCharges` (SUM) | M |
| Tooltips | `TenureMonths` (SUM) | M |

**Why:** the classic risk plot — churned (red) cluster at high score / low CLTV. **Info gained:** score threshold ≈ 70 cleanly separates the red cloud.
**Notes:** **Details = column (one point per customer); scatter X/Y/Size = measures only.** Because Y aggregates per point via Details, use the raw column `ChurnScore`/`avg_cltv` behavior — if points smear, switch Y to `avg_cltv` and X to `ChurnScore` with Details `ChurnKey` (guaranteed 1:1).

### 6.6 Top 10 Zips by Revenue — Clustered Bar

| Well | Field | Type |
|---|---|---|
| Y-axis | `ZipCode` | C |
| X-axis | `monthly_revenue` | M |
| Filters | Top N = 10 by `monthly_revenue` | |
| Tooltips | `geo_churn_rate` | M |

---

## 7. Page `geography` — Field-Level Risk

### 7.0 KPI cards

| # | Card title | Value well |
|---|---|---|
| K1 | Customers (map context) | `geo_customers` |
| K2 | Churn Rate (map context) | `geo_churn_rate` |
| K3 | High-Risk in View | `geo_high_risk` |
| K4 | Revenue at Risk in View | `geo_revenue_at_risk` |
| K5 | Top Churn City | `top_city_churn_rate` (La Puente 70%, text) |
| K6 | Top Churn Zip | `top_zip_churn_rate` (text) |

### 7.1 Zip Risk Map — Bubble Map (primary)

| Well | Field | Type |
|---|---|---|
| Latitude | `Latitude` | C |
| Longitude | `Longitude` | C |
| Size | `geo_customers` | M |
| Color saturation | `geo_churn_rate` | M |
| Tooltips | `geo_revenue_at_risk` | M |

**Why:** CA concentration of risk with churn heat. **Info gained:** which geographies bleed money. **Notes:** **Latitude/Longitude = columns only (numeric geo columns); Size/Color saturation = measures only.**

**Fallback (Filled map):** if the bubble map is too dense (7,043 points), use **Filled map**: `Location = State` (column only), `Color saturation = geo_churn_rate` (measure only). Region-level readability; loses zip granularity.

### 7.2 City Churn Table — Table

| Well | Field | Type |
|---|---|---|
| Columns (drag in order) | `City` | C |
| | `ZipCode` | C |
| | `geo_customers` | M |
| | `geo_churn_rate` | M |
| | `geo_high_risk` | M |
| | `geo_revenue_at_risk` | M |
| Formatting | color scale on `geo_churn_rate`; red on `geo_revenue_at_risk` | |

**Why:** zip-level drill for field teams. **Info gained:** smallest, highest-risk zips. **Notes:** **Table has NO Tooltips well.** Sort by `geo_churn_rate` desc.

### 7.3 Top 10 Cities by Churn Count — Clustered Bar

| Well | Field | Type |
|---|---|---|
| Y-axis | `City` | C |
| X-axis | `churned_customers` | M |
| Filters | Top N = 10 by `churned_customers` | |
| Tooltips | `geo_churn_rate` | M |

### 7.4 Top 10 Zips by Churn Rate (min base 3) — Clustered Bar

| Well | Field | Type |
|---|---|---|
| Y-axis | `ZipCode` | C |
| X-axis | `geo_churn_rate` | M |
| Filters | Advanced: `geo_customers` "is at least" 3; Top N = 10 by `geo_churn_rate` | |
| Formatting | diverging color scale on bars | |

**Why:** avoids the 100%-churn single-customer zip artifacts. **Info gained:** legitimately risky zips (e.g., 96161).

### 7.5 City Risk Quadrant — Scatter (optional)

| Well | Field | Type |
|---|---|---|
| Details | `City` | C |
| X-axis | `geo_customers` | M |
| Y-axis | `geo_churn_rate` | M |
| Size | `geo_high_risk` | M |

**Why:** bubble per city — size (customers) vs risk (churn). **Info gained:** big cities with high churn = priority.

---

## 8. Shared Slicer Bar (all pages)

| Slicer | Field | Type | Well |
|---|---|---|---|
| Gender | `dim_customer.Gender` | chip/tile | Field = column |
| Contract | `dim_contract.ContractType` | dropdown | Field = column |
| Payment Method | `dim_contract.PaymentMethod` | dropdown | Field = column |
| Tenure | `TenureBucket` | horizontal list | Field = column |
| Churn Status | `ChurnLabel` | toggle | Field = column |
| Score Threshold | Score field parameter (default 70) | numeric field parameter | Parameter (numeric) |

Page-specific slicers: `ServiceCategory` / `ServiceName` (services page); `State` / `City` / `ZipCode` (geography page).
**Notes:** slicers accept **columns only** (or field parameters). Every slicer cross-filters all visuals on the page. `Churn Status` drives the red/active framing.

---

## 9. Interactivity & Cross-Filtering Rules

- All visuals on a page cross-filter each other by default — keep this on.
- Set `ChurnLabel`, `ContractType`, `ServiceName` as report-level filters so slicers sync across pages (Edit interactions → disable for KPI cards if desired).
- **Tooltip pages:** create `tooltip_contract` (from ContractType), `tooltip_service` (from ServiceName), `tooltip_reason` (from ChurnReason) report pages, size ~ 400×250, and assign via visual → Format → Tooltips → Report page.
- **Drill-through:** from `geography` page visuals on `City`/`ZipCode` → `overview` (drill-through fields: `City`, `ZipCode`).
- **Bookmarks:** `theme_dark` / `theme_light` toggles per PRD.md §8.
- Rename page tabs in snake_case: `overview`, `churn`, `services`, `revenue`, `geography`.

---

## 10. Build Checklist (verify after each page)

1. Every KPI card uses a **measure** in Value (never a raw column).
2. Every `Legend` / `Details` / `X-axis` / `Small multiples` / `Location` / matrix `Rows`/`Columns` / `Explain by` contains only **columns**.
3. Every numeric axis (`Y-axis`, `X-axis` on scatter, `Size`, `Color saturation`, `Min/Max/Target`, `Analyze`, combo `Column/Line series`) contains only **measures**.
4. `TenureBucket` sorted by `TenureBucketOrder`; `ScoreBand` sorted by `ScoreBandOrder`.
5. Combo charts use Shared axis (column) + separate Column/Line series wells (measures).
6. Scatter plots: Details = key column (one point per row), X/Y/Size = measures, Legend = column.
7. Matrix: no Tooltips well used; color scale via Values background formatting.
8. Cross-filtering works both directions (services page validates the bidirectional bridge).
9. Verified values match PRD.md §5 (churn 26.54%, revenue at risk $139,131, etc.).
10. Press **Ctrl+S** in Power BI Desktop to persist all model changes to `Customer_Churn360_Analysis.pbix`.

---

*Prepared for the Churn360 project. Model (37 measures, 4 relationships, 5 calculated columns) is implemented and DAX-validated in `Customer_Churn360_Analysis.pbix`.*