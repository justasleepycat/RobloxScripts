local bypassAdonis = true


if bypassAdonis then
    for _, value in pairs(getgc(true)) do
        if typeof(value) == 'table' then
            local oldReadonly = isreadonly(value)
            setreadonly(value, false)


            if rawget(value, "indexInstance") or rawget(value, "newindexInstance") or rawget(value, "namecallInstance") or rawget(value, "newIndexInstance") then
                value.tvk = {
                    "kick",
                    function()
                        return task.wait(387420489)
                    end
                }
            end


            setreadonly(value, oldReadonly)
        end
    end
end


loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/Upbolt/Hydroxide/refs/heads/revision/init.lua"))()
loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/Upbolt/Hydroxide/refs/heads/revision/ui/main.lua"))()