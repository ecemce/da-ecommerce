-- Pet Shop 2018 Aylık Büyüme Oranı
WITH monthly_sales AS (
  SELECT 
    YearMonth,
    SUM(CalculatedSales) as CalculatedSales
  FROM `retail.analytics_vw_sales_kpis`
  WHERE BuyingCategory = 'Petshop'
    AND Year = 2018
  GROUP BY YearMonth
),

growth_calc AS (
  SELECT 
    YearMonth,
    CalculatedSales,
    LAG(CalculatedSales) OVER (ORDER BY YearMonth) as PreviousMonthSales,
    ROUND(
      ((CalculatedSales - LAG(CalculatedSales) OVER (ORDER BY YearMonth)) 
       / NULLIF(LAG(CalculatedSales) OVER (ORDER BY YearMonth), 0)) * 100, 
      2
    ) as GrowthRate_Percent
  FROM monthly_sales
)

SELECT 
  YearMonth as Month,
  ROUND(CalculatedSales, 2) as CalculatedSales,
  ROUND(PreviousMonthSales, 2) as PreviousMonthSales,
  GrowthRate_Percent
FROM growth_calc
ORDER BY YearMonth;

-- 2018'de en az 2 sipariş veren müşteri sayısı
SELECT 
  COUNT(DISTINCT Customer) as CustomersWithMin2Orders
FROM (
  SELECT 
    Customer,
    COUNT(DISTINCT OrderNo) as OrderCount
  FROM `retail.analytics_vw_sales_kpis`
  WHERE Year = 2018
  GROUP BY Customer
  HAVING COUNT(DISTINCT OrderNo) >= 2
);

WITH top5_skus AS (
  SELECT 
    Sku,
    SUM(Pcs) as TotalPieces
  FROM `retail.analytics_vw_sales_kpis`
  WHERE BuyingCategory = 'Anne Bebek Çocuk'
  GROUP BY Sku
  ORDER BY TotalPieces DESC
  LIMIT 5
)

SELECT 
  COUNT(DISTINCT v.Customer) as CustomerCount
FROM `retail.analytics_vw_sales_kpis` v
INNER JOIN top5_skus t
  ON v.Sku = t.Sku
WHERE v.BuyingCategory = 'Anne Bebek Çocuk';

-- 2019'da marka bazında 20+ SKU satılan ay sayısı
WITH brand_month_sku AS (
  SELECT 
    Brand,
    YearMonth,
    COUNT(DISTINCT Sku) as UniqueSKUs
  FROM `retail.analytics_vw_sales_kpis`
  WHERE Year = 2019
  GROUP BY Brand, YearMonth
  HAVING COUNT(DISTINCT Sku) > 20
)

SELECT 
  COUNT(DISTINCT YearMonth) as MonthsWithOver20SKUs
FROM brand_month_sku;

-- Bilgisayar kategorisinde her item category için en çok sipariş alan bölge
WITH region_orders AS (
  SELECT 
    ItemCategoryName as ItemCategory,
    Region,
    COUNT(DISTINCT OrderNo) as OrderCount
  FROM `retail.analytics_vw_sales_kpis`
  WHERE BuyingCategory = 'Bilgisayar'
  GROUP BY ItemCategoryName, Region
),

ranked_regions AS (
  SELECT 
    ItemCategory,
    Region,
    OrderCount,
    ROW_NUMBER() OVER (PARTITION BY ItemCategory ORDER BY OrderCount DESC) as rn
  FROM region_orders
)

SELECT 
  ItemCategory,
  Region as TopRegion,
  OrderCount
FROM ranked_regions
WHERE rn = 1
ORDER BY ItemCategory;


-- Her bölge için top 3 marka (gross sales bazında)
WITH brand_region_sales AS (
  SELECT 
    Region,
    Brand,
    SUM(Sales) as GrossSales,
    COUNT(DISTINCT OrderNo) as OrderCount,
    SUM(Pcs) as TotalPieces
  FROM `retail.analytics_vw_sales_kpis`
  WHERE Brand IS NOT NULL
    AND Region IS NOT NULL
  GROUP BY Region, Brand
),

