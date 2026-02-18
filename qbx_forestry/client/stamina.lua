-----------------------------------------------------------
-- CLIENT: STAMINA
-- Swing counter system. Zero cost when not winded.
-----------------------------------------------------------

local currentSwings = 12
local maxSwings = 12
local winded = false

-----------------------------------------------------------
-- INIT STAMINA (called on clock-in and resource start)
-----------------------------------------------------------
---@param forestryLevel number
function InitStamina(forestryLevel)
    maxSwings = math.min(
        Config.Stamina.MaxSwings,
        Config.Stamina.BaseSwings + math.floor(forestryLevel * Config.Stamina.SwingsPerLevel)
    )
    currentSwings = maxSwings
    winded = false
end

-----------------------------------------------------------
-- CONSUME SWING
-- Returns true if swing was consumed, false if winded.
-----------------------------------------------------------
---@return boolean canSwing
function ConsumeSwing()
    if winded then return false end

    if currentSwings <= 0 then
        EnterWindedState()
        return false
    end

    currentSwings = currentSwings - 1

    -- Warning at threshold
    if currentSwings == Config.Stamina.WarningThreshold then
        lib.notify({
            description = ('%d swings left before you need a break.'):format(currentSwings),
            type = 'warning',
        })
    end

    if currentSwings <= 0 then
        EnterWindedState()
    end

    return true
end

-----------------------------------------------------------
-- IS WINDED
-----------------------------------------------------------
---@return boolean
function IsWinded()
    return winded
end

-----------------------------------------------------------
-- CHECK STAMINA (on-demand status)
-----------------------------------------------------------
function CheckStamina()
    lib.notify({
        description = ('You have %d/%d swings remaining.'):format(currentSwings, maxSwings),
        type = 'inform',
    })
end

-----------------------------------------------------------
-- REFRESH STAMINA (on level-up)
-----------------------------------------------------------
---@param forestryLevel number
function RefreshStamina(forestryLevel)
    maxSwings = math.min(
        Config.Stamina.MaxSwings,
        Config.Stamina.BaseSwings + math.floor(forestryLevel * Config.Stamina.SwingsPerLevel)
    )
    currentSwings = maxSwings
    winded = false
end

-----------------------------------------------------------
-- ENTER WINDED STATE
-- Blocks actions, plays breathing anim, starts recovery.
-----------------------------------------------------------
function EnterWindedState()
    if winded then return end
    winded = true

    lib.notify({
        description = "You're winded. Catch your breath.",
        type = 'error',
    })

    -- Heavy breathing animation
    lib.requestAnimDict('amb@world_human_jog_standing@male@idle_a')
    TaskPlayAnim(cache.ped, 'amb@world_human_jog_standing@male@idle_a', 'idle_a', 8.0, -8.0, -1, 1, 0, false, false, false)

    -- Recovery timer
    CreateThread(function()
        local recoveryTime = Config.Stamina.WindedDuration
        local elapsed = 0

        while winded do
            Wait(200)

            local ped = cache.ped
            local speed = GetEntitySpeed(ped)

            -- Walking blocks recovery
            if speed > 0.5 then
                -- No recovery while moving
            else
                -- Check seated/lying multiplier
                local multiplier = 1.0
                if IsPedSittingInAnyVehicle(ped) or GetIsTaskActive(ped, 165) then
                    multiplier = Config.Stamina.SeatedRecoveryMultiplier
                end

                elapsed = elapsed + math.floor(200 * multiplier)
            end

            if elapsed >= recoveryTime then
                winded = false
                currentSwings = maxSwings
                ClearPedTasks(cache.ped)
                lib.notify({
                    description = "You've caught your breath.",
                    type = 'success',
                })
                break
            end
        end
    end)

    -- Sprint block during winded
    CreateThread(function()
        while winded do
            DisableControlAction(0, 21, true) -- Sprint
            Wait(0)
        end
    end)
end
