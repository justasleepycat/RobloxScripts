local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()

local RaycastMethods = {
	RaycastParams.new,
	Ray.new,
}

for i,v in pairs(RaycastMethods) do
	if isfunctionhooked(v) then
		restorefunction(v)
	end
end

for i,v in pairs(RaycastMethods) do
	local old; old = hookfunction(v, function(...)
		local script = getcallingscript()
		local scriptName = tostring(script)

		if string.find(scriptName, "Movement") then
			local args = {...}
			
			return old(unpack(args))
		end

		return old(...)
	end)
end