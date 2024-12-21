local SleepyDumper = {}

makefolder("DumpedScripts")
local scriptPath = ("DumpedScripts/%s"):format(string.gsub(game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name, "|", ""))
makefolder(scriptPath)

function SleepyDumper:DumpFunctions(config)
    local DumpedFunctions = {}
    local success, err = pcall(function()
        for i,v in pairs(getgc(true)) do
            local success, err = pcall(function()
                if typeof(v) == "function" then
                    local FuncInfo = getinfo(v)
                    if FuncInfo then
						local isInternalFunction = issynapsefunction ~= nil and issynapsefunction or is_synapse_function ~= nil and is_synapse_function
                        if isInternalFunction(v) then return end
                        local FuncName = FuncInfo.name
                        local FuncSource = FuncInfo.source
                        if FuncSource == "=[C]" then return end
                        if string.len(FuncName) < 2 then return end
                        FuncSource = string.gsub(FuncSource, "=", "")
                        table.insert(DumpedFunctions, {FuncName, FuncSource})
                    end
                end
			end)
            if not success then
				rconsoleprint(err)
			end
        end
        writefile(scriptPath.."/DumpedFunctions.lua", "")
        table.sort(DumpedFunctions, function(a, b)
            return a[1] < b[1]
        end)
        for i,v in pairs(DumpedFunctions) do
			appendfile(scriptPath.."/DumpedFunctions.lua", string.format("%s = %s\n", v[1], v[2]))
		end
	end)
    if not success then
		rconsoleprint(err)
	end
end

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

SleepyDumper:DumpFunctions()
--SleepyDumper:DumpInstance(game)






return SleepyDumper