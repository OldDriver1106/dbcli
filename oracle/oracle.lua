local env,java,select=env,java,select
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command
local oracle=env.class(env.db_core)
oracle.module_list={
    "ora",
    "findobj",
    "dbmsoutput",
    "sqlplus",
    "xplan",
    "desc",
    "snap",
    "sqlprof",
    "tracefile",
    "awrdump",
    "unwrap",
    "sys",
    "show",
    "exa",
    "rac",
    "chart",
    "ssh",
    "extvars",
    "sqlcl"
}

local home,tns=os.getenv("ORACLE_HOME"),os.getenv("TNS_ADM") or os.getenv("TNS_ADMIN")
if not home then
    local bin=os.find_extension("sqlplus",true)
    if bin then
        home=bin:gsub("[%w%.]+$",''):gsub("([\\/])bin%1$","")
    end
end

if not tns and home then
    tns=env.join_path(home..'/network/admin')
end

function oracle:ctor(isdefault)
    self.type="oracle"
    self.home=home
    self.tns_admin=tns
    if tns then java.system:setProperty("oracle.net.tns_admin",tns) end
    local header = "set feed off sqlbl on define off;\n";
    header = header.."ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';\n"
    header = header.."ALTER SESSION SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SSXFF';\n"
    header = header.."ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SSXFF TZH';\n"
    self.sql_export_header=header
    self.C,self.props={},{}
end

function oracle:helper(cmd)
    return ({
        CONNECT=[[
        Connect to Oracle database.
        Usage  : @@NAME <user>/<password>@<tns_name> [as sysdba]                                       or
                 @@NAME <user>/<password>@[//]host[:port][/[service_name][:server][/sid] ] [as sysdba] or
                 @@NAME <user>/<password>@[//]host[:port][:sid[:server] ] [as sysdba]                  or
                 @@NAME <user>/<password>@(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)...))                    or
                 @@NAME <user>/<password>@<jdbc_url in "data/jdbc_url.cfg">
        ]],
        CONN=[[Refer to command 'connect']],
    })[cmd]
end

