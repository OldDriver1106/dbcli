/*[[
Show execution plan. Usage: @@NAME {<sql_id> [<plan_hash_value>|<child_number>] [format1..n]} [-all|-last|-b|-d|-s|-ol|-adv] 
Option:
    -b    : show binding variables
    -d    : only show the plan from AWR views
    -s    : the plan with the simplest 'basic' format
    -ol   : show outline information
    -adv  : the plan with the 'advanced' format
    -all  : the plan with the 'ALLSTATS ALL' format
    -last : the plan with the 'ALLSTATS LAST' format
--[[
    &STAT: default={&DF &adaptive &binds &V3 &V4 &V5 &V6 &V7 &V8 &V9}
    &V3: none={} ol={outline alias}
    &LAST: default={ALL} last={LAST}
    &DF: default={ALLSTATS &LAST -PROJECTION -ALIAS}, basic={BASIC}, adv={advanced}, all={ALLSTATS ALL}
    &SRC: {
            default={0}, # Both
            d={2}        # Dictionary only
          }
    &binds: default={}, b={PEEKED_BINDS}
    @adaptive: 12.1={+REPORT +ADAPTIVE +METRICS} default={}
]]--
]]*/
set PRINTSIZE 9999
set feed off pipequery off

VAR C REFCURSOR Binding Variables
BEGIN
    IF :binds='PEEKED_BINDS' THEN
        open :c for
        WITH b1 AS
         (SELECT *
          FROM   (SELECT child_number || ':' || INST_ID r,last_captured l,0 flag,:V1 sql_id
                  FROM   gv$sql_bind_capture a
                  WHERE  sql_id = :V1
                  AND    1>&SRC
                  UNION ALL
                  SELECT snap_id || ':' || instance_number r,last_captured l,1 flag,:V1
                  FROM   dba_hist_sqlbind a
                  WHERE  sql_id = :V1
                  ORDER  BY l DESC NULLS LAST)
          WHERE  ROWNUM < 2),
        qry AS (
          SELECT /*+materialize*/ * FROM
             (SELECT position, NAME, datatype_string, value_string, inst_id, last_captured,0+regexp_substr(NAME,'\d+$') seq
              FROM   gv$sql_bind_capture a, b1
              WHERE  a.sql_id = b1.sql_id and a.sql_id = :V1
              AND    child_number || ':' || INST_ID = r
              AND    flag=0
              UNION ALL
              SELECT position, NAME, datatype_string, value_string, instance_number, last_captured,0+regexp_substr(NAME,'\d+$') seq
              FROM   dba_hist_sqlbind a, b1
              WHERE  a.sql_id = b1.sql_id and a.sql_id = :V1
              AND    flag=1
              AND    snap_id || ':' || instance_number = r)),
        qry1 AS(
              SELECT distinct
                     name,
                     nvl(max(last_captured) over(partition by name),date'2000-1-1') last_captured 
              FROM qry
        )
        SELECT DISTINCT 
               qry.NAME,
               datatype_string data_type,
               nvl2(qry.last_captured,value_string,'<no capture>') VALUE,
               inst_id,
               qry.last_captured
        FROM   qry,qry1 
        WHERE  nvl(qry.last_captured,date'2000-1-1')=qry1.last_captured
        AND    qry.name=qry1.name
        ORDER  by 1;
    END IF;
END;
/

