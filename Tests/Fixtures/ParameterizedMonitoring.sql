-------------------------------------------------------------------------
-- Parametreler (ihtiyaca göre değiştirin)
-------------------------------------------------------------------------
DECLARE @OnlyBlocking            BIT     = 0;      -- 1 = sadece blocking zincirindeki session'lar
DECLARE @MinCPUTimeMs            INT     = 0;       -- örn. 1000  -> en az 1 sn CPU harcamış
DECLARE @MinLogicalReads         BIGINT  = 0;       -- örn. 100000
DECLARE @DBNameFilter            SYSNAME = NULL;    -- optional database name
DECLARE @ExcludeHangfirePolling  BIT     = 1;       -- Hangfire JobQueue polling gürültüsünü gizle
DECLARE @ShowIdleSessions        BIT     = 0;       -- 0 = hiçbir işe karışmayan (bloklamayan/bloklanmayan,
                                                    --     açık transaction'ı olmayan) boşta bağlantıları gizle.
                                                    -- 1 = tüm user session'ları göster (eski/tam davranış)

;WITH Blockers AS
(
    -- Aktif request üzerinden bilinen doğrudan blocker ilişkileri
    SELECT session_id, blocking_session_id
    FROM sys.dm_exec_requests WITH (NOLOCK)
    WHERE blocking_session_id <> 0

    UNION

    -- dm_os_waiting_tasks, bazı bekleme türlerinde (ör. lock dışı senkronizasyon
    -- nesneleri) dm_exec_requests'in yakalayamadığı ilişkileri de yakalar
    SELECT wt.session_id, wt.blocking_session_id
    FROM sys.dm_os_waiting_tasks wt WITH (NOLOCK)
    WHERE wt.blocking_session_id IS NOT NULL
    AND wt.blocking_session_id <> 0
    AND wt.session_id <> wt.blocking_session_id
),
BlockingChain AS
(
    -- Zincirin köküdeki session'lar: kimse tarafından bloklanmayan ama
    -- başkasını bloklayan session'lar
    SELECT DISTINCT
        b.blocking_session_id AS RootBlocker,
        b.blocking_session_id AS SessionId,
        0                     AS Level
    FROM Blockers b
    WHERE NOT EXISTS (SELECT 1 FROM Blockers b2 WHERE b2.session_id = b.blocking_session_id)

    UNION ALL

    SELECT bc.RootBlocker, b.session_id, bc.Level + 1
    FROM Blockers b
    JOIN BlockingChain bc ON b.blocking_session_id = bc.SessionId
)
SELECT
    Sid                         = CONCAT('kill ', es.session_id),
    BlockingSid                 = CASE WHEN ISNULL(er.blocking_session_id, 0) <> 0
                                    THEN CONCAT('kill ', er.blocking_session_id) END,
    RootBlockerSid              = CASE WHEN bc.RootBlocker IS NOT NULL AND bc.RootBlocker <> es.session_id
                                    THEN CONCAT('kill ', bc.RootBlocker) END,
    BlockingLevel               = bc.Level,
    LastRequestStart            = CONVERT(VARCHAR(19), es.last_request_start_time, 120),
    ProgramName                 = LEFT(es.program_name, 40),
    ReqStatus                   = er.status,
    SessStatus                  = CASE WHEN es.status IN ('sleeping', 'background') THEN 'Sleep/Bkgnd' ELSE 'Active' END,
    DBName                      = DB_NAME(COALESCE(er.database_id, es.database_id)),
    Hostname                    = es.host_name,
    LoginName                   = es.login_name,
    wait_type                   = er.wait_type,
    wait_time_ms                = er.wait_time,
    wait_resource               = er.wait_resource,
    OpenTranCount               = er.open_transaction_count,
    LogicalReads                = er.logical_reads,
    SQLText                     = st.SQLText,
    CPUTime_ms                  = es.cpu_time,
    TotalCPU_ms                 = ISNULL(es.cpu_time, 0) + ISNULL(er.cpu_time, 0),
    SessAggIO                   = es.reads + es.writes,
    MemoryUsage_8KBPages        = es.memory_usage,
    GrantedQueryMemory_Pages    = er.granted_query_memory,
    NestLevel                   = er.nest_level,
    [RowCount]                  = er.row_count,
    Writes                      = er.writes,
    Reads                       = er.reads,
    SchedulerId                 = er.scheduler_id
FROM sys.dm_exec_sessions AS es WITH (NOLOCK)
LEFT JOIN sys.dm_exec_requests AS er WITH (NOLOCK)
    ON es.session_id = er.session_id
OUTER APPLY
(
    -- Aktif request varsa er.sql_handle, yoksa (sleeping) bağlantının
    -- en son çalıştırdığı sql_handle kullanılır
    SELECT TOP (1) sql_handle = COALESCE(er.sql_handle, c.most_recent_sql_handle)
    FROM sys.dm_exec_connections c WITH (NOLOCK)
    WHERE c.session_id = es.session_id
) h
OUTER APPLY
(
    SELECT SQLText =
        REPLACE(REPLACE(
            SUBSTRING(
                t.text,
                ISNULL(er.statement_start_offset, 0) / 2 + 1,
                (
                    CASE WHEN ISNULL(er.statement_end_offset, -1) = -1
                        THEN DATALENGTH(t.text)
                        ELSE er.statement_end_offset
                    END - ISNULL(er.statement_start_offset, 0)
                ) / 2 + 1
            ),
        CHAR(10), ' '), CHAR(13), ' ')
    FROM sys.dm_exec_sql_text(h.sql_handle) t
) st
LEFT JOIN BlockingChain bc
    ON bc.SessionId = es.session_id
WHERE es.session_id <> @@SPID
AND es.is_user_process = 1
AND (@DBNameFilter IS NULL OR DB_NAME(COALESCE(er.database_id, es.database_id)) = @DBNameFilter)
AND (
        @OnlyBlocking = 0
        OR ISNULL(er.blocking_session_id, 0) <> 0
        OR EXISTS (SELECT 1 FROM Blockers b WHERE b.blocking_session_id = es.session_id)
    )
AND (@MinCPUTimeMs = 0 OR ISNULL(er.cpu_time, es.cpu_time) >= @MinCPUTimeMs)
AND (@MinLogicalReads = 0 OR ISNULL(er.logical_reads, 0) >= @MinLogicalReads)
AND (
        @ShowIdleSessions = 1
        OR er.session_id IS NOT NULL          -- şu an aktif bir sorgu çalıştırıyor
        OR bc.SessionId IS NOT NULL           -- blocking zincirine dahil (bloklamış ya da bloklanmış)
        OR ISNULL(es.open_transaction_count, 0) > 0  -- açık transaction'ı var (henüz request üretmemiş olsa bile)
    )
AND (
        @ExcludeHangfirePolling = 0
        OR st.SQLText IS NULL
        OR ISNULL(er.wait_type,'') <> N'WAITFOR'
    )
ORDER BY
    CASE WHEN bc.RootBlocker IS NOT NULL THEN 0 ELSE 1 END,  -- blocking zincirindekiler önce
    bc.RootBlocker,
    bc.Level,
    LogicalReads DESC;