function oracle:connect(conn_str)
    local args,usr,pwd,conn_desc,url,isdba,server,server_sep,proxy_user,params,_
    local sqlplustr
    local driver="thin"
    if type(conn_str)=="table" then --from 'login' command
        args=conn_str
        server,proxy_user,sqlplustr=args.server,args.PROXY_USER_NAME,packer.unpack_str(args.oci_connection)
        usr,pwd,url,isdba=conn_str.user,packer.unpack_str(conn_str.password),conn_str.url,conn_str.internal_logon
        args.password=pwd
        if url and url:find("?",1,true) then
            url,params=url:match('(.*)(%?.*)')
        end
    else
        conn_str=conn_str or ""
        usr,_,pwd,conn_desc = conn_str:match('(.*)/("?)(.*)%2@(.+)')
        url, isdba=(conn_desc or conn_str):match('^(.*) as (%w+)$')
        if conn_desc and conn_desc:find("?",1,true) then
            conn_desc,params=conn_desc:match('(.*)(%?.*)')
        end
        if conn_desc == nil then
            local idx,two_task=conn_str:find("/",1,true),os.getenv("TWO_TASK")
            if idx and not conn_str:find("@",1,true) then
                if idx~=1 and two_task then
                    conn_str=(url or conn_str)..'@'..two_task..(isdba and (' as '..isdba) or '')
                    return self:connect(conn_str)
                elseif idx==1 and isdba then
                    env.checkerr(home and os.getenv("ORACLE_SID"),"Environment variable ORACLE_HOME/ORACLE_SID is not found, cannot login with oci driver!")
                    driver,usr,pwd,conn_desc,url="oci8","sys","sys","/ as sysdba",""
                end
            end
            if conn_desc == nil then return exec_command("HELP",{"CONNECT"}) end
        end
        if usr:find('%[.*%]') then usr,proxy_user=usr:match('(.*)%[(.*)%]') end
        
        sqlplustr,url=conn_str,url or conn_desc
        local host,port,server_sep,database=url:match('^[/]*([^:/]+)(:?%d*)([:/])(.+)$')
        local flag=true
        if database then
            if database:sub(1,1)=='/' then -- //<sid>
                flag,server_sep,database=false,':',database:sub(2)
            elseif database:match('^:(%w+)/([%w_]+)$') then -- /:<server>/<sid>
                flag,server_sep,server,database=false,':',database:match('^:(%w+)/([%w_]+)$')
            elseif database:match('^[%w_]+:(%w+)/([%w_]+)$') then --/<database>:<server>/<sid>
                flag,server_sep,server,database=false,':',database:match('^[%w_]+:(%w+)/([%w_]+)$')
            elseif database:match('^([%w_]+):(%w+)$') then--/<database>:<server>
                flag,server_sep,database,server=false,'/',database:match('^([%w_]+):(%w+)$')
            end
            if server then server=server:upper() end
            if port=="" then flag,port=false,':1521' end
            if not flag then 
                url=host..port..server_sep..database..(server and (':'..server) or '')
                sqlplustr=string.format('%s/%s@%s%s/%s%s',
                    usr..(proxy_user and ('['..proxy_user..']') or ''),
                    pwd,host,port,
                    server_sep==':' and server and (':'..server..'/'..database) or
                    server_sep==':' and not server and '/'..database or
                    database..(server and (':'..server) or ''),
                    isdba and (' as '..isdba) or '')
            end
        end
    end
    args=args or {user=usr,password=pwd,url="jdbc:oracle:"..driver..":@"..url..(params or ''),internal_logon=isdba}
    self:merge_props(
        {driverClassName="oracle.jdbc.driver.OracleDriver",
         defaultRowPrefetch=tostring(cfg.get("FETCHSIZE")),
         PROXY_USER_NAME=proxy_user,
         useFetchSizeWithLongColumn='true',
         useThreadLocalBufferCache="true",
         freeMemoryOnEnterImplicitCache="true",
         bigStringTryClob="true",
         clientEncoding=java.system:getProperty("input.encoding"),
         processEscapes='false',
         ['v$session.program']='SQL Developer',
         ['oracle.jdbc.defaultLobPrefetchSize']="2097152",
         ['oracle.jdbc.mapDateToTimestamp']="true",
         ['oracle.jdbc.maxCachedBufferSize']="104857600",
         ['oracle.jdbc.useNio']='true',
         ['oracle.jdbc.TcpNoDelay']='true',
         ["oracle.jdbc.J2EE13Compliant"]='true',
         ['oracle.jdbc.autoCommitSpecCompliant']='false',
         ['oracle.jdbc.useFetchSizeWithLongColumn']='true',
         ['oracle.net.networkCompression']='on',
         ['oracle.net.keepAlive']='true',
         ['oracle.jdbc.convertNcharLiterals']='true',
         ['oracle.net.ssl_server_dn_match']='true',
         ['oracle.jdbc.timezoneAsRegion']='false'
        },args)
    self:load_config(url,args)

    if args.jdbc_alias or not sqlplustr then
        local pwd=args.password
        if not pwd:find('^[%w_%$#]+$') and not pwd:find('^".*"$') then
            pwd='"'..pwd..'"'
        else
            pwd=pwd:match('^"*(.-)"*$')
        end
        sqlplustr=string.format("%s/%s@%s%s",args.user,pwd,args.url:match("@(.*)$"),args.internal_logon and " as "..args.internal_logon or "")
    end
    
    local prompt=args.jdbc_alias or url:gsub('.*@','')
    if event then event("BEFORE_ORACLE_CONNECT",self,sql,args,result) end
    env.set_title("")
    local data_source=java.new('oracle.jdbc.pool.OracleDataSource')
    self.working_db_link=nil
    self.conn,args=self.super.connect(self,args,data_source)
    self.conn=java.cast(self.conn,"oracle.jdbc.OracleConnection")
    self.conn_str=sqlplustr

    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    self.props={instance="#NUMBER",sid="#NUMBER",version="#NUMBER"}
    for k,v in ipairs{'db_user','db_version','nls_lang','isdba','service_name','db_role','container','israc','privs'} do 
        self.props[v]="#VARCHAR" 
    end
    local succ,err=pcall(self.exec,self,[[
        DECLARE
            vs  PLS_INTEGER  := dbms_db_version.version;
            ver PLS_INTEGER  := sign(vs-9);
            re  PLS_INTEGER  := dbms_db_version.release;
            sv  VARCHAR2(200):= sys_context('userenv','service_name');
            pv  VARCHAR2(32767) :=''; 
        BEGIN
            EXECUTE IMMEDIATE 'alter session set nls_date_format=''yyyy-mm-dd hh24:mi:ss''';
            EXECUTE IMMEDIATE 'alter session set nls_timestamp_format=''yyyy-mm-dd hh24:mi:ssxff''';
            EXECUTE IMMEDIATE 'alter session set nls_timestamp_tz_format=''yyyy-mm-dd hh24:mi:ssxff TZH:TZM''';
            BEGIN
                EXECUTE IMMEDIATE 'alter session set statistics_level=all';
                EXECUTE IMMEDIATE 'alter session set "_query_execution_cache_max_size"=8388608';
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            BEGIN
                EXECUTE IMMEDIATE 'alter session set optimizer_ignore_hints=false';
                EXECUTE IMMEDIATE 'alter session set optimizer_ignore_parallel_hints=false';
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            FOR r in(SELECT role p FROM SESSION_ROLES UNION ALL SELECT * FROM SESSION_PRIVS) LOOP
                pv := pv||'/'||r.p;
                exit when length(pv)>32000;
            END LOOP;

            :privs := pv;

            IF sv like 'SYS$%' THEN
                sv := NULL;
                BEGIN EXECUTE IMMEDIATE q'{select regexp_substr(value,'[^ ,]+') from v$parameter where name='service_names'}' into sv;
                EXCEPTION WHEN OTHERS THEN NULL;END;
            END IF;

            SELECT user,
                   (SELECT value FROM Nls_Database_Parameters WHERE parameter = 'NLS_RDBMS_VERSION') version,
                   (SELECT value FROM Nls_Database_Parameters WHERE parameter = 'NLS_LANGUAGE') || '_' ||
                   (SELECT value FROM Nls_Database_Parameters WHERE parameter = 'NLS_TERRITORY') || '.' || value nls,
            $IF dbms_db_version.version > 9 $THEN      
                   userenv('sid') ssid,
                   userenv('instance') inst,
            $ELSE
                   (select sid from v$mystat where rownum<2) ssid,
                   (select instance_number from v$instance where rownum<2) inst,
            $END

            $IF dbms_db_version.version > 11 $THEN
                   sys_context('userenv', 'con_name') con_name,
            $ELSE
                   null con_name,
            $END   
                   sys_context('userenv', 'isdba') isdba,
                   nvl(sv,sys_context('userenv', 'db_name') || nullif('.' || sys_context('userenv', 'db_domain'), '.')) service_name,
                   decode(sign(vs||re-111),1,decode(sys_context('userenv', 'DATABASE_ROLE'),'PRIMARY',' ','PHYSICAL STANDBY',' (Standby)>')) END,
                   decode((select count(distinct inst_id) from gv$version),1,'FALSE','TRUE'),vs
            INTO   :db_user,:db_version, :nls_lang, :sid, :instance, :container, :isdba, :service_name,:db_role, :israc,:version
            FROM   nls_Database_Parameters
            WHERE  parameter = 'NLS_CHARACTERSET';
            
            BEGIN
                IF :db_role IS NULL THEN 
                    EXECUTE IMMEDIATE q'[select decode(DATABASE_ROLE,'PRIMARY','',' (Standby)>') from v$database]'
                    into :db_role;
                ELSIF :db_role = ' ' THEN
                    :db_role := trim(:db_role);
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;END;
        END;]],self.props)
    self.props.isdba=self.props.isdba=='TRUE' and true or false
    self.props.israc=self.props.israc=='TRUE' and true or false
    if not succ then
        self.props.instance=1
        self.props.db_version='9.1'
        env.warn("Connecting with a limited user that cannot access many dba/gv$ views, some dbcli features may not work.")
    else
        local privs={}
        for _,priv in pairs(self.props.privs:split("/")) do
            if priv~="" then privs[priv]=true end
        end
        privs[self.props.db_user]=true
        self.props.privs=privs
        if prompt=="" or not prompt or prompt:find('[:/%(%)]') then prompt=self.props.service_name end
        prompt=prompt:match('([^%.]+)')
        self.conn_str=self.conn_str:gsub('(:%d+)([:/]+)([%w%.$#]+)',function(port,sep,sid)
            if sep==':' or sep=='//' then
                return port..'/'..self.props.service_name..'/'..sid
            end
            return port..sep..sid
        end,1)
        env._CACHE_PATH=env.join_path(env._CACHE_BASE,prompt:lower():trim(),'')
        loader:mkdir(env._CACHE_PATH)
        prompt=('%s%s'):format(prompt:upper(),self.props.db_role or '')
        env.set_prompt(nil,prompt,nil,2)
        self.session_title=('%s@%s   Instance: %s   SID: %s   Version: Oracle(%s)')
            :format(self.props.db_user,prompt,self.props.instance,self.props.sid,self.props.db_version)
        env.set_title(self.session_title)
        env.uv.os.setenv("NLS_LANG",self.props.nls_lang)
    end
    for k,v in pairs(self.props) do args[k]=v end
    args.oci_connection=packer.pack_str(self.conn_str)
    if not packer.unpack_str(args.oci_connection) then
        --env.warn("Failed to pack '%s', the unpack result is nil!",self.conn_str)
    end
    env.login.capture(self,args.jdbc_alias or args.url,args)
    if event then event("AFTER_ORACLE_CONNECT",self,sql,args,result) end
    print("Database connected.")
