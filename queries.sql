-- =============================================================================
-- Northwind Traders: sales analysis with PostgreSQL window functions
-- Dataquest guided project, Data Scientist in Python path
--
-- Every query below was executed against the Northwind PostgreSQL database.
-- Results are reported in README.md.
--
-- CONVENTION USED THROUGHOUT -------------------------------------------------
-- Net sales = order_details.quantity * order_details.unit_price * (1 - discount)
--
-- Two choices are deliberate and both matter:
--   1. unit_price is taken from order_details, NOT from products. The former is
--      the price at the time of sale; the latter is the current list price, and
--      using it silently restates history.
--   2. The (1 - discount) factor is applied. Omitting it overstates revenue by
--      $88,665.55 (6.55%), because 838 of 2,155 order lines carry a discount.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Orientation: what is in this database?
-- -----------------------------------------------------------------------------
SELECT table_name,
       (SELECT count(*)
          FROM information_schema.columns c
         WHERE c.table_name = t.table_name) AS n_cols
  FROM information_schema.tables t
 WHERE table_schema = 'public'
   AND table_type   = 'BASE TABLE'
 ORDER BY table_name;


-- -----------------------------------------------------------------------------
-- 1. Portfolio KPIs, and the size of the discount that a naive query would miss
-- -----------------------------------------------------------------------------
SELECT COUNT(DISTINCT o.order_id)                                   AS orders,
       COUNT(*)                                                     AS order_lines,
       COUNT(DISTINCT o.customer_id)                                AS customers,
       COUNT(DISTINCT o.employee_id)                                AS employees,
       COUNT(DISTINCT od.product_id)                                AS products_sold,
       ROUND(SUM(od.quantity * od.unit_price)::numeric, 2)          AS gross_sales,
       ROUND(SUM(od.quantity * od.unit_price
                 * (1 - od.discount))::numeric, 2)                  AS net_sales,
       ROUND((SUM(od.quantity * od.unit_price)
              - SUM(od.quantity * od.unit_price
                    * (1 - od.discount)))::numeric, 2)              AS discount_given,
       ROUND((100.0 * (SUM(od.quantity * od.unit_price)
                       - SUM(od.quantity * od.unit_price * (1 - od.discount)))
              / SUM(od.quantity * od.unit_price))::numeric, 2)      AS discount_pct,
       SUM(CASE WHEN od.discount > 0 THEN 1 ELSE 0 END)             AS discounted_lines
  FROM orders o
  JOIN order_details od ON o.order_id = od.order_id;


-- -----------------------------------------------------------------------------
-- 2. Data-quality check before trusting any time series
--    Are there orders with no line items? Is the last month complete?
-- -----------------------------------------------------------------------------
SELECT DATE_TRUNC('month', o.order_date)::date                      AS month,
       COUNT(*)                                                     AS orders,
       SUM(CASE WHEN od.order_id IS NULL THEN 1 ELSE 0 END)         AS orders_without_lines,
       SUM(CASE WHEN o.shipped_date IS NULL THEN 1 ELSE 0 END)      AS not_shipped
  FROM orders o
  LEFT JOIN (SELECT DISTINCT order_id FROM order_details) od
         ON od.order_id = o.order_id
 GROUP BY 1
 ORDER BY 1 DESC
 LIMIT 8;


-- -----------------------------------------------------------------------------
-- 3. Ranking employee sales performance
--    RANK() for the league table; SUM() OVER () and AVG() OVER () to express
--    each person relative to the whole team in the same pass.
-- -----------------------------------------------------------------------------
WITH emp_sales AS (
    SELECT e.employee_id,
           e.first_name || ' ' || e.last_name                       AS employee,
           e.title,
           COUNT(DISTINCT o.order_id)                               AS orders,
           ROUND(SUM(od.quantity * od.unit_price
                     * (1 - od.discount))::numeric, 2)              AS net_sales
      FROM employees e
      JOIN orders        o  ON o.employee_id = e.employee_id
      JOIN order_details od ON od.order_id   = o.order_id
     GROUP BY e.employee_id, employee, e.title
)
SELECT RANK() OVER (ORDER BY net_sales DESC)                        AS rank,
       employee,
       title,
       orders,
       net_sales,
       ROUND((net_sales / orders)::numeric, 2)                      AS avg_order_value,
       ROUND((100.0 * net_sales / SUM(net_sales) OVER ())::numeric, 2) AS pct_of_total,
       ROUND((net_sales - AVG(net_sales) OVER ())::numeric, 2)      AS vs_team_mean
  FROM emp_sales
 ORDER BY rank;


