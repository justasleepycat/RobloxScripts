-- Decompiled with the Synapse Z Luau decompiler.
-- NOTE: Currently in beta! Not representative of final product.

local v0_0_ = game
local v0_2_ = "ReplicatedStorage"
v0_0_ = v0_0_:GetService(v0_2_)
local v0_1_ = require
local v0_4_ = v0_0_.Game
local v0_3_ = v0_4_.Garage
v0_2_ = v0_3_.VehicleConf
v0_1_ = v0_1_(v0_2_)
v0_2_ = require
local v0_5_ = v0_0_.Game
v0_4_ = v0_5_.Garage
v0_3_ = v0_4_.VehicleData
v0_2_ = v0_2_(v0_3_)
v0_3_ = require
v0_5_ = v0_0_.Sale
v0_4_ = v0_5_.SaleConsts
v0_3_ = v0_3_(v0_4_)
v0_4_ = require
local v0_6_ = v0_0_.Sale
v0_5_ = v0_6_.SaleUtils
v0_4_ = v0_4_(v0_5_)
v0_5_ = require
local v0_7_ = v0_0_.Garage
v0_6_ = v0_7_.GarageUtils
v0_5_ = v0_5_(v0_6_)
v0_6_ = require
local v0_8_ = v0_0_.Ownership
v0_7_ = v0_8_.OwnershipConsts
v0_6_ = v0_6_(v0_7_)
v0_7_ = require
local v0_9_ = v0_0_.Std
v0_8_ = v0_9_.Signal
v0_7_ = v0_7_(v0_8_)
v0_8_ = require
local v0_10_ = v0_0_.Std
v0_9_ = v0_10_.Interval
v0_8_ = v0_8_(v0_9_)
v0_9_ = {}
v0_10_ = v0_7_.new
v0_10_ = v0_10_()
v0_9_.onSaleRefresh = v0_10_
v0_10_ = v0_4_.getNextSaleTime
v0_10_ = v0_10_()
local v0_11_ = v0_8_.every
local v0_12_ = 1
v0_11_ = v0_11_(v0_12_)
local v0_13_ = function()
    local v1_1_ = v0_4_
    local v1_0_ = v1_1_.getNextSaleTime
    v1_0_ = v1_0_()
    local v1_2_ = v0_10_
    v1_1_ = v1_2_ + 0.010000
    if v1_1_ < v1_0_ then
        v0_10_ = v1_1_
        v1_2_ = v0_9_
        v1_1_ = v1_2_.onSaleRefresh
        v1_1_:Fire()
    end
end
v0_11_:Connect(v0_13_)
v0_10_ = function(a1)
    local v2_3_ = v0_5_
    local v2_2_ = v2_3_.isVehicleCustomizationLimited
    v2_3_ = a1
    v2_2_ = v2_2_(v2_3_)
    local v2_1_ = not v2_2_
    if v2_1_ then
        v2_2_ = a1.None
        v2_1_ = not v2_2_
        if v2_1_ then
            v2_2_ = a1.Price
            if v2_2_ then
                v2_1_ = false
                v2_2_ = a1.Price
                v2_3_ = 1000000.000000
                if v2_2_ < v2_3_ then
                    v2_2_ = a1.Price
                    v2_3_ = 0
                    if v2_3_ >= v2_2_ then
                        v2_1_ = false
                    end
                    v2_1_ = true
                    v2_1_ = false
                end
            else
                v2_1_ = false
            end
            if v2_1_ then
                v2_2_ = a1.NoGarageUI
                v2_1_ = not v2_2_
            end
        end
    end
    return v2_1_
end
v0_11_ = function(a1)
    local v3_3_ = v0_5_
    local v3_2_ = v3_3_.isVehicleLimited
    v3_3_ = a1
    v3_2_ = v3_2_(v3_3_)
    local v3_1_ = not v3_2_
    if v3_1_ then
        v3_2_ = a1.None
        v3_1_ = not v3_2_
        if v3_1_ then
            v3_2_ = a1.Price
            if v3_2_ then
                v3_1_ = false
                v3_2_ = a1.Price
                v3_3_ = 1000000.000000
                if v3_2_ < v3_3_ then
                    v3_2_ = a1.Price
                    v3_3_ = 0
                    if v3_3_ >= v3_2_ then
                        v3_1_ = false
                    end
                    v3_1_ = true
                    v3_1_ = false
                end
            else
                v3_1_ = false
            end
            if v3_1_ then
                v3_2_ = a1.NoGarageUI
                v3_1_ = not v3_2_
                if v3_1_ then
                    v3_2_ = a1.ExcludeFromSale
                    v3_1_ = not v3_2_
                end
            end
        end
    end
    return v3_1_
