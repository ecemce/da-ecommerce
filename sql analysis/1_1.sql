--detaylı analiz için oluştutulan view: hbda-475216.retail.analytics_vw_sales_kpis
WITH base_orders AS (
  SELECT DISTINCT
    BuyingCategory,
    OrderNo,
    Sku,
    item_category,
    MerchantNo,
    Update_Date,
    ROUND(CAST(REPLACE(Sales, ',', '.') AS FLOAT64), 2) as Sales,
    Pcs,
    ROUND(ABS(CAST(REPLACE(ReturnSales, ',', '.') AS FLOAT64)), 2) as ReturnSales,
    ROUND(ABS(CAST(REPLACE(CancelSales, ',', '.') AS FLOAT64)), 2) as CancelSales
  FROM `hbda-475216.retail.orders` 
),
unique_customers AS (
  SELECT DISTINCT order_no, Customer, Bolge as Region
  FROM `hbda-475216.retail.customers`
),
unique_brands AS (
  SELECT DISTINCT Sku, Brand  
  FROM `hbda-475216.retail.brands`
),
unique_merchants AS (
  SELECT DISTINCT MerchantNo, MerchantName
  FROM `hbda-475216.retail.merchants`
),
unique_items AS (
  SELECT DISTINCT item_category, name as ItemCategoryName
  FROM `hbda-475216.retail.items`
)
SELECT 
  o.*,
  ROUND(o.Sales - o.ReturnSales - o.CancelSales, 2) as CalculatedSales,
  c.Customer,
  c.Region,
  b.Brand,
  COALESCE(m.MerchantName, o.MerchantNo) as MerchantName,
  i.ItemCategoryName,
  EXTRACT(YEAR FROM o.Update_Date) as Year,
  EXTRACT(MONTH FROM o.Update_Date) as Month,
  EXTRACT(QUARTER FROM o.Update_Date) as Quarter,
  DATE_TRUNC(o.Update_Date, MONTH) as YearMonth,
  FORMAT_DATE('%Y-%m', o.Update_Date) as YearMonthText
FROM base_orders o
LEFT JOIN unique_customers c ON o.OrderNo = c.order_no
LEFT JOIN unique_brands b ON o.Sku = b.Sku
LEFT JOIN unique_merchants m ON o.MerchantNo = m.MerchantNo
LEFT JOIN unique_items i ON o.item_category = i.item_category



-- ReturnSales negatif değer kontrolü için kontrol
SELECT *	
FROM `hbda-475216.retail.orders`	
WHERE SAFE_CAST(REPLACE(ReturnSales, ',', '.') AS FLOAT64) < 0;	

--Veri tipi dönüşümü yapıldı
UPDATE `hbda-475216.retail.customers`
SET Bolge = 'Akdeniz'
WHERE Bolge = 'Akden';

--Negatif ReturnSales değerlerine sahip OrderNolar kontrol edildi
SELECT 
  OrderNo,
  Sales,
  ReturnSales,
  CancelSales,
  Pcs,
  BuyingCategory,
  Update_Date
FROM `hbda-475216.retail.orders`
WHERE OrderNo IN (
  'order_11d58aac', 'order_0077a0eb', 'order_10a80c12', 'order_aa0a92b2',
  'order_6efddbe3', 'order_e8441296', 'order_4996228c', 'order_3e49e611',
  'order_6b3db554', 'order_426d15d1', 'order_180a1f1f', 'order_40ad7c0b',
  'order_442c03fc', 'order_2bc2ce93', 'order_2f5b0a45', 'order_0b10cb63'
)
ORDER BY OrderNo, Update_Date;

--Sales ve CalculatedSales farklarının bölge ve kategori bazında gruplandırılması
SELECT 
  Region,
  BuyingCategory,
  COUNT(*) as record_count,
  ROUND(SUM(Sales), 2) as total_sales,
  ROUND(SUM(CalculatedSales), 2) as total_calculated_sales,
  ROUND(SUM(ReturnSales), 2) as total_returns,
  ROUND(SUM(CancelSales), 2) as total_cancels,
  ROUND(SUM(Sales - CalculatedSales), 2) as total_difference,
  ROUND(AVG(Sales - CalculatedSales), 2) as avg_difference_per_order
FROM `hbda-475216.retail.analytics_vw_sales_kpis`
GROUP BY Region, BuyingCategory
HAVING SUM(Sales - CalculatedSales) 
ORDER BY total_difference DESC
LIMIT 20;

--Bçlge bazında sipariş değerleri
SELECT 
  Bolge as Region,
  COUNT(DISTINCT order_no) as OrderCount,
  COUNT(DISTINCT Customer) as CustomerCount
FROM `retail.customers`
GROUP BY Bolge
ORDER BY Bolge;


-- Merhcant bazında Cancel oranları
SELECT 
  MerchantName,
  COUNT(*) as total_orders,
  ROUND(SUM(CancelSales), 2) as total_cancel_amount,
  ROUND(AVG(CancelSales), 2) as avg_cancel_per_order,
  ROUND(SUM(CancelSales) / NULLIF(SUM(Sales), 0) * 100, 2) as cancel_rate_percentage,
  ROUND(SUM(Sales), 2) as total_sales
FROM `hbda-475216.retail.analytics_vw_sales_kpis`
GROUP BY MerchantName
ORDER BY avg_cancel_per_order DESC
LIMIT 15;

--Null merchantName bulgusu ve kontrolü
SELECT 
  o.MerchantNo,
  COUNT(*) as record_count,
  SUM(CAST(REPLACE(o.Sales, ',', '.') AS FLOAT64)) as total_sales
FROM `hbda-475216.retail.orders` o
LEFT JOIN `hbda-475216.retail.merchants` m ON o.MerchantNo = m.MerchantNo
WHERE m.MerchantName IS NULL
  AND CAST(REPLACE(o.Sales, ',', '.') AS FLOAT64) > 0
GROUP BY o.MerchantNo
ORDER BY total_sales DESC
LIMIT 10;

--Kış ayları ve diğer bölgelerin sezonsal kıyaslanması
SELECT 
  Region,
  CASE WHEN Month IN (12, 1, 2) THEN 'Kış' ELSE 'Diğer' END as season,
  ROUND(AVG(CancelSales), 2) as avg_cancel_per_order,
  COUNT(*) as order_count
FROM hbda-475216.retail.analytics_vw_sales_kpis
WHERE BuyingCategory = 'Bilgisayar'
GROUP BY Region, season
ORDER BY avg_cancel_per_order DESC;

--İlgili merchant bazında detaylı inceleme
SELECT 
  Region,
  BuyingCategory,
  COUNT(*) as order_count,
  ROUND(SUM(Sales), 2) as total_sales,
  ROUND(SUM(CancelSales), 2) as total_cancels,
  ROUND(SUM(ReturnSales), 2) as total_returns,
  ROUND(AVG(Sales), 2) as avg_sales_per_order
FROM `hbda-475216.retail.analytics_vw_sales_kpis`
WHERE MerchantName = 'merchantname_4c5892eb'
GROUP BY Region, BuyingCategory
ORDER BY total_sales DESC, order_count DESC;
