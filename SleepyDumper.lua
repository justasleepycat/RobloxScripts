local SleepyDumper = {}

makefolder("DumpedScripts")
local scriptPath = ("DumpedScripts/%s"):format(game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name)
makefolder(scriptPath)


function SleepyDumper:DumpInstance(instance : Instance)
    local success, err = pcall(function()
		if not instance:FindFirstChildWhichIsA("ModuleScript", true) and not instance:FindFirstChildWhichIsA("LocalScript", true) then
			return
		end

        local CurrentPath = scriptPath.."/"..tostring(instance)
        local loops,maxloops = 0,3

        local function DumpChildren(parent : Instance, path)
            if string.find(string.lower(path), ":") then
                return
            end
			makefolder(path)

            for i,v in pairs(parent:GetChildren()) do
				if v.Name == "CoreGui" then
					continue
				end
                if v:IsA("ModuleScript") or v:IsA("LocalScript") then
					if loops < maxloops then loops += 1 else loops = 0; task.wait(.01) end
                    local str = decompile(v)
                    writefile(path.."/"..tostring(v)..".lua", "--Script Path: "..tostring(v:GetFullName()).."\n"..str)
                end
                if v:FindFirstChildWhichIsA("ModuleScript", true) or v:FindFirstChildWhichIsA("LocalScript", true) then
                    DumpChildren(v, path.."/"..tostring(v))
                end
            end
        end
        DumpChildren(instance, CurrentPath)
        rconsoleprint("Dump finished.")
	end)
    if not success then
		print(err)
	end
end

-- Example usage
--SleepyDumper:DumpInstance(game:GetService("Workspace"))
--SleepyDumper:DumpInstance(game:GetService("ReplicatedStorage"))
--SleepyDumper:DumpInstance(game:GetService("StarterPlayer"))
SleepyDumper:DumpInstance(game)
return SleepyDumper