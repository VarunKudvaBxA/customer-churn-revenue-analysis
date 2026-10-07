# Power BI Guide - Customer Churn & Revenue Leakage Dashboard

`.pbix` files are binary, so this guide gives you everything to build the dashboard yourself in ~60-90 minutes.
Save the finished file as `powerbi/Customer_Churn.pbix`.

## 1. Load the data (Get Data -> Text/CSV, from `outputs/powerbi/`)

| File | Table name | Use |
|---|---|---|
| `customers_scored.csv` | `customers` | Main fact table: one row per customer with churn probability, risk decile/tier, revenue |
| `segment_leakage.csv` | `segments` | Revenue lost per balance x activity segment |
| `risk_deciles.csv` | `deciles` | Actual churn by model risk decile |
| `feature_importance.csv` | `drivers` | What drives churn |
| `cluster_profile.csv` | `clusters` | K-Means cluster averages |
| `retention_roi.csv` | `roi_table` | Pre-computed targeting scenarios |

Power Query checks: `is_churn`, `IsActiveMember`, `HasCrCard`, `NumOfProducts` = Whole number;
`Balance`, `annual_revenue`, `churn_prob`, `expected_revenue_loss` = Decimal. Add *Sort by column* helpers for
`age_band` (order: <30, 30-39, 40-49, 50-59, 60+) and `products_band`.

## 2. DAX measures

```DAX
Customers          = COUNTROWS(customers)
Churned            = SUM(customers[is_churn])
Churn Rate         = DIVIDE([Churned], [Customers])
Annual Revenue     = SUM(customers[annual_revenue])
Revenue Lost       = CALCULATE([Annual Revenue], customers[is_churn] = 1)
Revenue Lost %     = DIVIDE([Revenue Lost], [Annual Revenue])
Avg Tenure         = AVERAGE(customers[Tenure])
Avg Revenue / Customer = DIVIDE([Annual Revenue], [Customers])

Overall Churn Rate = CALCULATE([Churn Rate], ALL(customers))
Churn Gap (pp)     = ([Churn Rate] - [Overall Churn Rate]) * 100
Share of Loss      = DIVIDE([Revenue Lost], CALCULATE([Revenue Lost], ALL(customers)))

-- Forward-looking: customers who have NOT left but look like leavers
High-Risk Active Customers = CALCULATE([Customers], customers[is_churn] = 0, customers[risk_tier] = "High")
Expected Revenue at Risk   = CALCULATE(SUM(customers[expected_revenue_loss]), customers[is_churn] = 0)
```

**Retention what-if (3 parameters):** Modeling -> New parameter, each with a slicer:
- `Targeted Deciles` - Whole, 1 to 5, step 1, default 3
- `Cost per Offer` - Whole, 10 to 200, step 5, default 50
- `Save Rate` - Decimal, 0.05 to 0.6, step 0.05, default 0.30

```DAX
Targeted Customers =
    CALCULATE([Customers], customers[risk_decile] >= 11 - 'Targeted Deciles'[Targeted Deciles Value])
Revenue Saved =
    CALCULATE([Revenue Lost], customers[risk_decile] >= 11 - 'Targeted Deciles'[Targeted Deciles Value])
        * 'Save Rate'[Save Rate Value]
Campaign Cost = [Targeted Customers] * 'Cost per Offer'[Cost per Offer Value]
Net Benefit   = [Revenue Saved] - [Campaign Cost]
ROI           = DIVIDE([Net Benefit], [Campaign Cost])
```
(Sanity check: 3 deciles, $50, 30% should give **Net Benefit = $542,242** - same as Python and Excel.)

## 3. Pages

### Page 1 - Executive Summary
- **Cards:** Customers, Churn Rate, Revenue Lost, Revenue Lost %, Avg Tenure
- **Column charts:** Churn Rate by `Geography`, by `age_band`, by `products_band`
- **Donut:** Churned vs Retained
- **Slicers:** Geography, Gender, Activity

### Page 2 - Segments & Drivers
- **Bar chart:** `segments[revenue_lost]` by `segment` (sorted descending) - highlights the 100k+ Inactive segment
- **Matrix heatmap:** rows = `activity`, columns = `products_band`, values = Churn Rate (colour scale)
- **Bar chart:** `drivers[importance]` by `feature`
- **Table:** `clusters` (K-Means profile) with data bars on churn_rate
- **Text box (insight):** "Inactive customers holding 100k+ balances are 22% of customers but ~51% of revenue lost."

### Page 3 - At-Risk Customers & Retention ROI
- **Table:** top 50 customers where `is_churn = 0`, ordered by `expected_revenue_loss` (use a visual-level filter: `risk_tier = High`, `is_churn = 0`)
- **Column chart:** `deciles[actual_churn_rate]` by `risk_decile` (proves the model ranks risk)
- **What-if slicers** + **cards:** Targeted Customers, Revenue Saved, Campaign Cost, Net Benefit, ROI
- **Text box - Recommendations:**
  1. Target the top ~30% by risk: reaches ~66% of churners at about 3.6x ROI (assumptions on slide).
  2. Prioritise inactive, high-balance customers and customers with 1 or 3+ products.
  3. Cross-sell a 2nd product to single-product customers; 2-product customers churn the least.

## 4. Polish & publish
- Consistent theme (navy `#2F5D8C`, red `#C0392B` for loss), clear titles, no clutter, aligned grid.
- Add page navigation buttons + a "Data & assumptions" tooltip/text box.
- Export screenshots to `powerbi/screenshots/` for the GitHub README. Publish to Power BI Service if your account allows; otherwise a 60-second screen recording is a good alternative.
