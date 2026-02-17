-----------------------------------------------------------
-- CLIENT: IMMERSION
-- Old Timer NPC (Earl), camp spots, bulletin board,
-- forestry office NPC with shop interaction.
-----------------------------------------------------------

--- Spawned NPC entities for cleanup.
---@type table<number, boolean>
local spawnedNPCs = {}

--- Spawned camp props.
---@type table<number, boolean>
local spawnedCampProps = {}

--- Old Timer story rotation index (no immediate repeats).
local storyIndex = 1

-----------------------------------------------------------
-- FORESTRY OFFICE NPC + SHOP
-----------------------------------------------------------
function SetupForestryOffice()
    for _, office in ipairs(Config.ForestryOffice.Locations) do
        local npcData = office.npc

        -- Spawn NPC
        lib.requestModel(npcData.model)
        local npc = CreatePed(4, npcData.model, npcData.coords.x, npcData.coords.y, npcData.coords.z - 1.0, npcData.coords.w, false, true)
        SetEntityInvincible(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        FreezeEntityPosition(npc, true)
        SetModelAsNoLongerNeeded(npcData.model)
        spawnedNPCs[npc] = true

        -- Target options
        exports.ox_target:addLocalEntity(npc, {
            {
                name = 'forestry_office_shop',
                icon = 'fa-solid fa-store',
                label = 'Forestry Supply Shop',
                distance = 3.0,
                onSelect = function()
                    OpenForestryShop()
                end,
            },
            {
                name = 'forestry_office_permit',
                icon = 'fa-solid fa-id-card',
                label = 'Purchase Timber Permit ($500)',
                distance = 3.0,
                canInteract = function()
                    return PlayerState.loaded
                end,
                onSelect = function()
                    PurchasePermit()
                end,
            },
            {
                name = 'forestry_office_status',
                icon = 'fa-solid fa-chart-line',
                label = 'Check My Progress',
                distance = 3.0,
                canInteract = function()
                    return PlayerState.loaded
                end,
                onSelect = function()
                    ShowProgressStatus()
                end,
            },
        })
    end
end

function OpenForestryShop()
    local options = {}
    for _, shopItem in ipairs(Config.ForestryOffice.Shop) do
        local canBuy = true
        local desc = ('$%d'):format(shopItem.price)

        if shopItem.requiresCert then
            local hasCert = exports.ox_inventory:Search('count', shopItem.requiresCert)
            if not hasCert or hasCert < 1 then
                canBuy = false
                desc = desc .. ' (Requires ' .. shopItem.requiresCert:gsub('_', ' ') .. ')'
            end
        end

        options[#options + 1] = {
            title = shopItem.item:gsub('_', ' '):gsub('^%l', string.upper),
            description = desc,
            icon = 'fa-solid fa-box',
            disabled = not canBuy,
            onSelect = function()
                local input = lib.inputDialog('Purchase', {
                    { type = 'number', label = 'Quantity', min = 1, max = 10, default = 1 },
                })
                if not input then return end

                local success, err = lib.callback.await('forestry:shop:purchase', false, shopItem.item, input[1])
                if success then
                    lib.notify({ description = 'Purchase complete!', type = 'success' })
                else
                    local msgs = {
                        insufficient_funds = 'Not enough cash.',
                        inventory_full = 'Inventory full.',
                        missing_cert = 'Missing certification.',
                    }
                    lib.notify({ description = msgs[err] or 'Purchase failed.', type = 'error' })
                end
            end,
        }
    end

    lib.registerContext({
        id = 'forestry_shop',
        title = 'ðŸª“ Forestry Supply Shop',
        options = options,
    })
    lib.showContext('forestry_shop')
end

function PurchasePermit()
    local success, err = lib.callback.await('forestry:permit:purchase', false)
    if success then
        lib.notify({ description = 'Timber permit purchased! Valid for 7 days.', type = 'success' })
    else
        local msgs = {
            already_has_permit = 'You already have a valid permit.',
            insufficient_funds = 'Not enough cash ($500 required).',
        }
        lib.notify({ description = msgs[err] or 'Failed to purchase permit.', type = 'error' })
    end
end

function ShowProgressStatus()
    local data = lib.callback.await('forestry:player:getData', false)
    if not data then return end

    local fXPNeeded = data.nextForestryXP - data.forestryXP
    local wXPNeeded = data.nextWoodworkingXP - data.woodworkingXP

    lib.registerContext({
        id = 'forestry_progress',
        title = 'ðŸ“Š Forestry Progress',
        options = {
            {
                title = ('Forestry Level %d'):format(data.forestryLevel),
                description = ('XP: %d / %d (need %d more)'):format(
                    data.forestryXP, data.nextForestryXP, math.max(0, fXPNeeded)
                ),
                icon = 'fa-solid fa-tree',
                readOnly = true,
            },
            {
                title = ('Woodworking Level %d'):format(data.woodworkingLevel),
                description = ('XP: %d / %d (need %d more)'):format(
                    data.woodworkingXP, data.nextWoodworkingXP, math.max(0, wXPNeeded)
                ),
                icon = 'fa-solid fa-hammer',
                readOnly = true,
            },
            {
                title = 'Licenses',
                description = FormatLicenses(data.licenses),
                icon = 'fa-solid fa-id-badge',
                readOnly = true,
            },
        },
    })
    lib.showContext('forestry_progress')
end

function FormatLicenses(licenses)
    local parts = {}
    local labels = {
        timber_permit = 'Timber Permit',
        chainsaw_cert = 'Chainsaw Cert',
        crosscut_cert = 'Crosscut Cert',
        heavy_equipment = 'Heavy Equipment',
    }
    for key, label in pairs(labels) do
        local status = licenses[key] and 'âœ…' or 'âŒ'
        parts[#parts + 1] = status .. ' ' .. label
    end
    return table.concat(parts, ' | ')
end

-----------------------------------------------------------
-- BULLETIN BOARD
-----------------------------------------------------------
function SetupBulletinBoard()
    for _, office in ipairs(Config.ForestryOffice.Locations) do
        -- Board is near the office NPC
        local boardCoords = office.coords + vec3(2.0, 0.0, 0.0)

        exports.ox_target:addSphereZone({
            coords = boardCoords,
            radius = 2.0,
            debug = false,
            options = {
                {
                    name = 'forestry_bulletin',
                    icon = 'fa-solid fa-clipboard-list',
                    label = 'Bulletin Board',
                    distance = 2.5,
                    onSelect = function()
                        OpenBulletinBoard()
                    end,
                },
            },
        })
    end
end

function OpenBulletinBoard()
    local data = lib.callback.await('forestry:bulletin:getData', false)
    if not data then
        lib.notify({ description = 'Board is empty.', type = 'inform' })
        return
    end

    local options = {}

    -- Market update
    local marketDesc = ''
    if data.lumberMultipliers then
        for _, row in ipairs(data.lumberMultipliers) do
            local mult = tonumber(row.multiplier) or 1.0
            local icon = mult >= 1.5 and 'ðŸ”¥' or (mult <= 0.8 and 'â„ï¸' or 'â€¢')
            marketDesc = marketDesc .. ('%s %s: %.1fx\n'):format(icon, row.species, mult)
        end
    end

    options[#options + 1] = {
        title = 'ðŸ“ˆ Export Dock - Lumber Multipliers',
        description = marketDesc ~= '' and marketDesc or 'No data available',
        icon = 'fa-solid fa-chart-line',
        readOnly = true,
    }

    -- Furniture multipliers
    local furnitureDesc = ''
    if data.furnitureMultipliers then
        for _, row in ipairs(data.furnitureMultipliers) do
            local mult = tonumber(row.multiplier) or 1.0
            furnitureDesc = furnitureDesc .. ('%s: %.1fx\n'):format(row.category, mult)
        end
    end

    options[#options + 1] = {
        title = 'ðŸª‘ Export Dock - Furniture Multipliers',
        description = furnitureDesc ~= '' and furnitureDesc or 'No data available',
        icon = 'fa-solid fa-couch',
        readOnly = true,
    }

    -- Community stats
    options[#options + 1] = {
        title = 'ðŸŒ² Community Stats (This Week)',
        description = ('Trees Felled: %d\nTotal Earned: $%s'):format(
            data.treesThisWeek or 0,
            FormatNumber(data.earnedThisWeek or 0)
        ),
        icon = 'fa-solid fa-users',
        readOnly = true,
    }

    -- Safety tip
    local tips = {
        'Always clear your fall zone before felling. A falling tree deals 65-90% damage.',
        'Keep a smoke canister handy â€” bee swarms can slow you down for 20 seconds.',
        'Watch for widow makers on medium and large trees. Keep your health topped up.',
        'Sitting at a camp bench recovers stamina 2.5x faster than standing.',
        'Plant saplings at stumps for 15 XP and to help the forest regrow.',
    }
    options[#options + 1] = {
        title = 'âš ï¸ Safety Reminder',
        description = tips[math.random(#tips)],
        icon = 'fa-solid fa-triangle-exclamation',
        readOnly = true,
    }

    lib.registerContext({
        id = 'forestry_bulletin',
        title = 'ðŸ“‹ Forestry Bulletin Board',
        options = options,
    })
    lib.showContext('forestry_bulletin')
end

function FormatNumber(n)
    local str = tostring(math.floor(n))
    local formatted = str:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return formatted
end

-----------------------------------------------------------
-- CAMP SPOTS
-----------------------------------------------------------
function SetupCampSpots()
    for _, camp in ipairs(Config.CampSpots) do
        -- Spawn props within render distance
        local campProps = {}

        CreateThread(function()
            while true do
                local playerCoords = GetEntityCoords(cache.ped)
                local dist = #(playerCoords - camp.coords)

                if dist <= camp.renderDistance then
                    -- Spawn if not already
                    if #campProps == 0 then
                        for _, propDef in ipairs(camp.props) do
                            lib.requestModel(propDef.model)
                            local spawnPos = camp.coords + propDef.offset
                            local prop = CreateObject(propDef.model, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
                            if prop and prop ~= 0 then
                                SetEntityHeading(prop, propDef.heading or 0.0)
                                PlaceObjectOnGroundProperly(prop)
                                FreezeEntityPosition(prop, true)
                                campProps[#campProps + 1] = prop
                                spawnedCampProps[prop] = true
                            end
                            SetModelAsNoLongerNeeded(propDef.model)
                        end
                    end
                else
                    -- Despawn if too far
                    if #campProps > 0 then
                        for _, prop in ipairs(campProps) do
                            if DoesEntityExist(prop) then
                                DeleteEntity(prop)
                                spawnedCampProps[prop] = nil
                            end
                        end
                        campProps = {}
                    end
                end

                Wait(dist > camp.renderDistance * 2 and 10000 or 3000)
            end
        end)

        -- Sit target at camp bench location
        exports.ox_target:addSphereZone({
            coords = camp.coords,
            radius = 3.0,
            debug = false,
            options = {
                {
                    name = 'camp_sit_' .. camp.label,
                    icon = 'fa-solid fa-chair',
                    label = 'Sit Down',
                    distance = 2.0,
                    onSelect = function()
                        SitAtCamp(camp)
                    end,
                },
            },
        })
    end
end

function SitAtCamp(camp)
    local ped = cache.ped

    -- Face the camp fire
    TaskTurnPedToFaceCoord(ped, camp.coords.x, camp.coords.y, camp.coords.z, 1000)
    Wait(1000)

    -- Sit animation
    lib.requestAnimDict('anim@heists@heist_corona@single_team')
    TaskPlayAnim(ped, 'anim@heists@heist_corona@single_team', 'single_team_loop_boss', 8.0, -8.0, -1, 1, 0, false, false, false)

    lib.notify({
        description = 'Resting at camp. Stamina recovers faster while seated.',
        type = 'inform',
    })

    -- Wait until player moves
    CreateThread(function()
        while true do
            Wait(1000)
            if IsControlPressed(0, 32) or IsControlPressed(0, 33) or
               IsControlPressed(0, 34) or IsControlPressed(0, 35) then
                ClearPedTasks(ped)
                break
            end
        end
    end)
end

-----------------------------------------------------------
-- OLD TIMER NPC (EARL)
-----------------------------------------------------------
function SetupOldTimer()
    if not Config.OldTimer.Enabled then return end

    for _, location in ipairs(Config.OldTimer.Locations) do
        lib.requestModel(location.model)
        local npc = CreatePed(4, location.model, location.coords.x, location.coords.y, location.coords.z - 1.0, location.coords.w, false, true)
        SetEntityInvincible(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        FreezeEntityPosition(npc, true)
        TaskStartScenarioInPlace(npc, location.scenario, 0, true)
        SetModelAsNoLongerNeeded(location.model)
        spawnedNPCs[npc] = true

        exports.ox_target:addLocalEntity(npc, {
            {
                name = 'old_timer_talk',
                icon = 'fa-solid fa-comments',
                label = 'Talk to Earl',
                distance = 3.0,
                onSelect = function()
                    OpenOldTimerMenu()
                end,
            },
        })
    end
end

function OpenOldTimerMenu()
    lib.registerContext({
        id = 'old_timer_menu',
        title = 'ðŸª“ Earl - Old Timer',
        options = {
            {
                title = 'Got any advice for me?',
                icon = 'fa-solid fa-lightbulb',
                onSelect = function() OldTimerAdvice() end,
            },
            {
                title = 'What\'s selling right now?',
                icon = 'fa-solid fa-dollar-sign',
                onSelect = function() OldTimerMarket() end,
            },
            {
                title = 'How do I get better at this?',
                icon = 'fa-solid fa-arrow-up',
                onSelect = function() OldTimerProgression() end,
            },
            {
                title = 'Tell me about the trees around here.',
                icon = 'fa-solid fa-tree',
                onSelect = function() OldTimerSpecies() end,
            },
            {
                title = 'Any stories?',
                icon = 'fa-solid fa-book-open',
                onSelect = function() OldTimerStory() end,
            },
        },
    })
    lib.showContext('old_timer_menu')
end

-----------------------------------------------------------
-- EARL: ADVICE (Level-Aware)
-----------------------------------------------------------
function OldTimerAdvice()
    local level = PlayerState.forestryLevel
    local advice

    if level <= 6 then
        local tips = {
            'First thing, kid â€” always look up before you swing. Dead branches fall during felling. They call \'em widow makers for a reason. Keep your health full.',
            'Get yourself a timber permit from the office there. Rangers might not check, but it keeps things square. And start with the hatchet on small trees â€” learn the rhythm.',
            'Watch your stamina. Twelve swings don\'t last long when you\'re green. Sit on a bench at camp when you need to catch your breath â€” recovers much faster.',
            'That falling tree doesn\'t care if you\'re in the way. The skill check determines your yield, sure, but the fall zone? That\'ll put you on the ground. Stand behind, chop toward.',
        }
        advice = tips[math.random(#tips)]
    elseif level <= 17 then
        local tips = {
            'Now that you\'ve got the chainsaw, remember â€” one fuel can gives you about five trees. Budget it. And keep a sharpening kit around; dull tools mean bad cuts.',
            'Short logs are carryable but low value. Standard logs need a truck but pay better. Think about your transport before you start cutting everything short.',
            'Find yourself a partner with a crosscut saw. Two players working together can down a tree faster than a chainsaw, and you both get bonus yield.',
            'Bee swarms hit about one in fifteen trees. Keep a smoke canister in your pocket â€” it clears the bees and sometimes you get honeycomb out of it.',
            'Crews aren\'t just for company. Each active member adds ten percent XP. Four friends working together? That\'s forty percent on every action.',
        }
        advice = tips[math.random(#tips)]
    elseif level <= 30 then
        local tips = {
            'The real money starts at the sawmill. A raw log is worth maybe fifty bucks. Run it through debarker, head saw, edger, planer â€” that finished lumber sells for eighty at the buyer.',
            'Veneer is where the margins live. Oak, cedar, redwood, maple â€” slice them into veneer at level twenty, press three sheets into plywood at twenty-five. Math speaks for itself.',
            'Plant saplings at stumps. Fifteen XP, the tree comes back right away, and the next logger appreciates it. Good karma in the woods.',
            'When you\'ve got multiple people at the sawmill, each active station speeds everyone up by fifteen percent. Four stations running and everything moves at sixty percent faster.',
        }
        advice = tips[math.random(#tips)]
    else
        local tips = {
            'At your level, you should be watching the export dock. Those weekly multipliers swing from zero-seven to two-five. When redwood\'s hot, that\'s the day to deliver.',
            'The grandfather clock recipe â€” six finished oak lumber, two specialty cuts, one clock mechanism. Sells for thirty-five hundred at base. When specialty furniture multiplier hits three-x? Over ten grand.',
            'You know the market better than most. At level thirty-two, all your station times drop another fifteen percent. Stack that with throughput bonus and you\'re printing lumber.',
            'Crew leadership at your level is about efficiency. You set the pace, everyone benefits from the XP bonus. Best crew I ever ran had a dedicated feller, bucker, driver, and two millers.',
        }
        advice = tips[math.random(#tips)]
    end

    ShowEarlDialogue('ðŸ’¡ Earl\'s Advice', advice)
end

-----------------------------------------------------------
-- EARL: MARKET DATA (Dynamic)
-----------------------------------------------------------
function OldTimerMarket()
    local market = lib.callback.await('forestry:oldtimer:getMarket', false)
    if not market then
        ShowEarlDialogue('ðŸ“Š Market Talk', 'Eh, the radio\'s out. Can\'t tell you what\'s moving today.')
        return
    end

    local text = ''

    if market.hotSpecies then
        local speciesLabel = Config.TreeSpecies[market.hotSpecies] and Config.TreeSpecies[market.hotSpecies].label or market.hotSpecies
        text = text .. ('ðŸ”¥ **%s** is hot right now â€” %.1fx multiplier at the dock. Get it while it lasts.\n\n'):format(
            speciesLabel, market.hotMult
        )
    end

    if market.coldSpecies and market.coldSpecies ~= market.hotSpecies then
        local coldLabel = Config.TreeSpecies[market.coldSpecies] and Config.TreeSpecies[market.coldSpecies].label or market.coldSpecies
        text = text .. ('â„ï¸ I\'d steer clear of **%s** this week â€” only %.1fx. Barely worth the gas.\n\n'):format(
            coldLabel, market.coldMult
        )
    end

    if market.hotCategory then
        text = text .. ('ðŸª‘ Furniture-wise, **%s** pieces are in demand â€” %.1fx multiplier at the furniture dock.'):format(
            market.hotCategory, market.hotCatMult
        )
    end

    if text == '' then
        text = 'Market\'s pretty flat this week. No strong plays I can see.'
    end

    ShowEarlDialogue('ðŸ“Š What\'s Selling', text)
end

-----------------------------------------------------------
-- EARL: PROGRESSION NUDGE
-----------------------------------------------------------
function OldTimerProgression()
    local level = PlayerState.forestryLevel

    -- Find next meaningful unlock
    local milestones = {
        { level = 3,  desc = 'Level 3 unlocks the felling axe â€” handles medium trees.' },
        { level = 5,  desc = 'Level 5 opens the head saw and edger at the sawmill. You\'ll start seeing species names on trees too.' },
        { level = 7,  desc = 'Level 7 lets you take the chainsaw certification. Game changer â€” fastest tool for any tree size.' },
        { level = 10, desc = 'Level 10 opens the planer. Full processing chain to finished lumber. You\'ll also see tree sizes on inspection.' },
        { level = 14, desc = 'Level 14 gets you crosscut certification. Find a partner and you\'ll outpace a chainsaw on medium trees.' },
        { level = 18, desc = 'Level 18 qualifies you for the heavy equipment license. Skidders and logging trucks â€” no more carrying.' },
        { level = 20, desc = 'Level 20 unlocks the veneer slicer. Premium sheets from hardwood species â€” serious money.' },
        { level = 25, desc = 'Level 25 opens the plywood press. Three veneer sheets become one plywood panel â€” high-value product.' },
        { level = 30, desc = 'Level 30 â€” the specialty saw. Precision cuts from premium species for high-end furniture.' },
        { level = 50, desc = 'Level 50 â€” Forestry Legend. You\'ve done it all. Enjoy the title, you\'ve earned it.' },
    }

    local nextMilestone = nil
    for _, m in ipairs(milestones) do
        if level < m.level then
            nextMilestone = m
            break
        end
    end

    local text = ('You\'re at Forestry Level %d. '):format(level)
    if nextMilestone then
        text = text .. nextMilestone.desc
    else
        text = text .. 'You\'ve hit the top. Nothing left but perfecting the craft.'
    end

    ShowEarlDialogue('ðŸ“ˆ Getting Better', text)
end

-----------------------------------------------------------
-- EARL: SPECIES KNOWLEDGE
-----------------------------------------------------------
function OldTimerSpecies()
    local speciesInfo = {
        pine = 'Pine is your bread and butter. Large trees, decent yield, everywhere you look. The resin drips are good for turpentine if you\'re patient.',
        oak = 'Oak is the hardwood king. Medium trees, but that wood is dense â€” wears your tools faster. Furniture makers pay a premium for it.',
        birch = 'Birch is small and light â€” quick work for a hatchet. Low value per log, but you can process a dozen before lunch.',
        redwood = 'Redwood is the big prize. Massive trees, six logs per fell, two hundred a piece. But you need heavy gear to move them.',
        cedar = 'Cedar\'s got that smell. Aromatic wood, medium difficulty. Cedar chests and benches move fast at the furniture dock.',
        maple = 'Maple is the hardest wood in these parts. Beautiful grain, beautiful finish. The desk and nightstand recipes love it.',
    }

    local keys = {}
    for k in pairs(speciesInfo) do keys[#keys + 1] = k end
    local randomSpecies = keys[math.random(#keys)]

    ShowEarlDialogue('ðŸŒ² ' .. (Config.TreeSpecies[randomSpecies] and Config.TreeSpecies[randomSpecies].label or randomSpecies), speciesInfo[randomSpecies])
end

-----------------------------------------------------------
-- EARL: STORIES (Lore/Flavor)
-----------------------------------------------------------
local stories = {
    'Back in \'92, we had a redwood up at Chiliad that took three days to fell. The Old Growth boys â€” all eight of us â€” rotating shifts with crosscut saws. Chainsaws kept overheating. When it finally went down, the ground shook for a quarter mile. Biggest tree anyone ever saw in this state.',
    'I knew a fella named Dutch who could identify any tree by the sound of the axe. He\'d close his eyes, take one swing, and tell you the species, the age, even if it had termites. Never wrong. Not once.',
    'Worst day on the job was when my partner Jimmy didn\'t hear the timber call. Widow maker caught him on the shoulder. He was alright â€” broken collarbone, three months off. But I never forgot to yell twice after that.',
    'The old mill up at Sandy Shores used to process two hundred logs a day. Eight men, three shifts. Now it\'s just the community mill, but on a good day with a full crew? You can match those numbers.',
    'There\'s a saying among old loggers: "The forest takes back what it\'s owed." You fell a tree, plant a sapling. Simple as that. We\'ve been doing it since before the suits called it sustainability.',
    'My grandfather shipped cedar to Japan in the fifties. They\'d pay three times what the local mills offered. Some things never change â€” the export dock still has those weekly multipliers.',
    'I tried retirement twice. First time lasted six weeks. Second time, three days. Something about the sound of a chainsaw starting up in the morning... it\'s better than any alarm clock.',
}

function OldTimerStory()
    local story = stories[storyIndex]
    storyIndex = storyIndex + 1
    if storyIndex > #stories then storyIndex = 1 end

    ShowEarlDialogue('ðŸ“– Earl\'s Stories', story)
end

-----------------------------------------------------------
-- EARL: DIALOGUE DISPLAY
-----------------------------------------------------------
function ShowEarlDialogue(title, text)
    lib.registerContext({
        id = 'old_timer_dialogue',
        title = 'ðŸª“ Earl - ' .. title,
        menu = 'old_timer_menu',
        options = {
            {
                title = title,
                description = text,
                icon = 'fa-solid fa-quote-left',
                readOnly = true,
            },
        },
    })
    lib.showContext('old_timer_dialogue')
end

-----------------------------------------------------------
-- SELL NPCS
-----------------------------------------------------------
function SetupSellNPCs()
    -- Lumber Buyer
    for _, buyer in ipairs(Config.LumberBuyer.Locations) do
        lib.requestModel(buyer.npc.model)
        local npc = CreatePed(4, buyer.npc.model, buyer.npc.coords.x, buyer.npc.coords.y, buyer.npc.coords.z - 1.0, buyer.npc.coords.w, false, true)
        SetEntityInvincible(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        FreezeEntityPosition(npc, true)
        SetModelAsNoLongerNeeded(buyer.npc.model)
        spawnedNPCs[npc] = true

        exports.ox_target:addLocalEntity(npc, {
            {
                name = 'lumber_buyer_sell',
                icon = 'fa-solid fa-sack-dollar',
                label = 'Sell Lumber',
                distance = 3.0,
                canInteract = function() return PlayerState.onDuty end,
                onSelect = function()
                    OpenSellMenu('lumber_buyer')
                end,
            },
        })
    end

    -- Furniture Buyer
    for _, buyer in ipairs(Config.FurnitureBuyer.Locations) do
        lib.requestModel(buyer.npc.model)
        local npc = CreatePed(4, buyer.npc.model, buyer.npc.coords.x, buyer.npc.coords.y, buyer.npc.coords.z - 1.0, buyer.npc.coords.w, false, true)
        SetEntityInvincible(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        FreezeEntityPosition(npc, true)
        SetModelAsNoLongerNeeded(buyer.npc.model)
        spawnedNPCs[npc] = true

        exports.ox_target:addLocalEntity(npc, {
            {
                name = 'furniture_buyer_sell',
                icon = 'fa-solid fa-sack-dollar',
                label = 'Sell Furniture',
                distance = 3.0,
                canInteract = function() return PlayerState.onDuty end,
                onSelect = function()
                    OpenSellMenu('furniture_buyer')
                end,
            },
        })
    end
end

function OpenSellMenu(channel)
    local prices = lib.callback.await('forestry:economy:getSellOptions', false, channel)
    if not prices then
        lib.notify({ description = 'No items to sell here.', type = 'inform' })
        return
    end

    local options = {}

    for itemName, price in pairs(prices) do
        local count = exports.ox_inventory:Search('count', itemName)
        if count and count > 0 then
            options[#options + 1] = {
                title = ('%s (x%d)'):format(itemName:gsub('_', ' '):gsub('^%l', string.upper), count),
                description = ('$%d each â€” Sell All: $%d'):format(price, price * count),
                icon = 'fa-solid fa-box',
                onSelect = function()
                    local sellItems = { { item = itemName, quantity = count } }
                    local success, total = lib.callback.await('forestry:economy:sell', false, channel, sellItems)
                    if success then
                        lib.notify({ description = ('Sold for $%s!'):format(FormatNumber(total)), type = 'success' })
                    else
                        lib.notify({ description = 'Sale failed.', type = 'error' })
                    end
                end,
            }
        end
    end

    if #options == 0 then
        options[#options + 1] = {
            title = 'No items to sell',
            description = 'You don\'t have anything this buyer wants.',
            icon = 'fa-solid fa-box-open',
            readOnly = true,
        }
    end

    lib.registerContext({
        id = 'forestry_sell_' .. channel,
        title = channel == 'lumber_buyer' and 'ðŸªµ Sell Lumber' or 'ðŸª‘ Sell Furniture',
        options = options,
    })
    lib.showContext('forestry_sell_' .. channel)
end

-----------------------------------------------------------
-- CONTRACT BOARD
-----------------------------------------------------------
function SetupContractBoard()
    for _, office in ipairs(Config.ForestryOffice.Locations) do
        local boardCoords = office.coords + vec3(-2.0, 0.0, 0.0)

        exports.ox_target:addSphereZone({
            coords = boardCoords,
            radius = 2.0,
            debug = false,
            options = {
                {
                    name = 'forestry_contracts',
                    icon = 'fa-solid fa-file-contract',
                    label = 'Contract Board',
                    distance = 2.5,
                    canInteract = function() return PlayerState.onDuty end,
                    onSelect = function()
                        OpenContractBoard()
                    end,
                },
            },
        })
    end
end

function OpenContractBoard()
    local contracts = lib.callback.await('forestry:economy:getContracts', false)
    if not contracts or #contracts == 0 then
        lib.notify({ description = 'No active contracts available.', type = 'inform' })
        return
    end

    local options = {}

    for _, contract in ipairs(contracts) do
        local remaining = contract.quantity - contract.quantity_filled
        local speciesLabel = contract.species and (Config.TreeSpecies[contract.species] and Config.TreeSpecies[contract.species].label or contract.species) or 'Any Species'
        local itemLabel = contract.item_name:gsub('_', ' '):gsub('^%l', string.upper)

        options[#options + 1] = {
            title = ('%s â€” %d/%d needed'):format(itemLabel, remaining, contract.quantity),
            description = ('$%d/unit | Species: %s | Deadline: %s'):format(
                contract.price_per_unit, speciesLabel,
                contract.deadline or 'Unknown'
            ),
            icon = 'fa-solid fa-file-contract',
            onSelect = function()
                -- Check if player has items to deliver
                local count = exports.ox_inventory:Search('count', contract.item_name)
                if not count or count < 1 then
                    lib.notify({ description = 'You don\'t have any ' .. itemLabel .. ' to deliver.', type = 'error' })
                    return
                end

                local deliverQty = math.min(remaining, count)
                local success, result = lib.callback.await('forestry:economy:sell', false, 'contract', {
                    contractId = contract.id,
                    quantity = deliverQty,
                })

                if success then
                    lib.notify({
                        description = ('Delivered %d %s â€” earned $%s!'):format(deliverQty, itemLabel, FormatNumber(result)),
                        type = 'success',
                    })
                else
                    lib.notify({ description = result or 'Delivery failed.', type = 'error' })
                end
            end,
        }
    end

    lib.registerContext({
        id = 'forestry_contracts',
        title = 'ðŸ“‹ Lumber Contracts',
        options = options,
    })
    lib.showContext('forestry_contracts')
end

-----------------------------------------------------------
-- EXPORT DOCK TARGETS
-----------------------------------------------------------
function SetupExportDocks()
    -- Lumber export
    exports.ox_target:addSphereZone({
        coords = Config.LumberExport.Location,
        radius = 5.0,
        debug = false,
        options = {
            {
                name = 'lumber_export',
                icon = 'fa-solid fa-ship',
                label = 'Lumber Export Dock',
                distance = 4.0,
                canInteract = function() return PlayerState.onDuty end,
                onSelect = function()
                    OpenSellMenu('lumber_export')
                end,
            },
        },
    })

    -- Furniture export
    exports.ox_target:addSphereZone({
        coords = Config.FurnitureExport.Location,
        radius = 5.0,
        debug = false,
        options = {
            {
                name = 'furniture_export',
                icon = 'fa-solid fa-ship',
                label = 'Furniture Export Dock',
                distance = 4.0,
                canInteract = function() return PlayerState.onDuty end,
                onSelect = function()
                    OpenSellMenu('furniture_export')
                end,
            },
        },
    })
end

-----------------------------------------------------------
-- INIT ALL IMMERSION FEATURES
-----------------------------------------------------------
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(2000)

    SetupForestryOffice()
    SetupBulletinBoard()
    SetupCampSpots()
    SetupOldTimer()
    SetupSellNPCs()
    SetupContractBoard()
    SetupExportDocks()
end)

-----------------------------------------------------------
-- CLEANUP ON RESOURCE STOP
-----------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for npc in pairs(spawnedNPCs) do
        if DoesEntityExist(npc) then
            DeleteEntity(npc)
        end
    end
    spawnedNPCs = {}

    for prop in pairs(spawnedCampProps) do
        if DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end
    spawnedCampProps = {}
end)