end
v0_12_ = function(a1, a2)
    local sort = table.sort
    local v4_3_ = a1
    local v4_4_ = function(a1, a2)
        local v5_4_ = a1.Pointer
        local v5_5_ = a2
        local v5_3_ = v5_4_[v5_5_]
        v5_5_ = a2.Pointer
        local v5_6_ = a2
        v5_4_ = v5_5_[v5_6_]
        if v5_3_ >= v5_4_ then
            local v5_2_ = false
        end
        local v5_2_ = true
        return v5_2_
    end
    sort(v4_3_, v4_4_)
    v4_3_ = v0_4_
    local v4_2_ = v4_3_.getNumSalesPassed
    v4_2_ = v4_2_()
    local new = Random.new
    v4_4_ = v4_2_
    v4_3_ = new(v4_4_)
    v4_4_ = a1
    local v4_5_ = nil
    local v4_6_ = nil
    local v4_9_ = v4_3_:NextNumber()
    nil.SortNumber = v4_9_
    local sort = table.sort
    v4_5_ = a1
    v4_6_ = function(a1, a2)
        local v6_3_ = a1.SortNumber
        local v6_4_ = a2.SortNumber
        if v6_3_ >= v6_4_ then
            local v6_2_ = false
        end
        local v6_2_ = true
        return v6_2_
    end
    sort(v4_5_, v4_6_)
end
v0_13_ = function()
    local v7_0_ = {}
    local v7_1_ = {}
    local v7_5_ = v0_1_
    local v7_2_ = v7_5_.CATEGORIES
    local v7_3_ = nil
    local v7_4_ = nil
    local v7_8_ = v0_3_
    local v7_7_ = v7_8_.CATEGORY_NAME
    if nil ~= v7_7_ then
        local v7_9_ = v0_6_
        v7_8_ = v7_9_.COLOR_CATEGORY_TYPES
        v7_7_ = v7_8_[nil]
        if not v7_7_ then
            v7_9_ = v0_6_
            v7_8_ = v7_9_.TEXTURE_CATEGORY_TYPES
            v7_7_ = v7_8_[nil]
            if not v7_7_ then
                v7_7_ = require
                local v7_11_ = v0_0_
                local v7_10_ = v7_11_.Game
                v7_9_ = v7_10_.Garage
                v7_8_ = v7_9_.StoreData
                v7_10_ = nil
                v7_7_ = v7_7_(v7_8_:FindFirstChild(v7_10_))
                v7_8_ = v7_7_.Items
                v7_9_ = nil
                v7_10_ = nil
                local v7_15_ = {}
                v7_15_.CategoryName = nil
                v7_15_.Pointer = nil
                local v7_14_ = v7_0_
                local insert = table.insert
                insert(v7_14_, v7_15_)
                v7_8_ = true
                v7_1_[nil] = v7_8_
            end
        end
    end
    v7_2_ = 0
    v7_3_ = v7_1_
    v7_4_ = nil
    v7_5_ = nil
    v7_2_ += 1.000000
    v7_3_ = v0_12_
    v7_4_ = v7_0_
    v7_5_ = "Name"
    v7_3_(v7_4_, v7_5_)
    v7_3_ = {}
    v7_4_ = {}
    v7_5_ = {}
    local v7_6_ = v7_0_
    v7_7_ = nil
    v7_8_ = nil
    local v7_11_ = nil.CategoryName
    local v7_13_ = nil.Pointer
    local v7_15_ = v0_5_
    local v7_14_ = v7_15_.isVehicleCustomizationLimited
    v7_15_ = v7_13_
    v7_14_ = v7_14_(v7_15_)
    local v7_12_ = not v7_14_
    if v7_12_ then
        v7_14_ = v7_13_.None
        v7_12_ = not v7_14_
        if v7_12_ then
            v7_14_ = v7_13_.Price
            if v7_14_ then
                v7_12_ = false
                v7_14_ = v7_13_.Price
                v7_15_ = 1000000.000000
                if v7_14_ < v7_15_ then
                    v7_14_ = v7_13_.Price
                    v7_15_ = 0
                    if v7_15_ >= v7_14_ then
                        v7_12_ = false
                    end
                    v7_12_ = true
                    v7_12_ = false
                end
            else
                v7_12_ = false
            end
            if v7_12_ then
                v7_14_ = v7_13_.NoGarageUI
                v7_12_ = not v7_14_
            end
        end
    end
    if v7_12_ then
        v7_12_ = v7_5_[v7_11_]
        if not v7_12_ then
            local clone = table.clone
            v7_13_ = nil.Pointer
            v7_12_ = clone(v7_13_)
            v7_12_.CategoryName = v7_11_
            v7_14_ = v7_3_
            v7_15_ = v7_12_
            local insert = table.insert
            insert(v7_14_, v7_15_)
            v7_13_ = v7_4_[v7_11_]
            if not v7_13_ then
                v7_13_ = {}
                v7_4_[v7_11_] = v7_13_
            end
            v7_13_ = v7_4_[v7_11_]
            v7_15_ = nil.Pointer
            v7_14_ = v7_15_.Name
            v7_15_ = true
            v7_13_[v7_14_] = v7_15_
            v7_13_ = true
            v7_5_[v7_11_] = v7_13_
        end
    end
    v7_12_ = #v7_3_
    v7_14_ = v0_3_
    v7_13_ = v7_14_.NUM_VEHICLE_CUSTOMIZATIONS
    if v7_13_ > v7_12_ then
    end
    return v7_3_, v7_4_
