USE [AshopCommerce];
GO

DECLARE @sid varbinary(85);
DECLARE @sql nvarchar(max);
DECLARE @password nvarchar(128) = N'Dunya2!Mars1';
    

SELECT @sid = sid
FROM sys.database_principals
WHERE name = N'tancme'
  AND type = 'S'
  AND authentication_type = 1;

IF @sid IS NULL
    THROW 50000, 'SQL user tancme was not found.', 1;

IF EXISTS (
    SELECT 1
    FROM sys.server_principals
    WHERE name = N'tancme'
)
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM sys.server_principals
        WHERE name = N'tancme'
          AND sid = @sid
    )
        THROW 50001, 'Login tancme exists with a different SID.', 1;

    PRINT 'Login tancme already exists with the correct SID.';
END
ELSE
BEGIN
    SET @sql =
        N'CREATE LOGIN [tancme] WITH PASSWORD = '
        + QUOTENAME(@password, '''')
        + N', SID = ' + CONVERT(nvarchar(172), @sid, 1)
        + N', DEFAULT_DATABASE = [AshopCommerce]'
        + N', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;';

    EXEC sys.sp_executesql @sql;
    PRINT 'Login tancme created.';
END;
GO