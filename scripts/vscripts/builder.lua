-- A build ability is used (not yet confirmed)
function Build( event )
    local caster = event.caster
    local ability = event.ability
    local ability_name = ability:GetAbilityName()
    local building_name = ability:GetAbilityKeyValues()['UnitName']
    local gold_cost = ability:GetGoldCost(1) 
    local hero = caster:IsRealHero() and caster or caster:GetOwner()
    local playerID = hero:GetPlayerID()

    -- If the ability has an AbilityGoldCost, it's impossible to not have enough gold the first time it's cast
    -- Always refund the gold here, as the building hasn't been placed yet
    hero:ModifyGold(gold_cost, false, 0)

    -- Makes a building dummy and starts panorama ghosting
    BuildingHelper:AddBuilding(event)

    -- Additional checks to confirm a valid building position can be performed here
    event:OnPreConstruction(function(vPos)

        -- Check for minimum height if defined
        if not BuildingHelper:MeetsHeightCondition(vPos) then
            BuildingHelper:print("Failed placement of " .. building_name .." - Placement is below the min height required")
            SendErrorMessage(playerID, "#error_invalid_build_position")
            return false
        end

        -- If not enough resources to queue, stop
        if PlayerResource:GetGold(playerID) < gold_cost then
            BuildingHelper:print("Failed placement of " .. building_name .." - Not enough gold!")
            SendErrorMessage(playerID, "#error_not_enough_gold")
            return false
        end

        return true
    end)

    -- Position for a building was confirmed and valid
    event:OnBuildingPosChosen(function(vPos)
        -- Spend resources
        hero:ModifyGold(-gold_cost, false, 0)

        -- Play a sound
        EmitSoundOnClient("DOTA_Item.ObserverWard.Activate", PlayerResource:GetPlayer(playerID))
    end)

    -- The construction failed and was never confirmed due to the gridnav being blocked in the attempted area
    event:OnConstructionFailed(function()
        local playerTable = BuildingHelper:GetPlayerTable(playerID)
        local building_name = playerTable.activeBuilding

        BuildingHelper:print("Failed placement of " .. building_name)
    end)

    -- Cancelled due to ClearQueue
    event:OnConstructionCancelled(function(work)
        local building_name = work.name
        BuildingHelper:print("Cancelled construction of " .. building_name)

        -- Refund resources for this cancelled work
        if work.refund then
            hero:ModifyGold(gold_cost, false, 0)
        end
    end)

    -- A building unit was created
    event:OnConstructionStarted(function(unit)
        BuildingHelper:print("Started construction of " .. unit:GetUnitName() .. " " .. unit:GetEntityIndex())
        -- Play construction sound

        -- If it's an item-ability and has charges, remove a charge or remove the item if no charges left
        if ability.GetCurrentCharges and not ability:IsPermanent() then
            local charges = ability:GetCurrentCharges()
            charges = charges-1
            if charges == 0 then
                ability:RemoveSelf()
            else
                ability:SetCurrentCharges(charges)
            end
        end

        -- Units can't attack while building
        unit.original_attack = unit:GetAttackCapability()
        unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)

        -- Give item to cancel
        unit.item_building_cancel = CreateItem("item_building_cancel", hero, hero)
        if unit.item_building_cancel then 
            unit:AddItem(unit.item_building_cancel)
            unit.gold_cost = gold_cost
        end

        -- FindClearSpace for the builder
        FindClearSpaceForUnit(caster, caster:GetAbsOrigin(), true)
        caster:AddNewModifier(caster, nil, "modifier_phased", {duration=0.03})

        -- Remove invulnerability on npc_dota_building baseclass
        unit:RemoveModifierByName("modifier_invulnerable")
    end)

    -- A building finished construction
    event:OnConstructionCompleted(function(unit)
        BuildingHelper:print("Completed construction of " .. unit:GetUnitName() .. " " .. unit:GetEntityIndex())
        
        -- Play construction complete sound
        
        -- Remove the item
        if unit.item_building_cancel then
            UTIL_Remove(unit.item_building_cancel)
        end

        -- Give the unit their original attack capability
        unit:SetAttackCapability(unit.original_attack)

    end)

    -- These callbacks will only fire when the state between below half health/above half health changes.
    -- i.e. it won't fire multiple times unnecessarily.
    event:OnBelowHalfHealth(function(unit)
        BuildingHelper:print(unit:GetUnitName() .. " is below half health.")
    end)

    event:OnAboveHalfHealth(function(unit)
        BuildingHelper:print(unit:GetUnitName().. " is above half health.")        
    end)
end

-- Called when the Cancel ability-item is used
function CancelBuilding( keys )
    local building = keys.unit
    local hero = building:GetOwner()
    local playerID = building:GetPlayerOwnerID()

    BuildingHelper:print("CancelBuilding "..building:GetUnitName().." "..building:GetEntityIndex())

    -- Refund here
    if building.gold_cost then
        hero:ModifyGold(building.gold_cost, false, 0)
    end

    -- Eject builder
    local builder = building.builder_inside
    if builder then
        BuildingHelper:ShowBuilder(builder)
    end

    building:ForceKill(true) --This will call RemoveBuilding
end

-- Requires notifications library from bmddota/barebones
function SendErrorMessage( pID, string )
    Notifications:ClearBottom(pID)
    Notifications:Bottom(pID, {text=string, style={color='#E62020'}, duration=2})
    EmitSoundOnClient("General.Cancel", PlayerResource:GetPlayer(pID))
end
