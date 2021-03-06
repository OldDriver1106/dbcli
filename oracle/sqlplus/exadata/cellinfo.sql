SET PAGES 999 feed off
SELECT b.*
FROM   v$cell_config a,
       XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                cell VARCHAR2(20) path 'name',
                "upTime" VARCHAR2(15) path 'upTime',
                "accessLevelPerm" VARCHAR2(20) path 'accessLevelPerm',
                "status" VARCHAR2(15) path 'status',
                "bbuStatus" VARCHAR2(15) path 'bbuStatus',
                "cpuCount" VARCHAR2(8) path 'cpuCount',
                "memoryGB" VARCHAR2(8) path 'memoryGB',
                "ramCacheMode" VARCHAR2(4) path 'ramCacheMode',
                "ramCacheMaxGB" NUMBER(8) path 'round(ramCacheMaxSize div 1073741824)',
                "ramCacheGB" NUMBER(8) path 'round(ramCacheSize div 1073741824)',
                "temperature" NUMBER(3) path 'temperatureReading',
                "diagHistoryDays" NUMBER(5) path 'diagHistoryDays',
                "fanCount" VARCHAR2(5) path 'fanCount',
                "fanStatus" VARCHAR2(15) path 'fanStatus',
                "flashCacheMode" VARCHAR2(12) path 'flashCacheMode',
                --"flashCacheCompress" VARCHAR2(300) path 'flashCacheCompress',
                "id" VARCHAR2(15) path 'id',
                "cellVersion" VARCHAR2(40) path 'cellVersion',
                "interconnectCount" number(2) path 'interconnectCount',
                "interconnect1" VARCHAR2(10) path 'interconnect1',
                "interconnect2" VARCHAR2(10) path 'interconnect2',
                "iormBoost" VARCHAR2(10) path 'iormBoost',
                "ipaddress1" VARCHAR2(20) path 'ipaddress1',
                "ipaddress2" VARCHAR2(20) path 'ipaddress2',
                "kernelVersion" VARCHAR2(30) path 'kernelVersion',
                "locatorLEDStatus" VARCHAR2(8) path 'locatorLEDStatus',
                "makeModel" VARCHAR2(60) path 'makeModel',
                "metricHistoryDays" NUMBER(5) path 'metricHistoryDays',
                "notificationMethod" VARCHAR2(10) path 'notificationMethod',
                "notificationPolicy" VARCHAR2(25) path 'notificationPolicy',
                "smtpPort" NUMBER(5) path 'smtpPort',
                "smtpServer" VARCHAR2(30) path 'smtpServer',
                "smtpToAddr" VARCHAR2(100) path 'smtpToAddr',
                "smtpUseSSL" VARCHAR2(5) path 'smtpUseSSL',
                "offloadGroupEvents" VARCHAR2(20) path 'offloadGroupEvents',
                "powerCount" VARCHAR2(9) path 'powerCount',
                "powerStatus" VARCHAR2(15) path 'powerStatus',
                "releaseImageStatus" VARCHAR2(15) path 'releaseImageStatus',
                "releaseVersion" VARCHAR2(25) path 'releaseVersion',
                "rpmVersion" VARCHAR2(50) path 'rpmVersion',
                "releaseTrackingBug" number(15) path 'releaseTrackingBug',
                "rollbackVersion" VARCHAR2(30) path 'rollbackVersion',
                "temperatureStatus" VARCHAR2(15) path 'temperatureStatus',
                "usbStatus" VARCHAR2(15) path 'usbStatus') b
WHERE  conftype = 'CELL'
ORDER BY 1;

COL CELL FOR A20
COL FD FOR 9999
COL HD FOR 9999
COL ram_hit for 999.99 heading "RAM|Hit %" JUS CENTER 
COL fc_hit for 999.99  heading "FlashCache|Hit %" JUS CENTER 
COL fcc_hit for 999.99  heading "Columnar|Hit %" JUS CENTER 
COL allocfc heading     "Allocated|FlashCache" JUSTIFY CENTER
COL allocoltp heading   "Allocated|For OLTP" JUSTIFY CENTER
COL allocdirty heading  "Allocated|For Dirty" FOR A10 JUSTIFY CENTER
col total_size heading "Total|Size" JUS CENTER
COL used heading "Total|Used" JUS CENTER
col oltp_used heading "OLTP|Used" JUS CENTER
col cc_used heading "Columnar|Used" JUS CENTER
COL "|" FOR A1
COL ALLOC_RAM HEADING "Allocated|RAM" Just center
COL RAM_OLTP HEADING "RAM For|OLTP" Just center

