-- RaidSummonPlusSoulstone.lua
-- Soulstone tracking module for RaidSummonPlus addon
-- Handles tracking, display, and management of Soulstone buffs
-- WoW 1.12.1 (Vanilla) compatible version

-- Status constants for soulstones
SOULSTONE_STATUS = {
    ACTIVE = 1,   -- Has active soulstone
    EXPIRED = 2   -- Soulstone expired or was used
}

-- Variables for Soulstone tracking
-- Note: In vanilla WoW, we can only detect buff presence, not remaining time on other players
-- Therefore, we use static 30-minute timers for all soulstones
SOULSTONE_BUFF_NAMES = {
    "Soulstone Resurrection",
    "Minor Soulstone Resurrection",
    "Lesser Soulstone Resurrection",
    "Greater Soulstone Resurrection",
    "Major Soulstone Resurrection"
}

-- Helper function to output messages only when debug is enabled
function RaidSummonPlusSoulstone_DebugMessage(message)
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. message)
    end
end

-- Comprehensive data structure for soulstone spells and their resulting items
SOULSTONE_CREATION_SPELLS = {
    { name = "Create Soulstone (Major)", id = 20757, itemName = "Major Soulstone", itemId = 16896 },
    { name = "Create Soulstone (Greater)", id = 20756, itemName = "Greater Soulstone", itemId = 16895 },
    { name = "Create Soulstone", id = 20755, itemName = "Soulstone", itemId = 16893 },
    { name = "Create Soulstone (Lesser)", id = 20752, itemName = "Lesser Soulstone", itemId = 16892 },
    { name = "Create Soulstone (Minor)", id = 693, itemName = "Minor Soulstone", itemId = 5232 }
}

-- Soul Shard constant
SOUL_SHARD = {
    id = 6265,
    name = "Soul Shard"
}

SOULSTONE_DURATION = 30 * 60 -- 30 minutes in seconds
-- Table to store soulstone entries with expanded data
-- { name = "PlayerName", expiry = expiryTime, isSelfCast = true/false, status = SOULSTONE_STATUS.ACTIVE }
SOULSTONE_DATA = {} 
SOULSTONE_UPDATE_INTERVAL = 1 -- Update timer every second
SOULSTONE_TIMER_ACTIVE = false
SOULSTONE_AUTOSCAN_INTERVAL = 30 -- Auto-scan interval for soulstones (in seconds)

