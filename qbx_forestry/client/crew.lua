-----------------------------------------------------------
-- CLIENT: CREW SYSTEM
-- Crew formation UI, invite handling, roster display,
-- role selection, shared stash access, radio integration.
-----------------------------------------------------------

--- Current crew data synced from server.
---@class ClientCrewData
---@field crewId string
---@field leader number
---@field roster table[]
---@field stashId string

---@type ClientCrewData?
local CrewData = nil

-----------------------------------------------------------
-- CREW UPDATE (from server broadcast)
-----------------------------------------------------------
RegisterNetEvent('forestry:client:crew:update', function(data)
    CrewData = data

    if data then
        -- Auto-join radio if configured
        if Config.Crew.AutoRadio and GetResourceState(Config.Crew.RadioResource) == 'started' then
            JoinCrewRadio(data.crewId)
        end
    else
        LeaveCrewRadio()
    end
end)

-----------------------------------------------------------
-- CREW INVITE RECEIVED
-----------------------------------------------------------
RegisterNetEvent('forestry:client:crew:invite', function(fromSource, crewId)
    local fromPlayer = GetPlayerServerId(fromSource) and fromSource or fromSource

    local alert = lib.alertDialog({
        header = 'ðŸª“ Crew Invite',
        content = 'You\'ve been invited to join a logging crew.\n\nJoin up for XP bonuses and access to a shared stash.',
        centered = true,
        cancel = true,
    })

    if alert == 'confirm' then
        TriggerServerEvent('forestry:server:crew:acceptInvite', crewId)
    end
end)

-----------------------------------------------------------
-- CREW MENU (main context menu)
-----------------------------------------------------------
function OpenCrewMenu()
    if not PlayerState.onDuty then
        lib.notify({ description = 'You must be on duty.', type = 'error' })
        return
    end

    if not CrewData then
        -- Not in a crew: show create/join options
        lib.registerContext({
            id = 'forestry_crew_no_crew',
            title = 'ðŸª“ Logging Crew',
            options = {
                {
                    title = 'Create a Crew',
                    description = 'Start your own logging crew',
                    icon = 'fa-solid fa-plus',
                    onSelect = function()
                        local success, err = lib.callback.await('forestry:crew:create', false)
                        if not success then
                            lib.notify({ description = err or 'Failed to create crew.', type = 'error' })
                        end
                    end,
                },
                {
                    title = 'Check Stamina',
                    description = 'How many swings do you have left?',
                    icon = 'fa-solid fa-heart-pulse',
                    onSelect = function()
                        if CheckStamina then CheckStamina() end
                    end,
                },
            },
        })
        lib.showContext('forestry_crew_no_crew')
        return
    end

    -- In a crew: show roster and management
    local options = {}

    -- Roster display
    for _, member in ipairs(CrewData.roster) do
        local roleIcons = {
            leader  = 'ðŸ‘‘',
            feller  = 'ðŸª“',
            bucker  = 'ðŸªš',
            driver  = 'ðŸš›',
            miller  = 'âš™ï¸',
            general = 'ðŸŒ²',
        }
        local icon = roleIcons[member.role] or 'ðŸŒ²'
        local suffix = member.isLeader and ' (Leader)' or ''

        options[#options + 1] = {
            title = icon .. ' ' .. member.name .. suffix,
            description = 'Role: ' .. (member.role:gsub('^%l', string.upper)),
            icon = member.isLeader and 'fa-solid fa-crown' or 'fa-solid fa-user',
            readOnly = true,
        }
    end

    -- Separator
    options[#options + 1] = {
        title = 'â”€â”€â”€â”€â”€ Actions â”€â”€â”€â”€â”€',
        readOnly = true,
    }

    -- Shared stash
    options[#options + 1] = {
        title = 'Open Crew Stash',
        description = 'Shared inventory accessible by all members',
        icon = 'fa-solid fa-box-open',
        onSelect = function()
            if CrewData and CrewData.stashId then
                exports.ox_inventory:openInventory('stash', CrewData.stashId)
            end
        end,
    }

    -- Set own role
    options[#options + 1] = {
        title = 'Set My Role',
        description = 'Choose a cosmetic role label',
        icon = 'fa-solid fa-tag',
        onSelect = function()
            OpenRoleSelection()
        end,
    }

    -- Invite (leader only)
    local isLeader = CrewData.leader == cache.serverId
    if isLeader then
        options[#options + 1] = {
            title = 'Invite Nearby Player',
            description = 'Invite a lumberjack within 10m',
            icon = 'fa-solid fa-user-plus',
            onSelect = function()
                InviteNearbyPlayer()
            end,
        }

        options[#options + 1] = {
            title = 'Kick Member',
            description = 'Remove a crew member',
            icon = 'fa-solid fa-user-minus',
            onSelect = function()
                KickMember()
            end,
        }
    end

    -- Leave crew
    options[#options + 1] = {
        title = 'Leave Crew',
        description = isLeader and 'Leadership will transfer' or 'Leave your current crew',
        icon = 'fa-solid fa-right-from-bracket',
        onSelect = function()
            local confirm = lib.alertDialog({
                header = 'Leave Crew?',
                content = isLeader and 'You are the leader. Leadership will transfer to the next member.' or 'Are you sure you want to leave?',
                centered = true,
                cancel = true,
            })
            if confirm == 'confirm' then
                TriggerServerEvent('forestry:server:crew:leave')
            end
        end,
    }

    -- Stamina check
    options[#options + 1] = {
        title = 'Check Stamina',
        icon = 'fa-solid fa-heart-pulse',
        onSelect = function()
            if CheckStamina then CheckStamina() end
        end,
    }

    lib.registerContext({
        id = 'forestry_crew_menu',
        title = 'ðŸª“ Logging Crew',
        options = options,
    })
    lib.showContext('forestry_crew_menu')
