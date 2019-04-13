/*[[
Search SQL functions based on V$SQLFN_METADATA . Usage: @@NAME <keyword>

Sameple Output:
===============
ORCL> ora sqlfn like
    FUNC_ID     NAME     MINARGS MAXARGS DATATYPE  VERSION   ANALYTIC AGGREGATE OFFLOADABLE DISP_TYPE USAGE      DESCR       ARGS
    ------- ------------ ------- ------- -------- ---------- -------- --------- ----------- --------- ----- ---------------- ----
         26 OPTTLK             2       0 UNKNOWN  V6 Oracle  NO       NO        YES         REL-OP           LIKE
         27 OPTTNK             2       0 UNKNOWN  V6 Oracle  NO       NO        YES         REL-OP           NOT LIKE
         99 OPTLKO             1       0 UNKNOWN  V6 Oracle  NO       NO        NO          NORMAL           LIKE
        120 OPTTLK2            3       0 UNKNOWN  SQL/DS     NO       NO        YES         NORMAL           LIKE
        121 OPTTNK2            3       0 UNKNOWN  SQL/DS     NO       NO        YES         NORMAL           NOT LIKE
        405 OPTLLIK            2       0 UNKNOWN  V82 Oracle NO       NO        NO          NORMAL           LIKE
        406 OPTLNLIK           2       0 UNKNOWN  V82 Oracle NO       NO        NO          NORMAL           NOT LIKE
        469 OPTLIK2            2       0 UNKNOWN  V82 Oracle NO       NO        YES         NORMAL           LIKE2
        470 OPTLIK2N           2       0 UNKNOWN  V82 Oracle NO       NO        YES         NORMAL           NOT LIKE2
        471 OPTLIK2E           3       0 UNKNOWN  V82 Oracle NO       NO        YES         NORMAL           LIKE2
        472 OPTLIK2NE          3       0 UNKNOWN  V82 Oracle NO       NO        YES         NORMAL           NOT LIKE2
        473 OPTLIK4            2       0 UNKNOWN  V82 Oracle NO       NO        YES         NORMAL           LIKE4
        474 OPTLIK4N           2       0 UNKNOWN  V82 Oracle NO       NO        YES         NORMAL           NOT LIKE4

   --[[
        @ARGS: 1
   ]]--
]]*/

select a.*,(select listagg(datatype,',') within group(order by argnum) from  V$SQLFN_ARG_METADATA  where func_id=a.func_id) args
from V$SQLFN_METADATA  a
where rownum<=50
and   ((:V1 IS NULL AND OFFLOADABLE='YES')
   or  (:V1 IS NOT NULL AND  name||','||a.descr like upper('%&V1%')));