-- Table to track our own cast timers (like PallyPower's LastCast)
-- Only timers we set ourselves will count down - detected buffs don't get timers
SOULSTONE_CAST_TIMERS = {}

-- Format time like PallyPower does
function RaidSummonPlusSoulstone_FormatTime(time)
    if not time or time < 0 then
        return ""
    end
    local mins = math.floor(time / 60)
    local secs = time - (mins * 60)
    return string.format("%d:%02d", mins, secs)
end

-- Handle when a player is resurrected (soulstone used)
function RaidSummonPlusSoulstone_OnPlayerAlive()
    local playerName = UnitName("player")
    
    -- Check if the player had a soulstone and remove it
    for i = 1, table.getn(SOULSTONE_DATA) do
        if SOULSTONE_DATA[i].name == playerName then
            -- Mark as expired since soulstone was used
            SOULSTONE_DATA[i].status = SOULSTONE_STATUS.EXPIRED
            
            -- Remove from cast timers if it was self-cast
            if SOULSTONE_DATA[i].isSelfCast then
                SOULSTONE_CAST_TIMERS[playerName] = nil
            end
            
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Soulstone used for resurrection: " .. playerName)
            end
            
            -- Update display
            RaidSummonPlusSoulstone_UpdateDisplay()
            break
        end
    end
end

-- Initialize the Soulstone module
function RaidSummonPlusSoulstone_Initialize()
    -- Register for events if we're a warlock
    if UnitClass("player") == "Warlock" then
        -- Create matching title bar for soulstone section
        RaidSummonPlusSoulstone_CreateTitleBar()
        
        -- Initialize soulstone auto-scanning
        RaidSummonPlusSoulstone_InitAutoScan()
        
        -- Initial scan for soulstones (silently)
        RaidSummonPlusSoulstone_ScanRaid(true)
        
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Soulstone module initialized")
        end
    end
end

-- Check if a player has a soulstone buff and return the buff index if found
function RaidSummonPlusSoulstone_CheckForBuff(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end
    
    -- Skip non-players and players not in group
    local unitName = UnitName(unit)
    if not UnitIsPlayer(unit) or not RaidSummonPlus_IsPlayerInGroup(unitName) then
        return nil
    end
    
    -- The exact texture path for soulstone buff in vanilla WoW
    local SOULSTONE_TEXTURE = "Interface\\Icons\\Spell_Shadow_SoulGem"
    
    -- Check all possible buff slots (Turtle WoW supports 32 buffs)
    for i = 1, 32 do
        local buffTexture = UnitBuff(unit, i)
        
        if buffTexture then
            -- Check if it's the soulstone buff
            if buffTexture == SOULSTONE_TEXTURE then
                return i  -- Return the buff index instead of just true
            end
        end
    end
    
    return nil
end

-- Removed GetPlayerBuffId function - no longer needed for static timers

-- Removed GetTimeLeft function - we use static 30-minute timers only

-- Check if player has a soulstone item in inventory
function RaidSummonPlusSoulstone_HasStoneInInventory()
    -- Check each bag
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                -- Check against all possible soulstone item names
                for _, spellData in ipairs(SOULSTONE_CREATION_SPELLS) do
                    if string.find(link, spellData.itemName) then
                        if RaidSummonPlusOptions.debug then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Found " .. spellData.itemName .. " in bag " .. bag .. ", slot " .. slot)
                        end
                        return true, bag, slot, spellData.itemName
                    end
                end
            end
        end
    end
    
    return false
end

-- Try to create a soulstone - returns true if successful
function RaidSummonPlusSoulstone_TryCreateSoulstone()
    -- First check if we have soul shards
    local hasShard, _, _, shardCount = FindItem(SOUL_SHARD.name)
    
    -- Debug print for shard count
    if RaidSummonPlusOptions.debug then
        if hasShard then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Found " .. shardCount .. " Soul Shard" .. (shardCount > 1 and "s" or "") .. " in bags")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : No Soul Shards found in bags")
        end
    end
    
    if not hasShard or shardCount < 1 then
        return false, "No Soul Shards available"
    end
    
    -- Check if we already have a soulstone (might be on cooldown)
    local hasStone, _, _, stoneName = RaidSummonPlusSoulstone_HasStoneInInventory()
    if hasStone then
        return false, "Soulstone exists but is still on cooldown"
    end
    
    -- Debug - log what we're looking for
    if RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Searching for soulstone creation spells")
    end
    
    -- Define spells to try in order of preference (best to worst)
    local spellsToTry = {
        { pattern = "Major", item = "Major Soulstone" },
        { pattern = "Greater", item = "Greater Soulstone" },
        { pattern = "^Create Soulstone$", item = "Soulstone" },
        { pattern = "Lesser", item = "Lesser Soulstone" },
        { pattern = "Minor", item = "Minor Soulstone" }
    }
    
    -- Find all soulstone creation spells - SUPER OPTIMIZED SCANNING
    local foundSpells = {}
    
    -- Find the Demonology tab which contains soulstone spells
    local numTabs = GetNumSpellTabs()
    local demonologyTabIndex = nil
    local demonologyTabFirstSpell = 1
    local demonologyTabNumSpells = 0
    
    -- Log all tabs in debug mode to help identify the right one
    if RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Scanning spellbook tabs for Soulstone spells")
        for tab = 1, numTabs do
            local tabName, _, _, tabNumSpells = GetSpellTabInfo(tab)
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Tab " .. tab .. ": " .. tabName .. " (" .. tabNumSpells .. " spells)")
        end
    end
    
    -- Locate the Demonology tab
    for tab = 1, numTabs do
        local tabName, tabTexture, tabOffset, tabNumSpells = GetSpellTabInfo(tab)
        
        if tabName == "Demonology" then
            demonologyTabIndex = tab
            demonologyTabFirstSpell = tabOffset + 1 -- +1 because offsets start at 0
            demonologyTabNumSpells = tabNumSpells
            break
        end
    end
    
    -- If we found the Demonology tab, scan it first
    if demonologyTabIndex then
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Found Demonology tab with " .. demonologyTabNumSpells .. " spells")
        end
        
        -- Scan only Demonology tab spells
        local startIndex = demonologyTabFirstSpell
        local endIndex = startIndex + demonologyTabNumSpells - 1
        
        for i = startIndex, endIndex do
            local spellName = GetSpellName(i, BOOKTYPE_SPELL)
            if not spellName then break end
            
            if string.find(string.lower(spellName), "create soulstone") then
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Found spell: " .. spellName)
                end
                
                table.insert(foundSpells, {
                    index = i,
                    name = spellName
                })
            end
        end
    end
    
    -- If no spells found in Demonology tab, scan all tabs as fallback
    if table.getn(foundSpells) == 0 then
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : No soulstone spells found in Demonology tab, scanning all spells")
        end
        
        -- Calculate total spell count across all tabs for fallback
        local totalSpells = 0
        for tab = 1, numTabs do
            local _, _, _, numSpells = GetSpellTabInfo(tab)
            totalSpells = totalSpells + numSpells
        end
        
        for i = 1, totalSpells do
            local spellName = GetSpellName(i, BOOKTYPE_SPELL)
            if not spellName then break end
            
            if string.find(string.lower(spellName), "create soulstone") then
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Found spell: " .. spellName)
                end
                
                table.insert(foundSpells, {
                    index = i,
                    name = spellName
                })
            end
        end
    end
    
    -- Try to match each spell in order of preference
    for _, prefInfo in ipairs(spellsToTry) do
        for _, spellInfo in ipairs(foundSpells) do
            if string.find(spellInfo.name, prefInfo.pattern) then
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Found match: " .. spellInfo.name .. " matches pattern " .. prefInfo.pattern)
                end
                
                -- Cast this spell
                CastSpell(spellInfo.index, BOOKTYPE_SPELL)
                
                return true, "Creating " .. prefInfo.item
            end
        end
    end
    
    -- If we get here, we couldn't cast any of the spells
    return false, "No Soulstone creation spell available"
end

-- Apply soulstone tracking - ONLY sets timer when WE cast it (like PallyPower)
function RaidSummonPlusSoulstone_Apply(target, caster)
    -- Validate target name
    if not target or target == "" or target == "unknown" then
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Invalid soulstone target name: " .. tostring(target))
        end
        return
    end
    
    -- Only track soulstones on group members
    if not RaidSummonPlus_IsPlayerInGroup(target) then
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Ignoring soulstone on non-group member: " .. target)
        end
        return
    end
    
    -- Validate caster name
    if not caster or caster == "" then
        caster = UnitName("player") -- Default to player if no caster specified
    end
    
    local isSelfCast = (caster == UnitName("player"))
    
    -- CRITICAL: Only set timer if WE cast the soulstone (like PallyPower)
    if isSelfCast then
        -- Set our cast timer - this will count down
        SOULSTONE_CAST_TIMERS[target] = SOULSTONE_DURATION
        
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Started 30-minute timer for " .. target .. " (self-cast)")
        end
    end
    
    local entry = {
        name = target,
        expiry = isSelfCast and (GetTime() + SOULSTONE_DURATION) or nil,  -- Only set expiry for self-cast
        isSelfCast = isSelfCast,
        status = SOULSTONE_STATUS.ACTIVE
    }
    
    -- Add to our tracking data (replacing existing entry if present)
    local found = false
    for i = 1, table.getn(SOULSTONE_DATA) do
        if SOULSTONE_DATA[i].name == target then
            -- Only update expiry if this is a self-cast
            if isSelfCast then
                SOULSTONE_DATA[i].expiry = entry.expiry
            end
            SOULSTONE_DATA[i].isSelfCast = entry.isSelfCast
            SOULSTONE_DATA[i].status = SOULSTONE_STATUS.ACTIVE
            found = true
            break
        end
    end
    
    if not found then
        table.insert(SOULSTONE_DATA, entry)
    end
    
    -- Share with other warlocks - include self-cast flag
    local message = target .. ":" .. (entry.expiry or 0) .. ":" .. (isSelfCast and "1" or "0")
    SendAddonMessage(MSG_PREFIX_SOULSTONE, message, "RAID")
    
    -- Start the timer if not already running
    if not SOULSTONE_TIMER_ACTIVE then
        RaidSummonPlusSoulstone_StartTimer()
    end
    
    -- Update display
    RaidSummonPlusSoulstone_UpdateDisplay()
    
    -- Hide the frame whenever we apply a new soulstone (as the caster),
    -- regardless of other expired soulstones, but only if summon list is empty
    if isSelfCast and RaidSummonPlusDB and table.getn(RaidSummonPlusDB) == 0 and RaidSummonPlus_RequestFrame then
        -- Only hide if WE (the player) applied the soulstone
        RaidSummonPlus_RequestFrame:Hide()
        -- Update visibility state
        FRAME_VISIBILITY_STATE = "HIDDEN"
        
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hiding frame after soulstone application - you've ensured at least one active soulstone")
        end
    end
    
    if RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Soulstone applied to " .. target)
    end
end

-- Try to apply a soulstone to a target - avoids returning empty messages
function RaidSummonPlusSoulstone_TrySoulstoneTarget(targetName)
    -- First check if we have a ready soulstone
    local hasStone, bag, slot, stoneName = RaidSummonPlusSoulstone_HasStoneInInventory()
    
    if RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Attempting to soulstone " .. targetName)
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Has soulstone in inventory: " .. tostring(hasStone))
    end
    
    if hasStone then
        -- Target the player
        local targetFound = false
        
        -- If in raid, use raid targeting
        if UnitInRaid("player") then
            for j = 1, GetNumRaidMembers() do
                local raidName = GetRaidRosterInfo(j)
                if raidName == targetName then
                    TargetUnit("raid"..j)
                    targetFound = true
                    break
                end
            end
        end
        
        -- If not found in raid, check party
        if not targetFound and GetNumPartyMembers() > 0 then
            for j = 1, GetNumPartyMembers() do
                if UnitName("party"..j) == targetName then
                    TargetUnit("party"..j)
                    targetFound = true
                    break
                end
            end
        end
        
        -- If still not found, check if it's the player
        if not targetFound and UnitName("player") == targetName then
            TargetUnit("player")
            targetFound = true
        end
        
        if targetFound then
            -- Debug
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Target found, using " .. stoneName .. " from bag " .. bag .. ", slot " .. slot)
            end
            
            -- Mark that we're about to attempt using a soulstone - prevents success message
            SOULSTONE_ATTEMPT_ACTIVE = true
            SOULSTONE_ATTEMPT_TARGET = targetName
            SOULSTONE_ATTEMPT_TIME = GetTime()
            
            -- Use the stone from inventory
            UseContainerItem(bag, slot)
            
            -- Return without a message - cooldown handler will show appropriate message
            return true, nil
        else
            return false, "Could not target " .. targetName
        end
    else
        -- No stone in inventory, try to create one
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : No soulstone in inventory, trying to create one")
        end
        
        local success, message = RaidSummonPlusSoulstone_TryCreateSoulstone()
        
        if success then
            -- Return the creation message directly without adding player name
            return true, message
        else
            -- Just return the original message without adding anything
            return false, message
        end
    end
end

-- Timer function - decrements our cast timers like PallyPower
function RaidSummonPlusSoulstone_StartTimer()
    SOULSTONE_TIMER_ACTIVE = true
    
    -- Create a timer frame if it doesn't exist
    if not RaidSummonPlusSoulstone_TimerFrame then
        RaidSummonPlusSoulstone_TimerFrame = CreateFrame("Frame")
        RaidSummonPlusSoulstone_TimerFrame.lastUpdate = GetTime()
    end
    
    -- Set up the timer
    RaidSummonPlusSoulstone_TimerFrame:SetScript("OnUpdate", function()
        local currentTime = GetTime()
        local elapsed = currentTime - (this.lastUpdate or currentTime)
        this.lastUpdate = currentTime
        
        -- Decrement our cast timers (like PallyPower's LastCast)
        local needsUpdate = false
        for target, timeLeft in SOULSTONE_CAST_TIMERS do
            local newTime = timeLeft - elapsed
            if newTime <= 0 then
                -- Timer expired
                SOULSTONE_CAST_TIMERS[target] = nil
                needsUpdate = true
                
                -- Mark corresponding entry as expired
                for i = 1, table.getn(SOULSTONE_DATA) do
                    if SOULSTONE_DATA[i].name == target and SOULSTONE_DATA[i].isSelfCast then
                        SOULSTONE_DATA[i].status = SOULSTONE_STATUS.EXPIRED
                        
                        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Self-cast soulstone timer expired for " .. target)
                        end
                        break
                    end
                end
            else
                -- Update timer
                SOULSTONE_CAST_TIMERS[target] = newTime
            end
        end
        
        -- Skip updates if no timers changed and we haven't reached the update interval
        if not needsUpdate and currentTime < (this.nextUpdate or 0) then
            return
        end
        
        -- Check if we have any soulstones to track
        if table.getn(SOULSTONE_DATA) == 0 and not next(SOULSTONE_CAST_TIMERS) then
            -- No active soulstones or timers, stop the timer
            this:SetScript("OnUpdate", nil)
            SOULSTONE_TIMER_ACTIVE = false
            return
        end
        
        -- Always update the display when timers change (for visibility logic)
        -- But only update visual elements if frame is visible
        if needsUpdate then
            RaidSummonPlusSoulstone_UpdateDisplay()
        elseif RaidSummonPlus_RequestFrame and RaidSummonPlus_RequestFrame:IsVisible() then
            -- Regular timer updates only when frame is visible
            RaidSummonPlusSoulstone_UpdateDisplay()
        end
        
        -- Always set the next update time, even if frame is hidden
        this.nextUpdate = currentTime + SOULSTONE_UPDATE_INTERVAL
    end)
    
    -- Set the next update time
    RaidSummonPlusSoulstone_TimerFrame.nextUpdate = GetTime() + SOULSTONE_UPDATE_INTERVAL
end

-- Function to scan the raid for active soulstones
-- NEVER sets timers - only detects buff presence (like PallyPower detection)
function RaidSummonPlusSoulstone_ScanRaid(silent)
    -- Don't show the "Starting scan" message in silent mode
    if RaidSummonPlusOptions.debug and not silent then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Scanning for active soulstones...")
    end

    -- Save previous count for debug summary
    local previousCount = table.getn(SOULSTONE_DATA)
    
    -- Create a list of players who currently have soulstone buffs
    local playersWithBuffs = {}
    
    -- Check self first
    local playerName = UnitName("player")
    local playerBuffIndex = RaidSummonPlusSoulstone_CheckForBuff("player")
    if playerBuffIndex then
        playersWithBuffs[playerName] = true
    end

    -- Check if in raid
    if UnitInRaid("player") then
        local raidSize = GetNumRaidMembers()
        
        for i = 1, raidSize do
            local unit = "raid" .. i
            local name = UnitName(unit)
            
            -- Skip if it's the player (already checked)
            if name and name ~= playerName then
                local buffIndex = RaidSummonPlusSoulstone_CheckForBuff(unit)
                if buffIndex then
                    playersWithBuffs[name] = true
                end
            end
        end
    -- Check if in party
    elseif GetNumPartyMembers() > 0 then
        local partySize = GetNumPartyMembers()
        
        for i = 1, partySize do
            local unit = "party" .. i
            local name = UnitName(unit)
            
            -- Skip if it's the player (already checked)
            if name and name ~= playerName then
                local buffIndex = RaidSummonPlusSoulstone_CheckForBuff(unit)
                if buffIndex then
                    playersWithBuffs[name] = true
                end
            end
        end
    end
    
    -- Update existing entries based on buff detection
    -- Remove players who are no longer in group
    for i = table.getn(SOULSTONE_DATA), 1, -1 do
        local entry = SOULSTONE_DATA[i]
        
        if not RaidSummonPlus_IsPlayerInGroup(entry.name) then
            -- Remove players who are no longer in group
            table.remove(SOULSTONE_DATA, i)
            -- Also remove their timer if we have one
            SOULSTONE_CAST_TIMERS[entry.name] = nil
        elseif playersWithBuffs[entry.name] then
            -- Player still has buff - mark as active
            entry.status = SOULSTONE_STATUS.ACTIVE
        else
            -- Player no longer has buff
            if entry.isSelfCast and SOULSTONE_CAST_TIMERS[entry.name] then
                -- For self-cast soulstones, only mark expired if our timer says so
                -- (buff might have been used for resurrection)
                if SOULSTONE_CAST_TIMERS[entry.name] <= 0 then
                    entry.status = SOULSTONE_STATUS.EXPIRED
                end
            else
                -- For non-self-cast or no timer, mark as expired if no buff
                entry.status = SOULSTONE_STATUS.EXPIRED
            end
        end
    end
    
    -- Add new entries for players with buffs who aren't tracked yet
    -- CRITICAL: Never set timers here - only add entries without expiry times
    for playerName, _ in playersWithBuffs do
        local found = false
        for i = 1, table.getn(SOULSTONE_DATA) do
            if SOULSTONE_DATA[i].name == playerName then
                found = true
                break
            end
        end
        
        if not found then
            -- Add new entry WITHOUT timer - detection doesn't set timers
            table.insert(SOULSTONE_DATA, {
                name = playerName,
                expiry = nil,  -- No expiry time for detected buffs
                isSelfCast = false,  -- Assume not self-cast for detected buffs
                status = SOULSTONE_STATUS.ACTIVE
            })
            
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Detected new soulstone on " .. playerName .. " (no timer)")
            end
        end
    end
    
    -- Update display
    RaidSummonPlusSoulstone_UpdateDisplay()
    
    -- Start timer if we have any soulstones or cast timers
    if (table.getn(SOULSTONE_DATA) > 0 or next(SOULSTONE_CAST_TIMERS)) and not SOULSTONE_TIMER_ACTIVE then
        RaidSummonPlusSoulstone_StartTimer()
    end
    
    -- Print a single summary message of what was found
    local currentCount = table.getn(SOULSTONE_DATA)
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        if not silent or (previousCount ~= currentCount) then
            if currentCount == 0 then
                RaidSummonPlusSoulstone_DebugMessage("No soulstones found in group")
            else
                local activeNames = {}
                local expiredNames = {}
                
                for i = 1, currentCount do
                    if SOULSTONE_DATA[i].status == SOULSTONE_STATUS.ACTIVE then
                        table.insert(activeNames, SOULSTONE_DATA[i].name)
                    else
                        table.insert(expiredNames, SOULSTONE_DATA[i].name)
                    end
                end
                
                if table.getn(activeNames) > 0 then
                    RaidSummonPlusSoulstone_DebugMessage("Found " .. table.getn(activeNames) .. 
                        " active soulstone(s): " .. table.concat(activeNames, ", "))
                end
                
                if table.getn(expiredNames) > 0 then
                    RaidSummonPlusSoulstone_DebugMessage("Found " .. table.getn(expiredNames) .. 
                        " expired soulstone(s): " .. table.concat(expiredNames, ", "))
                end
            end
        end
    end
end



-- Initialize auto-scanning timer for soulstones
function RaidSummonPlusSoulstone_InitAutoScan()
    -- Create a timer frame if it doesn't exist
    if not RaidSummonPlusSoulstone_AutoScanFrame then
        -- Create frame
        RaidSummonPlusSoulstone_AutoScanFrame = CreateFrame("Frame")
        RaidSummonPlusSoulstone_AutoScanFrame.counter = 0
        
        -- Use a very simple update handler
        RaidSummonPlusSoulstone_AutoScanFrame:SetScript("OnUpdate", function()
            -- Skip if not a warlock
            if UnitClass("player") ~= "Warlock" then
                return
            end
            
            -- Simple counter increment
            local elapsed = arg1
            this.counter = this.counter + elapsed
            
            -- Check if time to scan
            if this.counter > SOULSTONE_AUTOSCAN_INTERVAL then
                this.counter = 0
                -- Pass true for silent mode
                RaidSummonPlusSoulstone_ScanRaid(true)
            end
        end)
        
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Soulstone auto-scan initialized (30s interval)")
        end
    end
end

-- Create a matching title bar for the soulstone section
function RaidSummonPlusSoulstone_CreateTitleBar()
    -- Make sure the soulstone frame exists
    if not RaidSummonPlus_SoulstoneFrame then
        return
    end
    
    -- Check if we already created the title frame
    if RaidSummonPlus_SoulstoneTitleFrame then
        return
    end
    
    -- Create a title frame to match the main title frame
    local titleFrame = CreateFrame("Frame", "RaidSummonPlus_SoulstoneTitleFrame", RaidSummonPlus_SoulstoneFrame)
    titleFrame:SetHeight(18)
    titleFrame:SetWidth(RaidSummonPlus_SoulstoneFrame:GetWidth())
    titleFrame:SetPoint("TOPLEFT", RaidSummonPlus_SoulstoneFrame, "TOPLEFT", 0, 0)
    
    -- Set the title frame backdrop to match the main title frame
    titleFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        tile = true
    })
    
    -- Move the existing header into our new title frame
    RaidSummonPlus_SoulstoneHeader:SetParent(titleFrame)
    RaidSummonPlus_SoulstoneHeader:ClearAllPoints()
    RaidSummonPlus_SoulstoneHeader:SetPoint("TOPLEFT", titleFrame, "TOPLEFT", 3, -2)
    
    -- Adjust the "None" text position
    if RaidSummonPlus_SoulstoneText then
        RaidSummonPlus_SoulstoneText:ClearAllPoints()
        RaidSummonPlus_SoulstoneText:SetPoint("TOPLEFT", RaidSummonPlus_SoulstoneFrame, "TOPLEFT", 8, -23)
    end
    
    -- Get the main headline font properties directly
    if RaidSummonPlus_RequestFrame_Header then
        -- Get the exact font info from the main header
        local fontFile, fontSize, fontFlags = RaidSummonPlus_RequestFrame_Header:GetFont()
        
        if fontFile then
            -- Apply the same font file and flags, but ensure the size matches exactly
            RaidSummonPlus_SoulstoneHeader:SetFont(fontFile, fontSize, fontFlags)
            
            -- Match the text color too
            local r, g, b, a = RaidSummonPlus_RequestFrame_Header:GetTextColor()
            RaidSummonPlus_SoulstoneHeader:SetTextColor(r, g, b, a or 1.0)
        else
            -- Fallback with the exact font defined in XML (RaidSummonPlus_GameFontHeader)
            RaidSummonPlus_SoulstoneHeader:SetFont("Interface\\AddOns\\RaidSummonPlus\\fonts\\Expressway.ttf", 11)
            RaidSummonPlus_SoulstoneHeader:SetTextColor(1, 1, 1, 1)
        end
    else
        -- Ensure we use the same font as defined in XML
        RaidSummonPlus_SoulstoneHeader:SetFont("Interface\\AddOns\\RaidSummonPlus\\fonts\\Expressway.ttf", 11)
        RaidSummonPlus_SoulstoneHeader:SetTextColor(1, 1, 1, 1)
    end
    
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Created matching title bar for soulstone section")
    end
