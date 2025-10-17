-- A/B Test sonuçları karşılaştırması
WITH user_groups AS (
  SELECT 
    anonymousid,
    CASE 
      WHEN MOD(ABS(FARM_FINGERPRINT(anonymousid)), 2) = 0 THEN 'control'
      ELSE 'variant'
    END as test_group,
    MAX(CASE WHEN page = 'onboarding' THEN 1 ELSE 0 END) as saw_onboarding,
    MAX(CASE WHEN page = 'home' THEN 1 ELSE 0 END) as reached_home
  FROM `hbda-475216.retail.clickstreams`
  WHERE anonymousid IS NOT NULL
  GROUP BY anonymousid
  HAVING saw_onboarding = 1
)

SELECT 
  test_group,
  COUNT(*) as total_users,
  SUM(reached_home) as completed_users,
  ROUND(SUM(reached_home) * 100.0 / COUNT(*), 2) as completion_rate_percent
FROM user_groups
GROUP BY test_group
ORDER BY test_group;
