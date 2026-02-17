-----------------------------------------------------------
-- CLIENT: CRAFTING
-- Furniture workshop and secondary product crafting.
-- All recipes from Config.FurnitureRecipes + SecondaryRecipes.
-----------------------------------------------------------

local isCrafting = false

-----------------------------------------------------------
-- SECONDARY RECIPES (non-furniture crafting)
-----------------------------------------------------------
local SecondaryRecipes = {
    {
        item = 'firewood_bundle', label = 'Firewood Bundle',
        level = 0, track = 'forestry',
        ingredients = { branch_bundle = 2 },
        duration = 4000,
        xp = 5, xpTrack = 'forestry',
    },
    {
        item = 'wood_pellets', label = 'Wood Pellets',
        level = 0, track = 'forestry',
        ingredients = { sawdust = 5 },
        duration = 5000,
        xp = 5, xpTrack = 'forestry',
    },
    {
        item = 'bark_mulch', label = 'Bark Mulch',
        level = 0, track = 'forestry',
        ingredients = { bark_raw = 3 },
        duration = 4000,
        xp = 5, xpTrack = 'forestry',
    },
    {
        item = 'turpentine', label = 'Turpentine',
        level = 0, track = 'forestry',
        ingredients = { resin_raw = 3 },
        duration = 8000,
        xp = 10, xpTrack = 'forestry',
    },
    {
        item = 'wood_finish', label = 'Wood Finish',
        level = 0, track = 'forestry',
        ingredients = { turpentine = 1 },
        duration = 3000,
        xp = 5, xpTrack = 'forestry',
    },
}

-----------------------------------------------------------
-- OPEN CRAFTING MENU
-- Shows available recipes based on WW level.
-----------------------------------------------------------
function OpenCraftingMenu()
    if isCrafting then return end

    local options = {}

    -- Furniture recipes
    for _, recipe in ipairs(Config.FurnitureRecipes) do
        local canCraft = PlayerState.woodworkingLevel >= recipe.level
        local ingredientText = BuildIngredientText(recipe.ingredients)
        local speciesText = recipe.species and (' [%s only]'):format(recipe.species) or ''

        options[#options + 1] = {
            title = recipe.label or recipe.item:gsub('furniture_', ''):gsub('_', ' '),
            description = ('%s%s | WW Lv%d | $%d NPC'):format(ingredientText, speciesText, recipe.level, recipe.price),
            icon = canCraft and 'fa-solid fa-hammer' or 'fa-solid fa-lock',
            disabled = not canCraft,
            onSelect = function()
                CraftFurniture(recipe)
            end,
            metadata = {
                { label = 'Level Required', value = recipe.level },
                { label = 'NPC Sell Price', value = '$' .. recipe.price },
            },
        }
    end

    -- Divider
    options[#options + 1] = {
        title = 'â”€â”€ Secondary Products â”€â”€',
        disabled = true,
    }

    -- Secondary recipes
    for _, recipe in ipairs(SecondaryRecipes) do
        local ingredientText = BuildIngredientText(recipe.ingredients)

        options[#options + 1] = {
            title = recipe.label,
            description = ingredientText,
            icon = 'fa-solid fa-mortar-pestle',
            onSelect = function()
                CraftSecondary(recipe)
            end,
        }
    end

    lib.registerContext({
        id = 'forestry_crafting_menu',
        title = 'ðŸªµ Crafting Workshop',
        options = options,
    })
    lib.showContext('forestry_crafting_menu')
end

