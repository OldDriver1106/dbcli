/*[[Show the coefficient of correlation against the specific stats/event/latch/etc. Usage: @@NAME "<name>" [<samples>] [source] [-p|-k|-s] [-g]
    source:  filter by the source_table field
    -p    :  sort by the Pearson's rho correlation coefficient(CORR_S), this is the default.
    -s    :  sort by the Spearman's rho correlation coefficient(CORR_S) 
    -k    :  sort by the Kendall's tau-b correlation coefficient(CORR_K)
    -g    :  target source tables are gv$ tables instead of v$ tables
     --[[
            &V1: default={DB CPU}
            &V2: default={12}
            &BASE: p={cop} s={cox} k={cok}
            &SRC : default={v$} g={gv$}
     --]]
]]*/
SET FEED OFF VERIFY  ON
PRO Calculating [&V1]'s coefficient of correlation by taking &V2 samples, it could take &V2*5 secs...

VAR cur REFCURSOR;
DECLARE
    c      XMLTYPE;
    c1     XMLTYPE;
    target VARCHAR2(100) := :V1;
    cur    SYS_REFCURSOR;
    hdl    dbms_xmlgen.ctxHandle;
    samples PLS_INTEGER := :V2;
    st      DATE;
    ed      DATE;
    sq      VARCHAR2(32767):=q'!
        SELECT /*+materialize no_expand*/
               to_char(sysdate,'YYMMDDHH24MISS') tstamp,src, n, unit, SUM(v) v
        FROM   (SELECT 'v$sysstat' src, NAME n, 'count' unit, VALUE v
                FROM   v$sysstat
                WHERE  VALUE > 0
                UNION ALL
                SELECT 'v$system_event',event, 'us' unit, TIME_WAITED_MICRO
                FROM   v$system_event
                WHERE  TIME_WAITED_MICRO > 0
                AND    wait_class != 'Idle'
                UNION ALL
                SELECT 'v$latch', NAME, 'gets' unit, gets + immediate_gets
                FROM   v$latch
                WHERE  gets + immediate_gets > 0
                UNION ALL
                SELECT 'v$mutex_sleep', '[' || MUTEX_TYPE || ']' || TRIM(REPLACE(LOCATION, CHR(10))), 'us' unit, wait_time
                FROM   v$mutex_sleep
                WHERE  wait_time > 0
                UNION ALL
                SELECT 'v$sys_time_model', stat_name, 'us' unit, VALUE
                FROM   v$sys_time_model
                WHERE  VALUE > 0)
        GROUP  BY src, n, unit !';
