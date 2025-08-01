-- RaidSummonPlusCompatibility.lua
-- Cross-addon compatibility module for RaidSummonPlus
-- Handles communication with other summon addons
-- WoW 1.12.1 (Vanilla) compatible version

-- Cross-addon compatibility setting (can be toggled via slash command)
RaidSummonPlus_CrossAddonCompatibility = true

-- Helper function to output messages only when debug is enabled
function RaidSummonPlusCompatibility_DebugMessage_Silent(message)
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. message)
    end
end

-- Supported summon addon prefixes for compatibility
OTHER_ADDON_PREFIXES = {
    -- Capslock addon (Sentilix)
    "Capslockv1",
    -- LockPort addon (seacrabsam)
    "RSAdd",
    "RSRemove",
    -- RaidSummon addon (Linae-Kronos) - uses same prefixes as LockPort
    -- "RSAdd",    -- Already listed above
    -- "RSRemove"  -- Already listed above
    -- Our own addon (RaidSummonPlus) - for completeness in debug messages
    "RSPAdd",
    "RSPRemove",
    "RSPSoulstone"
}

-- Function to check if a message prefix is from another summon addon
function RaidSummonPlus_IsOtherSummonAddon(prefix)
    for _, otherPrefix in ipairs(OTHER_ADDON_PREFIXES) do
        if prefix == otherPrefix then
            return true
        end
    end
    return false
end

-- Function to identify which addon a prefix belongs to
function RaidSummonPlus_GetAddonNameFromPrefix(prefix)
    if prefix == "Capslockv1" then
        return "Capslock (Sentilix)"
    elseif prefix == "RSAdd" or prefix == "RSRemove" then
        return "LockPort/RaidSummon (seacrabsam/Linae-Kronos)"
    elseif prefix == "RSPAdd" or prefix == "RSPRemove" or prefix == "RSPSoulstone" then
        return "RaidSummonPlus (our addon)"
    else
        return "Unknown addon"
    end
end

-- Function to parse player name from other addon messages
function RaidSummonPlus_ParseOtherAddonMessage(prefix, message)
    local playerName = nil
    local isAdd = false
    local isRemove = false
    
    -- Handle Capslock addon (Capslockv1) structured messages
    if prefix == "Capslockv1" then
        -- Format: cmd#message#recipient
        local _, _, cmd, msgContent, recipient = string.find(message, "([^#]*)#([^#]*)#([^#]*)")
        
        -- Debug log for Capslock messages
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Compat Debug|r : Capslock cmd=" .. (cmd or "nil") .. 
                ", content=" .. (msgContent or "nil") .. ", recipient=" .. (recipient or "nil"))
        end
        
        if cmd == "TX_SYNCADDQ" then
            -- Format: playername/priority
            local _, _, name, priority = string.find(msgContent, "([^/]*)/([^/]*)")
            if name then
                playerName = name
                isAdd = true
            end
        elseif cmd == "TX_SYNCREMQ" or cmd == "TX_SUMBEGIN" then
            -- Format: playername
            local _, _, name = string.find(msgContent, "([^/]*)")
            if name then
                playerName = name
                isRemove = true
            end
        end
    -- Handle LockPort (seacrabsam) & RaidSummon (Linae-Kronos) addons (RSAdd/RSRemove) simple messages
    elseif prefix == "RSAdd" then
        -- Message contains just the player name
        playerName = message
        isAdd = true
        
        -- Debug log for RSAdd messages
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Compat Debug|r : RSAdd for player=" .. (message or "nil"))
        end
    elseif prefix == "RSRemove" then
        -- Message contains just the player name
        playerName = message
        isRemove = true
        
        -- Debug log for RSRemove messages
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Compat Debug|r : RSRemove for player=" .. (message or "nil"))
        end
    end
    
    return playerName, isAdd, isRemove
end

-- Function to handle cross-addon compatibility messages
function RaidSummonPlusCompatibility_HandleMessage(prefix, message, sender)
    -- Only process if compatibility is enabled
    if not RaidSummonPlus_CrossAddonCompatibility then
        -- Only debug log if it's actually a summon addon prefix
        if RaidSummonPlus_IsOtherSummonAddon(prefix) then
            RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, "compatibility disabled")
        end
        return false
    end
    
    -- Check if this is from another summon addon
    if not RaidSummonPlus_IsOtherSummonAddon(prefix) then
        -- Don't log debug messages for non-summon addon prefixes to avoid spam
        return false
    end
    
    -- Skip processing our own addon's messages (they're handled by the main addon)
    if prefix == "RSPAdd" or prefix == "RSPRemove" or prefix == "RSPSoulstone" then
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            local addonName = RaidSummonPlus_GetAddonNameFromPrefix(prefix)
            RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, "skipped (our own addon)")
        end
        return false
    end
    
    -- Parse the message
    local playerName, isAdd, isRemove = RaidSummonPlus_ParseOtherAddonMessage(prefix, message)
    
    -- Capitalize player name for consistency (especially important for Capslock compatibility)
    if playerName then
        playerName = RaidSummonPlusCompatibility_CapitalizePlayerName(playerName)
    end
    
    if playerName and UnitName("player") ~= playerName then
        if isAdd then
            -- Add player to our list if not already present
            if not RaidSummonPlus_hasValue(RaidSummonPlusDB, playerName) then
                table.insert(RaidSummonPlusDB, playerName)
                RaidSummonPlus_UpdateList()
                local addonName = RaidSummonPlus_GetAddonNameFromPrefix(prefix)
                RaidSummonPlusCompatibility_DebugMessage_Silent("Added " .. playerName .. " from " .. addonName .. " (" .. prefix .. ")")
                RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, "added " .. playerName)
            else
                RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, playerName .. " already in list")
            end
            return true
        elseif isRemove then
            -- Remove player from our list
            if RaidSummonPlus_hasValue(RaidSummonPlusDB, playerName) then
                for i, v in ipairs(RaidSummonPlusDB) do
                    if v == playerName then
                        table.remove(RaidSummonPlusDB, i)
                        RaidSummonPlus_UpdateList()
                        local addonName = RaidSummonPlus_GetAddonNameFromPrefix(prefix)
                        RaidSummonPlusCompatibility_DebugMessage_Silent("Removed " .. playerName .. " from " .. addonName .. " (" .. prefix .. ")")
                        RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, "removed " .. playerName)
                        break
                    end
                end
            else
                RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, playerName .. " not in list")
            end
            return true
        else
            RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, "no action determined")
        end
    else
        RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, "invalid player or self")
    end
    
    return false
end

-- Helper function to capitalize first letter of player names (like Capslock does)
function RaidSummonPlusCompatibility_CapitalizePlayerName(name)
    if not name or name == "" then
        return name
    end
    
    -- Convert first character to uppercase, rest to lowercase
    return string.upper(string.sub(name, 1, 1)) .. string.lower(string.sub(name, 2))
end

-- Debug function to log compatibility message processing
function RaidSummonPlusCompatibility_DebugMessage(prefix, message, sender, action)
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        local addonName = RaidSummonPlus_GetAddonNameFromPrefix(prefix)
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Compat Debug|r : " .. 
            "Addon: " .. addonName .. 
            " | Prefix: " .. prefix .. 
            " | Message: " .. (message or "nil") .. 
            " | Sender: " .. (sender or "nil") .. 
            " | Action: " .. (action or "none"))
    end
end