SELECT NVL(CELL,'--TOTAL--') cell,
       CAST(DBMS_XPLAN.FORMAT_SIZE(SUM(decode("flashCacheStatus",'normal',"FlashCache"))) AS VARCHAR2(10)) "FlashCache",
       CAST(DBMS_XPLAN.FORMAT_SIZE(SUM(decode("flashCacheStatus",'normal',"FlashLog"))) AS VARCHAR2(10)) "FlashLog",
       SUM("CellDisks") "CellDisks",
       SUM("GridDisks") "GridDisks",
       SUM("HardDisks") "HardDisks",
       SUM("FlashDisks") "FlashDisks",
       SUM("maxHDIOPS") "HDmaxIOPS",
       SUM("maxFDIOPS") "FDmaxIOPS",
       SUM("maxHDMBPS") "HDmaxMBPS",
       SUM("maxFDMBPS") "FDmaxMBPS",
       SUM("dwhHDQL") "HDdwhQL",
       SUM("dwhFDQL") "FDdwhQL",
       SUM("oltpHDQL") "HDoltpQL",
       SUM("oltpFDQL") "FDoltpQL",
       CAST(MAX("hardDiskType") AS VARCHAR2(10)) "hardDiskType",
       CAST(MAX("flashDiskType") AS VARCHAR2(10)) "flashDiskType"
FROM   (SELECT extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell, b.*
        FROM   v$cell_config_info a,
               XMLTABLE('/cli-output/not-set' PASSING xmltype(a.confval) COLUMNS --
                        "FlashCache" INT path 'effectiveFlashCacheSize', "FlashLog" INT path 'effectiveFlashLogSize',
                        "GridDisks" INT path 'numGridDisks', "CellDisks" INT path 'numCellDisks', "HardDisks" INT path 'numHardDisks',
                        "FlashDisks" INT path 'numFlashDisks', "maxHDIOPS" INT path 'maxPDIOPS', "maxFDIOPS" INT path 'maxFDIOPS',
                        "maxHDMBPS" INT path 'maxPDMBPS', "maxFDMBPS" INT path 'maxFDMBPS', "dwhHDQL" INT path 'dwhPDQL', "dwhFDQL" INT path 'dwhFDQL',
                        "oltpHDQL" INT path 'oltpPDQL', "oltpFDQL" INT path 'oltpFDQL', "hardDiskType" VARCHAR2(300) path 'hardDiskType',
                        "flashDiskType" VARCHAR2(300) path 'flashDiskType', "flashCacheStatus" VARCHAR2(300) path 'flashCacheStatus',
                        "cellPkg" VARCHAR2(300) path 'cellPkg') b
        WHERE  conftype = 'AWRXML')
GROUP  BY ROLLUP(CELL);

WITH gstats as(
    SELECT nvl(cell_hash,0) cellhash,metric_name n, sum(metric_value) v
    FROM  v$cell_global
    group by metric_name,rollup(cell_hash))
SELECT * FROM (
    SELECT  NVL((SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELLNAME
                    AND    rownum < 2),'--TOTAL--') cell,
            nvl(cellhash,0) cellhash,
            SUM(DECODE(disktype, 'HardDisk', 1,0)) HD,
            SUM(DECODE(disktype, 'HardDisk', 0,1))  FD,
            CAST(DBMS_XPLAN.FORMAT_SIZE(SUM(DECODE(disktype, 'HardDisk', siz))) AS VARCHAR2(8)) HD_SIZE,
            CAST(DBMS_XPLAN.FORMAT_SIZE(SUM(DECODE(disktype, 'FlashDisk', siz))) AS VARCHAR2(8)) FD_SIZE,
            CAST(DBMS_XPLAN.FORMAT_SIZE(SUM(siz)) AS VARCHAR2(8)) total_size,
            CAST(DBMS_XPLAN.FORMAT_SIZE(SUM(freeSpace)) AS VARCHAR2(8)) unalloc,
            '|' "|"
    FROM   (SELECT  CELLNAME,CELLHASH,
                    b.*
            FROM   v$cell_config a,
            XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                        NAME VARCHAR2(300) path 'name',
                        diskType VARCHAR2(300) path 'diskType',
                        siz INT path 'size',
                        freeSpace INT path 'freeSpace') b
            WHERE  conftype = 'CELLDISKS') a
    GROUP  BY rollup((cellname,CELLHASH)))
