/*[[Report column usages. Usage: @@NAME [owner.]<table_name>
	--[[
		@check_access_usage: SYS.COL_USAGE$/SYS.COL_GROUP_USAGE$={1} default={0}
		@ver: 11.1={}
	--]]
]]*/
SET FEED OFF VERIFY ON
ora _find_object &V1
BEGIN
	IF nvl('&object_type','x') not like 'TABLE%' THEN
		raise_application_error(-20001,'Invalid table name: '||nvl(:V1,'no input parameter'));
	END IF;
END;
/
VAR cur1 REFCURSOR "Column Usages"
VAR cur2 REFCURSOR "Column Group Usage [used by dbms_stats.create_extended_stats('&object_owner','&object_name')]"
PRO &OBJECT_TYPE &OBJECT_OWNER..&OBJECT_NAME
PRO ***********************************************
pro 
DECLARE
    c1 SYS_REFCURSOR;
    c2 SYS_REFCURSOR;
BEGIN
    $IF &check_access_usage=0 $THEN
    OPEN c1 FOR
        SELECT DBMS_STATS.REPORT_COL_USAGE('&object_owner', '&object_name') report FROM dual;
    $ELSE
    OPEN c1 FOR
        SELECT /*+ ordered use_nl(o c cu) no_expand*/
                 c.INTERNAL_COLUMN_ID intcol#,
                 C.column_name COL_NAME,
                 CU.EQUALITY_PREDS EQ_PREDS,
                 CU.EQUIJOIN_PREDS EQJ_PREDS,
                 CU.NONEQUIJOIN_PREDS NO_EQ_PREDS,
                 CU.RANGE_PREDS,
                 CU.LIKE_PREDS,
                 CU.NULL_PREDS,
                 c.histogram,
                 c.NUM_BUCKETS buckets,
                 c.sample_size,
                 c.NUM_DISTINCT,
                 c.NUM_NULLS,
                 ROUND(((SELECT rowcnt FROM sys.tab$ WHERE obj# = o.object_id) - c.num_nulls) / GREATEST(c.NUM_DISTINCT, 1), 2) card,
                 C.DATA_DEFAULT "DEFAULT",
                 c.last_analyzed
                FROM   dba_objects o, dba_tab_cols c, SYS.COL_USAGE$ CU
                WHERE  o.owner = c.owner
                AND    o.object_name = c.table_name
                AND    cu.obj#(+) = &object_id
                AND    c.INTERNAL_COLUMN_ID =cu.intcol# (+)
                AND    o.object_id = &object_id
                AND    o.object_name = '&object_name'
                AND    o.owner       = '&object_owner'
                AND    (cu.obj# is not null or c.column_name like 'SYS\_%' escape '\')
                ORDER  BY 1;
    OPEN c2 FOR
    	SELECT COLS,
    		   REGEXP_SUBSTR(cols_and_cards,'[^//]+',1,1) col_names,
    		   REGEXP_SUBSTR(cols_and_cards,'[^//]+',1,2) cards,
    		   USAGES，
    		   (SELECT distinct sys.stragg(e.extension_name||' ') over() 
		        FROM   dba_tab_cols c, dba_stat_extensions e
		        WHERE  c.owner = '&object_owner'
		        AND    c.table_name = '&object_name'
		        AND    INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ',') > 0
		        AND    e.owner = c.owner
		        AND    e.table_name = c.table_name
		        AND    instr(e.extension, '"' || c.column_name || '"') > 0
		        AND    LENGTH(extension)-LENGTH(REPLACE(extension,','))=cu.col_count-1
		        GROUP BY e.extension_name
		        HAVING COUNT(1)=cu.col_count) extension_name
    	FROM (
			SELECT CU.COLS,
			       LENGTH(cu.cols)-LENGTH(REPLACE(cu.cols,','))+1 col_count,
					(SELECT '('||listagg(C.COLUMN_NAME,',') 
								WITHIN GROUP(ORDER BY INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ','))||')/('||--
		                    listagg(ROUND((SELECT rowcnt- c.num_nulls FROM sys.tab$ WHERE obj# = cu.obj#) / GREATEST(c.NUM_DISTINCT, 1), 2) ,', ') 
		                    	WITHIN GROUP(ORDER BY INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ',')) ||')'
			        FROM   dba_tab_cols c
			        WHERE  c.owner = '&object_owner'
			        AND    c.table_name = '&object_name'
			        AND    INSTR(',' || cu.cols || ',', ',' || c.INTERNAL_COLUMN_ID || ',') > 0) cols_and_cards,
			       CASE
			           WHEN BITAND(CU.FLAGS, 1) = 1 THEN
			            'FILTER '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 2) = 2 THEN
			            'JOIN '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 4) = 4 THEN
			            'GROUP_BY '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 8) = 8 THEN
			            'EXT_STATS_CREATED '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 16) = 16 THEN
			            'SRC_DIR '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 16) = 16 THEN
			            'SRC_SEED '
			       END || --
			       CASE
			           WHEN BITAND(CU.FLAGS, 64) = 64 THEN
			            'DROPPED '
			       END USAGES,
			       CU.FLAGS USAGEFLG
			FROM   SYS.COL_GROUP_USAGE$ CU
			WHERE  OBJ#=&object_id) cu;
    $END
    :cur1 := c1;
    :cur2 := c2;
END;

/