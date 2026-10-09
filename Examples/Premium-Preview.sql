-- Görünüm örneği: sunucudaki tablolara dokunmadan 100 satır üretir.
-- F5 veya Command + Return ile çalıştırın.
WITH s(n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM s WHERE n < 100
)
SELECT
  n AS [Sipariş],
  N'Müşteri ' + CAST(n AS nvarchar(10)) AS [Müşteri],
  CASE WHEN n % 3 = 0 THEN N'Ankara' ELSE N'İstanbul' END AS [Şehir],
  CAST(n * 149.90 AS decimal(12,2)) AS [Tutar],
  DATEADD(day, -n, CAST('2026-10-09' AS date)) AS [Tarih],
  CASE WHEN n % 4 = 0 THEN NULL ELSE N'Tamamlandı' END AS [Durum]
FROM s;