end

-----------------------------------------------------------
-- ROLE SELECTION
-----------------------------------------------------------
function OpenRoleSelection()
    local roleOptions = {
        { value = CrewRole.FELLER,  label = 'ðŸª“ Feller - Tree felling' },
        { value = CrewRole.BUCKER,  label = 'ðŸªš Bucker - Field processing' },
        { value = CrewRole.DRIVER,  label = 'ðŸš› Driver - Vehicle transport' },
        { value = CrewRole.MILLER,  label = 'âš™ï¸ Miller - Sawmill stations' },
        { value = CrewRole.GENERAL, label = 'ðŸŒ² General - All-rounder' },
    }

    local input = lib.inputDialog('Set Your Role', {
        {
            type = 'select',
            label = 'Role',
            options = roleOptions,
            required = true,
        },
    })

    if not input then return end

    local role = input[1]
    lib.callback.await('forestry:crew:setRole', false, cache.serverId, role)
end

-----------------------------------------------------------
-- INVITE NEARBY PLAYER
-----------------------------------------------------------
function InviteNearbyPlayer()
    local playerPed = cache.ped
    local playerCoords = GetEntityCoords(playerPed)

    -- Find nearby players
    local nearbyPlayers = {}
    local players = GetActivePlayers()

    for _, playerId in ipairs(players) do
        if playerId ~= PlayerId() then
            local targetPed = GetPlayerPed(playerId)
            if targetPed and targetPed ~= 0 then
                local targetCoords = GetEntityCoords(targetPed)
                local dist = #(playerCoords - targetCoords)
                if dist <= Config.Crew.InviteDistance then
                    local serverId = GetPlayerServerId(playerId)
                    nearbyPlayers[#nearbyPlayers + 1] = {
                        value = serverId,
                        label = ('Player %d (%.1fm)'):format(serverId, dist),
                    }
                end
            end
        end
    end

    if #nearbyPlayers == 0 then
        lib.notify({ description = 'No lumberjacks nearby to invite.', type = 'inform' })
        return
    end

    local input = lib.inputDialog('Invite to Crew', {
        {
            type = 'select',
            label = 'Player',
            options = nearbyPlayers,
            required = true,
        },
    })

    if not input then return end

    local targetSource = input[1]
    local success, err = lib.callback.await('forestry:crew:invite', false, targetSource)
    if success then
        lib.notify({ description = 'Invite sent!', type = 'success' })
    else
        local messages = {
            not_in_crew = 'You\'re not in a crew.',
            not_leader = 'Only the leader can invite.',
            target_in_crew = 'That player is already in a crew.',
            crew_full = 'Crew is full.',
            target_not_on_duty = 'That player isn\'t on duty as a lumberjack.',
            too_far = 'That player is too far away.',
        }
        lib.notify({ description = messages[err] or 'Failed to invite.', type = 'error' })
    end
end

-----------------------------------------------------------
-- KICK MEMBER
-----------------------------------------------------------
function KickMember()
    if not CrewData then return end

    local kickOptions = {}
    for _, member in ipairs(CrewData.roster) do
        if member.source ~= cache.serverId then
            kickOptions[#kickOptions + 1] = {
                value = member.source,
                label = member.name .. ' (' .. member.role .. ')',
            }
        end
    end

    if #kickOptions == 0 then
        lib.notify({ description = 'No members to kick.', type = 'inform' })
        return
    end

    local input = lib.inputDialog('Kick Member', {
        {
            type = 'select',
            label = 'Member',
            options = kickOptions,
            required = true,
        },
    })

    if not input then return end

    TriggerServerEvent('forestry:server:crew:kick', input[1])
end

-----------------------------------------------------------
-- RADIO INTEGRATION (optional)
-----------------------------------------------------------
local crewRadioChannel = nil

function JoinCrewRadio(crewId)
    -- pma-voice example
    if GetResourceState('pma-voice') ~= 'started' then return end

    -- Generate a numeric channel from crew ID hash
    local hash = 0
    for i = 1, #crewId do
        hash = (hash * 31 + string.byte(crewId, i)) % 9999 + 1
    end
    crewRadioChannel = hash

    exports['pma-voice']:setRadioChannel(crewRadioChannel)
end

function LeaveCrewRadio()
    if not crewRadioChannel then return end
    if GetResourceState('pma-voice') ~= 'started' then return end

    exports['pma-voice']:setRadioChannel(0)
    crewRadioChannel = nil
end

-----------------------------------------------------------
-- COMMAND & KEYBIND
-----------------------------------------------------------
RegisterCommand('crew', function()
    OpenCrewMenu()
end, false)

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
function IsInCrew()
    return CrewData ~= nil
end

function GetCrewData()
    return CrewData
end
