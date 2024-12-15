makefolder("DumpedScripts")
local scriptPath = ("DumpedScripts/%d"):format(game.PlaceId)
makefolder(scriptPath)


local function DumpInstance(instance : Instance)
    makefolder(scriptPath.."/"..tostring(instance))
    for i,v in pairs(instance:GetDescendants()) do
        if v.ClassName == "ModuleScript" or v.ClassName == "LocalScript" then
            local str = decompile(v)
            writefile(scriptPath.."/"..tostring(instance).."/"..tostring(v)..".lua", str)
        end
    end
end
DumpInstance(game.ReplicatedFirst)