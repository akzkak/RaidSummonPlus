-- RaidSummonPlusRitualofSouls.lua
-- Ritual of Souls module for RaidSummonPlus addon
-- Handles tracking, display, and announcements of Ritual of Souls
-- WoW 1.12.1 (Vanilla) compatible version

-- Constants for Ritual of Souls functionality
RITUAL_OF_SOULS_SPELL_ID = 45920  -- Spell ID for Ritual of Souls
RITUAL_OF_SOULS_SPELL_NAMES = {
    "Ritual of Souls",
    "ritual of souls"
}
-- Talent constants
MASTER_CONJUROR_TAB = 2           -- Demonology talent tab
MASTER_CONJUROR_INDEX = 1         -- Position in the Demonology tab

-- Cache for talent checks to improve performance
RITUAL_OF_SOULS_TALENT_CACHE = {
    rank = nil,
    lastCheck = 0,
    cacheDuration = 30  -- Cache talent rank for 30 seconds
}

-- Cached version of Master Conjuror rank check
function RaidSummonPlusRitualofSouls_GetCachedMasterConjurorRank()
    local currentTime = GetTime()
    
    -- Return cached value if it's still valid
    if RITUAL_OF_SOULS_TALENT_CACHE.rank ~= nil and 
       (currentTime - RITUAL_OF_SOULS_TALENT_CACHE.lastCheck) < RITUAL_OF_SOULS_TALENT_CACHE.cacheDuration then
        return RITUAL_OF_SOULS_TALENT_CACHE.rank
    end
    
    -- Cache expired or not set, get fresh value
    local rank = RaidSummonPlusRitualofSouls_GetMasterConjurorRank()
    
    -- Update cache
    RITUAL_OF_SOULS_TALENT_CACHE.rank = rank
    RITUAL_OF_SOULS_TALENT_CACHE.lastCheck = currentTime
    
    return rank
end

-- Function to get Master Conjuror talent rank with error handling
function RaidSummonPlusRitualofSouls_GetMasterConjurorRank()
    local success, result = pcall(function()
        local name, iconTexture, tier, column, currentRank, maxRank = GetTalentInfo(MASTER_CONJUROR_TAB, MASTER_CONJUROR_INDEX)
        
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Checking talent tab " .. MASTER_CONJUROR_TAB .. 
                ", index " .. MASTER_CONJUROR_INDEX)
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Found talent: " .. (name or "nil") .. 
                ", Rank: " .. (currentRank or "nil") .. "/" .. (maxRank or "nil"))
        end
        
        return currentRank or 0
    end)
    
    if not success then
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Error getting talent rank: " .. tostring(result))
        end
        return 0  -- Default to 0 if there's an error
    end
    
    return result
end

-- Function to get healthstone healing value based on talent points
function RaidSummonPlusRitualofSouls_GetHealthstoneHealValue(talentRank)
    if talentRank == 2 then
        return 1440
    elseif talentRank == 1 then
        return 1320
    else
        return 1200
    end
end

-- Add a debug function to scan all warlock talents
function RaidSummonPlusRitualofSouls_DebugTalents()
    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Scanning all Warlock talents")
    
    for tab=1,3 do
        local tabName = "Unknown"
        if tab == 1 then tabName = "Affliction"
        elseif tab == 2 then tabName = "Demonology"
        elseif tab == 3 then tabName = "Destruction"
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Tab " .. tab .. " (" .. tabName .. ")")
        
        for index=1,20 do
            local name, iconTexture, tier, column, currentRank, maxRank = GetTalentInfo(tab, index)
            if name then
                DEFAULT_CHAT_FRAME:AddMessage("  Index " .. index .. ": " .. name .. 
                    " (Rank " .. currentRank .. "/" .. maxRank .. ")")
            end
        end
    end
end