end

-- Variable to track previous frame state to avoid repeated messages
local FRAME_VISIBILITY_STATE = nil
local RaidSummonPlusSoulstone_LastLoggedState = nil

-- Function to update the soulstone display with styled buttons
function RaidSummonPlusSoulstone_UpdateDisplay()
    -- Safety check for UI elements
    if not RaidSummonPlus_SoulstoneHeader or not RaidSummonPlus_SoulstoneText then
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Error - UI elements not initialized")
        end
        return
    end
    
    -- Count active and expired entries
    local currentTime = GetTime()
    local activeCount = 0
    local expiredCount = 0
    
    for i = 1, table.getn(SOULSTONE_DATA) do
        if SOULSTONE_DATA[i].status == SOULSTONE_STATUS.ACTIVE then
            activeCount = activeCount + 1
        else
            expiredCount = expiredCount + 1
        end
    end
    
    -- Update the header to just show "Soulstones" without counts
    RaidSummonPlus_SoulstoneHeader:SetText("Soulstones")
    
    -- Hide all soulstone entry buttons first
    for i = 1, 5 do -- Assuming we'll show up to 5 soulstones max
        local buttonName = "RaidSummonPlus_Soulstone"..i
        local button = getglobal(buttonName)
        if button then
            button:Hide()
            -- Clear any existing click handler
            button:SetScript("OnClick", nil)
        end
    end
    
    -- Always hide the "None" text - we'll just use empty space instead
    RaidSummonPlus_SoulstoneText:Hide()
    
    -- Define a custom sort function to put active soulstones first, then expired, both sorted by expiry
    local function customSort(a, b)
        if a.status ~= b.status then
            return a.status < b.status  -- ACTIVE (1) comes before EXPIRED (2)
        else
            return a.expiry < b.expiry  -- Sort by expiry time (most urgent first)
        end
    end
    
    -- Make a copy to sort (avoid modifying original table directly)
    local sortedData = {}
    for i = 1, table.getn(SOULSTONE_DATA) do
        sortedData[i] = SOULSTONE_DATA[i]
    end
    
    -- Sort the data
    for i = 1, table.getn(sortedData) do
        for j = i + 1, table.getn(sortedData) do
            if customSort(sortedData[j], sortedData[i]) then
                local temp = sortedData[i]
                sortedData[i] = sortedData[j]
                sortedData[j] = temp
            end
        end
    end
    
    -- Show and update each entry button
    local displayCount = math.min(table.getn(sortedData), 5) -- Max 5 visible stones
    for i = 1, displayCount do
        local buttonName = "RaidSummonPlus_Soulstone"..i
        local button = getglobal(buttonName)
        if not button then
            -- Skip if button doesn't exist
            if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Button " .. buttonName .. " not found")
            end
            break
        end
        
        local entry = sortedData[i]
        local name = entry.name
        local displayText = name
        
        -- Show countdown timer ONLY for self-cast soulstones (like PallyPower)
        if entry.status == SOULSTONE_STATUS.ACTIVE then
            if entry.isSelfCast and SOULSTONE_CAST_TIMERS[name] then
                -- Show timer for self-cast soulstones
                local timeString = RaidSummonPlusSoulstone_FormatTime(SOULSTONE_CAST_TIMERS[name])
                displayText = name .. " (" .. timeString .. ")"
            else
                -- No timer for detected buffs - just show name (color indicates status)
                displayText = name
            end
        end
        
        -- Get the player's class if in raid/party
        local playerClass = nil
        
        -- First check if it's the player themselves
        if name == UnitName("player") then
            playerClass = UnitClass("player")
        -- Check raid roster
        elseif UnitInRaid("player") then
            for j = 1, GetNumRaidMembers() do
                local raidName, _, _, _, raidClass = GetRaidRosterInfo(j)
                if raidName == name then
                    playerClass = raidClass
                    break
                end
            end
        -- Check party members
        elseif GetNumPartyMembers() > 0 then
            for j = 1, GetNumPartyMembers() do
                local partyUnit = "party"..j
                if UnitName(partyUnit) == name then
                    playerClass = UnitClass(partyUnit)
                    break
                end
            end
        end
        
        -- Set text
        local textName = getglobal(buttonName.."TextName")
        if textName then
            textName:SetText(displayText)
            
            -- Clean color scheme: Class color for active, Red for expired
            if entry.status == SOULSTONE_STATUS.EXPIRED then
                -- Red for expired soulstones
                textName:SetTextColor(1, 0, 0, 1)
            elseif playerClass then
                -- Class color for ALL active soulstones (with or without countdown)
                local c = RaidSummonPlus_GetClassColour(string.upper(playerClass))
                textName:SetTextColor(c.r, c.g, c.b, 1)
            else
                -- Fallback: White for active soulstones without class info
                textName:SetTextColor(1, 1, 1, 1) -- White
            end
        end
        
        -- Set up the click handler based on status
        local playerName = name -- Store the name for closure
        local entryStatus = entry.status -- Store the status for closure
        
        -- Fix: Vanilla WoW uses different click handler format
        button:SetScript("OnClick", function()
            -- In Vanilla WoW, arg1 is the button clicked
            if arg1 == "LeftButton" then
                if entryStatus == SOULSTONE_STATUS.EXPIRED then
                    -- For expired soulstones, try to apply a new one
                    if RaidSummonPlusOptions.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Left-click on expired soulstone for " .. playerName)
                    end
                    local success, message = RaidSummonPlusSoulstone_TrySoulstoneTarget(playerName)
                    
                    -- Only display the message if it's not nil and debug is enabled
                    if message then
                        RaidSummonPlusSoulstone_DebugMessage(message)
                    end
                else
                    -- For active soulstones, just target the player
                    if RaidSummonPlusOptions.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Targeting " .. playerName)
                    end
                    
                    local targetFound = false
                    
                    -- If in raid, use raid targeting
                    if UnitInRaid("player") then
                        for j = 1, GetNumRaidMembers() do
                            local raidName = GetRaidRosterInfo(j)
                            if raidName == playerName then
                                TargetUnit("raid"..j)
                                targetFound = true
                                break
                            end
                        end
                    end
                    
                    -- If not found in raid, check party
                    if not targetFound and GetNumPartyMembers() > 0 then
                        for j = 1, GetNumPartyMembers() do
                            if UnitName("party"..j) == playerName then
                                TargetUnit("party"..j)
                                targetFound = true
                                break
                            end
                        end
                    end
                    
                    -- If still not found, check if it's the player
                    if not targetFound and UnitName("player") == playerName then
                        TargetUnit("player")
                        targetFound = true
                    end
                    
                    -- Debug message if target not found
                    if not targetFound and RaidSummonPlusOptions.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Could not target " .. playerName)
                    end
                end
            elseif arg1 == "RightButton" then
                -- Remove the entry from the list
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Removing " .. playerName .. " from soulstone list")
                end
                
                for i = 1, table.getn(SOULSTONE_DATA) do
                    if SOULSTONE_DATA[i].name == playerName then
                        table.remove(SOULSTONE_DATA, i)
                        
                        -- Check if this was the last entry and summon list is empty
                        if table.getn(SOULSTONE_DATA) == 0 and table.getn(RaidSummonPlusDB or {}) == 0 then
                            -- Hide the frame and update visibility state
                            if RaidSummonPlus_RequestFrame then
                                RaidSummonPlus_RequestFrame:Hide()
                                FRAME_VISIBILITY_STATE = "HIDDEN"
                                
                                if RaidSummonPlusOptions.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hiding frame - no soulstones or summons left")
                                end
                            end
                        end
                        
                        RaidSummonPlusSoulstone_UpdateDisplay()
                        break
                    end
                end
            end
        end)
        
        -- Show the button
        button:Show()
    end
    
    -- Update frame layout after displaying soulstones
    RaidSummonPlus_FixFrameLayout()
    
    -- Set up hover effects after updating the display
    RaidSummonPlus_SetupAllButtonHoverEffects()
    
    -- Check if the frame should be shown based on soulstone status
    -- Only when summon list is empty
    if RaidSummonPlusDB and table.getn(RaidSummonPlusDB) == 0 then
        if RaidSummonPlus_RequestFrame then
            -- Count active and expired soulstones
            local activeCount = 0
            local expiredCount = 0
            for i = 1, table.getn(SOULSTONE_DATA) do
                if SOULSTONE_DATA[i].status == SOULSTONE_STATUS.ACTIVE then
                    activeCount = activeCount + 1
                else
                    expiredCount = expiredCount + 1
                end
            end
            
            -- Frame should only show when NO active soulstones remain (but expired ones exist)
            local shouldShowFrame = (activeCount == 0 and expiredCount > 0)
            local shouldHideFrame = (activeCount == 0 and expiredCount == 0)
            
            -- Debug logging for visibility decisions
            if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                if activeCount > 0 then
                    -- Don't spam when soulstones are active, but log state occasionally
                    if not RaidSummonPlusSoulstone_LastLoggedState or RaidSummonPlusSoulstone_LastLoggedState ~= "ACTIVE_STONES" then
                        RaidSummonPlusSoulstone_DebugMessage("Frame hidden - " .. activeCount .. " active soulstone(s) remain")
                        RaidSummonPlusSoulstone_LastLoggedState = "ACTIVE_STONES"
                    end
                end
            end
            
            -- Track state changes to avoid redundant messages
            if shouldShowFrame then
                -- Only take action if state is changing
                if FRAME_VISIBILITY_STATE ~= "SHOWN" then
                    ShowUIPanel(RaidSummonPlus_RequestFrame, 1)
                    FRAME_VISIBILITY_STATE = "SHOWN"
                    RaidSummonPlusSoulstone_LastLoggedState = "SHOWN"
                    
                    -- Only print debug message when state changes
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Showing frame - ALL soulstones expired (" .. activeCount .. " active, " .. expiredCount .. " expired)")
                    end
                end
            elseif shouldHideFrame then
                -- Hide the frame if there are no soulstones and no summons
                if FRAME_VISIBILITY_STATE ~= "HIDDEN" then
                    RaidSummonPlus_RequestFrame:Hide()
                    FRAME_VISIBILITY_STATE = "HIDDEN"
                    RaidSummonPlusSoulstone_LastLoggedState = "HIDDEN"
                    
                    -- Only print debug message when state changes
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hiding frame - no soulstones or summons (" .. activeCount .. " active, " .. expiredCount .. " expired)")
                    end
                end
            end
        end
    end
