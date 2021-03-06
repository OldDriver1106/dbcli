/*[[
Show execution plan. Usage: @@NAME {<sql_id>|last [<plan_hash_value>|<child_number>] [format1..n]} [-all|-last|-b|-d|-s|-ol|-adv] 

Options:
    -b    : show binding variables
    -d    : only show the plan from AWR views
    -s    : the plan with the simplest 'basic' format
    -ol   : show outline information
    -adv  : the plan with the 'advanced' format
    -all  : the plan with the 'ALLSTATS ALL' format
    -last : the plan with the 'ALLSTATS LAST' format

--[[

    &STAT: default={&DF &adaptive &binds &V3 &V4 &V5 &V6 &V7 &V8 &V9}
    &V1: default={&_SQL_ID} last={X} x={X}
    &V3: none={} ol={outline alias &hint}
    &LAST: last={LAST} all={OUTLINE ALL} 
    &DF: default={ALLSTATS PARTITION REMOTE &LAST -PROJECTION -ALIAS}, basic={BASIC}, adv={advanced}, all={ALLSTATS ALL outline alias}
    &SRC: {
            default={0}, # Both
            d={2}        # Dictionary only
          }
    &binds: default={}, b={PEEKED_BINDS}
    @adaptive: 12.1={+REPORT +ADAPTIVE +METRICS} 11.2={+METRICS} default={}
    @hint    : 19={+HINT_REPORT -QBREGISTRY} DEFAULT={}
    @proj:  11.2={nvl2(projection,1+regexp_count(regexp_replace(regexp_replace(projection,'[\[.*?\]'),'\(.*?\)'),', '),null) proj} default={cast(null as number) proj}
    @check_access_ab : dba_hist_sqlbind={1} default={0}
    @check_access_awr: {
           dba_hist_sql_plan={UNION ALL
                  SELECT /*+no_expand*/ id,
                         min(id) over() minid,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         plan_hash_value,
                         2,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         dbid,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         &proj,
                         nvl2(access_predicates,CASE WHEN options LIKE 'STORAGE%' THEN 'S' ELSE 'A' END,'')||nvl2(filter_predicates,'F','')||NULLIF(search_columns,0) pred
                  FROM   dba_hist_sql_plan a
                  WHERE  a.sql_id = '&v1'
                  AND    '&v1' not in('X','&_sql_id')
                  AND    a.plan_hash_value = coalesce(:V2+0,(
                     select --+index(c.sql(WRH$_SQLSTAT.SQL_ID)) index(c.sn)
                            max(plan_hash_value) keep(dense_rank last order by snap_id)
                     from dba_hist_sqlstat c where sql_id=:V1),(
                     select max(plan_hash_value) keep(dense_rank last order by timestamp) 
                     from dba_hist_sql_plan where sql_id=:V1))} 
           default={0}
          }
    @check_access_advisor: {
           dba_advisor_sqlplans={
                  UNION ALL
                  SELECT id,
                         min(id) over() minid,
                         parent_id,
                         plan_hash_value,
                         4,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         plan_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         &proj,
                         nvl2(access_predicates,CASE WHEN options LIKE 'STORAGE%' THEN 'S' ELSE 'A' END,'')||nvl2(filter_predicates,'F','')||NULLIF(search_columns,0) pred
                  FROM   dba_advisor_sqlplans a
                  WHERE  a.sql_id = '&v1'
                  AND    '&v1' not in('X','&_sql_id')
                  AND    a.plan_hash_value = coalesce(:V2+0,(select max(plan_hash_value) keep(dense_rank last order by timestamp) from dba_advisor_sqlplans where sql_id=:V1))}
           default={}
    }

    @check_access_spm: {
           sys.sqlobj$plan={
                  UNION ALL
                  SELECT id,
                         min(id) over() minid,
                         parent_id,
                         null,
                         5,
                         TIMESTAMP,
                         NULL child_number,
                         st.sql_handle,
                         st.signature,
                         plan_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         &proj,
                         nvl2(access_predicates,CASE WHEN options LIKE 'STORAGE%' THEN 'S' ELSE 'A' END,'')||nvl2(filter_predicates,'F','')||NULLIF(search_columns,0) pred
                  FROM   sys.sql$text st,sys.sqlobj$plan a
                  WHERE  st.sql_handle = '&v1'
                  AND    '&v1' not in('X','&_sql_id')
                  AND    a.signature = st.signature
                  AND    a.plan_id = coalesce(:V2+0,(select max(plan_id) keep(dense_rank last order by timestamp) from sys.sqlobj$plan b where b.signature=a.signature))
           }
           default={}
    }
]]--
]]*/
set PRINTSIZE 9999
set feed off pipequery off verify off


