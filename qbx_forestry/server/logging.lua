-----------------------------------------------------------
-- SERVER: LOGGING
-- Optional Discord webhook integration.
-----------------------------------------------------------

---@param eventType string event key (e.g., 'largeSale', 'contractComplete')
---@param title string embed title
---@param description string embed description
---@param color? number embed color (default blue)
function ForestryLog(eventType, title, description, color)
    if not Config.Logging.Enabled then return end
    if not Config.Logging.WebhookURL or Config.Logging.WebhookURL == '' then return end

    -- Check if this specific event type is enabled
    if Config.Logging.Events and Config.Logging.Events[eventType] == false then return end

    local embed = {
        {
            title = title,
            description = description,
            color = color or 3447003,
            footer = { text = 'QBX Forestry' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        },
    }

    PerformHttpRequest(Config.Logging.WebhookURL, function() end, 'POST',
        json.encode({ embeds = embed }),
        { ['Content-Type'] = 'application/json' }
    )
end
