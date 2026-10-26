# SQL Window Functions for Northwind Traders

Sales analysis of the Northwind Traders database in PostgreSQL, using window functions: `RANK`, `ROW_NUMBER`, `NTILE`, `LAG`, and `SUM`/`AVG` with `OVER` and frame clauses.

Dataquest guided project, Data Scientist in Python path.

All queries in [`queries.sql`](queries.sql) were executed against the live database; every number below is real output, not an illustration.

## The database

| | |
|---|---|
| Orders | 830 |
| Order lines | 2,155 |
| Customers | 89 |
| Employees | 9 |
| Products sold | 77 |
| Period | 1996-07-04 to 1998-05-06 (23 months) |
| **Gross sales** | **$1,354,458.59** |
| **Net sales** | **$1,265,793.04** |

## Two decisions made before any window function

**1. Discounts are applied.** Net sales use `quantity * unit_price * (1 - discount)`. Omitting the discount factor, which is easy to do and common, overstates revenue by **$88,665.55 (6.55%)**, because **838 of 2,155 order lines (38.9%)** carry one. Every figure in this README is net.

**2. `unit_price` comes from `order_details`, not `products`.** The former is the price at the time of sale; the latter is the current list price. Joining to `products` for price silently restates history, and on a dataset spanning two years that is a real error rather than a pedantic one.

## Data quality checks that changed the analysis

Before trusting any time series, two things were worth verifying.

**Every order has line items.** No orders are orphaned, so no revenue is silently dropped by the join.

**The final month is partial.** Data ends on 1998-05-06, so May 1998 contains 6 days and 14 orders. Its month-over-month figure is **-85.2%**, which is an artefact of the cutoff and not a business event. Any growth chart that includes it tells a false story, and any trend conclusion must exclude it.

## Employee sales ranking

```sql
RANK()        OVER (ORDER BY net_sales DESC)
SUM(net_sales) OVER ()   -- share of team total, no self-join
AVG(net_sales) OVER ()   -- distance from team mean
```

| Rank | Employee | Title | Orders | Net sales | Avg order | % of total |
|---|---|---|---|---|---|---|
| 1 | Margaret Peacock | Sales Representative | 156 | $232,890.85 | $1,492.89 | 18.40% |
| 2 | Janet Leverling | Sales Representative | 127 | $202,812.84 | $1,596.95 | 16.02% |
| 3 | Nancy Davolio | Sales Representative | 123 | $192,107.60 | $1,561.85 | 15.18% |
| 4 | Andrew Fuller | Vice President, Sales | 96 | $166,537.76 | $1,734.77 | 13.16% |
| 5 | Laura Callahan | Inside Sales Coordinator | 104 | $126,862.28 | $1,219.83 | 10.02% |
| 6 | Robert King | Sales Representative | 72 | $124,568.23 | $1,730.11 | 9.84% |
| 7 | **Anne Dodsworth** | Sales Representative | 43 | $77,308.07 | **$1,797.86** | 6.11% |
| 8 | Michael Suyama | Sales Representative | 67 | $73,913.13 | $1,103.18 | 5.84% |
| 9 | Steven Buchanan | Sales Manager | 42 | $68,792.28 | $1,637.91 | 5.43% |

**The ranking by total conflates volume with effectiveness.** Anne Dodsworth is 7th by revenue and **1st by average order value** at $1,797.86, 20% above the team. Michael Suyama is 8th by revenue with the lowest average order at $1,103.18, which is a different problem requiring a different intervention. Peacock's top position comes substantially from volume: 156 orders, nearly four times Buchanan's 42, at a below-median order value.

Ranking people on one number and acting on it would coach the wrong behaviour in at least two of nine cases.

## Monthly sales, running total and growth

```sql
SUM(net_sales) OVER (ORDER BY month)                                  -- cumulative
LAG(net_sales) OVER (ORDER BY month)                                  -- prior month
AVG(net_sales) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
```