-- Main handler function for Ritual of Souls spell casts
function RaidSummonPlusRitualofSouls_HandleSpellCast(spellName)
    -- Early exit if ritual announcements are disabled
    if not RaidSummonPlusOptions or not RaidSummonPlusOptions.ritual then
        return false
    end
    
    -- More efficient detection - normalize spell name once
    local normalizedSpellName = string.lower(spellName or "")
    
    -- Check if this is a Ritual of Souls spell
    local isRitualOfSouls = false
    for _, ritualSpellName in ipairs(RITUAL_OF_SOULS_SPELL_NAMES) do
        if normalizedSpellName == string.lower(ritualSpellName) or 
           string.find(normalizedSpellName, "ritual of souls") then
            isRitualOfSouls = true
            break
        end
    end
    
    if not isRitualOfSouls then
        return false
    end
    
    -- Debug output only for relevant spells (Ritual of Souls)
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Ritual of Souls spell cast detected: " .. (spellName or "nil"))
    end
    
    -- If debug is enabled, scan all talents to help locate Master Conjuror
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        RaidSummonPlusRitualofSouls_DebugTalents()
    end
    
    -- Get talent rank with caching to avoid repeated lookups
    local talentRank = RaidSummonPlusRitualofSouls_GetCachedMasterConjurorRank()
    local healValue = RaidSummonPlusRitualofSouls_GetHealthstoneHealValue(talentRank)
    
    -- Determine default channel
    local defaultChannel, channelName
    if UnitInRaid("player") then
        defaultChannel = "RAID"
        channelName = "raid"
    elseif GetNumPartyMembers() > 0 then
        defaultChannel = "PARTY" 
        channelName = "party"
    else
        defaultChannel = "SAY"
        channelName = "say"
    end
    
    -- Create announcement message
    local message, customChannel
    -- Check if user has set a custom message
    if RaidSummonPlusOptions and RaidSummonPlusOptions["ritualMessage"] and RaidSummonPlusOptions["ritualMessage"] ~= "" then
        -- Use stored message, replace placeholders
        message = RaidSummonPlusOptions["ritualMessage"]
        message = string.gsub(message, "{healValue}", healValue)
        message = string.gsub(message, "{healvalue}", healValue)
        message = string.gsub(message, "{talentRank}", talentRank)
        message = string.gsub(message, "{talentrank}", talentRank)
        if talentRank > 0 then
            message = string.gsub(message, "{masterConjuror}", "(Master Conjuror Rank " .. talentRank .. ")")
            message = string.gsub(message, "{masterconjuror}", "(Master Conjuror Rank " .. talentRank .. ")")
        else
            message = string.gsub(message, "{masterConjuror}", "")
            message = string.gsub(message, "{masterconjuror}", "")
        end
        
        -- Handle specific channel placeholders with smart fallback
        if string.find(message, "{raid}") then
            -- Smart channel selection: use RAID if in raid, PARTY if in party
            if UnitInRaid("player") then
                customChannel = "RAID"
            elseif GetNumPartyMembers() > 0 then
                customChannel = "PARTY"
            else
                customChannel = "SAY"  -- Solo fallback
            end
            message = string.gsub(message, "{raid}", "")
        elseif string.find(message, "{party}") then
            customChannel = "PARTY"
            message = string.gsub(message, "{party}", "")
        elseif string.find(message, "{guild}") then
            customChannel = "GUILD"
            message = string.gsub(message, "{guild}", "")
        elseif string.find(message, "{say}") then
            customChannel = "SAY"
            message = string.gsub(message, "{say}", "")
        elseif string.find(message, "{yell}") then
            customChannel = "YELL"
            message = string.gsub(message, "{yell}", "")
        end
        
        -- Clean up any extra spaces at the beginning
        message = string.gsub(message, "^%s+", "")
    else
        -- Empty message means disabled - just return early
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Ritual message is empty, announcements disabled")
        end
        return true
    end
    
    -- Send using selected ritual channels
    local sent = false
    if RaidSummonPlusOptions["ritualChannelRaid"] and UnitInRaid("player") then
        SendChatMessage(message, "RAID"); sent = true
    end
    if RaidSummonPlusOptions["ritualChannelParty"] and GetNumPartyMembers() > 0 then
        SendChatMessage(message, "PARTY"); sent = true
    end
    if RaidSummonPlusOptions["ritualChannelSay"] then
        SendChatMessage(message, "SAY"); sent = true
    end
    if RaidSummonPlusOptions["ritualChannelYell"] then
        SendChatMessage(message, "YELL"); sent = true
    end
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug and not sent then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : No ritual channels selected or available")
    end
    
    return true
end

-- Initialize the Ritual of Souls module
function RaidSummonPlusRitualofSouls_Initialize()
    -- Only initialize if we're a warlock
    if UnitClass("player") == "Warlock" then
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Ritual of Souls module initialized")
        end
    end
end