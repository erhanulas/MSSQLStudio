-- MSSQL Studio: F5 / Command+Return çalıştırır.
-- Veritabanı değiştirmek için üstteki seçiciyi kullanın.
SELECT DB_NAME() AS [Database], @@SPID AS [Session], SYSDATETIME() AS [Server time];
GO
SELECT name, database_id, state_desc, recovery_model_desc
FROM sys.databases
ORDER BY database_id;
GO
-- Tamamlama: s. sonrasında Control+Space / Escape.
DECLARE @Sample TABLE (Id int, Name nvarchar(100), Price decimal(18,2));
INSERT INTO @Sample VALUES (1, N'Native SQL', 49.90), (2, N'İstanbul', 129.50);
SELECT s.Id, s.Name, s.Price
FROM @Sample AS s
ORDER BY s.Price DESC;
GO
PRINT N'Çoklu sonuç kümesi tamamlandı.';
