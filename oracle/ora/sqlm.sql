/*[[
    Get resource usage from SQL monitor. Usage: @@NAME {sql_id [<SQL_EXEC_ID>] [[plan_hash_value] -l|-a|-s]} | {. <keyword>} [-u|-f"<filter>"] [-avg]
    Related parameters for SQL monitor: 
        _sqlmon_recycle_time,_sqlmon_max_planlines,_sqlmon_max_plan,_sqlmon_threshold,control_management_pack_access,statistics_level
    -u  : Only show the SQL list within current schema
    -l  : List the records related to the specific SQL_ID
    -f  : List the records that match the predicates, i.e.: -f"MODULE='DBMS_SCHEDULER'"
    -s  : Plan format is "ALL-SESSIONS-SQL_FULLTEXT-SQL_TEXT", this is the default
    -a  : Plan format is "ALL-SQL_FULLTEXT-SQL_TEXT"
    -avg: Show avg time in case of listing the SQL monitor reports 
    
   --[[
      @ver: 12.1={} 11.2={--}
      &option : default={}, l={,sql_exec_id,plan_hash}
      &option1: default={count(distinct sql_exec_id) execs,round(sum(ELAPSED_TIME)/count(distinct sql_exec_id)*1e-6,2) avg_ela,}, l={}
      &filter: default={1=1},f={},l={sql_id=:V1},u={username=nvl('&0',sys_context('userenv','current_schema'))}
      &format: default={BASIC+PLAN+BINDS},s={ALL-SESSIONS}, a={ALL}
      &tot : default={1} avg={0}
      &avg : defult={1} avg={count(distinct sql_exec_id)}
   --]]
]]*/

set feed off VERIFY off
var c refcursor;
var c0 refcursor;
var c1 refcursor;
var rs CLOB;
var filename varchar2;
var plan_hash number;
col dur,avg_ela,ela,parse,queue,cpu,app,cc,cl,plsql,java,io,time format smhd2
col read,write,iosize,mem,temp,cellio,buffget,offload,offlrtn format kmg
col est_cost,est_rows,act_rows,ioreq,execs,outputs,FETCHES,dxwrite format TMB

DECLARE
    plan_hash  INT := regexp_substr(:V2, '^\d+$');
    start_time DATE;
    end_time   DATE;
    execs      INT;
    counter    INT := &tot;
