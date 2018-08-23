/*[[
Show ash wait chains. Usage: @@NAME {[<sql_id>|<sid>|-f"<filter>"] [YYMMDDHH24MI] [YYMMDDHH24MI]}|{-snap [secs]} [-sid] [-dash] [-flat]
This script references Tanel Poder's script
    --[[
        &tree  : default={1} flat={0}
        &V8    : ash={gv$active_session_history},dash={Dba_Hist_Active_Sess_History}
        &Filter: default={:V1 in(''||session_id,sql_id,sid)} -f={}
        &snap  : default={--}, snap={}
        &group : default={}, g={,&0}
        &grp1  : default={sql_ids}, sid={sids}, f={}
        &grp2  : default={sql_id}, sid={sid}, f={}
        &unit  : default={1}, dash={10}
        &INST1 : default={inst_id}, dash={instance_number}
        &OBJ   : default={dba_objects}, dash={(select obj# object_id,object_name from dba_hist_seg_stat_obj)}
        @CHECK_ACCESS_OBJ  : dba_objects={&obj}, default={all_objects}
        @INST: 11.2={'@'|| BLOCKING_INST_ID}, default={''}
        @secs: 11.2={round(sum(least(delta_time,nvl(tm_delta_db_time,delta_time)))*1e-6,2) db_time,} default={&unit}
        @exec_id:  11.2={CONNECT_BY_ROOT sql_id||nvl(sql_exec_id||to_char(sql_exec_start,'yymmddhh24miss'),session_id||','||&inst1||','||seq#) } default={null}
    --]]
]]*/

