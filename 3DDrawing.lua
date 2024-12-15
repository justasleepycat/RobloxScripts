local function DrawLine3D(config)
    local Workspace = game:GetService("Workspace")
    local line = Instance.new("Part")
    local highlight = Instance.new("Highlight", line)
    local Direction = (config.To - config.From)
    local length = (config.To - config.From).Magnitude

    highlight.FillColor = config.Color
    highlight.Adornee = line
    highlight.FillTransparency = 0
    highlight.OutlineTransparency = 1
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    line.CastShadow = false
    line.Material = Enum.Material.Plastic
    line.Anchored = true
    line.CanCollide = false
    line.CFrame = CFrame.new(config.From + Direction/2)
    line:PivotTo(CFrame.lookAt(line.CFrame.Position, config.To))
    line.Color = config.Color
    line.Size = Vector3.new(0.1, 0.1, math.min(2048, length))
    line.Parent = Workspace

    return line
end

local function UpdateLine3D(line, config)
    local Direction = (config.To - config.From)
    local length = (config.To - config.From).Magnitude

    line.CFrame = CFrame.new(config.From + Direction/2)
    line:PivotTo(CFrame.lookAt(line.CFrame.Position, config.To))
    line.Color = config.Color
    line.Size = Vector3.new(0.1, 0.1, length)
end





-- Example Usage
local funiLine = DrawLine3D({
    From = game.Players.LocalPlayer.Character:GetPivot().Position,
    To = Workspace.CurrentCamera.CFrame.Position,
    Color = Color3.new(1, 0, 0),
})

for i = 1,1000 do task.wait(.001)
	UpdateLine3D(funiLine, {
        From = game.Players.LocalPlayer.Character:GetPivot().Position,
        To = game.Players.LocalPlayer.Character:GetPivot().Position + game.Players.LocalPlayer.Character:GetPivot().LookVector*10,
        Color = Color3.new(1,0,0)
    })
end
funiLine:Destroy()