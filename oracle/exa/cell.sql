/*[[cellcli list cell]]*/
set printsize 3000
SELECT a.cellname, b.*
FROM   v$cell_config a,
       XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                "name" VARCHAR2(300) path 'name',
                "upTime" VARCHAR2(300) path 'upTime',
                "accessLevelPerm" VARCHAR2(300) path 'accessLevelPerm',
                "status" VARCHAR2(300) path 'status',
                "bbuStatus" VARCHAR2(300) path 'bbuStatus',
                "cpuCount" VARCHAR2(300) path 'cpuCount',
                "temperatureReading" VARCHAR2(300) path 'temperatureReading',
                "diagHistoryDays" VARCHAR2(300) path 'diagHistoryDays',
                "fanCount" VARCHAR2(300) path 'fanCount',
                "fanStatus" VARCHAR2(300) path 'fanStatus',
                "flashCacheMode" VARCHAR2(300) path 'flashCacheMode',
                "flashCacheCompress" VARCHAR2(300) path 'flashCacheCompress',
                "id" VARCHAR2(300) path 'id',
                "cellVersion" VARCHAR2(300) path 'cellVersion',
                "interconnectCount" VARCHAR2(300) path 'interconnectCount',
                "interconnect1" VARCHAR2(300) path 'interconnect1',
                "interconnect2" VARCHAR2(300) path 'interconnect2',
                "iormBoost" VARCHAR2(300) path 'iormBoost',
                "ipaddress1" VARCHAR2(300) path 'ipaddress1',
                "ipaddress2" VARCHAR2(300) path 'ipaddress2',
                "kernelVersion" VARCHAR2(300) path 'kernelVersion',
                "locatorLEDStatus" VARCHAR2(300) path 'locatorLEDStatus',
                "makeModel" VARCHAR2(300) path 'makeModel',
                "memoryGB" VARCHAR2(300) path 'memoryGB',
                "metricHistoryDays" VARCHAR2(300) path 'metricHistoryDays',
                "notificationMethod" VARCHAR2(300) path 'notificationMethod',
                "notificationPolicy" VARCHAR2(300) path 'notificationPolicy',
                "smtpPort" VARCHAR2(300) path 'smtpPort',
                "smtpServer" VARCHAR2(300) path 'smtpServer',
                "smtpToAddr" VARCHAR2(300) path 'smtpToAddr',
                "smtpUseSSL" VARCHAR2(300) path 'smtpUseSSL',
                "offloadGroupEvents" VARCHAR2(300) path 'offloadGroupEvents',
                "powerCount" VARCHAR2(300) path 'powerCount',
                "powerStatus" VARCHAR2(300) path 'powerStatus',
                "releaseImageStatus" VARCHAR2(300) path 'releaseImageStatus',
                "releaseVersion" VARCHAR2(300) path 'releaseVersion',
                "rpmVersion" VARCHAR2(300) path 'rpmVersion',
                "releaseTrackingBug" VARCHAR2(300) path 'releaseTrackingBug',
                "rollbackVersion" VARCHAR2(300) path 'rollbackVersion',
                "temperatureStatus" VARCHAR2(300) path 'temperatureStatus',
                "usbStatus" VARCHAR2(300) path 'usbStatus') b
WHERE  conftype = 'CELL'
ORDER BY 2;

col total_size,free_size,HD_SIZE,FD_SIZE,flash_cache,flash_log format kmg
SELECT NVL((SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
        FROM   v$cell_config c
        WHERE  c.CELLNAME = a.CELLNAME
        AND    rownum < 2),'--TOTAL') cell,
       cellhash,
       COUNT(DISTINCT NAME) DISKS,
       SUM(siz) total_size,
       SUM(freeSpace) free_size,
       SUM(DECODE(disktype, 'HardDisk', siz)) HD_SIZE,
       SUM(DECODE(disktype, 'FlashDisk', siz)) FD_SIZE,
       SUM(siz * is_fc) flash_cache,
       SUM(fl) flash_log
FROM   (SELECT CELLNAME,CELLHASH,
               b.*,
               (SELECT COUNT(1)
                FROM   v$cell_config d,
                       XMLTABLE('/cli-output/griddisk' PASSING xmltype(d.confval) COLUMNS --
                                cellDisk VARCHAR2(300) path 'cellDisk',
                                cacheby VARCHAR2(300) path 'cachedBy') c
                WHERE  INSTR(cacheby, b.name) > 0
                AND    d.cellname = a.cellname
                AND    ROWNUM < 2) is_fc,
               (SELECT SUM(siz)
                FROM   v$cell_state d,
                       XMLTABLE('/flashlogstore_stats' PASSING XMLTYPE(d.statistics_value) COLUMNS --
                                celldisk VARCHAR2(100) path 'stat[@name="celldisk"]',
                                siz INT path 'stat[@name="size"]') c
                WHERE  d.statistics_type = 'FLASHLOG'
                AND    d.cell_name = a.cellname
                AND    c.celldisk = b.name) fl
        FROM   v$cell_config a,
               XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                        NAME VARCHAR2(300) path 'name',
                        diskType VARCHAR2(300) path 'diskType',
                        siz INT path 'size',
                        freeSpace INT path 'freeSpace') b
        WHERE  conftype = 'CELLDISKS') a
GROUP  BY ROLLUP((cellname,CELLHASH))
ORDER BY cellname NULLS FIRST;