end

function oracle:parse(sql,params)
    local bind_info,binds,counter,index,org_sql={},{},0,0

    if cfg.get('SQLCACHESIZE') ~= self.MAX_CACHE_SIZE then
        self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    end

    local temp={}
    for k,v in pairs(params) do
        temp[type(k)=="string" and k:upper() or k]={k,v}
    end

    for k,v in pairs(temp) do
        params[v[1]]=nil
        params[k]=v[2]
    end

    org_sql,sql=sql,sql:gsub('%f[%w_%$:]:([%w_%$]+)',function(s)
        local k,s=s:upper(),':'..s
        local v=params[k]
        local typ
        if v==nil then return s end
        if bind_info[k] then return s:upper() end
        if type(v) =="table" then
            return s
        elseif type(v)=="number" then
            typ='NUMBER'
        elseif type(v)=="boolean" then
            typ='BOOLEAN'
        elseif v:sub(1,1)=="#" then
            typ,v=v:upper():sub(2),nil
            env.checkerr(self.db_types[typ],"Cannot find '"..typ.."' in java.sql.Types!")
        elseif type(v)=="string" and #v>32000 then
            typ='CLOB'
        else
            typ='VARCHAR'
        end

        if v==nil then
            if counter<2 then counter=counter+2 end
        else
            if counter~=1 and counter~=3 then counter=counter+1 end
        end

        local typename,typeid=typ,self.db_types[typ].id
        typ,v=self.db_types:set(typ,v)
        bind_info[k],binds[#binds+1]={typ,v,typeid,typename,nil,nil,s},k
        return s:upper()
    end)

    local sql_type=self.get_command_type(sql)
    local func,value,typeid,typename,inIdx,outIdx,vname=1,2,3,4,5,6,7
    if sql_type=="SELECT" or sql_type=="WITH" then 
        if sql:lower():find('%Wtable%s*%(') and not sql:lower():find('xplan') then 
            cfg.set("pipequery",'on')
        end
    end

    if sql_type=='EXPLAIN' or #binds>0 and (sql_type=="DECLARE" or sql_type=="BEGIN" or sql_type=="CALL") then
        local s0,s1,s2,index,typ,siz={},{},{},1,nil,#binds
        params={}

        if sql_type=='EXPLAIN' then
            bind_info,binds={},{}
        end

        for idx=1,#binds do
            typ=bind_info[binds[idx]][typename]
            if typ=="CURSOR" then
                bind_info[binds[idx]][inIdx]=0
                typ="SYS_REFCURSOR"
                s1[idx]="V"..(idx+1)..' '..typ..';/* :'..binds[idx]..'*/'
            else
                index=index+1;
                bind_info[binds[idx]][inIdx]=index
                typ=(typ=="VARCHAR" and "VARCHAR2(32767)") or typ
                s1[idx]="V"..(idx+1)..' '..typ..':=:'..index..';/* :'..binds[idx]..'*/'
            end
            s0[idx]=(idx==1 and 'USING ' or '') ..'IN OUT V'..(idx+1)    
        end

        for idx=1,#binds do
            index=index+1;
            bind_info[binds[idx]][outIdx]=index
            s2[idx]=":"..index.." := V"..(idx+1)..';' 
        end

        typ = org_sql:len()<=30000 and 'VARCHAR2(32767)' or 'CLOB' 
        local method=self.db_types:set(typ~='CLOB' and 'VARCHAR' or typ,org_sql)
        sql='DECLARE V1 %s:=:1;%sBEGIN EXECUTE IMMEDIATE V1 %s;%sEND;'
        sql=sql:format(typ,table.concat(s1,''),table.concat(s0,','),table.concat(s2,''))
        env.log_debug("parse","SQL:",sql)
        local prep=java.cast(self.conn:prepareCall(sql,1003,1007),"oracle.jdbc.OracleCallableStatement")
        prep[method](prep,1,org_sql)
        for k,v in ipairs(binds) do
            local p=bind_info[v]
            if p[inIdx]~=0 then
                env.log_debug("parse","Param In#"..k..'('..p[vname]..')',':'..p[inIdx]..'='..p[value])
                prep[p[func]](prep,p[inIdx],p[value])
            end
            params[v]={'#',p[outIdx],p[typename],p[func],p[value],p[inIdx]~=0 and p[inIdx] or nil}
            env.log_debug("parse","Param Out#"..k..'('..p[vname]..')',':'..p[outIdx]..'='..self.db_types:getTyeName(typeid))
            prep['registerOutParameter'](prep,p[outIdx],p[typeid])
        end
        env.log_debug("parse","Block-Params:",table.dump(params))
        return prep,org_sql,params
    elseif counter>1 then
        return self.super.parse(self,org_sql,params,':')
    else 
        org_sql=sql
    end

    params={}
    local prep=java.cast(self.conn:prepareCall(sql,1003,1007),"oracle.jdbc.OracleCallableStatement")
    for k,v in pairs(bind_info) do
        if v[func]=='#' then
            prep['registerOutParameter'](prep,k,v[typeid])
            params[k]={'#',k,v[typename],'registerOutParameter',v[typeid]}
        else
            prep[v[func].."AtName"](prep,k,v[value])
            params[k]={'$',k,v[typename],v[func].."AtName",v[value]}
        end
    end
    env.log_debug("parse","Query Params:",table.dump(params))

    return prep,org_sql,params
end

function oracle:exec(sql,...)
    local bypass=self:is_internal_call(sql)
    local args,prep_params=nil,{}
    local is_not_prep=type(sql)~="userdata"
    if type(select(1,...) or "")=="table" then
        args=select(1,...)
        if type(select(2,...) or "")=="table" then prep_params=select(2,...) end
    else
        args={...}
    end
    
    if is_not_prep then sql=event("BEFORE_ORACLE_EXEC",{self,sql,args}) [2] end
    local result=self.super.exec(self,sql,...)
    if is_not_prep and not bypass then 
        event("AFTER_ORACLE_EXEC",self,sql,args,result)
        self.print_feed(sql,result)
    end
    return result
end


function oracle:run_proc(sql)
    return self:query('BEGIN '..sql..';END;')
end

function oracle:asql_single_line(...)
    self.asql:exec(...)
end


function oracle:check_date(string,fmt)
    fmt=fmt or "YYMMDDHH24MI"
    local args={string and string~="" and string or " ",fmt,'#INTEGER','#VARCHAR'}
    self:internal_call([[
        BEGIN
           :4 := to_char(to_date(:1,:2),:2);
           :3 := 1;
        EXCEPTION WHEN OTHERS THEN
           :3 := 0;
        END;]],args)
    env.checkerr(args[3]==1,'Invalid date format("%s"), expected as "%s"!',string,fmt)
    return args[4]
end

function oracle:disconnect(...)
    self.super.disconnect(self,...)
    env.set_title("")
end

local is_executing=false

local ignore_errors={
    ['ORA-00028']='Connection is lost, please login again.',
    ['socket']='Connection is lost, please login again.',
    ['SQLRecoverableException']='Connection is lost, please login again.',
    ['ORA-01013']='default',
    ['connection abort']='default'
}

function oracle:handle_error(info)
    if not self.conn:isValid(3) then env.set_title("") end
    if is_executing then
        info.sql=nil
        return
    end

    for k,v in pairs(ignore_errors) do
        if info.error:lower():find(k:lower(),1,true) then
            info.sql=nil
            if v~='default' then
                info.error=v
            else
                info.error=info.error:match('^([^\n\r]+)')
            end
            return info
        end
    end

    local prefix,ora_code,msg=info.error:match('(%u%u%u+)%-(%d%d%d+): *(.+)')
    if ora_code then
        if prefix=='ORA' and tonumber(ora_code)>=20001 and tonumber(ora_code)<20999 then
            info.sql=nil
            info.error=msg:gsub('[\n\r]%s*ORA%-%d+.*$',''):gsub('%s+$','')
        else
            info.error=prefix..'-'..ora_code..': '..msg
        end
        return info
    end
        
    return info
end

function oracle:set_session(cmd,args)
    self:assert_connect()
    self:internal_call('set '..cmd.." "..(args or ""),{})
    return args
end

function oracle:set_db_link(name,value)
    if not value or value:lower()=="off" or value=="" then
        env.set_title(self.session_title)
        self.working_db_link=nil
        return ""
    else
        value=value:upper()
        local args={"#INTEGER"}
        local stmt=[[
        BEGIN
           execute immediate 'select * from dual@link';
           :1 := 1;
        EXCEPTION WHEN OTHERS THEN
           :1 := 0;
        END;]]
        self:internal_call(stmt:gsub("link",value),args)
        env.checkerr(args[1]==1,'Database link does not exists',string,fmt)
        self.working_db_link=value
        env.set_title(self.session_title.."   DB-LINK: "..value)
    end
end

function oracle:onload()
    self.db_types:load_sql_types('oracle.jdbc.OracleTypes')
    env.uv.os.setenv("NLS_DATE_FORMAT",'YYYY-MM-DD HH24:MI:SS')
    local default_desc='#Oracle database SQL statement'
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            env.remove_command(select(i,...))
            set_command(self,select(i,...), default_desc,self.exec,true,1,true)
        end
    end

    local function add_single_line_stmt(...)
        for i=1,select('#',...) do
            env.remove_command(select(i,...))
            set_command(self,select(i,...), default_desc,self.exec,false,1,true)
        end
    end

    add_single_line_stmt('commit','rollback','savepoint')
    add_default_sql_stmt('update','delete','insert','merge','truncate','drop','flashback')
    add_default_sql_stmt('explain','lock','analyze','grant','revoke','purge','audit','noaudit','comment')
    set_command(self,{"connect",'conn'},  self.helper,self.connect,false,2)
    set_command(self,"select",   default_desc,        self.query     ,true,1,true)
    set_command(self,"with",   default_desc,        self.query     ,self.check_completion,1,true)
    set_command(self,{"execute","exec","call"},default_desc,self.run_proc,false,2,true)
    set_command(self,{"declare","begin"},  default_desc,  self.query  ,self.check_completion,1,true)
    set_command(self,"create",   default_desc,        self.exec      ,self.check_completion,1,true)
    set_command(self,"alter" ,   default_desc,        self.exec      ,true,1,true)
    --cfg.init("dblink","",self.set_db_link,"oracle","Define the db link to run all SQLs in target db",nil,self)
    env.event.snoop('ON_SQL_ERROR',self.handle_error,self,1)
    env.set.inject_cfg({"transaction","role","constraint","constraints"},self.set_session,self)
end

function oracle:onunload()
    env.set_title("")
end

function oracle:get_library()
    if home then
        local files={}
        for i=10,7,-1 do
            local jar=env.join_path(home..'/jdbc/lib/ojdbc'..i..'.jar')
            if os.exists(jar) then 
                files[#files+1]=jar
                break
            end
        end
        if #files>0 then
            files[#files+1]=env.join_path(env.WORK_DIR..'/oracle/xdb6.jar')
            loader:addLibrary(env.join_path(home..'/lib'),false)
            env.uv.os.setenv('LD_LIBRARY_PATH',java.system:getProperty("java.library.path"))
            return files
        end
    end
    return nil
end

function oracle:grid_db_call(sqls,args,is_cache)
    local stmt={[[BEGIN]]}
    local clock=os.timer()
    if sqls.declare then
        table.insert(stmt,1,'DECLARE ')
        for k,v in ipairs(type(sqls.declare)=="table" and sqls.declare or {sqls.declare}) do
            table.insert(stmt,2,v:trim(';')..';')
        end
    end
    --stmt[#stmt+1]='BEGIN set transaction isolation level serializable;EXCEPTION WHEN OTHERS THEN NULL;END;'
    args=args or {}
    for idx,sql in ipairs(sqls) do
        local typ=self.get_command_type(sql.sql)
        if typ:find('SELECT') or typ:find('WITH') then
            local cursor='GRID_CURSOR_'..idx
            args[cursor]='#CURSOR'
            stmt[#stmt+1]='  OPEN :'..cursor..' FOR \n        '..sql.sql:trim(';')..';'
        else
            stmt[#stmt+1]=sql.sql:trim(';/')..';'
        end
    end
    stmt[#stmt+1]='END;'
    local results;
    if not is_cache then 
        result=self.super.exec(self,table.concat(stmt,'\n'),args)
    else
        result=self.super.exec_cache(self,table.concat(stmt,'\n'),args,is_cache)
    end
    self.grid_cost=os.timer()-clock
    if type(results)~="table" and type(results)~="userdata" then results=nil end
    for idx,sql in ipairs(sqls) do
        local cursor='GRID_CURSOR_'..idx
        sql.rs=args[cursor] or results
    end
end

return oracle.new()