RIGHT JOIN (
    select cellhash,
           round(sum(decode(n,'RAM cache read requests hit',v))/nullif(sum(decode(n,'RAM cache read requests hit',v,'RAM cache read misses',v)),0)*100,2) ram_hit,
           round(sum(decode(n,'Flash cache read requests hit',v))/nullif(sum(decode(n,'Flash cache read requests hit',v,'Flash cache misses and partial hits',v)),0)*100,2) fc_hit,
           round(sum(decode(n,'Flash cache read requests - columnar',v))/nullif(sum(decode(n,'Flash cache columnar read requests eligible',v)),0)*100,2) fcc_hit,
           '|' "|"
    from gstats
    group by cellhash       
    )
USING(cellhash)
RIGHT JOIN (
    SELECT * FROM (
        SELECT cellhash, n, 
               CAST(trim(DBMS_XPLAN.FORMAT_SIZE(v)) AS VARCHAR2(8)) v 
        FROM  gstats
        WHERE n LIKE '%alloc%' OR n LIKE '%use%' 
    ) PIVOT (
            MAX(v) FOR n IN(
            'Flash cache bytes allocated' AS allocfc,
            'Flash cache bytes allocated for OLTP data' AS allocoltp,
            'Flash cache bytes allocated for unflushed data' AS allocdirty,
            'Flash cache bytes used' AS used,
            'Flash cache bytes used for OLTP data' AS oltp_used,
            'Flash cache bytes used - columnar' AS cc_used,
            'RAM cache bytes allocated' as ALLOC_RAM,
            'RAM cache bytes allocated for OLTP data' as RAM_OLTP))) b 
USING(cellhash);

col "Offline|Disks" heading "Offline|Disks"
col "Flash|Disks" heading " Flash|Disks"
col "Offline|Disks" heading "Offline|Disks"
col "Flash|Cache" heading "Flash|Cache"
col "Disk|Size" heading "Disk|Size"
col  "Disk Group|Total Size" heading  "Disk Group|Total Size"
col "Disk Group|Free Size" heading "Disk Group|Free Size"
col "Usable|Size" heading "Usable|Size"
WITH grid AS(
    SELECT cellDisk,
           DISKGROUP,
           SUM(decode(diskType, 'HardDisk', 1, 0)) hd,
           SUM(decode(diskType, 'HardDisk', 0, 1)) fd,
           sum(errors) errors,
           sum(decode(status,'active',0,decode(trim(asmDiskName),'',0,1))) offlines,
           sum(siz) siz,
           sum(decode(trim(asmDiskName),'',siz,0)) usize,
           max(decode(trim(trim('"' from cachedBy)),'','N','Y')) fc
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/griddisk' PASSING xmltype(a.confval) COLUMNS --
                    cellDisk VARCHAR2(300) path 'cellDisk', "name" VARCHAR2(300) path 'name', diskType VARCHAR2(300) path 'diskType',
                    errors VARCHAR2(300) path 'errorCount',
                    siz INT path 'size',
                    status varchar2(30) path 'status',
                    DISKGROUP VARCHAR2(300) path 'asmDiskGroupName', asmDiskName VARCHAR2(300) path 'asmDiskName',
                    FAILGROUP VARCHAR2(300) path 'asmFailGroupName', "availableTo" VARCHAR2(300) path 'availableTo',
                    cachedBy VARCHAR2(300) path 'cachedBy', "cachingPolicy" VARCHAR2(300) path 'cachingPolicy',
                    "creationTime" VARCHAR2(300) path 'creationTime', "id" VARCHAR2(300) path 'id') b
    WHERE  conftype = 'GRIDDISKS'
    group  by DISKGROUP,celldisk),
 cell as(
    SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                    cellDisk VARCHAR2(300) path 'name',
                    siz INT path 'size',
                    diskType VARCHAR2(300) path 'diskType',
                    errors int path 'errorCount',
                    freeSpace INT path 'freeSpace') b
    WHERE  conftype = 'CELLDISKS'),
 storage as(
      select nvl(DISKGROUP,'(Free)') DISKGROUP,
             sum(nvl(hd,decode(diskType, 'HardDisk', 1, 0))) hd,
             sum(nvl(fd,decode(diskType, 'HardDisk', 0, 1))) fd,
             sum(nvl(offlines,1)) offlines,
             sum(nvl(g.errors,0)) errors,
             sum(nvl(g.siz,c.siz)) gsize,
             sum(c.siz-c.freeSpace-nvl(g.siz,0)) csize, 
             sum(c.freeSpace+nvl(g.usize,0)) usize,
             max(fc) fc
      from   cell c left join grid g using(cellDisk)
      group  by diskgroup
        )
