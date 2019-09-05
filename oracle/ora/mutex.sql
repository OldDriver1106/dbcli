/*[[
  Show mutex sleep info. Usage: @@NAME [<sid>] [<inst_id>]
  Refer to Doc ID 1298015.1/1298471.1/1310764.1

  Mainly used to diagnostic below events:
  =======================================
  * cursor: mutex X                  
  * cursor: mutex S                  
  * cursor: pin X                    
  * cursor: pin S                    
  * cursor: pin S wait on X          
  * library cache: mutex X           
  * library cache: bucket mutex X    
  * library cache: dependency mutex X
  * library cache: mutex S           


  Example Output:
  ================
    INST_ID        LAST_TIME           HASH    SLEEPS CNT     LOCATION      MUTEX_TYPE   OBJECT
    ------- ----------------------- ---------- ------ --- ---------------- ------------- -------------------
          2 2019-09-03 23:56:10.107 1011610568     25  25 kglhdgn2 106     Library Cache select type#,blocks
          2 2019-09-03 23:56:10.108 1736623433      5   5 kglpndl1  95     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      4   4 kgllkdl1  85     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      3   2 kglpnal1  90     Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      3   2 kglget2   2      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      2   2 kglpin1   4      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      1   1 kglpnal2  91     Library Cache SEG$
          3 2019-09-03 23:27:39.394 1736623433      3   3 kglpndl1  95     Library Cache SEG$
  --[[
        &V2: default={&instance}
        @OBJ_CACHE: {
                  12.1={(select owner to_owner,name to_name,addr to_address,TYPE,hash_value from_hash from v$db_object_cache)} 
                  default={(select a.*,
                    decode(to_type,
                          -1,'NONE',
                          0,'CURSOR',
                          1,'INDEX',
                          2,'TABLE',
                          3,'CLUSTER',
                          4,'VIEW',
                          5,'SYNONYM',
                          6,'SEQUENCE',
                          7,'PROCEDURE',
                          8,'FUNCTION',
                          9,'PACKAGE',
                          10,'NON-EXISTENT',
                          11,'PACKAGE BODY',
                          12,'TRIGGER',
                          13,'TYPE',
                          14,'TYPE BODY',
                          15,'OBJECT',
                          16,'USER',
                          17,'DBLINK',
                          18,'PIPE',
                          19,'TABLE PARTITION',
                          20,'INDEX PARTITION',
                          21,'LOB',
                          22,'LIBRARY',
                          23,'DIRECTORY',
                          24,'QUEUE',
                          25,'INDEX-ORGANIZED TABLE',
                          26,'REPLICATION OBJECT GROUP',
                          27,'REPLICATION PROPAGATOR',
                          28,'JAVA SOURCE',
                          29,'JAVA CLASS',
                          30,'JAVA RESOURCE',
                          31,'JAVA JAR',
                          32,'INDEX TYPE',
                          33,'OPERATOR',
                          34,'TABLE SUBPARTITION',
                          35,'INDEX SUBPARTITION',
                          36,'REPLICATED TABLE OBJECT',
                          37,'REPLICATION INTERNAL PACKAGE',
                          38,'CONTEXT POLICY',
                          39,'PUB SUB INTERNAL INFORMATION',
                          40,'LOB PARTITION',
                          41,'LOB SUBPARTITION',
                          42,'SUMMARY',
                          43,'DIMENSION',
                          44,'APP CONTEXT',
                          45,'STORED OUTLINE',
                          46,'RULESET',
                          47,'RESOURCE MANAGER PLAN',
                          48,'RESOURCE MANAGER CONSUMER GROUP',
                          49,'PENDING RESOURCE MANAGER PLAN',
                          50,'PENDING RESOURCE MANAGER CONSUMER GROUP',
                          51,'SUBSCRIPTION',
                          52,'LOCATION',
                          53,'REMOTE OBJECT',
                          54,'SNAPSHOT METADATA',
                          55,'XDB SCHEMA DATA',
                          56,'JAVA SHARED DATA',
                          57,'EDITION',
                          58,'TRANSFORMATION',
                          62,'RULE EVALUATION CONTEXT',
                          66,'SCHEDULER JOB',
                          67,'SCHEDULER PROGRAM',
                          68,'SCHEDULER CLASS',
                          69,'SCHEDULER WINDOW',
                          70,'MULTI-VERSIONED OBJECT',
                          72,'SCHEDULER GROUP',
                          74,'SCHEDULER SCHEDULE',
                          75,'SQL TUNING BASE OBJECT',
                          76,'HINTSET OBJECT',
                          77,'SCHEDULER GLOBAL ATTRIBUTE',
                          78,'SCHEDULER EARLIEST START TIME',
                          89,'SCHEDULER LIGHTWEIGHT JOB',
                          99,'OBJECT ID',
                          102,'CURSOR STATS',
                          109,'SECURITY CLASS',
                          110,'ACL',
                          111,'PDB',
                          115,'AUDIT POLICY',
                          126,'Optimizer Finding',
                          127,'Optimizer Directive Owner',
                          135,'USER PRIVILEGES',
                          145,'FED APP',
                          153,'CMP',
                          154,'Optimizer Expression Header',
                          155,'Optimizer Expresion Object',
                          158,'RUNTIME STATISTICS',
                          255,'NONE',
                          'INVALID TYPE:' || to_type) AS TYPE
                from v$object_dependency A)} 
                }
  --]]

]]*/

