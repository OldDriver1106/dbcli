/*[[find objects with object_id/object_name. Usage: @@NAME {object_id | [owner.]<object_name>[.subname]}
    --[[
        @check_access_obj: dba_objects={dba_objects}, default={all_objects}
        @ARGS: 1
    --]]
]]*/
SET FEED OFF
ora _find_object &V1
VAR cur REFCURSOR Top 50 matched objects;
BEGIN
    OPEN :cur FOR
        SELECT * FROM (
            SELECT /*+no_expand*/ 
                   object_id,DATA_OBJECT_ID,owner, object_name,object_type,
                   case when :object_type IN('PACKAGE','TYPE') then :object_subname else subobject_name end subobject_name,
                   CREATED,LAST_DDL_TIME,TIMESTAMP,STATUS,TEMPORARY,GENERATED,SECONDARY
            FROM   &check_access_obj 
            WHERE  owner=:object_owner
            AND    object_name=:object_name
            --AND    object_type like :object_type||'%'
            AND    (:object_type IN('PACKAGE','TYPE')  OR nvl(subobject_name,' ') like :object_subname||'%')
            ORDER  BY OBJECT_ID)
        WHERE ROWNUM<=50;
END;
/