VAR C REFCURSOR Binding Variables
VAR msg VARCHAR2
DECLARE/*INTERNAL_DBCLI_CMD*/
    msg       VARCHAR2(100);
    BINDS     XMLTYPE := XMLTYPE('<BINDS/>');
    ELEM      XMLTYPE;
    BIND_VAL  SYS.ANYDATA;
    BIND_TYPE VARCHAR2(128);
    DTYPE     VARCHAR2(128);
    STR_VAL   VARCHAR2(32767);
BEGIN
    IF :binds = 'PEEKED_BINDS' THEN
        FOR r IN (WITH qry AS
                       (SELECT a.*, dense_rank() over(ORDER BY decode(:V2,c,0,1),captured, r DESC) seq
                       FROM   (SELECT a.*, decode(MAX(was_captured) over(PARTITION BY r), 'YES', 0, 1) captured
                               FROM   (SELECT MAX(LAST_CAPTURED) OVER(PARTITION BY child_number,inst_id) || child_number || ':' || INST_ID r,
                                              ''||child_number c,
                                              was_captured,
                                              position,
                                              NAME,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              inst_id,
                                              last_captured,
                                              'GV$SQL_BIND_CAPTURE' SRC
                                       FROM   gv$sql_bind_capture a
                                       WHERE  sql_id = '&v1'
                                       AND    1 > &SRC
                                       $IF &check_access_ab=1 $THEN
                                       UNION ALL
                                       SELECT MAX(LAST_CAPTURED) OVER(PARTITION BY DBID,SNAP_ID,INSTANCE_NUMBER)||DBID||':'|| SNAP_ID || ':' || INSTANCE_NUMBER,
                                              ''||SNAP_ID c,
                                              was_captured,
                                              position,
                                              NAME,
                                              datatype,
                                              datatype_string,
                                              value_string,
                                              value_anydata,
                                              instance_number,
                                              last_captured,
                                              'DBA_HIST_SQLBIND' SRC
                                       FROM   dba_hist_sqlbind a
                                       WHERE  sql_id = '&v1'
                                       $END
                                       ) a) a)
                      SELECT inst_id inst,
                             position pos#,
                             qry.NAME,
                             datatype,
                             datatype_string,
                             value_string,
                             value_anydata,
                             to_char(qry.last_captured) last_captured,
                             src
                      FROM   qry
                      WHERE  seq = 1
                      ORDER  BY position) LOOP
            DTYPE    := r.datatype_string;
            BIND_VAL := r.value_anydata;
            IF BIND_VAL IS NOT NULL THEN
                CASE ANYDATA.GETTYPENAME(BIND_VAL)
                    WHEN ('SYS.NUMBER') THEN
                        STR_VAL := TO_CHAR(ANYDATA.ACCESSNUMBER(BIND_VAL));
                    WHEN ('SYS.VARCHAR2') THEN
                        STR_VAL := ANYDATA.ACCESSVARCHAR2(BIND_VAL);
                    WHEN ('SYS.DATE') THEN
                        STR_VAL := TO_CHAR(ANYDATA.ACCESSDATE(BIND_VAL));
                    WHEN ('SYS.RAW') THEN
                        STR_VAL := RAWTOHEX((ANYDATA.ACCESSRAW(BIND_VAL)));
                    WHEN ('SYS.CHAR') THEN
                        STR_VAL := ANYDATA.ACCESSCHAR(BIND_VAL);
                    WHEN ('SYS.NCHAR') THEN
                        STR_VAL := ANYDATA.ACCESSNCHAR(BIND_VAL);
                    WHEN ('SYS.NVARCHAR2') THEN
                        STR_VAL := ANYDATA.ACCESSNVARCHAR2(BIND_VAL);
                    WHEN ('SYS.UROWID') THEN
                        STR_VAL := ANYDATA.ACCESSUROWID(BIND_VAL);
                    WHEN ('SYS.TIMESTAMP') THEN
                        STR_VAL := TRIM('0' FROM ANYDATA.ACCESSTIMESTAMP(BIND_VAL));
                    ELSE
                        STR_VAL := NVL(r.value_string,'NOT AVAILABLE');
                END CASE;
            ELSE
                str_val := '<NOT CAPTURE>';
            END IF;
        
            SELECT XMLELEMENT("BIND",
                              XMLELEMENT("inst", r.inst),
                              XMLELEMENT("pos", r.pos#),
                              XMLELEMENT("name", r.name),
                              XMLELEMENT("value", nvl(str_val,r.value_string)),
                              XMLELEMENT("dtype", dtype),
                              XMLELEMENT("last_captured", r.last_captured),
                              XMLELEMENT("src", r.src))
            INTO   ELEM
            FROM   DUAL;
            BINDS := BINDS.APPENDCHILDXML('/*', ELEM);
        END LOOP;
        OPEN :C FOR
            SELECT EXTRACTVALUE(COLUMN_VALUE, '//inst') + 0 inst,
                   EXTRACTVALUE(COLUMN_VALUE, '//pos') + 0 pos#,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//name') AS VARCHAR2(128)) NAME,
                   EXTRACTVALUE(COLUMN_VALUE, '//value') VALUE,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//dtype') AS VARCHAR2(30)) data_type,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//last_captured') AS VARCHAR2(20)) last_captured,
                   CAST(EXTRACTVALUE(COLUMN_VALUE, '//src') AS VARCHAR2(30)) SOURCE
            FROM   TABLE(XMLSEQUENCE(EXTRACT(BINDS, '/BINDS/BIND')));
    END IF;
    
    IF '&v1' = '&_SQL_ID' THEN
        msg  := 'Displaying execution plan for last SQL: &_SQL_ID';
        :msg := 'PRO ' || msg || chr(10) || 'PRO ' || rpad('=', length(msg), '=');
    END IF;
END;
/

&msg

print c
WITH /*INTERNAL_DBCLI_CMD*/ sql_plan_data AS
 (SELECT /*+materialize*/*
  FROM   (SELECT /*+no_merge(a) NO_PQ_CONCURRENT_UNION*/ a.*,
                 dense_rank() OVER(ORDER BY flag, tm DESC, child_number DESC, plan_hash_value DESC,inst_id) seq
          FROM   (SELECT /*+no_expand*/ id,
                         min(id) over() minid,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         child_number    ha,
                         1               flag,
                         TIMESTAMP       tm,
                         child_number,
                         sql_id,
                         plan_hash_value,
                         inst_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         &proj,
                         nvl2(access_predicates,CASE WHEN options LIKE 'STORAGE%' THEN 'S' ELSE 'A' END,'')||nvl2(filter_predicates,'F','')||NULLIF(search_columns,0) pred
                  FROM   gv$sql_plan_statistics_all a
                  WHERE  a.sql_id = '&v1'
                  AND   ('&v1' != '&_sql_id' or inst_id=userenv('instance'))
                  AND    '&v1' !='X'
                  AND    1 > &SRC
                  AND    nvl('&V2'+0,-1) in(plan_hash_value,child_number,-1)
                  UNION ALL
                  SELECT /*+no_expand*/ id,
                         min(id) over() minid,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         plan_hash_value,
                         3,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         plan_id,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         &proj,
                         nvl2(access_predicates,CASE WHEN options LIKE 'STORAGE%' THEN 'S' ELSE 'A' END,'')||nvl2(filter_predicates,'F','')||NULLIF(search_columns,0) pred
                  FROM   all_sqlset_plans a
                  WHERE  a.sql_id = '&v1'
                  AND    '&v1' not in('X','&_sql_id')
                  AND    a.plan_hash_value = coalesce(:V2+0,(
                     select max(plan_hash_value) keep(dense_rank last order by timestamp) 
                     from all_sqlset_plans where sql_id=:V1))
                  &check_access_awr
                  &check_access_advisor
                  &check_access_spm
                  UNION  ALL
                  SELECT /*+noparallel*/
                         id,
                         min(id) over()  minid,
                         parent_id,
                         NULL            ha,
                         9               flag,
                         NULL            tm,
                         NULL,
                         ''||plan_id,
                         max(decode(id, 1, regexp_substr(regexp_substr(to_char(substr(other_xml,1,2000)), 'plan_hash_full.*?(\d+)', 1, 1, 'i'),'\d+'))) over()+0 plan_hash_value,
                         NULL,
                         qblock_name qb,
                         replace(object_alias,'"') alias,
                         &proj,
                         nvl2(access_predicates,CASE WHEN options LIKE 'STORAGE%' THEN 'S' ELSE 'A' END,'')||nvl2(filter_predicates,'F','')||NULLIF(search_columns,0) pred
                  FROM   plan_table a
                  WHERE  '&v1' not in('&_sql_id')
                  AND    plan_id=(select max(plan_id) keep(dense_rank last order by timestamp) 
                                  from plan_table
                                  where nvl(upper(:V1),'X') in(statement_id,''||plan_id,'X'))) a
         WHERE flag>=&src)
  WHERE  seq = 1),
hierarchy_data AS
 (SELECT id, parent_id,pred,qb,alias,proj,plan_hash_value,minid
  FROM   sql_plan_data
  START  WITH id = minid
  CONNECT BY PRIOR id = parent_id
  ORDER  SIBLINGS BY id DESC),
ordered_hierarchy_data AS
 (SELECT id,minid,
         parent_id AS pid,
         pred,qb,alias,proj,
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
  FROM   qry, TABLE(dbms_xplan.display( 'all_sqlset_plans',NULL,format,'plan_id=nvl('''||inst_id||''',plan_id) and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 3
  UNION ALL
  SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display( 'dba_advisor_sqlplans',NULL,format,'plan_id='||inst_id||' and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 4
  UNION ALL
  SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display( 'sys.sqlobj$plan',NULL,format,'plan_id='||inst_id||' and signature=' || plan_hash)) a
  WHERE  flag = 5
  UNION ALL
  SELECT a.*
  FROM   qry,TABLE(dbms_xplan.display('plan_table',NULL,format,'plan_id=''' || sq || '''')) a
  WHERE  flag = 9
  UNION  ALL
  SELECT a.*
  FROM   qry,TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'child_number=' || plan_hash || ' and sql_id=''' || sq ||''' and inst_id=' || inst_id)) a
  WHERE  flag = 1),
xplan_data AS
 (SELECT /*+ordered use_nl(o x) materialize no_merge(o)*/
           x.plan_table_output AS plan_table_output,
           nvl(o.id,x.oid) id,
           o.pid,
           o.pred,o.qb,o.alias,o.proj,
           o.oid,
           o.maxid,
           r,
           max(o.minid) over() as minid,
           COUNT(*) over() AS rc
  FROM   (select rownum r, 
                 CASE WHEN regexp_like(plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(plan_table_output, '[0-9]+')) END oid,
                 x.* 
         from   xplan x) x
  LEFT   OUTER JOIN ordered_hierarchy_data o
  ON     (o.id = x.oid))
SELECT plan_table_output
FROM   xplan_data --
model  dimension by (r)
measures(plan_table_output,id,maxid,pred,oid,minid,qb,alias,nullif(proj,null) proj,
         greatest(max(length(maxid)) over () + 3, 5) as csize,
         nvl(greatest(max(length(pred)) over () + 3, 7),0) as psize,
         nvl(greatest(max(length(qb)) over () + 3, 6),0) as qsize,
         nvl(greatest(max(length(alias)) over () + 3, 8),0) as asize,
         nvl(greatest(max(length(proj)) over () + 3, 7),0) as jsize,
         cast(null as varchar2(128)) as inject,
         rc)
rules sequential order (
        inject[r] = case
              when plan_table_output[cv()] like '------%' then 
                   rpad('-', csize[cv()]+psize[cv()]+jsize[cv()]+qsize[cv()]+asize[cv()]+1, '-') || '{PLAN}'  
              when id[cv()+2] = 0 then
                   '|' || lpad('Ord ', csize[cv()]) || '{PLAN}' 
                       || decode(psize[cv()],0,'',rpad(' Pred', psize[cv()]-1)||'|')
                       || lpad('Proj |', jsize[cv()]) 
                       || decode(qsize[cv()],0,'',rpad(' Q.B', qsize[cv()]-1)||'|')
                       || decode(asize[cv()],0,'',rpad(' Alias', asize[cv()]-1)||'|')
              when id[cv()] is not null then
                   '|' || lpad(oid[cv()]||' ', csize[cv()]) || '{PLAN}'  
                       || decode(psize[cv()],0,'',rpad(' '||pred[cv()], psize[cv()]-1)||'|')
                       || lpad(proj[cv()] || ' |', jsize[cv()]) 
                       || decode(qsize[cv()],0,'',rpad(' '||qb[cv()], qsize[cv()]-1)||'|')
                       || decode(asize[cv()],0,'',rpad(' '||alias[cv()] , asize[cv()]-1)||'|')
          end,
        plan_table_output[r] = case
             when inject[cv()] is not null then
                  replace(inject[cv()], '{PLAN}',plan_table_output[cv()])
             else plan_table_output[cv()]
         end)
order  by r;