BEGIN
    IF target IS NULL THEN
        raise_application_error(-20001, 'Please specify the target measure input!');
    END IF;
    sq  := replace(sq,'v$','&SRC');
    hdl := dbms_xmlgen.newcontext(sq);
    st  := SYSDATE;
    c   := dbms_xmlgen.getxmltype(hdl);
    FOR i IN 1 .. samples LOOP
        dbms_lock.sleep(5);
        dbms_xmlgen.restartquery(hdl);
        c1 := dbms_xmlgen.getxmltype(hdl);
        c  := c.appendChildXML('/ROWSET', c1.extract('/ROWSET/ROW'));
    END LOOP;
    ed  := SYSDATE;
    dbms_xmlgen.closecontext(hdl);
    OPEN cur FOR
        WITH snap AS
         (SELECT /*+materialize*/*
          FROM   (SELECT ROWNUM seq, tstamp, src, n, unit, v - LAG(v) OVER(PARTITION BY src, n ORDER BY tstamp) v
                  FROM   XMLTABLE('/ROWSET/ROW' PASSING c COLUMNS 
                                  tstamp INT PATH 'TSTAMP',
                                  src VARCHAR2(50) PATH 'SRC',
                                  n VARCHAR2(300) PATH 'N',
                                  unit VARCHAR2(30) PATH 'UNIT',
                                  v INT PATH 'V') b)
          WHERE  v IS NOT NULL),
        ranges as(SELECT tstamp,LAG(tstamp) OVER(ORDER BY tstamp) sstamp FROM (SELECT DISTINCT tstamp FROM snap)),
        ash as(
            select /*+materialize ordered no_merge(ash)*/ 
                   tstamp,sql_id,NVL(regexp_substr(program, '\(.*\)'), program) program,
                   CASE WHEN current_obj# > 1 THEN to_char(current_obj#) when current_obj#!=-1 then 'UNDO' END obj#,
                   sum(delta_time) v
            from (select * from &src.active_session_history where sample_time+0 between st and ed) ash,ranges
            where sample_time+0 between nvl(to_date(sstamp,'YYMMDDHH24MISS')+1e-5,st) and to_date(tstamp,'YYMMDDHH24MISS')
            group by tstamp,sql_id,program,CASE WHEN current_obj# > 1 THEN to_char(current_obj#) when current_obj#!=-1 then 'UNDO' END
        )，
        stats as (
            select * from snap 
            union all
            select 1e6+rownum seq,tstamp,'&src.ash' src,n,'us' unit,v
            FROM (
                select tstamp,'[SQL] '||sql_id n, sum(v) v
                from ash where sql_id is not null
                group by tstamp,sql_id
                union all
                select tstamp,'[PROGRAM] '||program,sum(v)
                from ash where program is not null
                group by tstamp,program
                union all
                select tstamp,'[OBJ#] '||obj#,sum(v)
                from ash where obj# is not null
                group by tstamp,obj#))
        select * from stats;
    --Detected error which has to split into 2 statements.  (ORA-00600: internal error code, arguments: [qcsfbdnp:1], [B1], [], [2], [], [], [], [], [], [], [], [])
    hdl:=dbms_xmlgen.newcontext(cur);
    c:=dbms_xmlgen.getxmltype(hdl);
    dbms_xmlgen.closecontext(hdl);
    open cur for    
        with stats as(select /*+materialize*/* 
                      from XMLTABLE('/ROWSET/ROW' PASSING c COLUMNS
                                  seq    INT PATH 'SEQ',
                                  tstamp INT PATH 'TSTAMP',
                                  src VARCHAR2(50) PATH 'SRC',
                                  n VARCHAR2(300) PATH 'N',
                                  unit VARCHAR2(30) PATH 'UNIT',
                                  v INT PATH 'V')),
        st2 AS
         (SELECT /*+no_expand*/ tstamp, v, seq
          FROM   stats
          WHERE  LOWER(n) = LOWER(target)
          OR     LOWER(n) LIKE '%] ' || LOWER(target)),
        res AS
         (SELECT a.*, CEIL(ROWNUM / 2) r1, MOD(ROWNUM, 2) R2
          FROM   (SELECT /*+use_hash(st1 st2) ordered*/ src,
                         unit,
                         n,
                         trunc(CORR(st1.v, st2.v) * 100, 6) cop,
                         trunc(CORR_S(NVL(st1.v, 0), nvl(st2.v, 0)) * 100, 6) cox,
                         trunc(CORR_K(NVL(st1.v, 0), nvl(st2.v, 0)) * 100, 6) cok
                  FROM   st2,(SELECT * FROM stats WHERE (:V3 is null or regexp_like(src||' '||lower(n),lower(:V3)))) st1
                  WHERE  st1.tstamp = st2.tstamp
                  AND    st2.seq != st1.seq
                  GROUP  BY src, unit, n
                  ORDER  BY ABS(&BASE) DESC NULLS LAST) a
          WHERE  ROWNUM <= 60 AND &BASE IS NOT NULL)
        SELECT MAX(DECODE(R2, 1, src)) src,
               MAX(DECODE(R2, 1, n)) NAME,
               MAX(DECODE(R2, 1, cop)) "CORR(%)",
               MAX(DECODE(R2, 1, cox)) "CORR_S(%)",
               MAX(DECODE(R2, 1, cok)) "CORR_K(%)",
               '|' "|",
               MAX(DECODE(R2, 0, src)) src,
               MAX(DECODE(R2, 0, n)) NAME,
               MAX(DECODE(R2, 0, cop)) "CORR(%)",
               MAX(DECODE(R2, 0, cox)) "CORR_S(%)",
               MAX(DECODE(R2, 0, cok)) "CORR_K(%)"
        FROM   res
        GROUP  BY r1
        ORDER  BY r1;
    :cur := cur;
END;
/