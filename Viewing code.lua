-- Decompiled with the Synapse Z Luau decompiler.
-- NOTE: Currently in beta! Not representative of final product.

local v0_2_ = script
local v0_1_ = v0_2_.Parent
local v0_0_ = v0_1_.Parent
local v0_3_ = "Handle"
v0_1_ = v0_0_:WaitForChild(v0_3_)
v0_2_ = game
local v0_4_ = "Players"
v0_2_ = v0_2_:GetService(v0_4_)
v0_3_ = v0_2_.LocalPlayer
v0_4_ = {}
local v0_5_ = game
local v0_7_ = "RunService"
v0_5_ = v0_5_:GetService(v0_7_)
local v0_6_ = game
local v0_8_ = "Debris"
v0_6_ = v0_6_:GetService(v0_8_)
v0_7_ = game
local v0_9_ = "UserInputService"
v0_7_ = v0_7_:GetService(v0_9_)
v0_9_ = workspace
v0_8_ = v0_9_.Camera
v0_9_ = function()
    local v1_0_ = v0_7_
    v1_0_ = v1_0_:GetMouseLocation()
    local v1_1_ = v0_8_
    local v1_3_ = v1_0_.X
    local v1_4_ = v1_0_.Y
    v1_1_ = v1_1_:ViewportPointToRay(v1_3_, v1_4_)
    local v1_2_ = workspace
    local new = Ray.new
    local v1_5_ = v1_1_.Origin
    local v1_7_ = v1_1_.Direction
    local v1_6_ = v1_7_ * 1000.000000
    v1_4_ = new(v1_5_, v1_6_)
    v1_5_ = table.create(1)
    local v1_8_ = workspace
    v1_7_ = v1_8_.Map
    v1_6_ = v1_7_.Ignore
    v1_5_[1] = v1_6_
    return v1_2_:FindPartOnRayWithIgnoreList(v1_4_, v1_5_)
