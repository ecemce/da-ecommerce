-- Marketplace verisinin incelenmesi
SELECT 
  COUNT(*) as total_rows,
  COUNT(DISTINCT SKU) as unique_skus,
  COUNT(DISTINCT merchant_name) as unique_merchants,
  MIN(timestamp) as first_timestamp,
  MAX(timestamp) as last_timestamp,
  DATE_DIFF(MAX(DATE(timestamp)), MIN(DATE(timestamp)), DAY) as day_range
FROM `retail.marketplace`;

--ilgili analiz için oluşturulan view: `hbda-475216.retail.marketplace_vw`
SELECT 
  merchant_name,
  SKU,
  Brand,
  
  category_hierarchy,
  SPLIT(category_hierarchy, ':')[OFFSET(0)] AS category_lvl1,
  SPLIT(category_hierarchy, ':')[SAFE_OFFSET(1)] AS category_lvl2,
  SPLIT(category_hierarchy, ':')[SAFE_OFFSET(2)] AS category_lvl3,
  
  SAFE_CAST(SPLIT(last_and_discounted_price, ';')[OFFSET(0)] AS FLOAT64) AS last_price,
  SAFE_CAST(SPLIT(last_and_discounted_price, ';')[SAFE_OFFSET(1)] AS FLOAT64) AS discounted_price,
  
  CASE 
    WHEN SAFE_CAST(SPLIT(last_and_discounted_price, ';')[OFFSET(0)] AS FLOAT64) > 0 
    THEN ROUND(
      (SAFE_CAST(SPLIT(last_and_discounted_price, ';')[OFFSET(0)] AS FLOAT64) - 
       SAFE_CAST(SPLIT(last_and_discounted_price, ';')[SAFE_OFFSET(1)] AS FLOAT64)) / 
      SAFE_CAST(SPLIT(last_and_discounted_price, ';')[OFFSET(0)] AS FLOAT64) * 100, 2)
    ELSE 0 
  END AS discount_rate_pct,
  
  SAFE_CAST(stock_quantity AS INT64) AS stock_quantity,
  SAFE_CAST(REGEXP_EXTRACT(shipment_day, r'\d+') AS INT64) AS shipment_day_num,
  
  timestamp,
  
  DATETIME_TRUNC(timestamp, HOUR) AS hour_bucket,
  DATETIME_TRUNC(timestamp, DAY) AS day_bucket,
  
  CONCAT(
    CAST(DATE(timestamp) AS STRING), 
    '_P', 
    CAST(DIV(EXTRACT(HOUR FROM timestamp), 3) AS STRING)
  ) AS period_3h
  
FROM `hbda-475216.retail.marketplace` 
WHERE last_and_discounted_price IS NOT NULL

-- Merchant'ların genel durumu
SELECT 
  merchant_name,
  COUNT(*) as total_submissions,
  COUNT(DISTINCT SKU) as unique_skus,
  COUNT(DISTINCT period_3h) as periods_active,
  COUNT(DISTINCT day_bucket) as days_active,
  ROUND(AVG(last_price), 2) as avg_last_price,
  ROUND(AVG(discounted_price), 2) as avg_discounted_price,
  ROUND(AVG(discount_rate_pct), 2) as avg_discount_rate,
  SUM(stock_quantity) as total_stock
FROM `hbda-475216.retail.marketplace_vw`
GROUP BY merchant_name
ORDER BY total_submissions DESC;

-- Veri setindeki periyot dağılımı
SELECT 
  SUBSTR(period_3h, 1, 10) as date_part,
  SUBSTR(period_3h, 12, 2) as period_number,
  COUNT(DISTINCT merchant_name) as active_merchants,
  SUM(CASE WHEN merchant_name = 'Merchant A' THEN 1 ELSE 0 END) as merchant_a_submissions
FROM `hbda-475216.retail.marketplace_vw`
GROUP BY date_part, period_number
ORDER BY date_part, period_number;