SELECT  /*+no_merge(c) no_merge(a) use_hash(c a)*/
        DISTINCT a.*, cast(listagg(decode(mod(r,8),0,chr(10),'')||tbs,',') WITHIN GROUP(ORDER BY tbs) OVER(PARTITION BY DISKGROUP) as varchar2(200)) tablespaces
FROM   (SELECT  /*+no_merge(c) no_merge(b) use_hash(c b a)*/
                cast(nvl(diskgroup,'--TOTAL--') as varchar2(20)) diskgroup,
                a.type type,
                cast(a.DATABASE_COMPATIBILITY as varchar2(15)) "DB_COMP",
                SUM(hd)  "Hard|Disks",
                SUM(fd) "Flash|Disks",
                sum(greatest(nvl(a.OFFLINE_DISKS,0),b.offlines)) "Offline|Disks",
                sum(b.errors) errs,
                Cast(MAX(fc) as VARCHAR2(5)) "Flash|Cache",
                CAST(trim(DBMS_XPLAN.FORMAT_SIZE(sum(gsize))) AS VARCHAR2(11)) "Disk|Size",
                CAST(trim(DBMS_XPLAN.FORMAT_SIZE(SUM(a.TOTAL_MB) * 1024 * 1024)) AS VARCHAR2(11))  "Disk Group|Total Size",
                CAST(trim(DBMS_XPLAN.FORMAT_SIZE(SUM(a.FREE_MB) * 1024 * 1024)) AS VARCHAR2(11)) "Disk Group|Free Size",
                CAST(trim(DBMS_XPLAN.FORMAT_SIZE(SUM(a.USABLE_FILE_MB) * 1024 * 1024)) AS VARCHAR2(11)) "Usable|Size"
                --,regexp_replace(listagg(b.FAILGROUP, '/') WITHIN GROUP(ORDER BY b.failgroup), '([^/]+)(/\1)+', '\1') failgroups
        FROM    storage b,
                v$asm_diskgroup a
        WHERE  a.name(+) = b.DISKGROUP
        GROUP  BY rollup((DISKGROUP,type,DATABASE_COMPATIBILITY))) a,
(SELECT c.*,row_number() over(PARTITION by dg order by tbs) r
 FROM
    (SELECT DISTINCT tbs, regexp_substr(FILE_NAME, '[^\+\\\/]+') dg
            FROM   (SELECT TABLESPACE_NAME tbs, file_name
                    FROM   dba_data_files
                    UNION ALL
                    SELECT TABLESPACE_NAME tbs, file_name
                    FROM   dba_temp_files
                    UNION ALL
                    SELECT '(Redo)' tbs, MEMBER
                    FROM   gv$logfile
                    UNION ALL
                    SELECT '(FlashBack)', NAME
                    FROM   V$FLASHBACK_DATABASE_LOGFILE
                    WHERE  ROWNUM <= 30
                    UNION ALL
                    SELECT '(ArchivedLog)', NAME
                    FROM   V$ARCHIVED_LOG
                    WHERE  ROWNUM <= 30)) c) c
    WHERE  a.DISKGROUP = c.dg(+)
ORDER  BY 1;