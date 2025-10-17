--funnel analysis için oluşturulan view: hbda-475216.retail.clickstreams_vw_fa
SELECT
  anonymousid,
  sessionid,
  userid,
  channel,
  CASE 
    WHEN LOWER(page) = 'home' THEN 'home'
    WHEN LOWER(page) = 'onboarding' THEN 'onboarding'
    WHEN LOWER(page) IN (
      'select mahalle', 'selectmahalle',
      'select ilce', 'selectilce',
      'select kayitli adres', 'selectkayitliadres'
    ) THEN 'address_selection'
  END AS page_grup,
  datetime,
  ROW_NUMBER() OVER (PARTITION BY sessionid ORDER BY datetime) AS event_sequence
FROM `retail.clickstreams`
WHERE LOWER(page) NOT IN ('others')
  AND page IS NOT NULL
  AND TRIM(page) != ''
  AND LOWER(page) IN (
      'home', 'onboarding',
      'select mahalle', 'selectmahalle',
      'select ilce', 'selectilce',
      'select kayitli adres', 'selectkayitliadres'
  )
ORDER BY sessionid, datetime



-- Funnel pathlerin analizi 
WITH session_paths AS (
  SELECT 
    sessionid,
    anonymousid as user_id,
    userid as member_id,
    channel,
    STRING_AGG(page_grup, ' -> ' ORDER BY event_sequence) as journey_path
  FROM `retail.clickstreams_vw_fa`
  GROUP BY sessionid, anonymousid, userid, channel
),

classified_paths AS (
  SELECT 
    sessionid,
    user_id,
    member_id,
    channel,
    journey_path,
    CASE 
      -- A: onboarding -> home
      WHEN journey_path = 'onboarding -> home' 
        THEN 'Start > Onboarding > Home'
      
      -- A1: sadece onboarding (exit)
      WHEN journey_path = 'onboarding' 
        THEN 'Start > Onboarding > Exit'
      
      -- B: sadece home (direkt)
      WHEN journey_path = 'home' 
        THEN 'Start > Home'
      
      -- C: address_selection -> home
      WHEN journey_path = 'address_selection -> home' 
        THEN 'Start > Address Selection > Home'
      
      -- C1: sadece address_selection (exit)
      WHEN journey_path = 'address_selection' 
        THEN 'Start > Address Selection > Exit'
      
      ELSE 'OTHER'
    END as funnel_general
  FROM session_paths
)

-- Percentage distribution
SELECT 
  funnel_general as `Funnel General`,
  
  -- Session percentage
  CONCAT(
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2), 
    '%'
  ) as `Session`,
  
  -- User percentage
  CONCAT(
    ROUND(COUNT(DISTINCT user_id) * 100.0 / (SELECT COUNT(DISTINCT user_id) FROM classified_paths WHERE funnel_general != 'OTHER'), 2),
    '%'
  ) as `User`,
  
  -- Member percentage
  CONCAT(
    ROUND(
      COUNT(DISTINCT CASE WHEN member_id IS NOT NULL AND member_id != '' THEN member_id END) * 100.0 
      / (SELECT COUNT(DISTINCT member_id) FROM classified_paths WHERE funnel_general != 'OTHER' AND member_id IS NOT NULL AND member_id != ''),
      2
    ),
    '%'
  ) as `Member`

FROM classified_paths
WHERE funnel_general != 'OTHER'
GROUP BY funnel_general
ORDER BY funnel_general;
