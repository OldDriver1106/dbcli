local env,os=env,os
local exec,sleep=env.eval_line,env.sleep
local interval,stack={},{}
local threads=env.RUNNING_THREADS
interval.cmd='ITV'

function interval.itv(sec,count,target)
    env.checkerr(sec,'Invalid syntax! Usage: ITV <START [seconds] [remark]|END|seconds times command>')
    local cmd,org_count,sec,count=sec:upper(),count,tonumber(sec),tonumber(count)
    local thread,cmds=threads[#threads],stack[threads[#threads]]
    if cmd=="START" then
        target=target and target:gsub("[ \t]+$","")
        stack[thread]={timer=count or 1,clock=os.clock(),msg=target,{interval.cmd ,{cmd,org_count,target}}}
        if target then print(target) end
    elseif cmd=="END" then
        if not cmds then return end;
        local sleep
        if type(env.sleep)=="function" then 
            sleep=env.sleep
        elseif type(env.sleep)=="table" then
            sleep=env.sleep.sleep
        else
            env.raise("Cannot find function env.sleep!")
        end
        if(cmds.msg) then print("") end
        sleep(cmds.timer)
        stack[thread]=nil
        for idx,cmd in ipairs(cmds) do
            env.exec_command(cmd[1],cmd[2])
        end
    elseif cmd=="OFF" then
        stack[thread]=nil
    else
        if not sec or not count or not target or sec<=0 or count<=0 then
            env.raise('Invalid syntax!')
        end
        for i=1,count do
            exec(target)
            if i<count then sleep(sec) end
        end
    end
end

function interval.clear_stack()
    
end

function interval.capture(cmd,args)
    local cmds=stack[threads[#threads]]
    if not cmds then return end
    cmds[#cmds+1]={cmd,args}
end


function interval.onload()
    env.set_command(nil,{"INTERVAL",interval.cmd},[[
        Run a command with specific interval, type 'help itv' for detail. Usage: ITV <START [seconds] [remark]|END|seconds times command>
        Example:
            1)  itv 5 5 ora actives
            2)  refer to 'show itvtest'
      ]],interval.itv,'__SMART_PARSE__',4)
    if env.event then env.event.snoop('BEFORE_COMMAND',interval.capture,nil,99) end
end

return interval