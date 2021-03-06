/*[[
    Search SQLs by text. Usage: @@NAME <keyword> [-r]
    -r: the keyword is a Regular Expression, otherwise a LIKE expresssion

    --[[
        @ARGS: 1
        &filter : default={upper(sql_text_) like upper('%&V1%') or (sql_id='&v1')} r={regexp_like(sql_text_||SQL_ID,'&V1','in') or (sql_id='&v1')}
        @CHECK_ACCESS_GV: {
            GV$SQLSTATS_PLAN_HASH={V$SQLSTATS_PLAN_HASH}
            GV$SQLSTATS={V$SQLSTATS_PLAN_HASH}
            GV$SQLAREA_PLAN_HASH={V$SQLAREA_PLAN_HASH}
            GV$SQLAREA={V$SQLAREA}
            GV$SQL={V$SQL}
        }
        @CHECK_ACCESS_AWR: {
            DBA_HIST_SQLTEXT={
                UNION
                SELECT 'DBA_HIST_SQLTEXT',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_ FROM DBA_HIST_SQLTEXT A)
                WHERE  (&filter)
            }
        }

        @CHECK_ACCESS_SPM: {
            DBA_SQL_PLAN_BASELINES={
                UNION
                SELECT 'DBA_SQL_PLAN_BASELINES',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_,PLAN_NAME SQL_ID FROM DBA_SQL_PLAN_BASELINES A)
                WHERE  (&filter)
            }
        }

        @CHECK_ACCESS_SQL_PROFILES: {
            DBA_SQL_PROFILES={
                UNION
                SELECT 'DBA_SQL_PROFILES',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_,NAME SQL_ID FROM DBA_SQL_PROFILES A)
                WHERE  (&filter)
            }
        }

        @CHECK_ACCESS_SQL_PATCHES: {
            DBA_SQL_PATCHES={
                UNION
                SELECT 'DBA_SQL_PATCHES',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_,NAME SQL_ID FROM DBA_SQL_PATCHES A)
                WHERE  (&filter)
            }
        }

        @CHECK_ACCESS_SQLSET_STATEMENTS: {
            DBA_SQLSET_STATEMENTS={
                UNION
                SELECT 'DBA_SQLSET_STATEMENTS',SQL_ID,TO_CHAR(SUBSTR(SQL_TEXT,1,1000))
                FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_ FROM DBA_SQLSET_STATEMENTS A)
                WHERE  (&filter)
            }
        }

        @CHECK_ACCESS_SQL_MONITOR: {
            GV$SQL_MONITOR={
                UNION
                SELECT * FROM TABLE(gv$(CURSOR(
                    SELECT 'GV$SQL_MONITOR',SQL_ID,SQL_TEXT
                    FROM   (SELECT A.*,SQL_TEXT SQL_TEXT_ FROM V$SQL_MONITOR A)
                    WHERE  (&filter)
                )))
            }
        }
    --]]
]]*/
SELECT /*+no_expand*/
       SOURCE,SQL_ID,
       substr(TRIM(regexp_replace(replace(sql_text,chr(0)), '[' || chr(1) || chr(10) || chr(13) || chr(9) || ' ]+', ' ')), 1, 300) sql_text
FROM (
    SELECT 'G&CHECK_ACCESS_GV' SOURCE, a.*
    FROM   TABLE(gv$(CURSOR(
        SELECT sql_id,
               sql_text
        FROM   (SELECT a.*, a.SQL_FULLTEXT sql_text_ FROM &CHECK_ACCESS_GV a)
        WHERE  (&filter)))) a
    &CHECK_ACCESS_AWR
    &CHECK_ACCESS_SPM
    &CHECK_ACCESS_SQL_PROFILES
    &CHECK_ACCESS_SQL_PATCHES
    &CHECK_ACCESS_SQLSET_STATEMENTS
    &CHECK_ACCESS_SQL_MONITOR
)
WHERE ROWNUM<=100
ORDER BY 1,2