-- Merchant A'nın SKU bazında fiyat pozisyonu
WITH sku_price_comparison AS (
  SELECT 
    SKU,
    merchant_name,
    AVG(last_price) as avg_price,
    AVG(discounted_price) as avg_discounted_price,
    AVG(discount_rate_pct) as avg_discount_rate
  FROM `hbda-475216.retail.marketplace_vw`
  GROUP BY SKU, merchant_name
),
sku_market_prices AS (
  SELECT 
    SKU,
    MIN(avg_price) as market_min_price,
    MAX(avg_price) as market_max_price,
    AVG(avg_price) as market_avg_price,
    COUNT(DISTINCT merchant_name) as competitor_count
  FROM sku_price_comparison
  GROUP BY SKU
  HAVING competitor_count > 1 
)
SELECT 
  CASE 
    WHEN spc.avg_price = smp.market_min_price THEN 'En Ucuz'
    WHEN spc.avg_price < smp.market_avg_price THEN 'Ortalamanın Altında'
    WHEN spc.avg_price = smp.market_avg_price THEN 'Ortalama'
    ELSE 'Ortalamanın Üstünde'
  END as price_position,
  COUNT(*) as sku_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM sku_price_comparison spc
JOIN sku_market_prices smp ON spc.SKU = smp.SKU
WHERE spc.merchant_name = 'Merchant A'
GROUP BY price_position
ORDER BY sku_count DESC;



-- Merchant A'nın en pahalı olduğu SKU × period kombinasyonları
WITH period_sku_prices AS (
  SELECT 
    period_3h,
    SKU,
    merchant_name,
    AVG(last_price) as avg_price_in_period,
    AVG(discounted_price) as avg_discounted_price_in_period,
    SUM(stock_quantity) as total_stock_in_period
  FROM `hbda-475216.retail.marketplace_vw`
  GROUP BY period_3h, SKU, merchant_name
),
competitive_skus AS (
  SELECT 
    period_3h,
    SKU,
    COUNT(DISTINCT merchant_name) as competitor_count,
    AVG(CASE WHEN merchant_name != 'Merchant A' THEN avg_price_in_period END) as avg_price_others,
    MAX(CASE WHEN merchant_name = 'Merchant A' THEN avg_price_in_period END) as price_merchant_a
  FROM period_sku_prices
  GROUP BY period_3h, SKU
  HAVING competitor_count > 1 AND price_merchant_a IS NOT NULL
)
SELECT 
  period_3h,
  SKU,
  ROUND(price_merchant_a, 2) as merchant_a_price,
  ROUND(avg_price_others, 2) as competitors_avg_price,
  ROUND(price_merchant_a - avg_price_others, 2) as price_difference,
  ROUND(price_merchant_a / avg_price_others, 3) as price_ratio,
  CASE 
    WHEN price_merchant_a / avg_price_others < 0.95 THEN 'Agresif Düşük'
    WHEN price_merchant_a / avg_price_others < 1.00 THEN 'Rakip Altı'
    WHEN price_merchant_a / avg_price_others <= 1.05 THEN 'Rekabetçi'
    WHEN price_merchant_a / avg_price_others <= 1.15 THEN 'Premium'
    ELSE 'Çok Yüksek'
  END as price_strategy
FROM competitive_skus
ORDER BY price_difference DESC 
LIMIT 20;

-- Kategori bazında Merchant A'nın fiyat pozisyonu
WITH period_sku_prices AS (
  SELECT 
    period_3h,
    SKU,
    category_lvl1,
    category_lvl2,
    category_lvl3,
    merchant_name,
    AVG(last_price) as avg_price_in_period
  FROM `hbda-475216.retail.marketplace_vw`
  GROUP BY period_3h, SKU, category_lvl1, category_lvl2, category_lvl3, merchant_name
),
competitive_skus AS (
  SELECT 
    period_3h,
    SKU,
    category_lvl1,
    category_lvl2,
    category_lvl3,
    COUNT(DISTINCT merchant_name) as competitor_count,
    AVG(CASE WHEN merchant_name != 'Merchant A' THEN avg_price_in_period END) as avg_price_others,
    MAX(CASE WHEN merchant_name = 'Merchant A' THEN avg_price_in_period END) as price_merchant_a
  FROM period_sku_prices
  GROUP BY period_3h, SKU, category_lvl1, category_lvl2, category_lvl3
  HAVING competitor_count > 1 AND price_merchant_a IS NOT NULL
)
SELECT 
  category_lvl1,
  category_lvl2,
  COUNT(*) as total_observations,
  COUNT(DISTINCT SKU) as unique_skus,
  ROUND(AVG(price_merchant_a), 2) as avg_merchant_a_price,
  ROUND(AVG(avg_price_others), 2) as avg_competitors_price,
  ROUND(AVG(price_merchant_a - avg_price_others), 2) as avg_price_difference,
  ROUND(AVG(price_merchant_a / avg_price_others), 3) as avg_price_ratio
