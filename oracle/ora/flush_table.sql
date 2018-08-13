/*[[
	Invalidates all cursors present in v$sql which refer to the specific table. Usage: @@NAME [owner.]<table>
	Refer to: http://joze-senegacnik.blogspot.com/2009/12/force-cursor-invalidation.html
	--[[
		@check_access_dba: dba_tab_columns={dba_tab_columns} default={all_tab_columns}
	--]]
]]*/
ora _find_object "&V1" 1
DECLARE
    srec    DBMS_STATS.STATREC;
    distcnt NUMBER;
    density NUMBER;
    nullcnt NUMBER;
    avgclen NUMBER;
    colname VARCHAR2(128);
BEGIN
    DBMS_STATS.GET_COLUMN_STATS(ownname => :OBJECT_OWNER,
                                tabname => :OBJECT_NAME,
                                colname => colname,
                                distcnt => distcnt,
                                density => density,
                                nullcnt => nullcnt,
                                srec    => srec,
                                avgclen => avgclen);
    DBMS_STATS.SET_COLUMN_STATS(ownname       => :OBJECT_OWNER,
                                tabname       => :OBJECT_NAME,
                                colname       => colname,
                                distcnt       => distcnt,
                                density       => density,
                                nullcnt       => nullcnt,
                                srec          => srec,
                                avgclen       => avgclen,
                                no_invalidate => FALSE,
                                force         => TRUE);
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -6532 THEN
            FOR r IN (SELECT *
                      FROM   &check_access_dba
                      WHERE  owner = :OBJECT_OWNER
                      AND    table_name = :OBJECT_NAME
                      AND    NUM_DISTINCT > 0) LOOP
                DBMS_STATS.GET_COLUMN_STATS(ownname => :OBJECT_OWNER,
                                            tabname => :OBJECT_NAME,
                                            colname => r.column_name,
                                            distcnt => distcnt,
                                            density => density,
                                            nullcnt => nullcnt,
                                            srec    => srec,
                                            avgclen => avgclen);
                DBMS_STATS.SET_COLUMN_STATS(ownname       => :OBJECT_OWNER,
                                            tabname       => :OBJECT_NAME,
                                            colname       => r.column_name,
                                            distcnt       => distcnt,
                                            density       => density,
                                            nullcnt       => nullcnt,
                                            srec          => srec,
                                            avgclen       => avgclen,
                                            no_invalidate => FALSE,
                                            force         => TRUE);
            END LOOP;
        ELSE
            RAISE;
        END IF;
END;
/