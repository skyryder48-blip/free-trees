-----------------------------------------------------------
-- SERVER: CREW SYSTEM
-- Ephemeral session-based crews with stash, XP bonuses,
-- and cooperative mechanics.
-----------------------------------------------------------

--- Active crews: crewId -> crewData
---@type table<string, table>
local Crews = {}

--- Player to crew mapping: source -> crewId
---@type table<number, string>
local PlayerCrews = {}

--- Counter for unique crew IDs
local crewCounter = 0

-----------------------------------------------------------
-- CREATE CREW
-----------------------------------------------------------
---@param source number
---@return boolean success
---@return string? crewIdOrError
function CreateCrew(source)
    if PlayerCrews[source] then
        return false, 'already_in_crew'
    end

    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    local cache = GetPlayerCacheBySource(source)
    if not cache then return false, 'not_loaded' end

    crewCounter = crewCounter + 1
    local crewId = ('crew_%d_%d'):format(source, crewCounter)
    local playerName = cache.name or ('Player %d'):format(source)

    Crews[crewId] = {
        id = crewId,
        leader = source,
        members = {
            [source] = {
                citizenid = citizenid,
                name = playerName,
                role = CrewRole.LEADER,
                lastActivity = GetGameTimer(),
            },
        },
        stashId = crewId .. '_stash',
        createdAt = GetGameTimer(),
        disbandedAt = nil,
    }

    PlayerCrews[source] = crewId

    -- Register ox_inventory stash
    exports.ox_inventory:RegisterStash(
        Crews[crewId].stashId,
        'Crew Stash - ' .. playerName,
        Config.Crew.SharedStashSlots,
        Config.Crew.SharedStashWeight
    )

    BroadcastCrewUpdate(crewId)

    TriggerClientEvent('ox_lib:notify', source, {
        description = 'Crew created! Invite nearby players.',
        type = 'success',
    })

    return true, crewId
end

-----------------------------------------------------------
-- INVITE TO CREW
-----------------------------------------------------------
---@param source number leader source
---@param targetSource number invite target
---@return boolean success
---@return string? reason
function InviteToCrew(source, targetSource)
    local crewId = PlayerCrews[source]
    if not crewId then return false, 'not_in_crew' end

    local crew = Crews[crewId]
    if not crew then return false, 'crew_not_found' end

    -- Only leader can invite
    if crew.leader ~= source then return false, 'not_leader' end

    -- Target checks
    if PlayerCrews[targetSource] then return false, 'target_in_crew' end

    -- Crew size limit
    local memberCount = 0
    for _ in pairs(crew.members) do memberCount = memberCount + 1 end
    if memberCount >= Config.Crew.MaxMembers then return false, 'crew_full' end

    -- Distance check
    local sourceCoords = GetEntityCoords(GetPlayerPed(source))
    local targetCoords = GetEntityCoords(GetPlayerPed(targetSource))
    if #(sourceCoords - targetCoords) > Config.Crew.InviteDistance then
        return false, 'too_far'
    end

    -- Target must be on duty
    local targetCitizenid = GetCitizenId(targetSource)
    if not targetCitizenid then return false, 'target_not_loaded' end

    local targetCache = GetPlayerCache(targetCitizenid)
    if not targetCache then return false, 'target_not_loaded' end

    -- Send invite to target client
    local leaderCache = GetPlayerCacheBySource(source)
    local leaderName = leaderCache and leaderCache.name or ('Player %d'):format(source)

    TriggerClientEvent('forestry:client:crew:invite', targetSource, crewId, source, leaderName)

    return true, nil
end