-- -----------------------------------------------------------------------------
-- 4 & 5. Running total of monthly sales, month-over-month growth,
--        and a 3-month moving average, in one pass
--
--        SUM() OVER (ORDER BY month)  -> cumulative revenue
--        LAG()                        -> previous month, for growth
--        AVG() OVER (... 2 PRECEDING) -> smoothing, since MoM is very noisy here
-- -----------------------------------------------------------------------------
WITH monthly AS (
    SELECT DATE_TRUNC('month', o.order_date)::date                  AS month,
           ROUND(SUM(od.quantity * od.unit_price
                     * (1 - od.discount))::numeric, 2)              AS net_sales,
           COUNT(DISTINCT o.order_id)                               AS orders
      FROM orders o
      JOIN order_details od ON od.order_id = o.order_id
     GROUP BY 1
)
SELECT month,
       orders,
       net_sales,
       SUM(net_sales) OVER (ORDER BY month)                         AS running_total,
       LAG(net_sales) OVER (ORDER BY month)                         AS prev_month,
       ROUND((100.0 * (net_sales - LAG(net_sales) OVER (ORDER BY month))
              / LAG(net_sales) OVER (ORDER BY month))::numeric, 1)  AS mom_growth_pct,
       ROUND(AVG(net_sales) OVER (ORDER BY month
                                  ROWS BETWEEN 2 PRECEDING
                                           AND CURRENT ROW)::numeric, 2) AS moving_avg_3m
  FROM monthly
 ORDER BY month;


-- -----------------------------------------------------------------------------
-- 6. Identifying high-value customers
--    NTILE(4) splits the customer base into revenue quartiles. The aggregate
--    then measures how lopsided the book is.
--    Note SUM(SUM(...)) OVER (): the inner SUM aggregates within the GROUP BY,
--    the outer window SUM totals across all groups, giving a share without a
--    second scan or a self-join.
-- -----------------------------------------------------------------------------
WITH cust AS (
    SELECT c.customer_id,
           c.company_name,
           c.country,
           COUNT(DISTINCT o.order_id)                               AS orders,
           ROUND(SUM(od.quantity * od.unit_price
                     * (1 - od.discount))::numeric, 2)              AS net_sales
      FROM customers c
      JOIN orders        o  ON o.customer_id = c.customer_id
      JOIN order_details od ON od.order_id   = o.order_id
     GROUP BY c.customer_id, c.company_name, c.country
),
tiered AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY net_sales DESC)                  AS quartile
      FROM cust
)
SELECT quartile,
       COUNT(*)                                                     AS customers,
       ROUND(SUM(net_sales)::numeric, 2)                            AS total_sales,
       ROUND((100.0 * SUM(net_sales)
              / SUM(SUM(net_sales)) OVER ())::numeric, 2)           AS pct_of_revenue,
       ROUND(AVG(net_sales)::numeric, 2)                            AS avg_per_customer,
       SUM(orders)                                                  AS total_orders
  FROM tiered
 GROUP BY quartile
 ORDER BY quartile;


-- 6b. The top customers by name, with a cumulative share column
WITH cust AS (
    SELECT c.company_name,
           c.country,
           COUNT(DISTINCT o.order_id)                               AS orders,
           ROUND(SUM(od.quantity * od.unit_price
                     * (1 - od.discount))::numeric, 2)              AS net_sales
      FROM customers c
      JOIN orders        o  ON o.customer_id = c.customer_id
      JOIN order_details od ON od.order_id   = o.order_id
     GROUP BY c.company_name, c.country
)
SELECT RANK() OVER (ORDER BY net_sales DESC)                        AS rank,
       company_name,
       country,
       orders,
       net_sales,
       ROUND((net_sales / orders)::numeric, 2)                      AS avg_order,
       ROUND((100.0 * net_sales / SUM(net_sales) OVER ())::numeric, 2) AS pct_of_revenue,
       ROUND((100.0 * SUM(net_sales) OVER (ORDER BY net_sales DESC)
              / SUM(net_sales) OVER ())::numeric, 1)                AS cumulative_pct
  FROM cust
 ORDER BY rank
 LIMIT 10;


