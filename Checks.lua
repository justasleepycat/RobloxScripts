local Checks = {}

function Checks:IsVisible(startPos : Vector3, endPos : Vector3, MaxDistance : number,ignore : table)
    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude
    RayParams.FilterDescendantsInstances = ignore
    RayParams.IgnoreWater = true
    RayParams.RespectCanCollide = true
    local result : RaycastResult = game:GetService("Workspace"):Raycast(startPos, (endPos - startPos).Unit * MaxDistance, RayParams)
    return result
end

--[[ Available Functions
    IsVisible(startPos : Vector3, endPos : Vector3, MaxDistance : number,ignore : table) <-- uses raycasting and returns the raycastresult
]]
if false then
    for i,v in pairs(game.Workspace.Threats:GetChildren()) do
        local visible = Checks:IsVisible(game.Players.LocalPlayer.Character.Head.CFrame.Position, v:GetPivot().Position, 1000, {game.Players.LocalPlayer.Character})
        if visible.Instance and visible.Instance:IsDescendantOf(v) then
            print(v:GetFullName())
        end
    end
end


return Checks