-----------------------------------------------------------
-- ACCEPT INVITE
-----------------------------------------------------------
RegisterNetEvent('forestry:server:crew:acceptInvite', function(crewId)
    local src = source

    if PlayerCrews[src] then
        TriggerClientEvent('ox_lib:notify', src, { description = 'Already in a crew.', type = 'error' })
        return
    end

    local crew = Crews[crewId]
    if not crew then
        TriggerClientEvent('ox_lib:notify', src, { description = 'Crew no longer exists.', type = 'error' })
        return
    end

    local citizenid = GetCitizenId(src)
    if not citizenid then return end

    local cache = GetPlayerCacheBySource(src)
    local playerName = cache and cache.name or ('Player %d'):format(src)

    crew.members[src] = {
        citizenid = citizenid,
        name = playerName,
        role = CrewRole.GENERAL,
        lastActivity = GetGameTimer(),
    }

    PlayerCrews[src] = crewId
    BroadcastCrewUpdate(crewId)

    TriggerClientEvent('ox_lib:notify', src, {
        description = 'Joined the crew!',
        type = 'success',
    })
end)

-----------------------------------------------------------
-- SET CREW ROLE
-----------------------------------------------------------
---@param source number requesting player
---@param targetSource number target player
---@param role string CrewRole value
---@return boolean success
---@return string? reason
function SetCrewRole(source, targetSource, role)
    local crewId = PlayerCrews[source]
    if not crewId then return false, 'not_in_crew' end

    local crew = Crews[crewId]
    if not crew then return false, 'crew_not_found' end

    -- Allow leader to set any role, or self-set non-leader role
    if source ~= crew.leader and source ~= targetSource then
        return false, 'not_leader'
    end

    -- Can't demote leader via this function
    if targetSource == crew.leader and role ~= CrewRole.LEADER then
        return false, 'cannot_demote_leader'
    end

    local member = crew.members[targetSource]
    if not member then return false, 'target_not_in_crew' end

    member.role = role
    BroadcastCrewUpdate(crewId)

    return true, nil
end

-----------------------------------------------------------
-- REMOVE PLAYER FROM CREW
-----------------------------------------------------------
---@param src number player source
---@param reason string 'left'|'kicked'|'disconnected'|'off_duty'
function RemovePlayerFromCrew(src, reason)
    local crewId = PlayerCrews[src]
    if not crewId then return end

    local crew = Crews[crewId]
    if not crew then
        PlayerCrews[src] = nil
        return
    end

    local wasLeader = (crew.leader == src)
    crew.members[src] = nil
    PlayerCrews[src] = nil

    -- Count remaining members
    local remaining = {}
    for memberSrc, memberData in pairs(crew.members) do
        remaining[#remaining + 1] = { source = memberSrc, data = memberData }
    end

    if #remaining == 0 then
        -- Crew empty, mark for cleanup
        crew.disbandedAt = GetGameTimer()
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Crew disbanded.',
            type = 'inform',
        })
        return
    end

    -- Transfer leadership if leader left
    if wasLeader then
        -- Find longest-active member
        local longestActive = remaining[1]
        for _, m in ipairs(remaining) do
            if m.data.lastActivity > longestActive.data.lastActivity then
                longestActive = m
            end
        end

        crew.leader = longestActive.source
        longestActive.data.role = CrewRole.LEADER

        TriggerClientEvent('ox_lib:notify', longestActive.source, {
            description = 'You are now the crew leader.',
            type = 'inform',
        })
    end

    BroadcastCrewUpdate(crewId)

    if reason ~= 'disconnected' then
        TriggerClientEvent('ox_lib:notify', src, {
            description = reason == 'kicked' and 'You were kicked from the crew.' or 'Left the crew.',
            type = 'inform',
        })
    end
end

-----------------------------------------------------------
-- KICK FROM CREW (leader only)
-----------------------------------------------------------
---@param leaderSource number
---@param targetSource number
---@return boolean success
---@return string? reason
function KickFromCrew(leaderSource, targetSource)
    local crewId = PlayerCrews[leaderSource]
    if not crewId then return false, 'not_in_crew' end

    local crew = Crews[crewId]
    if not crew then return false, 'crew_not_found' end

    if crew.leader ~= leaderSource then return false, 'not_leader' end
    if leaderSource == targetSource then return false, 'cannot_kick_self' end

    if not crew.members[targetSource] then return false, 'target_not_in_crew' end

    RemovePlayerFromCrew(targetSource, 'kicked')
    return true, nil
