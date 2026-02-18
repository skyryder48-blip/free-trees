-----------------------------------------------------------
-- SERVER: INVENTORY
-- Server-authoritative inventory operations wrapping
-- ox_inventory exports.
-----------------------------------------------------------

-----------------------------------------------------------
-- FIND CHOPPING TOOL
-- Search player inventory for any valid chopping tool.
-----------------------------------------------------------
---@param source number player server id
---@return table? toolInfo {name, slot, metadata, toolData}
---@return string? errorReason
function FindChoppingTool(source)
    local cache = GetPlayerCacheBySource(source)
    local forestryLevel = cache and cache.forestryLevel or 0

    for toolName in pairs(Config.ChoppingTools) do
        local result = exports.ox_inventory:Search(source, 'slots', toolName)
        if result and #result > 0 then
            local slot = result[1]
            local toolData = Config.Tools[toolName]
            if not toolData then goto continue end

            -- Level check
            if toolData.levelReq and forestryLevel < toolData.levelReq then
                return nil, 'level_too_low'
            end

            -- Certification check
            if toolData.requiresCert then
                local certCount = exports.ox_inventory:Search(source, 'count', toolData.requiresCert)
                if not certCount or certCount < 1 then
                    return nil, 'missing_cert'
                end
            end

            -- Durability check
            local metadata = slot.metadata or {}
            local durability = metadata.durability
            if durability ~= nil and durability <= 0 then
                return nil, 'broken'
            end

            -- Fuel check (chainsaw)
            if toolData.fuelPerUse then
                local fuel = metadata.fuel
                if fuel ~= nil and fuel <= 0 then
                    return nil, 'no_fuel'
                end
            end

            return {
                name = toolName,
                slot = slot.slot,
                metadata = metadata,
                toolData = toolData,
            }, nil
            ::continue::
        end
    end

    return nil, 'no_tool'
end

-----------------------------------------------------------
-- FIND SPECIFIC TOOL
-- Search for a named tool in player inventory.
-----------------------------------------------------------
---@param source number
---@param toolName string
---@return table? toolInfo
---@return string? errorReason
function FindSpecificTool(source, toolName)
    local cache = GetPlayerCacheBySource(source)
    local forestryLevel = cache and cache.forestryLevel or 0

    local toolData = Config.Tools[toolName]
    if not toolData then return nil, 'no_tool' end

    local result = exports.ox_inventory:Search(source, 'slots', toolName)
    if not result or #result == 0 then
        return nil, 'no_tool'
    end

    local slot = result[1]

    -- Level check
    if toolData.levelReq and forestryLevel < toolData.levelReq then
        return nil, 'level_too_low'
    end

    -- Certification check
    if toolData.requiresCert then
        local certCount = exports.ox_inventory:Search(source, 'count', toolData.requiresCert)
        if not certCount or certCount < 1 then
            return nil, 'missing_cert'
        end
    end

    -- Durability check
    local metadata = slot.metadata or {}
    local durability = metadata.durability
    if durability ~= nil and durability <= 0 then
        return nil, 'broken'
    end

    -- Fuel check
    if toolData.fuelPerUse then
        local fuel = metadata.fuel
        if fuel ~= nil and fuel <= 0 then
            return nil, 'no_fuel'
        end
    end

    return {
        name = toolName,
        slot = slot.slot,
        metadata = metadata,
        toolData = toolData,
    }, nil
end

-----------------------------------------------------------
-- DEDUCT TOOL DURABILITY
-- Reduce durability; break tool at 0.
-----------------------------------------------------------
---@param source number
---@param toolInfo table from FindChoppingTool/FindSpecificTool
---@param amount number durability to deduct
---@return boolean success
function DeductToolDurability(source, toolInfo, amount)
    local maxDur = toolInfo.toolData.maxDurability or 100
    local currentDur = toolInfo.metadata.durability or maxDur

    local newDur = currentDur - (amount or 1)

    if newDur <= 0 then
        -- Tool breaks
        exports.ox_inventory:RemoveItem(source, toolInfo.name, 1, nil, toolInfo.slot)
        TriggerClientEvent('ox_lib:notify', source, {
            description = 'Your ' .. toolInfo.name:gsub('_', ' ') .. ' broke!',
            type = 'error',
        })
        return true
    end

    -- Update metadata
    local newMeta = {}
    for k, v in pairs(toolInfo.metadata) do newMeta[k] = v end
    newMeta.durability = newDur

    exports.ox_inventory:SetMetadata(source, toolInfo.slot, newMeta)
    return true
end

-----------------------------------------------------------
-- DEDUCT CHAINSAW FUEL
-----------------------------------------------------------
---@param source number
---@param toolInfo table
---@param amount number fuel to deduct
---@return boolean success
function DeductChainsawFuel(source, toolInfo, amount)
    local maxFuel = Config.Tools.MaxFuel or 25
    local currentFuel = toolInfo.metadata.fuel or maxFuel
    local fuelCost = (toolInfo.toolData.fuelPerUse or 1) * (amount or 1)

    local newFuel = math.max(0, currentFuel - fuelCost)

    local newMeta = {}
    for k, v in pairs(toolInfo.metadata) do newMeta[k] = v end
    newMeta.fuel = newFuel

    exports.ox_inventory:SetMetadata(source, toolInfo.slot, newMeta)

    if newFuel <= 0 then
        TriggerClientEvent('ox_lib:notify', source, {
            description = 'Chainsaw is out of fuel.',
            type = 'warning',
        })
    end

    return true
end

-----------------------------------------------------------
-- HAS VALID PERMIT
-- Check forestry_permits table for non-expired permit.
-----------------------------------------------------------
---@param source number
---@return boolean
function HasValidPermit(source)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false end

    local row = MySQL.single.await(
        'SELECT id FROM forestry_permits WHERE citizenid = ? AND expires_at > NOW()',
        { citizenid }
    )

    return row ~= nil
end

-----------------------------------------------------------
-- GRANT ITEM
-- Wrapper for ox_inventory:AddItem.
-----------------------------------------------------------
---@param source number
---@param itemName string
---@param count number
---@param metadata? table
---@return boolean success
function GrantItem(source, itemName, count, metadata)
    if not exports.ox_inventory:CanCarryItem(source, itemName, count) then
        TriggerClientEvent('ox_lib:notify', source, {
            description = 'Inventory full.',
            type = 'error',
        })
        return false
    end

    local success = exports.ox_inventory:AddItem(source, itemName, count, metadata)
    return success ~= false
end

-----------------------------------------------------------
-- GRANT LOGS
-- Add log items with species/quality metadata.
-----------------------------------------------------------
---@param source number
---@param logType string 'short'|'standard'|'long'
---@param speciesKey string
---@param quality string 'normal'|'damaged'
---@param count number
---@return boolean success
function GrantLogs(source, logType, speciesKey, quality, count)
    local logConfig = Config.LogTypes[logType]
    if not logConfig then return false end

    local itemName = logConfig.item
    local metadata = {
        species = speciesKey,
        quality = quality or LogQuality.NORMAL,
    }

    return GrantItem(source, itemName, count, metadata)
end