end
local v0_10_ = v0_0_.Equipped
local v0_12_ = function(a1)
    local v2_1_ = wait
    v2_1_()
    v2_1_ = v0_1_
    local v2_3_ = "Boop"
    v2_1_ = v2_1_:WaitForChild(v2_3_)
    local v2_2_ = 0
    v2_1_.Volume = v2_2_
    v2_2_ = v0_4_
    local v2_5_ = v0_4_
    local v2_4_ = #v2_5_
    v2_3_ = v2_4_ + 1.000000
    v2_4_ = a1.Button1Down
    local v2_6_ = function()
        local v3_2_ = v0_2_
        local v3_1_ = v3_2_.LocalPlayer
        local v3_0_ = v3_1_.Character
        if not v3_0_ then
            return
        end
        local v3_3_ = workspace
        v3_2_ = v3_3_.GameState
        v3_1_ = v3_2_.NightCutscene
        v3_0_ = v3_1_.Value
        if v3_0_ then
            return
        end
        v3_0_ = v0_9_
        v3_0_ = v3_0_()
        v3_1_ = v3_0_
        if v3_1_ then
            v3_1_ = v3_0_.Name
        end
        if not v3_0_ then
            return
        end
        v3_2_ = nil
        local v3_5_ = "Accessory"
        v3_3_ = v3_0_:FindFirstChildOfClass(v3_5_)
        if v3_3_ then
            v3_5_ = "#Bypassable"
            local v3_6_ = true
            v3_3_ = v3_0_:FindFirstChild(v3_5_, v3_6_)
            v3_2_ = v3_3_
        else
            v3_5_ = "#Bypassable"
            v3_3_ = v3_0_:FindFirstChild(v3_5_)
            v3_2_ = v3_3_
        end
        if not v3_2_ then
            v3_0_ = v3_0_.Parent
            v3_5_ = "#Bypassable"
            v3_3_ = v3_0_:FindFirstChild(v3_5_)
            v3_2_ = v3_3_
        end
        v3_3_ = workspace
        while v3_0_ ~= v3_3_ do
            v3_5_ = "Folder"
            v3_3_ = v3_0_:IsA(v3_5_)
            if v3_3_ then
                v3_3_ = v3_0_.Name
                while v3_3_ == "Cameras" do
                    while not v3_2_ do
                    end
                end
            end
            while not v3_2_ do
            end
        end
        if v3_2_ then
            v3_3_ = pairs
            local v3_6_ = workspace
            v3_5_ = v3_6_.Services
            local v3_4_ = v3_5_.Bypassable
            v3_3_, v3_4_, v3_5_ = v3_3_(v3_4_:GetChildren())
            for v3_6_, v3_7_ in v3_3_, v3_4_, v3_5_ do
                local v3_8_ = v3_7_.Value
                local v3_9_ = v3_2_.Parent
                if v3_8_ == v3_9_ then
                    local v3_10_ = workspace
                    v3_9_ = v3_10_.Services
                    v3_8_ = v3_9_.BypassRequest
                    local v3_11_ = v3_7_.Name
                    v3_10_ = tonumber
                    v3_10_ = v3_10_(v3_11_)
                    v3_11_ = v3_1_
                    v3_8_:InvokeServer(v3_10_, v3_11_)
                    return
                end
            end
        end
    end
    local insert = table.insert
    insert(v2_4_:connect(v2_6_))
    v2_1_ = pairs
    v2_4_ = workspace
    v2_3_ = v2_4_.Services
    v2_2_ = v2_3_.Bypassable
    v2_1_, v2_2_, v2_3_ = v2_1_(v2_2_:GetChildren())
    for v2_4_, v2_5_ in v2_1_, v2_2_, v2_3_ do
        local v2_7_ = v2_5_.Value
        local v2_9_ = "Reader1"
        v2_7_ = v2_7_:FindFirstChild(v2_9_)
        if v2_7_ then
            v2_7_ = v2_5_.Value
            v2_6_ = v2_7_.Reader1
            local v2_8_ = "Union"
            v2_6_ = v2_6_:FindFirstChild(v2_8_)
            if not v2_6_ then
                v2_6_ = v2_5_.Value
                v2_8_ = "Part"
                v2_6_ = v2_6_:FindFirstChildOfClass(v2_8_)
                if not v2_6_ then
                    v2_6_ = v2_5_.Value
                    v2_8_ = "MeshPart"
                    v2_6_ = v2_6_:FindFirstChildOfClass(v2_8_)
                end
            end
        end
        v2_6_ = v2_5_.Value
        local v2_8_ = "Part"
        v2_6_ = v2_6_:FindFirstChildOfClass(v2_8_)
        if not v2_6_ then
            v2_6_ = v2_5_.Value
            v2_8_ = "MeshPart"
            v2_6_ = v2_6_:FindFirstChildOfClass(v2_8_)
        end
        v2_8_ = script
        v2_7_ = v2_8_.Light
        v2_7_ = v2_7_:Clone()
        v2_8_ = "TempHighlight"
        v2_7_.Name = v2_8_
        v2_7_.Adornee = v2_6_
        v2_9_ = v0_3_
        v2_8_ = v2_9_.PlayerGui
        v2_7_.Parent = v2_8_
        v2_8_ = spawn
        v2_9_ = function()
            local v4_1_ = v0_0_
            local v4_0_ = v4_1_.Parent
            local v4_2_ = v0_3_
            v4_1_ = v4_2_.Character
            while v4_0_ == v4_1_ do
                v4_1_ = v2_7_
                v4_0_ = v4_1_.ImageLabel
                local v4_4_ = v2_7_
                local v4_3_ = v4_4_.ImageLabel
                v4_2_ = v4_3_.Rotation
                v4_1_ = v4_2_ + 2.000000
                v4_0_.Rotation = v4_1_
                v4_1_ = v0_5_
                v4_0_ = v4_1_.Stepped
                v4_0_:Wait()
            end
            v4_0_ = v0_6_
            v4_2_ = v2_7_
            local v4_3_ = 0
            v4_0_:AddItem(v4_2_, v4_3_)
        end
        v2_8_(v2_9_)
        v2_8_ = v2_5_.Value
        local v2_10_ = "Reader2"
        v2_8_ = v2_8_:FindFirstChild(v2_10_)
        if v2_8_ then
            v2_9_ = v2_5_.Value
            v2_8_ = v2_9_.Reader2
            v2_10_ = "Union"
            v2_8_ = v2_8_:FindFirstChild(v2_10_)
            if v2_8_ then
                v2_10_ = v2_5_.Value
                v2_9_ = v2_10_.Reader2
                v2_8_ = v2_9_.Union
                v2_10_ = script
                v2_9_ = v2_10_.Light
                v2_9_ = v2_9_:Clone()
                v2_10_ = "TempHighlight"
                v2_9_.Name = v2_10_
                v2_9_.Adornee = v2_8_
                local v2_11_ = v0_3_
                v2_10_ = v2_11_.PlayerGui
                v2_9_.Parent = v2_10_
                v2_10_ = spawn
                v2_11_ = function()
                    local v5_1_ = v0_0_
                    local v5_0_ = v5_1_.Parent
                    local v5_2_ = v0_3_
                    v5_1_ = v5_2_.Character
                    while v5_0_ == v5_1_ do
                        v5_1_ = v2_9_
                        v5_0_ = v5_1_.ImageLabel
                        local v5_4_ = v2_9_
                        local v5_3_ = v5_4_.ImageLabel
                        v5_2_ = v5_3_.Rotation
                        v5_1_ = v5_2_ + 2.000000
                        v5_0_.Rotation = v5_1_
                        v5_1_ = v0_5_
                        v5_0_ = v5_1_.Stepped
                        v5_0_:Wait()
                    end
                    v5_0_ = v0_6_
                    v5_2_ = v2_9_
                    local v5_3_ = 0
                    v5_0_:AddItem(v5_2_, v5_3_)
                end
                v2_10_(v2_11_)
            end
        end
    end
end
v0_10_:Connect(v0_12_)
v0_10_ = v0_0_.Unequipped
v0_12_ = function()
    local v6_1_ = v0_1_
    local v6_0_ = v6_1_.Boop
    v6_1_ = 0.500000
    v6_0_.Volume = v6_1_
    v6_0_ = pairs
    v6_1_ = v0_4_
    local v6_0_, v6_1_, v6_2_ = v6_0_(v6_1_)
    for v6_3_, v6_4_ in v6_0_, v6_1_, v6_2_ do
    end
    v6_0_ = {}
    v0_4_ = v6_1_
end
v0_10_:Connect(v0_12_)