ranked_brands AS (
  SELECT 
    Region,
    Brand,
    GrossSales,
    OrderCount,
    TotalPieces,
    ROW_NUMBER() OVER (PARTITION BY Region ORDER BY GrossSales DESC) as rank
  FROM brand_region_sales
)

SELECT 
  Region,
  Brand,
  ROUND(GrossSales, 2) as GrossSales,
  OrderCount,
  TotalPieces,
  rank
FROM ranked_brands
WHERE rank <= 3
ORDER BY Region, rank;

-- 2 ay önce alışveriş yapıp sonra hiç almayan müşteriler 
WITH customer_last_purchase AS (
  SELECT 
    Customer,
    MAX(DATE(Update_Date)) as LastPurchaseDate  
  FROM `retail.analytics_vw_sales_kpis`
  GROUP BY Customer
),

data_max_date AS (
  SELECT DATE(MAX(Update_Date)) as MaxDate 
  FROM `retail.analytics_vw_sales_kpis`
)

SELECT 
  c.Customer,
  c.LastPurchaseDate,
  DATE_DIFF(d.MaxDate, c.LastPurchaseDate, MONTH) as MonthsSinceLastPurchase,
  COUNT(DISTINCT o.OrderNo) as TotalOrders,
  ROUND(SUM(o.CalculatedSales), 2) as TotalLifetimeSales
FROM customer_last_purchase c
CROSS JOIN data_max_date d
LEFT JOIN `retail.analytics_vw_sales_kpis` o
  ON c.Customer = o.Customer
WHERE DATE_DIFF(d.MaxDate, c.LastPurchaseDate, MONTH) = 2
GROUP BY c.Customer, c.LastPurchaseDate, MonthsSinceLastPurchase
ORDER BY TotalLifetimeSales DESC;

-- Yeni müşteri vs mevcut müşteri analizi
WITH date_range AS (
  SELECT 
    MAX(YearMonth) as MaxMonth,
    FORMAT_DATE('%Y-%m', 
      DATE_SUB(PARSE_DATE('%Y-%m', MAX(YearMonth)), INTERVAL 2 MONTH)
    ) as TwoMonthsAgo
  FROM `retail.analytics_vw_sales_kpis`
),

customer_first_purchase AS (
  SELECT 
    Customer,
    MIN(YearMonth) as FirstPurchaseMonth
  FROM `retail.analytics_vw_sales_kpis`
  GROUP BY Customer
),

last_2_months_customers AS (
  SELECT DISTINCT
    v.Customer,
    cfp.FirstPurchaseMonth
  FROM `retail.analytics_vw_sales_kpis` v
  INNER JOIN customer_first_purchase cfp
    ON v.Customer = cfp.Customer
  CROSS JOIN date_range dr
  WHERE v.YearMonth >= dr.TwoMonthsAgo
),

customer_classification AS (
  SELECT 
    Customer,
    FirstPurchaseMonth,
    CASE 
      WHEN FirstPurchaseMonth >= (SELECT TwoMonthsAgo FROM date_range) 
      THEN 'New'
      ELSE 'Existing'
    END as CustomerType
  FROM last_2_months_customers
)

SELECT 
  CustomerType,
  COUNT(DISTINCT Customer) as CustomerCount,
  ROUND(COUNT(DISTINCT Customer) * 100.0 / SUM(COUNT(DISTINCT Customer)) OVER (), 2) as Percentage
FROM customer_classification
GROUP BY CustomerType

UNION ALL

SELECT 
  'Total' as CustomerType,
  COUNT(DISTINCT Customer) as CustomerCount,
  100.00 as Percentage
FROM customer_classification
ORDER BY CustomerType DESC;

























