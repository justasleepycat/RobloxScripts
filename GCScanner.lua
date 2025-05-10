local GCScanner = {}

function GCScanner:ModifyValuesByIndex(list)
    local loops,maxloops = 0,10000
    local foundVars = {}
    for i,v in pairs(getgc(true)) do
		if loops < maxloops then loops += 1 else loops = 0; task.wait(.01) end
        if typeof(v) == "table" then
            for i2,v2 in pairs(v) do
                for i3,v3 in pairs(list) do
					if string.find(tostring(i2):lower(), tostring(v3.Index):lower()) then
                        if typeof(v[i2]) == v3.Type or v3.Type == "Any" then
                           if v3.Debug then
				print(v[i2])
							end
                            v[i2] = v3.NewValues.value ~= nil and v3.NewValues.value
 
						end
					end
				end
            end
        end
    end
    return foundVars
end

function GCScanner:FindValuesByIndex(list)
    local loops,maxloops = 0,10000
    local foundVars = {}
    for i,v in pairs(getgc(true)) do
		if loops < maxloops then loops += 1 else loops = 0; task.wait(.01) end
        if typeof(v) == "table" then
            for i2,v2 in pairs(v) do
                for i3,v3 in pairs(list) do
					if string.find(tostring(i2):lower(), tostring(v3.Index):lower()) then
                        if typeof(v[i2]) == v3.Type or v3.Type == "Any" then
                            if list.ReturnParentTable then
								table.insert(foundVars, {i = i,v = v})
							else
								table.insert(foundVars, {i = i2,v = v2})
							end
						end
					end
				end
            end
        end
    end
    return foundVars
end

-- Example
if false then
    GCScanner:ModifyValuesByIndex({
        {
            Index = "RPM",
            Type = "number", -- use Any to not filter
            ReturnParent = false,
            Debug = true,
            NewValues = {index = nil, value = 1000}
        }
    })

    local vars = GCScanner:FindValuesByIndex({
        {
            Index = "Weapon",
            Type = "number",
            ReturnParentTable = false
        }
    })
    for i,entry in pairs(vars) do
        print(entry.i,entry.v)
    end
end

-- Example
if false then
    GCScanner:ModifyValuesByIndex({
        {
            Index = "RPM",
            Type = "number", -- use Any to not filter
            ReturnParent = false,
            Debug = true,
            NewValues = {index = nil, value = 1000}
        }
    })
end


return GCScanner