end

-----------------------------------------------------------
-- GET CREW MEMBERS NEAR PLAYER
-- Used for relay loading bonus.
-----------------------------------------------------------
---@param source number
---@param radius number
---@return number count
function GetCrewMembersNearPlayer(source, radius)
    local crewId = PlayerCrews[source]
    if not crewId then return 1 end

    local crew = Crews[crewId]
    if not crew then return 1 end

    local sourceCoords = GetEntityCoords(GetPlayerPed(source))
    local count = 0

    for memberSrc in pairs(crew.members) do
        local memberCoords = GetEntityCoords(GetPlayerPed(memberSrc))
        if #(sourceCoords - memberCoords) <= radius then
            count = count + 1
        end
    end

    return math.max(1, count)
end

-----------------------------------------------------------
-- GET CREW XP MULTIPLIER
-- +10% per active crew member, cap +40%.
-----------------------------------------------------------
---@param source number
---@return number multiplier (1.0 = no bonus)
function GetCrewXPMultiplier(source)
    local crewId = PlayerCrews[source]
    if not crewId then return 1.0 end

    local crew = Crews[crewId]
    if not crew then return 1.0 end

    local now = GetGameTimer()
    local activeCount = 0

    for _, memberData in pairs(crew.members) do
        if (now - memberData.lastActivity) <= Config.Crew.ActivityWindow then
            activeCount = activeCount + 1
        end
    end

    if activeCount <= 1 then return 1.0 end

    local bonus = math.min(
        (activeCount - 1) * Config.Crew.XPBonusPerMember,
        Config.Crew.XPBonusCap
    )

    return 1.0 + bonus
end

-----------------------------------------------------------
-- UPDATE CREW ACTIVITY
-- Called when a player performs a forestry action.
-----------------------------------------------------------
---@param source number
function UpdateCrewActivity(source)
    local crewId = PlayerCrews[source]
    if not crewId then return end

    local crew = Crews[crewId]
    if not crew then return end

    local member = crew.members[source]
    if member then
        member.lastActivity = GetGameTimer()
    end
end

-----------------------------------------------------------
-- BROADCAST CREW UPDATE
-- Send roster to all crew members.
-----------------------------------------------------------
function BroadcastCrewUpdate(crewId)
    local crew = Crews[crewId]
    if not crew then return end

    local roster = {}
    for memberSrc, memberData in pairs(crew.members) do
        roster[#roster + 1] = {
            source = memberSrc,
            name = memberData.name,
            role = memberData.role,
            isLeader = (memberSrc == crew.leader),
        }
    end

    local update = {
        crewId = crewId,
        leader = crew.leader,
        roster = roster,
        stashId = crew.stashId,
    }

    for memberSrc in pairs(crew.members) do
        TriggerClientEvent('forestry:client:crew:update', memberSrc, update)
    end
end

-----------------------------------------------------------
-- LEAVE CREW (player-initiated)
-----------------------------------------------------------
RegisterNetEvent('forestry:server:crew:leave', function()
    RemovePlayerFromCrew(source, 'left')
end)

-----------------------------------------------------------
-- KICK FROM CREW (leader-initiated)
-----------------------------------------------------------
RegisterNetEvent('forestry:server:crew:kick', function(targetSource)
    KickFromCrew(source, targetSource)
end)

-----------------------------------------------------------
-- STASH CLEANUP THREAD
-- Remove stashes from disbanded crews after delay.
-----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(60000)

        local now = GetGameTimer()
        local toRemove = {}

        for crewId, crew in pairs(Crews) do
            if crew.disbandedAt then
                if (now - crew.disbandedAt) >= Config.Crew.StashCleanupDelay then
                    toRemove[#toRemove + 1] = crewId
                end
            end
        end

        for _, crewId in ipairs(toRemove) do
            Crews[crewId] = nil
            lib.print.info(('[Forestry] Cleaned up disbanded crew: %s'):format(crewId))
        end
    end
end)
