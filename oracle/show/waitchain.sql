/*[[Show info in v$wait_chains
    --[[
        @check_version: 11.2={}
    ]]--
]]*/

col in_wait format smhd2
WITH c AS(SELECT /*+materialize*/c.*, c.SID||','||c.sess_serial#||',@'||c.instance sess#,nullif(c.blocker_SID||','||c.blocker_sess_serial#||',@'||c.blocker_instance,',,@') blocker# FROM  v$wait_chains c),
    r1(cid,sess#,lv,blocker#,root) AS
     (SELECT chain_id,sess#, 0 lv,blocker#,sess# root
      FROM   c
      WHERE  nvl(blocker#,sess#)=sess#
      UNION ALL
      SELECT c.chain_id,c.sess#, r1.lv + 1,c.blocker#,r1.root
      FROM   c, r1
      WHERE  c.blocker#=r1.sess#
      AND   (c.blocker#!=c.sess# or r1.lv<2)
      AND    r1.lv < 10)
    SEARCH DEPTH FIRST BY cid SET cid_order
SELECT rpad(' ',lv*3)|| nvl(wait_event_text,chain_signature) wait_event_text,
       c.sess# sid,
       c.blocker# block_sid,
       (SELECT s1.sql_id
        FROM   gv$session s1
        WHERE  s1.inst_id = c.instance
        AND    s1.sid = c.sid
        AND    s1.serial# = c.sess_serial#) sql_id,
       (SELECT s2.sql_id
        FROM   gv$session s2
        WHERE  s2.inst_id = c.blocker_instance
        AND    s2.sid = c.blocker_sid
        AND    s2.serial# = c.blocker_sess_serial#) bl_sql_id,
       osid,
       pid,
       blocker_osid bl_osid,
       blocker_pid bl_pid,
       in_wait_secs in_wait,
       p1,
       p1_text p1text,
       p2,
       p2_text p2text,
       p3,
       p3_text p3text,
       row_wait_obj#
FROM   (select r1.*,max(lv) over(partition by root) max_lv from r1) r ,c
WHERE  c.sess#=r.sess#
  AND  (max_lv>0 or not exists(select * from v$event_name where wait_class='Idle' and name=wait_event_text) and wait_event_text!='<not in a wait>')
ORDER  BY cid_order