BEGIN
    IF :V1 IS NOT NULL AND '&option' IS NULL THEN
        EXECUTE IMMEDIATE 'alter session set "_sqlmon_max_planlines"=3000';
        OPEN :c FOR
            SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(report_level => '&format-SQL_FULLTEXT-SQL_TEXT', TYPE => 'TEXT', sql_id => :V1, SQL_EXEC_ID => :V2, inst_id => :INSTANCE) AS report FROM   dual;
        BEGIN
            :rs       := DBMS_SQLTUNE.REPORT_SQL_MONITOR(report_level => 'ALL', TYPE => 'ACTIVE', sql_id => :V1, SQL_EXEC_ID => :V2, inst_id => :INSTANCE);
            :filename := 'sqlm_' || :V1 || '.html';
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    ELSE
        OPEN :c FOR
            SELECT *
            FROM   (SELECT /*+no_expand*/
                             a.sql_id &OPTION,
                             &option1 to_char(MIN(sql_exec_start), 'MMDD HH24:MI:SS') first_seen,
                             to_char(MAX(last_refresh_time), 'MMDD HH24:MI:SS') last_seen,
                             MAX(sid || ',@' || inst_id) keep(dense_rank LAST ORDER BY nvl2(px_qcsid,to_date(null),last_refresh_time) nulls first) last_sid,
                             MAX(status) keep(dense_rank LAST ORDER BY last_refresh_time, sid) last_status,
                             round(sum((last_refresh_time - sql_exec_start)*nvl2(px_qcsid,0,1))/&avg * 86400, 2) dur,
                             round(sum(ELAPSED_TIME)/&avg * 1e-6, 2) ela,
                             round(sum(QUEUING_TIME)/&avg * 1e-6, 2) QUEUE,
                             round(sum(CPU_TIME)/&avg * 1e-6, 2) CPU,
                             round(sum(APPLICATION_WAIT_TIME)/&avg * 1e-6, 2) app,
                             round(sum(CONCURRENCY_WAIT_TIME)/&avg * 1e-6, 2) cc,
                             round(sum(CLUSTER_WAIT_TIME)/&avg * 1e-6, 2) cl,
                             round(sum(PLSQL_EXEC_TIME)/&avg * 1e-6, 2) plsql,
                             round(sum(JAVA_EXEC_TIME)/&avg * 1e-6, 2) JAVA,
                             round(sum(USER_IO_WAIT_TIME)/&avg * 1e-6, 2) io,
                             round(sum(PHYSICAL_READ_BYTES)/&avg, 2) READ,
                             round(sum(PHYSICAL_WRITE_BYTES)/&avg, 2) WRITE,
                             substr(regexp_replace(regexp_replace(MAX(sql_text), '^\s+|[' || CHR(10) || CHR(13) || ']'), '\s{2,}', ' '), 1, 200) sql_text
                    FROM   (SELECT a.*, SQL_PLAN_HASH_VALUE plan_hash
                            FROM   gv$sql_monitor a
                            WHERE  NOT regexp_like(a.process_name, '^[pP]\d+$')
                            AND    (plan_hash IS NULL AND :V2 IS NOT NULL OR NOT regexp_like(upper(TRIM(SQL_TEXT)), '^(BEGIN|DECLARE|CALL)'))
                            AND    (:V2 IS NULL OR a.sql_id ||'_'|| sql_plan_hash_value||'_'|| sql_exec_id || lower(sql_text) LIKE '%' || lower(:V2) || '%')
                            AND    (&filter)) a
                    GROUP  BY sql_id &OPTION
                    ORDER  BY last_seen DESC)
            WHERE  ROWNUM <= 100
            ORDER  BY last_seen, ela;
        IF :V1 IS NOT NULL AND '&option' IS NOT NULL THEN
            SELECT /*+no_expand*/ MAX(sql_plan_hash_value) KEEP(DENSE_RANK LAST ORDER BY SQL_EXEC_START) INTO plan_hash 
            FROM  gv$sql_monitor 
            WHERE sql_id = :V1 AND (plan_hash IS NULL OR plan_hash in(sql_exec_id,sql_plan_hash_value));
        
            IF plan_hash IS NOT NULL THEN
                SELECT MIN(sql_exec_start), MAX(last_refresh_time), COUNT(DISTINCT sql_exec_id)
                INTO   start_time, end_time, execs
                FROM   gv$sql_monitor
                WHERE  sql_id = :V1
                AND    sql_plan_hash_value = plan_hash;
            
                IF counter = 0 THEN
                    counter := execs;
                END IF;
            
                OPEN :c0 FOR
                    SELECT DECODE(phv, plan_hash, '*', ' ') || phv plan_hash,
                           COUNT(DISTINCT sql_exec_id) execs,
                           SUM(nvl2(ERROR_MESSAGE, 1, 0)) errs,
                           round(SUM(FETCHES), 2) FETCHES,
                           to_char(MIN(sql_exec_start), 'MMDD HH24:MI:SS') first_seen,
                           to_char(MAX(last_refresh_time), 'MMDD HH24:MI:SS') last_seen,
                           round(SUM((last_refresh_time - sql_exec_start)*nvl2(px_qcsid,0,1)) * 86400/&avg, 2) dur,
                           round(SUM((first_refresh_time - sql_exec_start)*nvl2(px_qcsid,0,1)) * 86300/&avg, 2) parse,
                           round(SUM(ELAPSED_TIME) * 1e-6 /&avg, 2) ela,
                           round(SUM(QUEUING_TIME) * 1e-6 /&avg, 2) QUEUE,
                           round(SUM(CPU_TIME) * 1e-6 /&avg, 2) CPU,
                           round(SUM(APPLICATION_WAIT_TIME) * 1e-6 /&avg, 2) app,
                           round(SUM(CONCURRENCY_WAIT_TIME) * 1e-6 /&avg, 2) cc,
                           round(SUM(CLUSTER_WAIT_TIME) * 1e-6 /&avg, 2) cl,
                           round(SUM(PLSQL_EXEC_TIME) * 1e-6 /&avg, 2) plsql,
                           round(SUM(JAVA_EXEC_TIME) * 1e-6 /&avg, 2) JAVA,
                           round(SUM(USER_IO_WAIT_TIME) * 1e-6 /&avg, 2) io,
                           round(SUM(io_interconnect_bytes) /&avg, 2) cellio,
                           round(SUM(PHYSICAL_READ_BYTES) /&avg, 2) READ,
                           round(SUM(PHYSICAL_WRITE_BYTES) /&avg, 2) WRITE,
                           round(SUM(DIRECT_WRITES) /&avg, 2) dxwrite,
                           round(SUM(BUFFER_GETS)*8192 /&avg, 2) buffget,
                           &ver round(SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES) /&avg, 2) offload,
                           &ver round(SUM(IO_CELL_OFFLOAD_RETURNED_BYTES) /&avg, 2) offlrtn,
                           MAX(PX_MAXDOP) DOP,
                           MAX(DOPS) SIDS,
                           regexp_replace(MAX(ERROR_MESSAGE) keep(dense_rank LAST ORDER BY nvl2(ERROR_MESSAGE, last_refresh_time, NULL) NULLS FIRST),'[' || chr(9) || chr(10) || chr(13) || ' ]+', ' ') last_error
                    FROM   (SELECT a.*,sql_plan_hash_value phv,
                                   count(distinct inst_id||','||sid) over(partition by sql_exec_id) dops 
                            FROM gv$sql_monitor a WHERE sql_id = :V1) b
                    GROUP  BY phv
                    ORDER  BY decode(phv, plan_hash, SYSDATE + 1, MAX(last_refresh_time));
            
                OPEN :c1 FOR
                    WITH ASH AS
                     (SELECT /*+materialize*/id, SUM(cnt) aas, MAX(SUBSTR(event, 1, 30) || '(' || cnt || ')') keep(dense_rank LAST ORDER BY cnt) top_event
                      FROM   (SELECT id, nvl(event, 'ON CPU') event, round(SUM(flag) / counter, 3) cnt
                              FROM   (SELECT a.*, rank() over(PARTITION BY sql_exec_id ORDER BY flag) r
                                      FROM   (SELECT SQL_PLAN_LINE_ID id, event, current_obj#, sql_exec_id, 1 flag
                                              FROM   gv$active_session_history
                                              WHERE  sql_id = :V1
                                              AND    sql_plan_hash_value = plan_hash
                                              AND    sample_time BETWEEN start_time AND end_time
                                              UNION ALL
                                              SELECT SQL_PLAN_LINE_ID id, event, current_obj#, sql_exec_id, 10 flag
                                              FROM   dba_hist_active_sess_history
                                              WHERE  sql_id = :V1
                                              AND    sql_plan_hash_value = plan_hash
                                              AND    sample_time BETWEEN start_time AND end_time) a)
                              WHERE  r = 1
                              GROUP  BY id, event)
                      GROUP  BY id),
                    SQLM as (SELECT /*+materialize*/ plan_line_id ID,
                                   MAX(plan_parent_id) pid,
                                   MIN(lpad(' ', plan_depth, ' ') || plan_operation || NULLIF(' ' || plan_options, ' ')) operation,
                                   MAX(plan_object_name) name,
                                   round(SUM(TIME) / counter, 3) TIME,
                                   round(100 * SUM(TIME) / NULLIF(SUM(tick),0), 2) "%",
                                   --MAX(plan_cost) est_cost,
                                   MAX(plan_cardinality) est_rows,
                                   round(SUM(output_rows) / execs, 2) act_rows,
                                   round(SUM(starts) / execs, 2) execs,
                                   round(SUM(output_rows) / counter, 3) outputs,
                                   round(SUM(io_interconnect_bytes) / counter, 3) cellio,
                                   round(SUM(physical_read_bytes + physical_write_bytes) / counter, 3) iosize,
                                   round(SUM(physical_read_requests + physical_write_requests) / counter, 3) ioreq,
                                   MAX(workarea_max_mem) mem,
                                   MAX(workarea_max_tempseg) temp
                            FROM   (SELECT a.*, ((b.last_refresh_time - b.sql_exec_start)*86400+1)*NVL2(b.px_qcsid,0,1) tick,
                                           ((max(last_change_time)  over(partition by b.sql_exec_id,plan_line_id)-
                                            min(first_change_time) over(partition by b.sql_exec_id,plan_line_id))*86400+1)*NVL2(b.px_qcsid,0,1) TIME
                                    FROM   gv$sql_plan_monitor a, gv$sql_monitor b
                                    WHERE  b.sql_id = :V1
                                    AND    b.sql_plan_hash_value = plan_hash
                                    AND    b.sql_id = a.sql_id
                                    AND    b.sql_exec_id = a.sql_exec_id
                                    AND    b.inst_id = a.inst_id
                                    AND    b.sid = a.sid
                                    AND    b.sql_plan_hash_value = a.sql_plan_hash_value)
                            GROUP  BY plan_line_id)
                    SELECT row_number() over(ORDER BY rownum DESC) OID, m.*
                    FROM   (select * FROM (SELECT * FROM SQLM LEFT JOIN ash USING (id)) START WITH ID = (SELECT MIN(id) FROM SQLM) CONNECT BY PRIOR id = pid ORDER SIBLINGS BY id DESC) m
                    ORDER  BY id;
            END IF;
        END IF;
    END IF;
END;
/
print c;
save rs filename
set colsep |
print c0;
print c1;