end
local v0_14_ = function()
    local v8_0_ = {}
    local v8_1_ = v0_2_
    local v8_2_ = nil
    local v8_3_ = nil
    local v8_8_ = {}
    v8_8_.Pointer = nil
    local v8_7_ = v8_0_
    local insert = table.insert
    insert(v8_7_, v8_8_)
    v8_1_ = v0_12_
    v8_2_ = v8_0_
    v8_3_ = "Make"
    v8_1_(v8_2_, v8_3_)
    v8_1_ = {}
    v8_2_ = {}
    v8_3_ = v8_0_
    local v8_4_ = nil
    local v8_5_ = nil
    local v8_9_ = v8_7_.Pointer
    local v8_11_ = v0_5_
    local v8_10_ = v8_11_.isVehicleLimited
    v8_11_ = v8_9_
    v8_10_ = v8_10_(v8_11_)
    v8_8_ = not v8_10_
    if v8_8_ then
        v8_10_ = v8_9_.None
        v8_8_ = not v8_10_
        if v8_8_ then
            v8_10_ = v8_9_.Price
            if v8_10_ then
                v8_8_ = false
                v8_10_ = v8_9_.Price
                v8_11_ = 1000000.000000
                if v8_10_ < v8_11_ then
                    v8_10_ = v8_9_.Price
                    v8_11_ = 0
                    if v8_11_ >= v8_10_ then
                        v8_8_ = false
                    end
                    v8_8_ = true
                    v8_8_ = false
                end
            else
                v8_8_ = false
            end
            if v8_8_ then
                v8_10_ = v8_9_.NoGarageUI
                v8_8_ = not v8_10_
                if v8_8_ then
                    v8_10_ = v8_9_.ExcludeFromSale
                    v8_8_ = not v8_10_
                end
            end
        end
    end
    if v8_8_ then
        v8_10_ = v8_7_.Pointer
        v8_9_ = v8_1_
        local insert_0 = table.insert
        insert_0(v8_9_, v8_10_)
        v8_9_ = v8_7_.Pointer
        v8_8_ = v8_9_.Make
        v8_9_ = true
        v8_2_[v8_8_] = v8_9_
    end
    v8_8_ = #v8_1_
    v8_10_ = v0_3_
    v8_9_ = v8_10_.NUM_VEHICLES
    if v8_9_ > v8_8_ then
    end
    return v8_1_, v8_2_
end
local v0_15_ = nil
v0_9_._cachedOnSaleVehicleCustomizations = v0_15_
v0_15_ = nil
v0_9_._cachedOnSaleVehicleCustomizationsMap = v0_15_
v0_15_ = function()
    local v9_1_ = v0_9_
    local v9_0_ = v9_1_._cachedOnSaleVehicleCustomizations
    if v9_0_ == nil then
        v9_0_ = v0_9_
        v9_1_ = v0_9_
        local v9_2_ = v0_13_
        local v9_2_, v9_3_ = v9_2_()
        v9_0_._cachedOnSaleVehicleCustomizations = v9_2_
        v9_1_._cachedOnSaleVehicleCustomizationsMap = v9_3_
        v9_1_ = 60
        local v9_4_ = v0_4_
        v9_3_ = v9_4_.getTimeToNextSale
        v9_3_ = v9_3_()
        v9_2_ = v9_3_ - 1.000000
        local min = math.min
        v9_0_ = min(v9_1_, v9_2_)
        local delay = task.delay
        v9_2_ = v9_0_
        v9_3_ = function()
            local v10_0_ = v0_9_
            local v10_1_ = nil
            v10_0_._cachedOnSaleVehicleCustomizations = v10_1_
            v10_0_ = v0_9_
            v10_1_ = nil
            v10_0_._cachedOnSaleVehicleCustomizationsMap = v10_1_
        end
        delay(v9_2_, v9_3_)
    end
