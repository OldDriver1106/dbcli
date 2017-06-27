local env=env
local hotkeys={}
function hotkeys.help()

    return [[
        Ctrl+G                       : Cancle command
        Ctrl+D                       : Delete char
        Alt+BackSpace                : Kill previous word
        Alt+Left                     : Move to previous word
        Alt+Right                    : Move to next word
        Shift+Left                   : Scroll left
        Shift+Right                  : Scroll right
        Ctrl+C  or 'Q'               : Abort running command
        Ctrl+L                      * : Clear screen
        Ctrl+U                       : Kill all words that before cursor
        Ctrl+K                       : Kill all words that after cursor]]
end

function hotkeys.call(_,_,x)
    local maps=console:getKeyMap("-L");
    local hdl=env.grid.new()
    hdl:add{"Key","*","Description",'|',"Key","*","Description"}
    local row
    for key,desc in maps:gmatch('("[^\n\r]+") +([^\n\r]+)[\n\r]') do
        key=key:gsub('"(.-)"',' $HEADCOLOR$%1$NOR$ ')
        if not row then 
            row={key,' ',desc} 
        else
            row[#row+1],row[#row+2],row[#row+3],row[#row+4]='|',key,' ',desc
            hdl:add(row)
            row=nil
        end
    end
    if row then hdl:add(row) end
    hdl:print()
end


function hotkeys.onload()
    env.set_command(nil,"KEYMAP",{"Show available hot keys. type '@@NAME' for more information.",hotkeys.help},hotkeys.call,false,2)
end

return hotkeys