

        game:GetService("RunService"):setThrottleFramerateEnabled(false)
    end
end


local function ToggleOptimizer()
    Optimizer.Enabled = not Optimizer.Enabled
    DisableEffects()
    MaximizePerformance()
    OptimizeInstances()
    CleanMemory()
    print("Enhanced FPS Optimizer: " .. (Optimizer.Enabled and "ON" or "OFF"))
end


game:GetService("UserInputService").InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.RightControl then
        ToggleOptimizer()
    end
end)


ToggleOptimizer()


game:GetService("RunService").Heartbeat:Connect(function()
    if Optimizer.Enabled then
        CleanMemory()
    end
end)