FROM competitive_skus
GROUP BY category_lvl1, category_lvl2
HAVING unique_skus >= 5  
ORDER BY avg_price_difference DESC
LIMIT 15;


-- SKU bazında stok payı analizi
WITH sku_stock_analysis AS (
  SELECT 
    period_3h,
    SKU,
    merchant_name,
    AVG(stock_quantity) as avg_stock_in_period
  FROM `hbda-475216.retail.marketplace_vw`
  WHERE stock_quantity IS NOT NULL
  GROUP BY period_3h, SKU, merchant_name
),
sku_total_stock AS (
  SELECT 
    period_3h,
    SKU,
    SUM(avg_stock_in_period) as total_market_stock,
    COUNT(DISTINCT merchant_name) as merchant_count,
    MAX(CASE WHEN merchant_name = 'Merchant A' THEN avg_stock_in_period END) as merchant_a_stock
  FROM sku_stock_analysis
  GROUP BY period_3h, SKU
  HAVING merchant_count > 1 AND merchant_a_stock IS NOT NULL
)
SELECT 
  SKU,
  COUNT(*) as periods_observed,
  ROUND(AVG(merchant_a_stock), 0) as avg_merchant_a_stock,
  ROUND(AVG(total_market_stock), 0) as avg_total_market_stock,
  ROUND(AVG(merchant_a_stock / total_market_stock * 100), 2) as avg_stock_share_pct,
  ROUND(MIN(merchant_a_stock / total_market_stock * 100), 2) as min_stock_share_pct,
  ROUND(MAX(merchant_a_stock / total_market_stock * 100), 2) as max_stock_share_pct,
  CASE 
    WHEN AVG(merchant_a_stock / total_market_stock * 100) >= 70 THEN 'Dominant (70%+)'
    WHEN AVG(merchant_a_stock / total_market_stock * 100) >= 50 THEN 'Market Leader (50-70%)'
    WHEN AVG(merchant_a_stock / total_market_stock * 100) >= 30 THEN 'Strong Player (30-50%)'
    ELSE 'Follower (<30%)'
  END as market_position
FROM sku_total_stock
GROUP BY SKU
ORDER BY avg_stock_share_pct DESC
LIMIT 20;


-- Merchant A'nın market pozisyonu
WITH sku_stock_analysis AS (
  SELECT 
    period_3h,
    SKU,
    merchant_name,
    AVG(stock_quantity) as avg_stock_in_period
  FROM `hbda-475216.retail.marketplace_vw`
  WHERE stock_quantity IS NOT NULL
  GROUP BY period_3h, SKU, merchant_name
),
sku_total_stock AS (
  SELECT 
    period_3h,
    SKU,
    SUM(avg_stock_in_period) as total_market_stock,
    COUNT(DISTINCT merchant_name) as merchant_count,
    MAX(CASE WHEN merchant_name = 'Merchant A' THEN avg_stock_in_period END) as merchant_a_stock
  FROM sku_stock_analysis
  GROUP BY period_3h, SKU
  HAVING merchant_count > 1 AND merchant_a_stock IS NOT NULL
),
sku_avg_shares AS (
  SELECT 
    SKU,
    AVG(merchant_a_stock / total_market_stock * 100) as avg_stock_share_pct
  FROM sku_total_stock
  GROUP BY SKU
)
SELECT 
  CASE 
    WHEN avg_stock_share_pct >= 70 THEN 'Dominant (70%+)'
    WHEN avg_stock_share_pct >= 50 THEN 'Market Leader (50-70%)'
    WHEN avg_stock_share_pct >= 30 THEN 'Strong Player (30-50%)'
    WHEN avg_stock_share_pct >= 20 THEN 'Competitive (20-30%)'
    ELSE 'Follower (<20%)'
  END as market_position,
  COUNT(*) as sku_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage_of_portfolio,
  ROUND(MIN(avg_stock_share_pct), 2) as min_share_in_category,
  ROUND(MAX(avg_stock_share_pct), 2) as max_share_in_category,
  ROUND(AVG(avg_stock_share_pct), 2) as avg_share_in_category
FROM sku_avg_shares
GROUP BY market_position
ORDER BY 
  CASE market_position
    WHEN 'Dominant (70%+)' THEN 1
    WHEN 'Market Leader (50-70%)' THEN 2  
    WHEN 'Strong Player (30-50%)' THEN 3
    WHEN 'Competitive (20-30%)' THEN 4
    ELSE 5
  END;