set feed off

SELECT DISTINCT *
FROM   TABLE(gv$(CURSOR ( --
          SELECT /*+ordered user_nl(b)*/
                  userenv('instance') inst_id,
                  sid,
                  a.event,
                  P1 HASH_VALUE,
                  trunc(a.p3 / 65536) mutex_location_id,
                  decode(trunc(p2 / 4294967296), 0, trunc(P2 / 65536), trunc(P2 / 4294967296)) SID_HOLDING_MUTEX,
                  a.sql_id,
                  substr(TRIM(b.to_name), 1, 100) || CASE
                      WHEN b.to_name LIKE 'table_%' AND
                           regexp_like(regexp_substr(b.to_name, '[^\_]+', 1, 4), '^[0-9A-Fa-f]+$') THEN
                       ' (obj# ' || to_number(regexp_substr(b.to_name, '[^\_]+', 1, 4), 'xxxxxxxxxx') || ')'
                  END SQL_TEXT
          FROM   v$session a, &OBJ_CACHE b
          WHERE  a.p1 = b.from_hash(+)
          AND    a.sid=nvl(0+:v1,a.sid)
          AND    a.p1text = 'idn'
          AND    a.p2text = 'value'
          AND    a.p3text = 'where'
          AND    userenv('instance') = nvl(:V2, userenv('instance')))));

SELECT * FROM (
    SELECT *
    FROM   TABLE(gv$(CURSOR(
                      SELECT  /*+ordered use_nl(b)*/
                              DISTINCT 
                              userenv('instance') inst_id,
                              a.*,
                              substr(to_name, 1, 100) OBJ
                      FROM   (
                          SELECT mutex_identifier HASH_VALUE,
                                 MAX(SLEEP_TIMESTAMP) LAST_TIME,
                                 SUM(sleeps) sleeps,
                                 COUNT(1) CNT,
                                 SUM(gets) gets,
                                 location,
                                 mutex_type,
                                 p1raw
                          FROM   v$mutex_sleep_history
                          WHERE  userenv('instance') = nvl(:V2, userenv('instance'))
                          AND   (:V1 IS NULL OR :V1 IN(requesting_session,blocking_session))
                          GROUP  BY mutex_identifier,location, mutex_type,p1raw
                      ) A,&OBJ_CACHE b
                      WHERE a.HASH_VALUE=b.from_hash(+)
                     )))
    ORDER  BY LAST_TIME DESC)
WHERE  rownum <= 50;
