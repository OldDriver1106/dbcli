local env,java=env,java
local runtime=java.require("java.lang.Runtime",true):getRuntime()
local helper={}

function helper.jvm()
    local grid=env.grid
    local set=env.set
    local rows={{},{}}
    local function add(name,value)
        local siz=#rows[1]+1
        rows[1][siz],rows[2][siz]=name,value
    end
    for k,v in java.pairs(java.system:getProperties()) do
        if tostring(k)~="" then
            add(k,type(v)=="string" and v:gsub('(['..(env.IS_WINDOWS and ';' or ':')..'])','%1\n') or tostring(v))
        end
    end
    set.set("PIVOT",1)
    grid.print(rows)
end

function helper.env(target,depth)
    if target and target:sub(1,1)~='-' and target:sub(1,1)~='+' then
        if type(_G[target])=="table" then
            return print(table.dump(_G[target],nil,depth))
        end
        if target:find("%.") then
            local obj=_G
            for v in target:gmatch('([^%.]+)') do
                if type(obj)~="table" then return end
                obj=obj[v]
                if not obj then return end
            end
            return print(table.dump(obj,nil,depth))
        end
        return
    end
    local grid=env.grid
    local set=env.set
    local rows={{},{}}
    local function add(name,value)
        if target then
            local ind,pat=target:sub(1,1),target:sub(2)
            local mat = tostring(value):match(pat) and true or false
            if mat~=(ind=='+' and true or false) then
                return
            end
        end
        local siz=#rows[1]+1
        rows[1][siz],rows[2][siz]=name,value
    end
    add("Memory.LUA(KB)",math.floor(collectgarbage("count")))
    add("Memory.JVM(KB)",math.floor((runtime:totalMemory()-runtime:freeMemory())/1024))
    if rows[2][1] and rows[2][2] then
        add("Memory.Total(KB)",rows[2][1]+rows[2][2])
    end
    add("ENV.locale",os.setlocale())
    local prefix=env.WORK_DIR:len()+1
    for k,v in pairs(env) do
        --if not (k=='_G' or k=='_ENV' or k=='env') then
        if type(v)=="table" and type(v.props)=="table" then
            for i,j in pairs(v.props) do
                add(k.."."..i,j)
            end
        end
        local t=type(v)
        if t=="function" then
            v=string.from(v)
        elseif t=="table" and k~='env' and k~='_G' and k~='package' and k~='_ENV' then
            t=table.dump(v,nil,2):match('function(%([^%)]+%))')
            v= t and 'table'..t or tostring(v,'',3)
        elseif t=="string" then
            v='"'..v..'"'
        end
        add('env.'..k,v)
    end
    if math.fmod(#rows[1],2)==1 then
        add("","")
    end
    add('package.path',package.path:gsub(';',';\n'))
    add('package.cpath',package.cpath:gsub(';',';\n'))
    set.set("PIVOT",1)
    grid.print(rows)
end

function helper.helper(cmd,...)
    local grid,_CMDS=env.grid,env._CMDS
    local rows={}
    if cmd and cmd:sub(1,1)~="-" then
        cmd = cmd:upper()
        if not _CMDS[cmd] or not _CMDS[cmd].HELPER then
            if env.event then env.event.callback("ON_HELP_NOTFOUND",cmd,...) end
            return 
        end
        local helps,target
        if type(_CMDS[cmd].HELPER) =="function" then
            local args,sub= _CMDS[cmd].OBJ and {_CMDS[cmd].OBJ,cmd,...} or {cmd,...}
            helps,sub = (_CMDS[cmd].HELPER)(table.unpack(args))
            helps = helps or "No help information."
            target= table.concat({cmd,sub}," ")
        else
            helps = _CMDS[cmd].HELPER or ""
            target=cmd
        end
        if helps=="" then return end
        helps=helps:gsub('^(%s*[^\n\r]+)[Uu]sage[: \t]+(@@NAME)','%1\n$USAGECOLOR$Usage:$NOR$ %2'):gsub('([eE]xamples?)%s*: *','$USAGECOLOR$%1:$NOR$ ')
        local spaces=helps:match("([ \t]*)%S") or ""
        helps=('\n'..helps):gsub("\r?\n"..spaces,"\n"):gsub("%s+$",""):gsub("@@NAME",target:lower())
        if helps:sub(1,1)=="\n" then helps=helps:sub(2) end

        local grid=env.grid
        helps=helps:gsub('%[(%s*%|.-%|)%s*%]',function(s)
            local tab,s0=grid.new(),s..' '
            local space=s:match('([ \t]*)|') or ''
            local _,cfg=grid.get_config(s0)
            s0:gsub('[^\n%S]*(|[^\r\n]+|)%s+',function(s1)
                local row={}
                s1:gsub('([^%|]+)',function(s2)
                    row[#row+1]=s2:trim():gsub('\\n','\n'):gsub('\\%]',']')
                    if #row==1 and #tab.data>1 then row[1]='$BOLD$'..row[1]..' $NOR$' end
                end)
                if #row >1 then tab:add(row) end
            end)
            if #tab.data==0 then return s end
            for k,v in pairs(cfg) do tab[k]=v end
            return space..table.concat(grid.merge({tab}),'\n'..space)
        end)
        return print(helps)
    elseif cmd=="-e" or cmd=="-E" then
        return helper.env(...)
    elseif cmd=="-j" or cmd=="-J" then
        return helper.jvm(...)
    elseif cmd=="-dump" then
        local cmd=java.loader:dumpClass(env.WORK_DIR.."dump")
        io.write("Command: "..cmd.."\n");
        return os.execute(cmd)
    elseif cmd=="-buildjar" then
        local uv=env.uv
        local dels='"'..env.join_path(env.WORK_DIR..'/dump/*.jar*')..'"'
        if env.IS_WINDOWS then
            os.execute("del "..dels)
        else
            os.execute("rm -f "..dels)
        end
        for f,p in pairs{rt='',
                          jce='',
                          jsse='',
                          charsets='',
                          localedata='ext/',
                          sunjce_provider='ext/',
                          sunec='ext/',
                          sunmscapi='ext/',
                          ojdbc8='/dump/',
                          xmlparserv2='/dump/',
                          oraclepki='/dump/',
                          osdt_cert='/dump/',
                          osdt_core='/dump/',
                          --orai18n='/dump/',
                          xdb6='/dump/'} do
            local dir=env.join_path(env.WORK_DIR..'/dump/'..f)
            local jar=env.join_path(env.WORK_DIR..(env.IS_WINDOWS and 'jre' or (env.PLATFORM=='mac' and 'jre_mac') or 'jre_linux')..'/lib/'..p..f..'.jar')
            if p:sub(1,1)=='/' then jar=env.join_path(env.WORK_DIR..p..f..'.jar') end
            local list={}
            for _,f in ipairs(os.list_dir(dir,'*',999)) do
                list[#list+1]=f.fullname:sub(#dir+2):gsub("[\\/]","/")
            end
            loader:createJar(list,jar)
            os.execute('pack200 -r -O -G "'..jar..'" "'..jar..'"')
        end
        return
    elseif cmd=="-stack" then
        return env.print_stack()
    elseif cmd=="-verbose" then
        local dest=select(1,...)
        if not dest then
            dest=env.WORK_DIR.."cache"..env.PATH_DEL.."verbose.log"
            local f=io.open(dest)
            local txt=f:read("*a")
            f:close()
            for v in txt:gmatch("%[Loaded%s+(%S+).-%]") do
                v=v:gsub("%.class$","")
                java.loader:copyClass(v)
            end
            for v in txt:gmatch("(%S+)%.class%W") do
                java.loader:copyClass(v)
            end
        else
            java.loader:copyClass(dest)
        end
        return
    end

    local flag=(cmd=="-a" or cmd=="-A") and 1 or 0
    table.insert(rows,{"Command","Abbr.","Max Args"})
    if flag==1 then
        table.append(rows[#rows],"Cross-lines?","Source")
    end
    table.insert(rows[#rows],"Decription")
    local ansi=env.ansi
    for k,v in pairs(_CMDS) do
        if k~="___ABBR___" and (v.DESC and not v.DESC:find("[ \t]*#") or flag==1) then
            table.insert(rows,{
                    k,
                    v.ABBR,
                    v.ARGS-1})
            if flag==1 then
                table.append(rows[#rows],(type(v.MULTI)=="function" or type(v.MULTI)=="string") and "Auto" or v.MULTI and 'Yes' or 'No',v.FILE)
            end
            local desc=v.DESC and v.DESC:gsub("^[%s#]+","") or " "
            desc=desc:gsub("([Uu]sage)(%s*:%s*)(@@NAME)","$USAGECOLOR$Usage:$NOR$ "..k:lower()):gsub("@@NAME","$USAGECOLOR$"..k:lower().."$NOR$")
            table.insert(rows[#rows],desc)
            if (v.COLOR or "")~="" then
                rows[#rows][1]=ansi.mask(v.COLOR,rows[#rows][1])
                rows[#rows][2]=ansi.mask(v.COLOR,rows[#rows][2])
            end
        end
    end
    print("Available comands:\n===============")
    grid.sort(rows,1,true)
    grid.print(rows)
    return ""
end

function helper.desc()
    return [[
        Type 'help' to see the available comand list. Usage: @@NAME [<command>[,<sub_command1>...]|-a|-j|-stack|-e [<obj>]|help ]
        Options:
           -stack     To print stack of historical commands
           -a         To show all commands, including the hidden commands.
           -j         To show current JVM information
           -e         To show current environment infomation. Usage: help -e [<lua_table>[.<sub_table>] ]
           Internal:
                -verbose [class] :  dump a class or classes from verbose.log into dir "dunmp"
                -dump            :  dump classed of current process into dir "dunmp"
                -buildjar        :  build jars from in dir "dunmp"
        Other commands:
            help                             To brief the available commands(excluding hiddens)
            help <command>                   To show the help detail of a specific command
            help <command> [<sub_command>]   i.e. help ora actives
     ]]
end

env.set_command(nil,'help',helper.desc,helper.helper,false,9)
return helper