col db_time format smhd2
SET verify on feed off
var cur refcursor
BEGIN
    IF &tree=0 THEN
        open :cur for
            WITH bclass AS (SELECT class, ROWNUM r from v$waitstat),
            ash_data AS (SELECT /*+QB_NAME(ash) LEADING(a) USE_HASH(u) SWAP_JOIN_INPUTS(u) */
                        sample_time+0 stime,
                        SESSION_ID||'@'||&INST1 SID,
                        nullif(blocking_session|| &INST,'@') b_sid,
                        u.username,
                        CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
                          REGEXP_REPLACE(SUBSTR(a.program,INSTR(a.program,'(')), '\d', 'n')
                        ELSE
                            '('||REGEXP_REPLACE(REGEXP_REPLACE(a.program, '(.*)@(.*)(\(.*\))', '\1'), '\d', 'n')||')'
                        END || ' ' program2,
                        NVL(a.event||CASE WHEN p3text='class#'
                                          THEN ' ['||(SELECT class FROM bclass WHERE r = a.p3)||']' ELSE null END,'ON CPU')
                                   || ' ' event2,
                        TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p1 ELSE null END, '0XXXXXXXXXXXXXXX') p1hex,
                        TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p2 ELSE null END, '0XXXXXXXXXXXXXXX') p2hex,
                        TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p3 ELSE null END, '0XXXXXXXXXXXXXXX') p3hex,
                        a.*
                    FROM  &V8 a, dba_users u
                    WHERE a.user_id = u.user_id (+)
                    AND   sample_time BETWEEN NVL(TO_DATE(NVL(:V2,:STARTTIME),'YYMMDDHH24MI'),SYSDATE-7) AND NVL(TO_DATE(NVL(:V3,:ENDTIME),'YYMMDDHH24MI'),SYSDATE)
              &snap AND   sample_time>=sysdate - nvl(:V1,60)/86400  
              ),
            chains AS (
                SELECT /*+NO_EXPAND*/
                      level lvl,
                      sid w_sid,
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(nvl(sql_id,program2)     , '>')||decode(connect_by_isleaf,1,nvl2(b_sid,'>(Idle)','')),'(>.+?)\1+','\1 +')), '>', ' > ') sql_ids,
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(program2||event2, '>')||decode(connect_by_isleaf,1,nvl2(b_sid,'>(Idle)','')),'(>.+?)\1+','\1 +')), '>', ' > ') path, -- there's a reason why I'm doing this (ORA-30004 :)
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(sid,'>')||decode(connect_by_isleaf,1,nullif('>'||b_sid,'>')),'(>.+?)\1+','\1 +')), '>', ' > ') sids,
                      &exec_id sql_exec,
                      CONNECT_BY_ROOT current_obj# obj#,
                      CONNECT_BY_ISLEAF isleaf,
                      CONNECT_BY_ISCYCLE iscycle,
                      d.*
                FROM  ash_data d
                CONNECT BY NOCYCLE (PRIOR d.b_sid = d.sid AND PRIOR stime = stime)
                START WITH (:V1 is null and b_sid is not null or &filter)
            )
            SELECT * FROM (
                SELECT LPAD(ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100)||'%',5,' ') "%This",
                       SUM(&UNIT) AAS,count(distinct sql_exec) execs, &secs
                       &snap w_sid, b_sid,
                       (SELECT nvl(max(object_name),decode(obj#,0,'Undo Header',-1,'Undo Block',''||obj#)) FROM &CHECK_ACCESS_OBJ WHERE object_id=obj#) Waiting_object
                       &group, &grp1, path wait_chain
                FROM   chains c
                WHERE  isleaf = 1
                GROUP BY obj# &group , path,&grp1 &snap , w_sid, b_sid
                ORDER BY AAS DESC
                )
            WHERE ROWNUM <= 50;
    ELSE
        OPEN :cur FOR
            WITH bclass AS (SELECT class, ROWNUM r from v$waitstat),
            ash_data AS (SELECT /*+QB_NAME(ash) LEADING(a) USE_HASH(u) SWAP_JOIN_INPUTS(u) */
                        sample_time+0 stime,
                        SESSION_ID||'@'||&INST1 SID,
                        nullif(blocking_session|| &INST,'@') b_sid,
                        u.username,
                        CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
                          REGEXP_REPLACE(SUBSTR(a.program,INSTR(a.program,'(')), '\d', 'n')
                        ELSE
                            '('||REGEXP_REPLACE(REGEXP_REPLACE(a.program, '(.*)@(.*)(\(.*\))', '\1'), '\d', 'n')||')'
                        END || ' ' program2,
                        NVL(a.event||CASE WHEN p3text='class#'
                                          THEN ' ['||(SELECT class FROM bclass WHERE r = a.p3)||']' ELSE null END,'ON CPU')
                                   || ' ' event2,
                        TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p1 ELSE null END, '0XXXXXXXXXXXXXXX') p1hex,
                        TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p2 ELSE null END, '0XXXXXXXXXXXXXXX') p2hex,
                        TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p3 ELSE null END, '0XXXXXXXXXXXXXXX') p3hex,
                        a.*
                    FROM  &V8 a, dba_users u
                    WHERE a.user_id = u.user_id (+)
              &snap AND   sample_time>=sysdate - nvl(:V1,60)/86400
                    AND   sample_time BETWEEN NVL(TO_DATE(NVL(:V2,:STARTTIME),'YYMMDDHH24MI'),SYSDATE-7) 
                                          AND NVL(TO_DATE(NVL(:V3,:ENDTIME),'YYMMDDHH24MI'),SYSDATE)),
            chains AS (
                SELECT /*+NO_EXPAND*/
                       LEVEL lvl,
                       sid w_sid,
                       TRIM('>' FROM regexp_replace(SYS_CONNECT_BY_PATH(trim(decode(:grp2,'sql_id',nvl(sql_id, program2),&grp2)),'>') || 
                            decode(connect_by_isleaf, 1, nvl2(b_sid, decode(:grp2,'sid',b_sid,'(Idle)'), '')),'(>.+?)\1+','\1 \1')) sql_ids,
                       TRIM('>' FROM regexp_replace(SYS_CONNECT_BY_PATH(TRIM(program2 || event2), '>') || decode(connect_by_isleaf, 1, nvl2(b_sid, '(Idle)', '')), '(>.+?)\1+', '\1 \1')) p, 
                       &exec_id sql_exec,
                       CONNECT_BY_ROOT decode(:grp2,'sql_id',nvl(sql_id, program2),&grp2) root_sql,
                       trim(decode(:grp2,'sql_id',nvl(sql_id, program2),&grp2)||decode(connect_by_isleaf, 1, nvl2(b_sid, ' > '||decode(:grp2,'sid',b_sid,'(Idle)'),'')))  sq_id,
                       trim(program2 || event2||decode(connect_by_isleaf, 1, nvl2(b_sid, ' > (Idle)',''))) env,
                       COUNT(1) OVER(PARTITION BY CONNECT_BY_ROOT decode(:grp2,'sql_id',nvl(sql_id, program2),&grp2)) root_cnt,
                       d.*
                FROM  ash_data d
                CONNECT BY NOCYCLE (PRIOR d.b_sid = d.sid AND PRIOR stime = stime)
                START WITH (:V1 is null and b_sid is not null or &filter)),
            calc AS
             (SELECT root_cnt + COUNT(1) root_cnt,
                     MAX(max(current_obj#)) OVER(ORDER BY COUNT(1) DESC) current_obj#,
                     root_sql,
                     sql_ids,
                     p,
                     max(sq_id) sq_id,
                     to_char(RATIO_TO_REPORT(COUNT(*)) OVER () * 100,'990.00')||'%' pct,
                     max(env) env,
                     COUNT(DISTINCT sql_exec) execs,
                     SUM(&UNIT) aas,
                     ROW_NUMBER() OVER(ORDER BY COUNT(1) DESC,root_cnt desc,greatest(regexp_count(sql_ids,'>'),regexp_count(p,'>'))) R,
                     greatest(regexp_count(sql_ids,'>'),regexp_count(p,'>')) lvl
              FROM   chains
              GROUP  BY root_cnt, root_sql, sql_ids, p)
            SELECT pct "This(%)",
                   aas,
                   execs, root_sql root_item,
                   (SELECT nvl(max(object_name),decode(current_obj#,0,'Undo Header',-1,'Undo Block',''||current_obj#)) FROM &CHECK_ACCESS_OBJ WHERE object_id=a.current_obj#) Waiting_object,
                   decode(level,1,'',' |')||lpad(' ',(level-1)*2-1,' ')||' '||sq_id path_1,
                   decode(level,1,'',' |')||lpad(' ',(level-1)*2-1,' ')||' '||env wait_event,
                   replace(replace(replace(p,' >','(+)>'),'>',' > '),'(Idle)',' > (Idle)') full_path
            FROM   calc a
            WHERE r<=80
            START  WITH lvl = 0
            CONNECT BY NOCYCLE sql_ids LIKE PRIOR sql_ids || '%' 
                AND    p LIKE PRIOR p || '%'
                AND    lvl = PRIOR lvl + 1
            ORDER  SIBLINGS BY root_cnt DESC;
    END IF;
END;
/