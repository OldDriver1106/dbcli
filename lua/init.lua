local env=env
local dirs={"cache","data","lib/ext"}
local init={
    module_list={
       --Libraries ->
        "lib/json",
        "lib/MessagePack",
        "lib/ProFi",
        "lib/misc",
        "lib/class",
        "lib/re",
        "lib/uv",
        "lib/flamegraph",

        --"locale",
        --CLI commands ->
        "lua/hotkeys",
        "lua/packer",
        "lua/trace",
        "lua/ansi",
        "lua/printer",
        "lua/event",
        "lua/grid",
        "lua/helper",
        "lua/sleep",
        "lua/set",
        "lua/host",
        "lua/search",
        "lua/history",
        "lua/alias",
        "lua/interval",
        "lua/db_core",
        "lua/login",
        "lua/var",
        "lua/scripter",
        "lua/snapper",
        "lua/ssh",
        "lua/tester",
        "lua/graph",
        "lua/subsystem",
        "lua/ilua",
        "lua/delta"}
}
local plugins,M={},{JVM={load_seq=0,onload=os.clock()-_G.__startclock,load=_G.__loadclock}}
init.databases={oracle="oracle/oracle",mssql="mssql/mssql",db2="db2/db2",mysql="mysql/mysql",pgsql='pgsql/pgsql'}
local default_database=env.CURRENT_DB or 'oracle'
local clock,load_seq=os.clock,0
env._M=M
function init.init_path(env)
    local java=java
    java.system=java.require("java.lang.System")
    java.loader=loader
    env('java',java)

    local path=package.path
    local path_del
    if path:sub(1,1)=="." then
        path_del=path:match("([\\/])")
        env("WORK_DIR",'..'..path_del)
    else
        env("WORK_DIR",path:gsub('%w+[\\/]%?.lua$',""))
        path_del=env.WORK_DIR:sub(-1)
    end
    local lib=jit.os:lower()
    lib=lib=='osx' and 'mac' or lib
    lib=lib=="windows" and jit.arch or lib
    env("PATH_DEL",path_del)
    env("CPATH_DEL",path_del=='/' and ':' or ';')
    env("PLATFORM",console:getPlatform())
    env("IS_WINDOWS",env.PLATFORM=="windows" or env.PLATFORM=="cygwin" or env.PLATFORM=="mingw" or env.PLATFORM=="conemu")
    env("_CACHE_BASE",env.WORK_DIR.."cache"..path_del)
    env("_CACHE_PATH",env._CACHE_BASE)
    env("LIB_PATH",env.join_path(env.WORK_DIR,'lib/'..lib))
    local package=package
    local cpath=java.system:getProperty('java.library.path')
    local paths={}
    for v in cpath:gmatch("([^"..env.CPATH_DEL.."]+)") do
        paths[#paths+1]=v..path_del.."?."..(env.IS_WINDOWS and "dll" or "so")
    end
    package.cpath=table.concat(paths,';')
    package.path="?.lua"
    
    for _,v in ipairs({"lua","lib","bin"}) do
        local path=string.format("%s%s%s",env.WORK_DIR,v,path_del)
        local p1=path.."?.lua"
        package.path  = package.path .. ';' ..p1
    end

    for _,v in ipairs(dirs) do
        loader:mkdir(env.WORK_DIR..v)
    end
end

local function exec(func,...)
    if func==nil and type(select(1,...))=="string" then 
        return print('Error on loading module: '..tostring(select(1,...)):gsub(env.WORK_DIR,""))
    end
    if type(func)~='function' then return end
    local res,rtn=env.pcall(func,...)
    if not res then
        return print('Error on loading module: '..tostring(rtn):gsub(env.WORK_DIR,""))
    end
    return rtn
end

function init.db_list()
    local keys={}
    for k,_ in pairs(init.databases) do
        keys[#keys+1]=k
    end
    table.sort(keys)
    return keys
end

function init.set_database(_,db)
    if not db then return nil end
    db=db:lower()
    if db==env.CURRENT_DB then return db end
    env.checkerr(init.databases[db],'Invalid database type!')
    if env.CURRENT_DB then
        print("Switching database ...")
        env.safe_call(env.event and env.event.callback,'ON_DATABASE_ENV_UNLOADED',env.CURRENT_DB)
        env.CURRENT_DB=db
        env.reload()
    end
end

function init.load_database()
    local res
    if not env.CURRENT_DB then
        if env.set and env.set._p then env.CURRENT_DB=env.set._p['database'] end
        if not env.CURRENT_DB then
            for _,k in ipairs(env.__ARGS__) do
                env.CURRENT_DB=k:lower():match('database%s*(%w+)')
                if env.CURRENT_DB then break end
            end
        end
        env.CURRENT_DB=env.CURRENT_DB or default_database
    end
    local file=init.databases[env.CURRENT_DB]
    if not file then return end
    local short_dir,name=file:match("^(.-)([^\\/]+)$")
    local dir=env.join_path(env.WORK_DIR,short_dir)
    local timer,load_seq=clock(),load_seq+1
    env[name]=exec(loadfile(dir..name..'.lua'))
    M[short_dir]={load=clock()-timer,load_seq=load_seq}
    timer=clock()
    exec(type(env[name])=="table" and env[name].onload,env[name],name)
    M[short_dir].onload=clock()-timer
    init.module_list[#init.module_list+1]=file
    env.module_list[#env.module_list+1]=env.join_path(file)
    if env.event then env.event.callback('ON_DB_ENV_LOADED',env.CURRENT_DB) end
    env[name].ROOT_PATH,env[name].SHORT_PATH=dir,short_dir
    env.getdb=function() return env[name] end
    if env[name].module_list then
        local pattern='^'..name..'[\\/]'
        local list={}
        for k,v in ipairs(env[name].module_list) do
            list[k]=v:find(pattern) and v or (short_dir..v)
        end
        env[name].C={}
        init.load_modules(list,env[name].C,name)
    end
end

function init.load_modules(list,tab,module_name)
    local n
    local root,del,dofile=env.WORK_DIR,env.PATH_DEL,dofile
    if not module_name then module_name=env.callee():match("([^\\/]+)") end

    --load plugin infomation
    if type(plugins[module_name])=='table' then
        for k,v in ipairs(plugins[module_name]) do
            if not v:match('[\\/]') then 
                v=module_name..'/'..v 
                plugins[module_name][k]=v
            end
            list[#list+1]=v
        end
    end
   
    local load_list,timer={}
    for _,v in ipairs(list) do
        local path=v
        v=env.join_path(v)
        n=v:match("([^\\/]+)$")
        if not v:lower():match('%.lua') then
            v=v..'.lua'
        else
            n=n:sub(1,#n-4)
        end
        clock=os.timer or os.clock
        timer,load_seq=clock(),load_seq+1
        local file=io.open(v,'r')
        if not file then
            file=root..v
        else
            file:close();
            file=v
        end
        local c,err=loadfile(file,nil,nil,env)
        tab[n]=exec(c,err or env)
        M[n]={load=clock()-timer,onload=tab[n],path=path,load_seq=load_seq}
        load_list[#load_list+1]=n
        if file:find(env.WORK_DIR,1,true)==1 then 
            file=file:sub(#env.WORK_DIR+1)
        end
        env.module_list[#env.module_list+1]=file:gsub('%.lua$','')
    end

    for _,k in ipairs(load_list) do
        local v,path=M[k].onload,M[k].path
        timer=clock()
        exec(type(v)=="table" and v.onload,v,k)
        M[k].onload,M[k].path=clock()-timer
        M[path],M[k]=M[k]
    end

end

function init.onload(env)
    env.module_list={(env.join_path('lua/env'))}
    plugins={}
    
    local file=env.join_path(env.WORK_DIR,'data','plugin.cfg')
    local f=io.open(file,"a")
    if f then f:close() end
    
    local config,err=env.loadfile(file)
    if not config then
        io.write('Error on reading data/plugin.cfg: '..err..'\n')
    else
        err,config=pcall(config)
        if not err then 
            io.write('Error on reading data/plugin.cfg: '..config..'\n')
        elseif type(config)=='table' then
            plugins=config
        end
    end
    env.plugins=plugins
    local p=print
    init.load_modules(init.module_list,env)
    init.load_database()
    if env.set then env.set.init({"platform","database"},env.CURRENT_DB,init.set_database,'core','Define current database type',table.concat(init.db_list(),',')) end
end

function init.unload(list,tab)
    if type(tab)~='table' then return end
    for i=#list,1,-1 do
        local m=list[i]:match("([^\\/]+)$")
        if type(tab[m])=="table" and type(tab[m].onunload)=="function" then
            if type(tab[m].C)=="table" and type(tab[m].module_list)=="table" then
                init.unload(tab[m].module_list,tab[m].C)
                tab[m].C=nil
            end
            tab[m].onunload(tab[m])
        end
        tab[m]=nil
    end
end

return init