| Month | Orders | Net sales | Running total | MoM |
|---|---|---|---|---|
| 1996-07 | 22 | $27,861.90 | $27,861.90 | |
| 1996-12 | 31 | $45,239.63 | $208,083.98 | -0.8% |
| 1997-06 | 30 | $36,362.80 | $489,549.94 | -32.4% |
| 1997-12 | 48 | $71,398.43 | $825,169.18 | +64.0% |
| 1998-01 | 55 | $94,222.11 | $919,391.29 | +32.0% |
| 1998-02 | 54 | $99,415.29 | $1,018,806.58 | +5.5% |
| 1998-03 | 73 | $104,854.16 | $1,123,660.74 | +5.5% |
| 1998-04 | 74 | $123,798.68 | $1,247,459.42 | +18.1% |
| 1998-05 | 14 | $18,333.63 | $1,265,793.05 | *-85.2% (partial month)* |

The business grew substantially: April 1998 at $123,799 is **4.4 times** July 1996 at $27,862, and order volume rose from 22 to 74 a month.

**Month-over-month growth on this data is too noisy to manage by.** It swings between -34.8% and +64.0% in consecutive months on a book of 30 to 50 orders, where a handful of large orders moves the figure. That is why the query also computes a 3-month moving average: the same series smoothed is readable, and the raw MoM column mostly measures sampling noise.

## High-value customers

`NTILE(4)` over customers ordered by revenue:

| Quartile | Customers | Total sales | % of revenue | Avg per customer | Orders |
|---|---|---|---|---|---|
| **1 (top)** | 23 | $852,661.76 | **67.36%** | $37,072.25 | 371 |
| 2 | 22 | $266,726.88 | 21.07% | $12,123.95 | 227 |
| 3 | 22 | $108,152.81 | 8.54% | $4,916.04 | 145 |
| 4 (bottom) | 22 | $38,251.56 | **3.02%** | $1,738.71 | 87 |

**The top quartile, 23 of 89 customers, produces 67.4% of revenue**, and the average customer in it is worth 21 times one in the bottom quartile. The top three customers alone account for 25.2%.

| Rank | Customer | Country | Orders | Net sales | % of revenue | Cumulative |
|---|---|---|---|---|---|---|
| 1 | QUICK-Stop | Germany | 28 | $110,277.31 | 8.71% | 8.7% |
| 2 | Ernst Handel | Austria | 30 | $104,874.98 | 8.29% | 17.0% |
| 3 | Save-a-lot Markets | USA | 31 | $104,361.95 | 8.24% | 25.2% |
| 4 | Rattlesnake Canyon Grocery | USA | 18 | $51,097.80 | 4.04% | 29.3% |
| 5 | Hungry Owl All-Night Grocers | Ireland | 19 | $49,979.91 | 3.95% | 33.2% |

That concentration is the commercial risk worth flagging: losing QUICK-Stop alone removes 8.7% of revenue.

## Category share

| Rank | Category | Products | Net sales | % of total | Cumulative |
|---|---|---|---|---|---|
| 1 | Beverages | 12 | $267,868.18 | 21.16% | 21.16% |
| 2 | Dairy Products | 10 | $234,507.28 | 18.53% | 39.69% |
| 3 | Confections | 13 | $167,357.23 | 13.22% | 52.91% |
| 4 | Meat/Poultry | 6 | $163,022.36 | 12.88% | 65.79% |
| 5 | Seafood | 12 | $131,261.74 | 10.37% | 76.16% |
| 6 | Condiments | 12 | $106,047.08 | 8.38% | 84.54% |
| 7 | Produce | 5 | $99,984.58 | 7.90% | 92.44% |
| 8 | Grains/Cereals | 7 | $95,744.59 | 7.56% | 100% |

## Top three products per category

`ROW_NUMBER()` rather than `RANK()`, because management asked for three rows per category and `RANK()` returns four on a tie.