end

-- Process an addon message for soulstone data
function RaidSummonPlusSoulstone_ProcessMessage(message, sender)
    -- Handle Soulstone messages using simple, safe string operations
    local colonPos = string.find(message, ":")
    if colonPos then
        local target = string.sub(message, 1, colonPos - 1)
        local rest = string.sub(message, colonPos + 1)
        local secondColonPos = string.find(rest, ":")
        
        -- Validate target name and ensure they're in the group
        if not target or target == "" or target == "unknown" or not RaidSummonPlus_IsPlayerInGroup(target) then
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Ignoring soulstone message for invalid or non-group player: " .. tostring(target))
            end
            return
        end
        
        -- Handle both new format (with self-cast flag) and old format
        local expiry, isSelfCast
        if secondColonPos then
            -- New format with self-cast flag
            expiry = tonumber(string.sub(rest, 1, secondColonPos - 1))
            isSelfCast = (string.sub(rest, secondColonPos + 1) == "1")
        else
            -- Old format without self-cast flag (assume not self-cast)
            expiry = tonumber(rest)
            isSelfCast = false
        end
        
        if target and expiry then
            -- Check if this player already exists in our tracking table
            local found = false
            for i = 1, table.getn(SOULSTONE_DATA) do
                if SOULSTONE_DATA[i].name == target then
                    -- Only update if the received data is newer (active beats expired)
                    if SOULSTONE_DATA[i].status == SOULSTONE_STATUS.EXPIRED or expiry > SOULSTONE_DATA[i].expiry then
                        SOULSTONE_DATA[i].expiry = expiry
                        SOULSTONE_DATA[i].isSelfCast = isSelfCast
                        SOULSTONE_DATA[i].status = SOULSTONE_STATUS.ACTIVE
                    end
                    found = true
                    break
                end
            end
            
            -- Add new entry if not found
            if not found then
                table.insert(SOULSTONE_DATA, {
                    name = target,
                    expiry = expiry,
                    isSelfCast = isSelfCast,
                    status = SOULSTONE_STATUS.ACTIVE
                })
            end
            
            -- Update the display
            RaidSummonPlusSoulstone_UpdateDisplay()
            
            -- Start the timer if not already running
            if not SOULSTONE_TIMER_ACTIVE then
                RaidSummonPlusSoulstone_StartTimer()
            end
        end
    end