-----------------------------------------------------------
-- BUILD INGREDIENT TEXT
-----------------------------------------------------------
---@param ingredients table
---@return string
function BuildIngredientText(ingredients)
    local parts = {}
    for item, count in pairs(ingredients) do
        parts[#parts + 1] = ('%dx %s'):format(count, item:gsub('_', ' '))
    end
    return table.concat(parts, ', ')
end

-----------------------------------------------------------
-- CRAFT FURNITURE
-----------------------------------------------------------
---@param recipe table
function CraftFurniture(recipe)
    if isCrafting then return end

    -- Check WW level
    if PlayerState.woodworkingLevel < recipe.level then
        lib.notify({ description = ('Requires Woodworking Level %d.'):format(recipe.level), type = 'error' })
        return
    end

    -- Check ingredients client-side (server re-validates)
    for item, count in pairs(recipe.ingredients) do
        local have = exports.ox_inventory:Search('count', item)
        if not have or have < count then
            lib.notify({
                description = ('Missing: %dx %s (have %d)'):format(count, item:gsub('_', ' '), have or 0),
                type = 'error',
            })
            return
        end
    end

    -- Check species-specific lumber if required
    if recipe.species then
        for item, count in pairs(recipe.ingredients) do
            if item == 'lumber_finished' or item == 'lumber_rough' then
                local slots = exports.ox_inventory:Search('slots', item)
                local speciesCount = 0
                if slots then
                    for _, slot in ipairs(slots) do
                        if slot.metadata and slot.metadata.species == recipe.species then
                            speciesCount = speciesCount + slot.count
                        end
                    end
                end
                if speciesCount < count then
                    lib.notify({
                        description = ('Need %dx %s lumber (have %d)'):format(count, recipe.species, speciesCount),
                        type = 'error',
                    })
                    return
                end
            end
        end
    end

    isCrafting = true

    -- Calculate craft time with bonuses
    local baseDuration = 15000 -- Default craft time
    local duration = baseDuration

    -- WW level bonuses
    for level, bonus in pairs(Config.WoodworkingBonuses) do
        if PlayerState.woodworkingLevel >= level and bonus.craftTimeReduction then
            duration = duration * (1.0 - bonus.craftTimeReduction)
        end
    end

    -- Crafting animation
    lib.requestAnimDict('mini@repair')
    TaskPlayAnim(cache.ped, 'mini@repair', 'fixing_a_ped', 8.0, -8.0, -1, 1, 0, false, false, false)

    local completed = lib.progressCircle({
        duration = math.floor(duration),
        label = ('Crafting %s...'):format(recipe.label or recipe.item),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(cache.ped)

    if not completed then
        isCrafting = false
        return
    end

    -- Server processes craft
    local success, result = lib.callback.await('forestry:crafting:complete', false,
        recipe.item, recipe.species
    )

    if success then
        lib.notify({
            title = 'Crafted!',
            description = result and result.label or recipe.item:gsub('_', ' '),
            type = 'success',
            duration = 4000,
        })
    else
        lib.notify({ description = result or 'Crafting failed.', type = 'error' })
    end

    isCrafting = false
end

-----------------------------------------------------------
-- CRAFT SECONDARY PRODUCT
-----------------------------------------------------------
---@param recipe table
function CraftSecondary(recipe)
    if isCrafting then return end

    -- Check ingredients
    for item, count in pairs(recipe.ingredients) do
        local have = exports.ox_inventory:Search('count', item)
        if not have or have < count then
            lib.notify({
                description = ('Missing: %dx %s'):format(count, item:gsub('_', ' ')),
                type = 'error',
            })
            return
        end
    end

    isCrafting = true

    lib.requestAnimDict('mini@repair')
    TaskPlayAnim(cache.ped, 'mini@repair', 'fixing_a_ped', 8.0, -8.0, -1, 1, 0, false, false, false)

    local completed = lib.progressCircle({
        duration = recipe.duration,
        label = ('Crafting %s...'):format(recipe.label),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(cache.ped)

    if not completed then
        isCrafting = false
        return
    end

    -- Server processes
    local success = lib.callback.await('forestry:crafting:completeSecondary', false,
        recipe.item, recipe.ingredients
    )

    if success then
        lib.notify({
            description = ('Crafted %s!'):format(recipe.label),
            type = 'success',
        })
    else
        lib.notify({ description = 'Crafting failed.', type = 'error' })
    end

    isCrafting = false
end
