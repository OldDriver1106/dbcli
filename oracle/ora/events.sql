/*[[List the available event number that used by 'alter session set events' statement. Usage: @@NAME [filter] 
   --[[
   @ALIAS: err
   --]]
]]*/
set feed off
DECLARE
    err_msg  VARCHAR2(2000);
    filter varchar2(300):= LOWER(:V1);
    rtn      PLS_INTEGER;
    cnt      PLS_INTEGER:=0;
    mx       PLS_INTEGER:=65535;
    facility varchar2(30);
    function msg(code PLS_INTEGER) return varchar2 IS
    BEGIN
        rtn:=utl_lms.get_message(abs(code),'rdbms',nvl(facility,'ora'),'us',err_msg);
        return trim(err_msg);
    END;
BEGIN
    IF filter IS NULL THEN
        filter:='%';
        mx:=10999;
    ELSE
        IF regexp_like(filter,'\d+$') THEN
            facility := lower(regexp_substr(filter,'^[a-zA-Z]+'));
            dbms_output.put_line(msg(regexp_substr(filter,'\d+$')));
            RETURN;
        END IF;
        filter:='%'||lower(filter)||'%';
    END IF;
    dbms_output.enable(null);
    FOR err_num IN 10000 .. mx LOOP
        err_msg := msg(err_num);
        IF err_msg NOT LIKE '%Message ' || err_num || ' not found%' AND lower(err_msg) LIKE filter THEN
            dbms_output.put_line('ORA-'||err_num||': ' ||err_msg);
            cnt := cnt +1;
        END IF;
    END LOOP;
    dbms_output.put_line(cnt||' codes matched.');
END;
/

