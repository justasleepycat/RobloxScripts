for i,v in pairs(getgc(true)) do
	if typeof(v) == "function" then
		pcall(function()
			if getinfo(v).name == "CheatCheck" then
				hookfunction(v, newcclosure(function()
					return
				end))
			end
			if getinfo(v).name == "CheatCheck0" then
				hookfunction(v, newcclosure(function()
					return
				end))
			end
			if getinfo(v).name == "getDisabled" and string.find(getinfo(v).source, "CircleActionUtils") then
				hookfunction(v, newcclosure(function()
					return false
				end))
			end
		end)
	end
end