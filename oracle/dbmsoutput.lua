local env=env
local snoop,cfg,default_db=env.event.snoop,env.set,env.db
local flag = 1

local output={}
local prev_transaction

function output.setOutput(db)
    local flag=cfg.get("ServerOutput")
    local stmt="begin dbms_output."..(flag=="on" and "enable(null)" or "disable()")..";end;"
    pcall(function() (db or default_db):internal_call(stmt) end)
end

output.stmt=[[    
        DECLARE/*INTERNAL_DBCLI_CMD*/
            l_line   VARCHAR2(32767);
            l_done   PLS_INTEGER := 32767;
            l_buffer VARCHAR2(32767);
            l_arr    dbms_output.chararr;
            l_lob    CLOB;
            l_enable VARCHAR2(3) := :enable;
            l_size   PLS_INTEGER;
        BEGIN
            dbms_output.get_lines(l_arr, l_done);
            IF l_enable = 'on' THEN
                FOR i IN 1 .. l_done LOOP
                    l_buffer := l_buffer || l_arr(i) || chr(10);
                    l_size   := lengthb(l_buffer);
                    IF l_size + 255 > 32400 OR (l_lob IS NOT NULL AND l_buffer IS NOT NULL AND i = l_done) THEN
                        IF l_lob IS NULL THEN
                            dbms_lob.createtemporary(l_lob, TRUE);
                        END IF;
                        dbms_lob.writeappend(l_lob, l_size, l_buffer) ;
                        l_buffer := NULL;
                    END IF;
                END LOOP;
            END IF;
            :buff := l_buffer;
            :txn := dbms_transaction.local_transaction_id;
            :lob := l_lob;
        END;]]

function output.getOutput(db,sql)
    local isOutput=cfg.get("ServerOutput")
    if sql~=output.stmt and not db:is_internal_call(sql) then
        local args={enable=isOutput,buff="#VARCHAR",txn="#VARCHAR",lob="#CLOB"}
        if not pcall(db.internal_call,db,output.stmt,args) then return end  
        local result=args.lob or args.buff
        if isOutput == "on" and result and result:match("[^\n%s]+") then
            result=result:gsub("[\n\r]","\n")
            print(result)
        end

        if prev_transaction~=args.txn then
            prev_transaction = args.txn
            env.set_title(prev_transaction and "TXN_ID: "..prev_transaction or "")
        end
    end    
end


function output.get_error_output(info)
    if info.sql==output.stmt then
        info.sql=nil
    elseif info.db:is_connect() then
        output.getOutput(info.db,info.sql)
    end
    return info
end

snoop("ON_SQL_ERROR",output.get_error_output,nil,40)
snoop("AFTER_ORACLE_CONNECT",output.setOutput)
snoop("AFTER_ORACLE_EXEC",output.getOutput,nil,50)

cfg.init("ServerOutput",
    "on",
    function(name,value)        
        output.setOutput(nil)
        return value
    end,
    "oracle",
    "Print Oracle dbms_output after each execution",
    "on,off")

return output