end

-- Handle soulstone related events with improved status updating
local LAST_ERROR_MESSAGE_TIME = 0
local ERROR_MESSAGE_COOLDOWN = 2.0 -- Only show one error message every 2 seconds

-- Variables to track soulstone usage attempts
SOULSTONE_ATTEMPT_ACTIVE = false
SOULSTONE_ATTEMPT_TARGET = nil
SOULSTONE_ATTEMPT_TIME = 0
local SOULSTONE_ATTEMPT_TIMEOUT = 1.0 -- Timeout after 1 second

-- Function to check if any soulstone item is on cooldown
function RaidSummonPlusSoulstone_IsAnySoulstoneOnCooldown()
    -- Check in bags first
    local hasSoulstone, bag, slot, stoneName = RaidSummonPlusSoulstone_HasStoneInInventory()
    if hasSoulstone then
        local start, duration, enable = GetContainerItemCooldown(bag, slot)
        if start > 0 and duration > 0 then
            return true
        end
    end
    
    -- Check for soulstone names in all bags
    for _, spellData in ipairs(SOULSTONE_CREATION_SPELLS) do
        for bag = 0, 4 do
            for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, spellData.itemName) then
                    local start, duration, enable = GetContainerItemCooldown(bag, slot)
                    if start > 0 and duration > 0 then
                        return true
                    end
                end
            end
        end
    end
    
    -- Check worn items too
    for slot = 0, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            for _, spellData in ipairs(SOULSTONE_CREATION_SPELLS) do
                if string.find(link, spellData.itemName) then
                    local start, duration, enable = GetInventoryItemCooldown("player", slot)
                    if start > 0 and duration > 0 then
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

