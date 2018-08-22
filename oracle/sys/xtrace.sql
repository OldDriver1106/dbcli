/*[[Show info in x$trace of a specific sid. Usage: @@NAME {<sid> [inst_id]}
  --[[
    @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
  --]]
]]*/
SELECT * FROM (
    select * from &gv
        select /*+no_expand*/ case when (select 0+regexp_substr(version,'^\d+') from v$instance)<11 then null else time/86400000000+date'2000-1-1' end "#",a.* 
        from x$trace a 
        where sid=:V1 and (:V2 is null or inst_id=:V2) and inst_id=nvl(:instance,inst_id)
    ))) a
    order by a.time desc)
WHERE ROWNUM<=300 order by time;