-- -----------------------------------------------------------------------------
-- 7. Percentage of sales for each category, with a cumulative (Pareto) column
--    SUM() OVER () is the grand total; SUM() OVER (ORDER BY ...) is the
--    running total that turns the table into a concentration curve.
-- -----------------------------------------------------------------------------
WITH cat AS (
    SELECT c.category_name,
           ROUND(SUM(od.quantity * od.unit_price
                     * (1 - od.discount))::numeric, 2)              AS net_sales,
           COUNT(DISTINCT p.product_id)                             AS products
      FROM categories    c
      JOIN products      p  ON p.category_id = c.category_id
      JOIN order_details od ON od.product_id = p.product_id
     GROUP BY c.category_name
)
SELECT RANK() OVER (ORDER BY net_sales DESC)                        AS rank,
       category_name,
       products,
       net_sales,
       ROUND((100.0 * net_sales / SUM(net_sales) OVER ())::numeric, 2) AS pct_of_total,
       ROUND((100.0 * SUM(net_sales) OVER (ORDER BY net_sales DESC)
              / SUM(net_sales) OVER ())::numeric, 2)                AS cumulative_pct
  FROM cat
 ORDER BY rank;


-- -----------------------------------------------------------------------------
-- 8. Top three products per category
--    ROW_NUMBER() rather than RANK(): management asked for three rows per
--    category, and RANK() would return four on a tie. The window function has
--    to be computed in a subquery because WHERE runs before window functions.
-- -----------------------------------------------------------------------------
WITH prod AS (
    SELECT c.category_name,
           p.product_name,
           ROUND(SUM(od.quantity * od.unit_price
                     * (1 - od.discount))::numeric, 2)              AS net_sales
      FROM categories    c
      JOIN products      p  ON p.category_id = c.category_id
      JOIN order_details od ON od.product_id = p.product_id
     GROUP BY c.category_name, p.product_name
),
ranked AS (
    SELECT category_name,
           product_name,
           net_sales,
           ROW_NUMBER() OVER (PARTITION BY category_name
                              ORDER BY net_sales DESC)              AS rn,
           ROUND((100.0 * net_sales
                  / SUM(net_sales) OVER (PARTITION BY category_name))::numeric, 1)
                                                                    AS pct_of_category
      FROM prod
)
SELECT category_name, rn, product_name, net_sales, pct_of_category
  FROM ranked
 WHERE rn <= 3
 ORDER BY category_name, rn;


-- -----------------------------------------------------------------------------
-- 9. Product concentration: is the category ranking really a product ranking?
--    Added because section 7 showed Beverages on top, and this asks why.
-- -----------------------------------------------------------------------------
WITH prod AS (
    SELECT p.product_name,
           ROUND(AVG(od.unit_price)::numeric, 2)                    AS avg_price,
           SUM(od.quantity)                                         AS units,
           ROUND(SUM(od.quantity * od.unit_price
                     * (1 - od.discount))::numeric, 2)              AS net_sales
      FROM products p
      JOIN order_details od ON od.product_id = p.product_id
     GROUP BY p.product_name
)
SELECT ROW_NUMBER() OVER (ORDER BY net_sales DESC)                  AS rank,
       product_name,
       avg_price,
       units,
       net_sales,
       ROUND((100.0 * net_sales / SUM(net_sales) OVER ())::numeric, 2) AS pct_of_all_sales,
       ROUND((100.0 * SUM(net_sales) OVER (ORDER BY net_sales DESC)
              / SUM(net_sales) OVER ())::numeric, 1)                AS cumulative_pct
  FROM prod
 ORDER BY rank
 LIMIT 10;