-- Main handler function for soulstone-related events
function RaidSummonPlusSoulstone_HandleEvent(event, ...)
    -- Check if we need to clear a stale attempt
    if SOULSTONE_ATTEMPT_ACTIVE and GetTime() - SOULSTONE_ATTEMPT_TIME > SOULSTONE_ATTEMPT_TIMEOUT then
        -- Our attempt has timed out with no error - must have succeeded
        if SOULSTONE_ATTEMPT_TARGET then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Using Soulstone on " .. SOULSTONE_ATTEMPT_TARGET)
        end
        SOULSTONE_ATTEMPT_ACTIVE = false
        SOULSTONE_ATTEMPT_TARGET = nil
    end

    -- Handle buff application events
    if event == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS" or
       event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" or
       event == "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS" then
        
        local message = arg1
        
        -- Check for Soulstone buff application
        for i = 1, table.getn(SOULSTONE_BUFF_NAMES) do
            local buffName = SOULSTONE_BUFF_NAMES[i]
            local gainPattern = " gains " .. buffName
            local startIndex = string.find(message, gainPattern)
            
            if startIndex then
                -- Extract player name (everything before " gains ")
                local targetName = string.sub(message, 1, startIndex - 1)
                
                -- Only process if player is in group
                if targetName and string.len(targetName) > 0 and RaidSummonPlus_IsPlayerInGroup(targetName) then
                    -- Apply the soulstone tracking
                    RaidSummonPlusSoulstone_Apply(targetName, UnitName("player"))
                    
                    -- Find this player in our tracking data and update status immediately
                    local found = false
                    for j = 1, table.getn(SOULSTONE_DATA) do
                        if SOULSTONE_DATA[j].name == targetName then
                            -- If this was an expired entry, update UI after changing status
                            local wasExpired = (SOULSTONE_DATA[j].status == SOULSTONE_STATUS.EXPIRED)
                            
                            -- Update to active status and reset expiry
                            SOULSTONE_DATA[j].status = SOULSTONE_STATUS.ACTIVE
                            SOULSTONE_DATA[j].expiry = GetTime() + SOULSTONE_DURATION
                            
                            -- Update UI immediately if status changed
                            if wasExpired then
                                RaidSummonPlusSoulstone_UpdateDisplay()
                                if RaidSummonPlusOptions.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Updated " .. targetName .. " status to ACTIVE")
                                end
                            end
                            
                            found = true
                            break
                        end
                    end
                    
                    -- If player wasn't in our list, add them
                    if not found then
                        table.insert(SOULSTONE_DATA, {
                            name = targetName,
                            expiry = GetTime() + SOULSTONE_DURATION,
                            isSelfCast = (UnitName("player") == UnitName("target")),
                            status = SOULSTONE_STATUS.ACTIVE
                        })
                        
                        -- Update display with the new entry
                        RaidSummonPlusSoulstone_UpdateDisplay()
                    end
                elseif RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Ignoring soulstone on non-group member: " .. targetName)
                end
                
                break
            end
        end
    elseif event == "UNIT_AURA" and arg1 then
        -- Only check for soulstone if unit is player, in party, or in raid
        local unitName = UnitName(arg1)
        if unitName and UnitIsPlayer(arg1) and RaidSummonPlus_IsPlayerInGroup(unitName) then
            -- Now check for soulstone only after confirming they're in our group
            local buffIndex = RaidSummonPlusSoulstone_CheckForBuff(arg1)
            if buffIndex then
                -- Check if this player exists in our tracking data
                local found = false
                for i = 1, table.getn(SOULSTONE_DATA) do
                    if SOULSTONE_DATA[i].name == unitName then
                        -- If this was expired, update status and refresh UI
                        local wasExpired = (SOULSTONE_DATA[i].status == SOULSTONE_STATUS.EXPIRED)
                        
                        -- Update to active status
                        SOULSTONE_DATA[i].status = SOULSTONE_STATUS.ACTIVE
                        SOULSTONE_DATA[i].expiry = GetTime() + SOULSTONE_DURATION
                        
                        -- Update UI immediately if status changed
                        if wasExpired then
                            RaidSummonPlusSoulstone_UpdateDisplay()
                            if RaidSummonPlusOptions.debug then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Updated " .. unitName .. " status to ACTIVE via UNIT_AURA")
                            end
                        end
                        
                        found = true
                        break
                    end
                end
                
                -- If not found, add them
                if not found then
                    RaidSummonPlusSoulstone_Apply(unitName, UnitName("player"))
                    
                    if RaidSummonPlusOptions.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Detected Soulstone on " .. unitName .. " via UNIT_AURA")
                    end
                end
            end
        end
    elseif event == "SPELLCAST_START" then
        -- Check for Soulstone cast
        for _, buffName in ipairs(SOULSTONE_BUFF_NAMES) do
            if string.find(arg1 or "", buffName) then
                if UnitExists("target") and UnitIsPlayer("target") then
                    -- Store the target name, we'll confirm the buff in UNIT_AURA or buff message events
                    if RaidSummonPlusOptions.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Detected Soulstone cast on " .. UnitName("target"))
                    end
                end
                break
            end
        end
    elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" or event == "UI_ERROR_MESSAGE" then
        -- Get the error message
        local message = arg1
        local currentTime = GetTime()
        
        -- IMPROVED COOLDOWN DETECTION - better than previous solution
        local isSoulstoneError = false
        
        -- First check: Explicit mentions of soulstone in the error
        if (string.find(message, "[Ss]oulstone") or string.find(message, "Resurrection")) and 
           (string.find(message, "not ready") or string.find(message, "cooldown")) then
            isSoulstoneError = true
        -- Second check: We were actively trying to use a soulstone
        elseif SOULSTONE_ATTEMPT_ACTIVE and 
              (string.find(message, "Item is not ready yet") or string.find(message, "isn't ready")) then
            isSoulstoneError = true
        -- REMOVED: Third check that caused false positives with Hearthstone and other items
        -- This was checking ALL items with cooldowns, not just soulstones
        end
        
        -- Exit early if it's not a soulstone error
        if not isSoulstoneError then
            return
        end
        
        -- Only process error messages if we're past the cooldown period
        if currentTime - LAST_ERROR_MESSAGE_TIME < ERROR_MESSAGE_COOLDOWN then
            return
        end
        
        -- This is a non-suppressed soulstone error, show the message
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : |cffff0000Soulstone is on cooldown|r - Cannot use it yet")
        LAST_ERROR_MESSAGE_TIME = currentTime
        
        -- Clear any active soulstone attempt since it failed
        SOULSTONE_ATTEMPT_ACTIVE = false
        SOULSTONE_ATTEMPT_TARGET = nil
    end
end