| Category | # | Product | Net sales | % of category |
|---|---|---|---|---|
| Beverages | 1 | **Côte de Blaye** | $141,396.74 | **52.8%** |
| Beverages | 2 | Ipoh Coffee | $23,526.70 | 8.8% |
| Beverages | 3 | Chang | $16,355.96 | 6.1% |
| Dairy Products | 1 | Raclette Courdavault | $71,155.70 | 30.3% |
| Dairy Products | 2 | Camembert Pierrot | $46,825.48 | 20.0% |
| Dairy Products | 3 | Mozzarella di Giovanni | $24,900.13 | 10.6% |
| Meat/Poultry | 1 | **Thüringer Rostbratwurst** | $80,368.67 | **49.3%** |
| Meat/Poultry | 2 | Alice Mutton | $32,698.38 | 20.1% |
| Meat/Poultry | 3 | Perth Pasties | $20,574.17 | 12.6% |
| Confections | 1 | Tarte au sucre | $47,234.97 | 28.2% |
| Confections | 2 | Sir Rodney's Marmalade | $22,563.36 | 13.5% |
| Confections | 3 | Gumbär Gummibärchen | $19,849.14 | 11.9% |

## The finding the category ranking hides

Beverages is the top category, which invites a conclusion about beverages. The product table says otherwise:

| Rank | Product | Avg price | Units | Net sales | % of ALL sales |
|---|---|---|---|---|---|
| 1 | **Côte de Blaye** | **$245.93** | 623 | $141,396.74 | **11.17%** |
| 2 | Thüringer Rostbratwurst | $116.04 | 746 | $80,368.67 | 6.35% |
| 3 | Raclette Courdavault | $51.13 | 1,496 | $71,155.70 | 5.62% |
| 4 | Tarte au sucre | $46.41 | 1,083 | $47,234.97 | 3.73% |
| 5 | Camembert Pierrot | $32.13 | 1,577 | $46,825.48 | 3.70% |

**A single product, Côte de Blaye, is 11.2% of all company revenue and 52.8% of its category.** At $245.93 it is five times the average price of anything else in the top ten, and it sells 623 units against Camembert Pierrot's 1,577. Beverages does not lead because the company sells a lot of drinks; it leads because it sells one very expensive wine.

The top ten products are **44.2%** of all revenue, out of 77 products sold.

That distinction matters for the decision the ranking was meant to inform. "Stock and market the top category" and "protect the supply of one luxury SKU and understand who buys it" are different actions, and only the product-level query distinguishes them.

## Window function techniques used

| Technique | Where | Why |
|---|---|---|
| `RANK()` | employees, customers, categories | league tables where ties should share a rank |
| `ROW_NUMBER()` | top-N per category | guarantees exactly N rows per partition |
| `NTILE(4)` | customer quartiles | equal-sized buckets without manual thresholds |
| `LAG()` | month-over-month growth | prior row without a self-join |
| `SUM() OVER ()` | share-of-total columns | grand total alongside detail in one pass |
| `SUM() OVER (ORDER BY ...)` | running totals, Pareto | cumulative without a correlated subquery |
| `AVG() OVER (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` | 3-month moving average | explicit frame to smooth a noisy series |
| `SUM(SUM(x)) OVER ()` | quartile revenue share | window over an aggregate, avoiding a second scan |
| `PARTITION BY` | per-category ranking and shares | restart the window per group |

A note on ordering: `WHERE` is evaluated before window functions, so `WHERE rn <= 3` cannot reference `ROW_NUMBER()` in the same query level. Both top-N queries compute the window in a CTE and filter outside it.

## Limitations

- **23 months of a small book.** 830 orders across 89 customers is thin enough that single large orders move monthly figures materially, which is why the MoM column is reported with a warning rather than as a metric.
- **Northwind is a synthetic teaching database.** The patterns are plausible but not real trading behaviour, and nothing here should be read as a finding about wholesale food distribution.
- **May 1998 is a partial month** and is excluded from any growth reading.
- **Freight, cost of goods and returns are absent**, so this is revenue analysis, not profitability. The most-discounted products could be the least profitable and nothing here would reveal it.
- **Employee comparisons ignore tenure, territory and account assignment.** Buchanan and Dodsworth cover different regions, and ranking them against each other without controlling for territory is suggestive rather than conclusive.

## Files

- [`queries.sql`](queries.sql): every query, commented, in the order the analysis runs.