WITH sql_plan_data AS
 (SELECT /*+materialize*/*
  FROM   (SELECT /*+no_merge(a)*/ a.*,
                 dense_rank() OVER(ORDER BY flag, tm DESC, child_number DESC, plan_hash_value DESC,inst_id) seq
          FROM   (SELECT id,
                         min(id) over() minid,
                         parent_id,
                         child_number    ha,
                         0               flag,
                         TIMESTAMP       tm,
                         child_number,
                         sql_id,
                         plan_hash_value,
                         0+USERENV('INSTANCE') inst_id
                  FROM   v$sql_plan a
                  WHERE  a.sql_id = :V1
                  AND    (:V2 is null or :V2 in(plan_hash_value,child_number))
                  UNION ALL
                  SELECT id,
                         min(id) over() minid,
                         parent_id,
                         child_number    ha,
                         1               flag,
                         TIMESTAMP       tm,
                         child_number,
                         sql_id,
                         plan_hash_value,
                         inst_id
                  FROM   gv$sql_plan_statistics_all a
                  WHERE  a.sql_id = :V1
                  AND    (:V2 is null or :V2 in(plan_hash_value,child_number))
                  UNION ALL
                  SELECT /*+no_expand*/ id,
                         min(id) over() minid,
                         parent_id,
                         plan_hash_value,
                         2,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         dbid
                  FROM   dba_hist_sql_plan a
                  WHERE  a.sql_id = :V1
                  AND    a.plan_hash_value = coalesce(:V2+0,(
                     select --+index(c.sql(WRH$_SQLSTAT.SQL_ID)) index(c.sn)
                            max(plan_hash_value) keep(dense_rank last order by snap_id)
                     from dba_hist_sqlstat c where sql_id=:V1),(
                     select max(plan_hash_value) keep(dense_rank last order by timestamp) 
                     from dba_hist_sql_plan where sql_id=:V1))
                  UNION  ALL
                  SELECT /*+noparallel*/ 
                         id,
                         min(id) over()  minid,
                         parent_id,
                         NULL            ha,
                         3               flag,
                         NULL            tm,
                         NULL,
                         statement_id,
                         max(decode(id, 1, regexp_substr(to_char(substr(other_xml,1,2000)), 'plan_hash_full.*?(\d+)', 1, 1, 'i', 1))) over()+0 plan_hash_value,
                         NULL
                  FROM   plan_table a
                  WHERE  nvl(upper(:V1),'x') in(statement_id,''||plan_id,'x')
                  ) a
         WHERE flag>=&src)
  WHERE  seq = 1),
hierarchy_data AS
 (SELECT id, parent_id, plan_hash_value,minid
  FROM   sql_plan_data
  START  WITH id = minid
  CONNECT BY PRIOR id = parent_id
  ORDER  SIBLINGS BY id DESC),
ordered_hierarchy_data AS
 (SELECT /*+materialize*/
         id,minid,
         parent_id AS pid,
         plan_hash_value AS phv,
         row_number() over(PARTITION BY plan_hash_value ORDER BY rownum DESC) AS OID,
         MAX(id) over(PARTITION BY plan_hash_value) AS maxid
  FROM   hierarchy_data),
qry AS
 (SELECT DISTINCT sql_id sq,
                  flag flag,
                  '&STAT' format,
                  NVL(child_number, plan_hash_value) plan_hash,
                  inst_id
  FROM   sql_plan_data
  WHERE  rownum<2),
xplan AS
 (SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display( 'dba_hist_sql_plan',NULL,format,'dbid='||inst_id||' and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 2
  UNION ALL
  SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display_cursor(sq, plan_hash, format)) a
  WHERE  flag = 0
  UNION ALL
  SELECT a.*
  FROM   qry,TABLE(dbms_xplan.display('plan_table',NULL,format,'statement_id=''' || sq || '''')) a
  WHERE  flag = 3
  UNION  ALL
  SELECT a.*
  FROM   qry,TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'child_number=' || plan_hash || ' and sql_id=''' || sq ||''' and inst_id=' || inst_id)) a
  WHERE  flag = 1),
xplan_data AS
 (SELECT /*+ordered use_nl(o) materialize*/
           x.plan_table_output AS plan_table_output,
           nvl(o.id,CASE WHEN regexp_like(x.plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(x.plan_table_output, '[0-9]+')) END) id,
           o.pid,
           o.oid,
           o.maxid,
           rownum r,
           max(o.minid) over() as minid,
           COUNT(*) over() AS rc
  FROM   xplan x
  LEFT   OUTER JOIN ordered_hierarchy_data o
  ON     (o.id = CASE WHEN regexp_like(x.plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(x.plan_table_output, '[0-9]+')) END))
SELECT plan_table_output
FROM   xplan_data --
model  dimension by (r)
measures (plan_table_output,id,maxid,pid,oid,minid,
         greatest(max(length(maxid)) over () + 3, 6) as csize,
         cast(null as varchar2(128)) as inject,
         rc)
rules sequential order (
    inject[r] = case
          when plan_table_output[cv()] like '------%' then rpad('-', csize[cv()]*2, '-')
          when id[cv()+2] = minid[cv()]
          then '|' || lpad('Pid |', csize[cv()]) || lpad('Ord |', csize[cv()])
          when id[cv()] is not null
          then '|' || lpad(pid[cv()] || ' |', csize[cv()]) || lpad(oid[cv()] || ' |', csize[cv()])
      end,
    plan_table_output[r] = case
         when inject[cv()] like '---%'
         then inject[cv()] || plan_table_output[cv()]
         when inject[cv()] is not null
         then regexp_replace(plan_table_output[cv()], '\|', inject[cv()], 1, 2)
         else plan_table_output[cv()]
     END)
order  by r;