end
local v0_16_ = function()
    local v11_0_ = v0_15_
    v11_0_()
    local v11_1_ = v0_9_
    v11_0_ = v11_1_._cachedOnSaleVehicleCustomizations
    return v11_0_
end
v0_9_.getOnSaleVehicleCustomizations = v0_16_
v0_16_ = function(a1, a2)
    if a1 == nil then
        local v12_3_ = false
    end
    local v12_3_ = true
    local v12_4_ = "categoryName must not be nil"
    local v12_2_ = assert
    v12_2_(v12_3_, v12_4_)
    if a2 == nil then
        v12_3_ = false
    end
    v12_3_ = true
    v12_4_ = "itemName must not be nil"
    v12_2_ = assert
    v12_2_(v12_3_, v12_4_)
    v12_2_ = v0_15_
    v12_2_()
    v12_2_ = false
    local v12_5_ = v0_9_
    v12_4_ = v12_5_._cachedOnSaleVehicleCustomizationsMap
    v12_3_ = v12_4_[a1]
    if v12_3_ ~= nil then
        local v12_6_ = v0_9_
        v12_5_ = v12_6_._cachedOnSaleVehicleCustomizationsMap
        v12_4_ = v12_5_[a1]
        v12_3_ = v12_4_[a2]
        if v12_3_ ~= true then
            v12_2_ = false
        end
        v12_2_ = true
    end
    return v12_2_
end
v0_9_.isVehicleCustomizationOnSale = v0_16_
v0_16_ = nil
v0_9_._cachedOnSaleVehicles = v0_16_
v0_16_ = nil
v0_9_._cachedOnSaleVehiclesMap = v0_16_
v0_16_ = function()
    local v13_1_ = v0_9_
    local v13_0_ = v13_1_._cachedOnSaleVehicles
    if v13_0_ == nil then
        v13_0_ = v0_9_
        v13_1_ = v0_9_
        local v13_2_ = v0_14_
        local v13_2_, v13_3_ = v13_2_()
        v13_0_._cachedOnSaleVehicles = v13_2_
        v13_1_._cachedOnSaleVehiclesMap = v13_3_
        v13_1_ = 60
        local v13_4_ = v0_4_
        v13_3_ = v13_4_.getTimeToNextSale
        v13_3_ = v13_3_()
        v13_2_ = v13_3_ - 1.000000
        local min = math.min
        v13_0_ = min(v13_1_, v13_2_)
        local delay = task.delay
        v13_2_ = v13_0_
        v13_3_ = function()
            local v14_0_ = v0_9_
            local v14_1_ = nil
            v14_0_._cachedOnSaleVehicles = v14_1_
            v14_0_ = v0_9_
            v14_1_ = nil
            v14_0_._cachedOnSaleVehiclesMap = v14_1_
        end
        delay(v13_2_, v13_3_)
    end
end
local v0_17_ = function()
    local v15_0_ = v0_16_
    v15_0_()
    local v15_1_ = v0_9_
    v15_0_ = v15_1_._cachedOnSaleVehicles
    return v15_0_
end
v0_9_.getOnSaleVehicles = v0_17_
v0_17_ = function(a1)
    if a1 == nil then
        local v16_2_ = false
    end
    local v16_2_ = true
    local v16_3_ = "vehicleMake must not be nil"
    local v16_1_ = assert
    v16_1_(v16_2_, v16_3_)
    v16_1_ = v0_16_
    v16_1_()
    local v16_4_ = v0_9_
    v16_3_ = v16_4_._cachedOnSaleVehiclesMap
    v16_2_ = v16_3_[a1]
    if v16_2_ ~= true then
        v16_1_ = false
    end
    v16_1_ = true
    return v16_1_
end
v0_9_.isVehicleOnSale = v0_17_
return v0_9_
