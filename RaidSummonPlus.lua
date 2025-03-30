-- RaidSummonPlus.lua
-- Enhanced version of RaidSummon addon with persistent window position, improved frame visibility, and combat detection
-- WoW 1.12.1 (Vanilla) compatible version

-- Variables for tracking summon status
local SUMMON_PENDING = false
local SUMMON_TARGET = nil
local SUMMON_TIMER = nil
local SUMMON_FAIL_REASON = nil
local SUMMON_MESSAGES = {}
local RITUAL_OF_SUMMONING_SPELL_ID = 698 -- Spell ID for Ritual of Summoning

-- Auto-check constants and variables
local AUTO_CHECK_INTERVAL = 5.0 -- Check every 5 seconds
local AUTO_CHECK_FRAME = nil
local LAST_AUTO_CHECK_TIME = 0
local LAST_CHECKED_PLAYERS = {} -- Cache of recently checked players
local CHECK_CACHE_DURATION = 3.0 -- Only recheck players after 3 seconds

local RaidSummonPlusOptions_DefaultSettings = {
    whisper = true,
    zone    = true,
    shards  = true,
    debug   = false,
    ritual  = true,    -- New option for Ritual of Souls announcements, on by default
    frameX  = nil,     -- Position coordinates
    frameY  = nil,     -- Position coordinates
    framePoint = nil,  -- Anchor point
    frameRelativePoint = nil  -- Relative anchor point
}

-- Event registration function
function RaidSummonPlus_EventFrame_OnLoad()
    -- Register standard events
    this:RegisterEvent("VARIABLES_LOADED")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("CHAT_MSG_ADDON")
    this:RegisterEvent("CHAT_MSG_RAID")
    this:RegisterEvent("CHAT_MSG_RAID_LEADER")
    this:RegisterEvent("CHAT_MSG_SAY")
    this:RegisterEvent("CHAT_MSG_YELL")
    this:RegisterEvent("CHAT_MSG_WHISPER")
    this:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
    this:RegisterEvent("SPELLCAST_START")
    
    -- Add detection for other warlocks casting Ritual of Summoning
    this:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
    
    -- Register events for Soulstone tracking
    this:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
    this:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
    this:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
    this:RegisterEvent("UNIT_AURA")
    
    -- Add UI error event for cooldown detection
    this:RegisterEvent("UI_ERROR_MESSAGE")
    
    -- Commands
    SlashCmdList["RAIDSUMMONPLUS"] = RaidSummonPlus_SlashCommand
    SLASH_RAIDSUMMONPLUS1 = "/raidsummonplus"
    SLASH_RAIDSUMMONPLUS2 = "/rsp"
    -- Maintain compatibility with old commands
    SlashCmdList["RAIDSUMMON"] = RaidSummonPlus_SlashCommand
    SLASH_RAIDSUMMON1 = "/raidsummon"
    SLASH_RAIDSUMMON2 = "/rs"
    MSG_PREFIX_ADD        = "RSPAdd"
    MSG_PREFIX_REMOVE    = "RSPRemove"
    MSG_PREFIX_SOULSTONE = "RSPSoulstone"
    RaidSummonPlusDB = {}
    RaidSummonPlusLoc_Header = "RaidSummonPlus"
    
    -- Force hide frame on load
    if RaidSummonPlus_RequestFrame then
        RaidSummonPlus_RequestFrame:Hide()
    end
end

-- Create auto-check frame and handler
function RaidSummonPlus_InitAutoCheck()
    -- Skip if not a warlock
    if UnitClass("player") ~= "Warlock" then
        return
    end
    
    -- Create a timer frame if it doesn't exist
    if not AUTO_CHECK_FRAME then
        AUTO_CHECK_FRAME = CreateFrame("Frame")
        AUTO_CHECK_FRAME.elapsed = 0
        
        AUTO_CHECK_FRAME:SetScript("OnUpdate", function()
            -- Skip if in combat to prevent performance issues
            if InCombatLockdown and InCombatLockdown() then
                return
            end
            
            -- Skip if no summon list (most common performance optimization)
            if not RaidSummonPlusDB or table.getn(RaidSummonPlusDB) == 0 then
                return
            end
            
            -- Simple counter increment
            local elapsed = arg1
            this.elapsed = this.elapsed + elapsed
            
            -- Check if it's time to perform the auto-check
            if this.elapsed > AUTO_CHECK_INTERVAL then
                this.elapsed = 0
                -- Perform the check
                RaidSummonPlus_AutoCheckNearbyPlayers()
            end
        end)
        
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Auto-check initialized (" .. AUTO_CHECK_INTERVAL .. "s interval)")
        end
    end
end

-- Function to check if players in summon list are nearby
function RaidSummonPlus_AutoCheckNearbyPlayers()
    -- Early exit conditions - performance optimization
    if not RaidSummonPlusDB or table.getn(RaidSummonPlusDB) == 0 then
        return
    end
    
    -- Only check if we're in a group
    if not UnitInRaid("player") and GetNumPartyMembers() == 0 then
        return
    end
    
    -- Performance: Only update player cache every few seconds
    local currentTime = GetTime()
    if currentTime - LAST_AUTO_CHECK_TIME < 1.0 then
        return -- Throttle checks to prevent excessive function calls
    end
    LAST_AUTO_CHECK_TIME = currentTime
    
    -- Save current target to restore after checks
    local originalTarget = nil
    if UnitExists("target") then
        originalTarget = UnitName("target")
    end
    
    local playersRemoved = 0
    
    -- Get raid member data for targeting - only once per check
    RaidSummonPlus_GetRaidMembers()
    
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Running auto-check for nearby players...")
    end
    
    -- Create a copy of the summon list to avoid issues with removing while iterating
    local playersToCheck = {}
    for i, v in ipairs(RaidSummonPlusDB) do
        -- Performance: Skip players we checked recently
        if not LAST_CHECKED_PLAYERS[v] or 
           (currentTime - LAST_CHECKED_PLAYERS[v]) > CHECK_CACHE_DURATION then
            table.insert(playersToCheck, v)
        end
    end
    
    -- Check each player in the list - limit checks to 3 players per cycle for performance
    local checksThisCycle = 0
    local maxChecksPerCycle = 3 -- Only check up to 3 players each time to spread the work
    
    for _, playerName in ipairs(playersToCheck) do
        -- Only process a limited number of players each cycle
        checksThisCycle = checksThisCycle + 1
        if checksThisCycle > maxChecksPerCycle then
            break
        end
        
        -- Record that we checked this player
        LAST_CHECKED_PLAYERS[playerName] = currentTime
        
        local UnitID = nil
        
        -- Find the player's raid/party UnitID
        if RaidSummonPlus_UnitIDDB then
            for i, v in ipairs(RaidSummonPlus_UnitIDDB) do
                if v.rName == playerName then
                    UnitID = "raid"..v.rIndex
                    break
                end
            end
        end
        
        -- Only continue if we found a valid UnitID
        if UnitID then
            -- Target the player
            TargetUnit(UnitID)
            
            -- Check if they're in range
            if Check_TargetInRange() then
                -- Player is in range, remove from summon list
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : <" .. playerName .. "> has been summoned already (|cffff0000in range|r)")
                
                -- Remove from list
                for i, v in ipairs(RaidSummonPlusDB) do
                    if v == playerName then
                        SendAddonMessage(MSG_PREFIX_REMOVE, playerName, "RAID")
                        table.remove(RaidSummonPlusDB, i)
                        playersRemoved = playersRemoved + 1
                        break
                    end
                end
            elseif RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Auto-check: <" .. playerName .. "> is not in range")
            end
        end
    end
    
    -- Restore original target if possible
    if originalTarget then
        TargetByName(originalTarget)
    else
        ClearTarget()
    end
    
    -- Update the UI if we removed any players
    if playersRemoved > 0 then
        RaidSummonPlus_UpdateList()
    end
    
    -- Clean up old entries from LAST_CHECKED_PLAYERS
    for player, lastTime in LAST_CHECKED_PLAYERS do
        if currentTime - lastTime > CHECK_CACHE_DURATION * 2 then
            LAST_CHECKED_PLAYERS[player] = nil
        end
    end
end

-- Helper function to check if a player is in our group (raid or party)
function RaidSummonPlus_IsPlayerInGroup(playerName)
    -- Check if it's the player themselves
    if playerName == UnitName("player") then
        return true
    end
    
    -- Check if in raid
    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid"..i)
            if name == playerName then
                return true
            end
        end
    -- Check if in party
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party"..i)
            if name == playerName then
                return true
            end
        end
    end
    
    return false
end

-- Set up hover effects for all buttons in the addon with debug throttling and better red handling
local LAST_HOVER_DEBUG_TIME = 0
local HOVER_DEBUG_COOLDOWN = 0.5 -- Only log hover debug every 0.5 seconds

function RaidSummonPlus_SetupAllButtonHoverEffects()
    -- Apply to all summon list buttons
    for i = 1, 10 do
        local button = getglobal("RaidSummonPlus_NameList" .. i)
        if button then
            -- Clear any existing handlers 
            button:SetScript("OnEnter", nil)
            button:SetScript("OnLeave", nil)
            
            -- Set up actual hover handlers
            button:SetScript("OnEnter", function()
                local textName = getglobal(this:GetName() .. "TextName")
                if textName then
                    -- Store original color
                    local r, g, b, a = textName:GetTextColor()
                    this.originalColor = {r = r, g = g, b = b, a = a or 1.0}
                    
                    -- Special handling for red text (expired soulstones)
                    if r > 0.9 and g < 0.2 and b < 0.2 then
                        -- For red text, add orange glow by increasing green component
                        textName:SetTextColor(1.0, 0.5, 0.0, a or 1.0)
                    else
                        -- Standard brightening for non-red text
                        textName:SetTextColor(
                            math.min(1.0, r * 1.5),
                            math.min(1.0, g * 1.5),
                            math.min(1.0, b * 1.5),
                            a or 1.0
                        )
                    end
                    
                    -- Throttled debug message for hover events
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        local currentTime = GetTime()
                        if currentTime - LAST_HOVER_DEBUG_TIME > HOVER_DEBUG_COOLDOWN then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : OnEnter triggered for " .. this:GetName())
                            LAST_HOVER_DEBUG_TIME = currentTime
                        end
                    end
                end
            end)
            
            button:SetScript("OnLeave", function()
                local textName = getglobal(this:GetName() .. "TextName")
                if textName and this.originalColor then
                    -- Restore original color
                    textName:SetTextColor(
                        this.originalColor.r,
                        this.originalColor.g,
                        this.originalColor.b,
                        this.originalColor.a
                    )
                    
                    -- Throttled debug message for hover events
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        local currentTime = GetTime()
                        if currentTime - LAST_HOVER_DEBUG_TIME > HOVER_DEBUG_COOLDOWN then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : OnLeave triggered for " .. this:GetName())
                            LAST_HOVER_DEBUG_TIME = currentTime
                        end
                    end
                end
            end)
        end
    end
    
    -- Apply to all soulstone buttons too (for consistency)
    for i = 1, 5 do
        local button = getglobal("RaidSummonPlus_Soulstone" .. i)
        if button then
            -- Clear any existing handlers
            button:SetScript("OnEnter", nil)
            button:SetScript("OnLeave", nil)
            
            -- Set up actual hover handlers
            button:SetScript("OnEnter", function()
                local textName = getglobal(this:GetName() .. "TextName")
                if textName then
                    -- Store original color
                    local r, g, b, a = textName:GetTextColor()
                    this.originalColor = {r = r, g = g, b = b, a = a or 1.0}
                    
                    -- Special handling for red text (expired soulstones)
                    if r > 0.9 and g < 0.2 and b < 0.2 then
                        -- For red text, add orange glow by increasing green component
                        textName:SetTextColor(1.0, 0.5, 0.0, a or 1.0)
                    else
                        -- Standard brightening for non-red text
                        textName:SetTextColor(
                            math.min(1.0, r * 1.5),
                            math.min(1.0, g * 1.5),
                            math.min(1.0, b * 1.5),
                            a or 1.0
                        )
                    end
                    
                    -- Throttled debug message for hover events
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        local currentTime = GetTime()
                        if currentTime - LAST_HOVER_DEBUG_TIME > HOVER_DEBUG_COOLDOWN then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : OnEnter triggered for " .. this:GetName())
                            LAST_HOVER_DEBUG_TIME = currentTime
                        end
                    end
                end
            end)
            
            button:SetScript("OnLeave", function()
                local textName = getglobal(this:GetName() .. "TextName")
                if textName and this.originalColor then
                    -- Restore original color
                    textName:SetTextColor(
                        this.originalColor.r,
                        this.originalColor.g,
                        this.originalColor.b,
                        this.originalColor.a
                    )
                    
                    -- Throttled debug message for hover events
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        local currentTime = GetTime()
                        if currentTime - LAST_HOVER_DEBUG_TIME > HOVER_DEBUG_COOLDOWN then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : OnLeave triggered for " .. this:GetName())
                            LAST_HOVER_DEBUG_TIME = currentTime
                        end
                    end
                end
            end)
        end
    end
end

-- Specific fix for dynamic frame heights - works with XML anchoring
function RaidSummonPlus_FixFrameLayout()
    -- Make sure frames exist
    if not RaidSummonPlus_RequestFrame or not RaidSummonPlus_SoulstoneFrame then
        return
    end
    
    -- Count visible items in each section
    local visibleSummonItems = 0
    for i=1,10 do
        if getglobal("RaidSummonPlus_NameList"..i):IsVisible() then
            visibleSummonItems = visibleSummonItems + 1
        end
    end
    
    local stoneCount = table.getn(SOULSTONE_DATA)
    local visibleSoulstoneItems = math.min(stoneCount, 5) -- Max 5 visible stones
    
    -- Track if layout changes are needed
    local needsUpdate = false
    
    -- Check if current layout values differ from previous values
    if not RaidSummonPlus_PreviousLayoutValues then
        RaidSummonPlus_PreviousLayoutValues = {
            summonItems = -1, -- Force initial update
            stoneItems = -1   -- Force initial update
        }
        needsUpdate = true
    else
        -- Only update when the number of items changes
        needsUpdate = (
            RaidSummonPlus_PreviousLayoutValues.summonItems ~= visibleSummonItems or
            RaidSummonPlus_PreviousLayoutValues.stoneItems ~= stoneCount
        )
    end
    
    -- Skip layout calculation if no update needed
    if not needsUpdate then
        return
    end
    
    -- Remember current values for next check
    RaidSummonPlus_PreviousLayoutValues.summonItems = visibleSummonItems
    RaidSummonPlus_PreviousLayoutValues.stoneItems = stoneCount
    
    -- Calculate heights - include ONLY their own content
    local mainHeaderHeight = 18   -- Header space
    local itemHeight = 16         -- Height of each item row
    
    -- Calculate frame heights - each frame only includes its own content
    local calculatedSummonHeight = mainHeaderHeight + (visibleSummonItems * itemHeight)
    local calculatedSoulstoneHeight = mainHeaderHeight  -- Start with just the header height
    
    -- Only add item heights if we have soulstones
    if stoneCount > 0 then
        calculatedSoulstoneHeight = calculatedSoulstoneHeight + (visibleSoulstoneItems * itemHeight)
    end
    
    -- Apply minimum heights
    local minSummonHeight = 100
    local minSoulstoneHeight = 40  -- Empty soulstone section should be at least 40px
    local summonFrameHeight = math.max(calculatedSummonHeight, minSummonHeight)
    local soulstoneFrameHeight = math.max(calculatedSoulstoneHeight, minSoulstoneHeight)
    
    -- Set heights appropriately
    RaidSummonPlus_RequestFrame:SetHeight(summonFrameHeight)
    RaidSummonPlus_SoulstoneFrame:SetHeight(soulstoneFrameHeight)
    
    -- Update the title frame width to match parent frame
    if RaidSummonPlus_SoulstoneTitleFrame then
        RaidSummonPlus_SoulstoneTitleFrame:SetWidth(RaidSummonPlus_SoulstoneFrame:GetWidth())
    end
end

local function RaidSummonPlus_Initialize()
    if not RaidSummonPlusOptions then
        RaidSummonPlusOptions = {}
    end
    for i in RaidSummonPlusOptions_DefaultSettings do
        if (RaidSummonPlusOptions[i] == nil) then
            RaidSummonPlusOptions[i] = RaidSummonPlusOptions_DefaultSettings[i]
        end
    end
    
    -- Initialize auto-check for nearby players
    RaidSummonPlus_InitAutoCheck()
    
    -- Register for logout/exit events to save position
    local logout_frame = CreateFrame("Frame")
    logout_frame:RegisterEvent("PLAYER_LOGOUT")
    logout_frame:SetScript("OnEvent", function()
        -- Save position when player logs out or exits game
        if event == "PLAYER_LOGOUT" and RaidSummonPlus_RequestFrame then
            RaidSummonPlus_SaveFramePosition()
        end
    end)
end

-- Save frame position to saved variables
function RaidSummonPlus_SaveFramePosition()
    if not RaidSummonPlus_RequestFrame then
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Cannot save position - frame not initialized")
        end
        return
    end
    
    if not RaidSummonPlus_RequestFrame:IsVisible() then
        return
    end
    
    local point, relativeTo, relativePoint, xOfs, yOfs = RaidSummonPlus_RequestFrame:GetPoint()
    if point and xOfs and yOfs then
        -- Store complete position data
        RaidSummonPlusOptions.framePoint = point
        RaidSummonPlusOptions.frameRelativePoint = relativePoint
        RaidSummonPlusOptions.frameX = xOfs
        RaidSummonPlusOptions.frameY = yOfs
        
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Position saved: " .. 
                point .. ", " .. tostring(xOfs) .. ", " .. tostring(yOfs))
        end
    end
end

-- Restore frame position from saved variables
function RaidSummonPlus_RestoreFramePosition()
    if not RaidSummonPlus_RequestFrame then
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Cannot restore position - frame not initialized")
        end
        return
    end
    
    if RaidSummonPlusOptions.frameX and RaidSummonPlusOptions.frameY then
        RaidSummonPlus_RequestFrame:ClearAllPoints()
        
        -- Use stored point values if available, otherwise default to CENTER
        local point = RaidSummonPlusOptions.framePoint or "CENTER"
        local relativePoint = RaidSummonPlusOptions.frameRelativePoint or "CENTER"
        
        RaidSummonPlus_RequestFrame:SetPoint(point, UIParent, relativePoint, 
                                           RaidSummonPlusOptions.frameX, 
                                           RaidSummonPlusOptions.frameY)
        
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Position restored: " .. 
                point .. ", " .. tostring(RaidSummonPlusOptions.frameX) .. ", " .. 
                tostring(RaidSummonPlusOptions.frameY))
        end
    end
end

-- Function to handle mouse entering a name list button - brighten the text color
function RaidSummonPlus_NameListButton_OnEnter()
    -- Get the text object for this button
    local textName = getglobal(this:GetName().."TextName")
    if textName then
        -- Store original color values
        local r, g, b, a = textName:GetTextColor()
        this.originalColor = {
            r = r,
            g = g,
            b = b,
            a = a or 1.0
        }
        
        -- Brighten text by 20%
        textName:SetTextColor(
            math.min(1.0, r * 1.2),
            math.min(1.0, g * 1.2),
            math.min(1.0, b * 1.2),
            a or 1.0
        )
    end
end

-- Function to handle mouse leaving a name list button - restore original color
function RaidSummonPlus_NameListButton_OnLeave()
    -- Get the text object for this button
    local textName = getglobal(this:GetName().."TextName")
    
    -- Restore original color if available
    if textName and this.originalColor then
        textName:SetTextColor(
            this.originalColor.r,
            this.originalColor.g,
            this.originalColor.b,
            this.originalColor.a
        )
    end
end

-- Initialize button for proper hover effect
function RaidSummonPlus_InitializeButton(button)
    -- We're not using this function anymore - it's replaced by RaidSummonPlus_SetupAllButtonHoverEffects
    -- Left for compatibility
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Old InitializeButton called for " .. button:GetName())
    end
end

-- Main event handler function for RaidSummonPlus - processes all addon events
function RaidSummonPlus_EventFrame_OnEvent()
    if event == "VARIABLES_LOADED" then
        this:UnregisterEvent("VARIABLES_LOADED")
        RaidSummonPlus_Initialize()

        -- Don't try to restore position immediately - delay it
        local waitFrame = CreateFrame("Frame")
        local counter = 0
        waitFrame:SetScript("OnUpdate", function()
            counter = counter + 1
            -- Wait a few frames for UI to initialize
            if counter > 5 and RaidSummonPlus_RequestFrame then
                RaidSummonPlus_RestoreFramePosition()
                waitFrame:SetScript("OnUpdate", nil)
                
                -- Ensure frame is hidden at startup
                RaidSummonPlus_RequestFrame:Hide()
                
                -- Initialize Soulstone frame if it exists
                if RaidSummonPlus_SoulstoneText then
                    RaidSummonPlus_SoulstoneText:SetText("None")
                    RaidSummonPlus_SoulstoneHeader:SetText("Soulstones")
                    RaidSummonPlus_SoulstoneFrame:Show()
                    
                    -- Initialize soulstone module
                    if RaidSummonPlusSoulstone_Initialize then
                        RaidSummonPlusSoulstone_Initialize()
                    end
                end
                
                -- Initialize Ritual of Souls module
                if RaidSummonPlusRitualofSouls_Initialize then
                    RaidSummonPlusRitualofSouls_Initialize()
                end
                
                -- Initialize hover effects
                RaidSummonPlus_SetupAllButtonHoverEffects()
            end
        end)
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Additional check to ensure frame stays hidden until needed
        if RaidSummonPlus_RequestFrame then
            if not RaidSummonPlusDB or table.getn(RaidSummonPlusDB) == 0 then
                RaidSummonPlus_RequestFrame:Hide()
            else
                -- Only update list if we actually have something to show
                RaidSummonPlus_UpdateList()
            end
        end
        
        -- Scan for existing Soulstones silently (no chat messages)
        if RaidSummonPlusSoulstone_ScanRaid then
            RaidSummonPlusSoulstone_ScanRaid(true)
        end
        
        -- Ensure hover effects are set up
        RaidSummonPlus_SetupAllButtonHoverEffects()
        
    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_WHISPER" then    
        if string.find(arg1, "^123") then
            -- Debug message to confirm detection
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Detected 123 from player: " .. arg2)
            end
            
            -- Add directly to our own list
            if not RaidSummonPlus_hasValue(RaidSummonPlusDB, arg2) and UnitName("player")~=arg2 then
                table.insert(RaidSummonPlusDB, arg2)
            end
            
            -- Sync with other addon users in raid
            SendAddonMessage(MSG_PREFIX_ADD, arg2, "RAID")
            
            -- Update the UI
            RaidSummonPlus_UpdateList()
        end
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == MSG_PREFIX_ADD then
            if not RaidSummonPlus_hasValue(RaidSummonPlusDB, arg2) and UnitName("player")~=arg2 then
                table.insert(RaidSummonPlusDB, arg2)
                RaidSummonPlus_UpdateList()
            end
        elseif arg1 == MSG_PREFIX_REMOVE then
            if RaidSummonPlus_hasValue(RaidSummonPlusDB, arg2) then
                for i, v in ipairs (RaidSummonPlusDB) do
                    if v == arg2 then
                        table.remove(RaidSummonPlusDB, i)
                        RaidSummonPlus_UpdateList()
                        break
                    end
                end
            end
        elseif arg1 == MSG_PREFIX_SOULSTONE then
            -- Forward to the soulstone module
            if RaidSummonPlusSoulstone_ProcessMessage then
                RaidSummonPlusSoulstone_ProcessMessage(arg2, arg4)
            end
        end
        
elseif event == "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF" then
        -- Check for Ritual of Summoning cast by other warlocks
        if string.find(arg1, "casts Ritual of Summoning") then
            -- Extract the warlock's name (everything before " casts")
            local warlockName = string.gsub(arg1, " casts Ritual of Summoning.*", "")
            
            -- Only process if warlock is in player's group and not the player themselves
            if warlockName and warlockName ~= UnitName("player") and RaidSummonPlus_IsPlayerInGroup(warlockName) then
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Detected " .. warlockName .. " casting Ritual of Summoning")
                end
                
                -- Find the warlock in the raid
                local warlockTarget = nil
                if UnitInRaid("player") then
                    for i = 1, GetNumRaidMembers() do
                        local raidUnit = "raid"..i
                        local raidName = UnitName(raidUnit)
                        
                        if raidName == warlockName then
                            -- Found the warlock, check their target
                            local targetUnit = raidUnit.."target"
                            if UnitExists(targetUnit) and UnitIsPlayer(targetUnit) then
                                warlockTarget = UnitName(targetUnit)
                                break
                            end
                        end
                    end
                elseif GetNumPartyMembers() > 0 then
                    -- Similar check for party members
                    for i = 1, GetNumPartyMembers() do
                        local partyUnit = "party"..i
                        local partyName = UnitName(partyUnit)
                        
                        if partyName == warlockName then
                            -- Found the warlock, check their target
                            local targetUnit = partyUnit.."target"
                            if UnitExists(targetUnit) and UnitIsPlayer(targetUnit) then
                                warlockTarget = UnitName(targetUnit)
                                break
                            end
                        end
                    end
                end
                
                -- More specific logic and clearer debug messages
                if warlockTarget then
                    if RaidSummonPlus_hasValue(RaidSummonPlusDB, warlockTarget) then
                        -- Target found and in our summon list - remove from list
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. warlockName .. " is summoning " .. warlockTarget .. " - removing from your list")
                        
                        for i, v in ipairs(RaidSummonPlusDB) do
                            if v == warlockTarget then
                                SendAddonMessage(MSG_PREFIX_REMOVE, warlockTarget, "RAID")
                                table.remove(RaidSummonPlusDB, i)
                                RaidSummonPlus_UpdateList()
                                break
                            end
                        end
                    elseif RaidSummonPlusOptions.debug then
                        -- Target found but not in our summon list
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. warlockName .. " is summoning " .. warlockTarget .. " (not in your summon list)")
                    end
                elseif RaidSummonPlusOptions.debug then
                    -- Could not determine target at all
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Could not determine " .. warlockName .. "'s target (no target or target not accessible)")
                end
            elseif RaidSummonPlusOptions.debug and warlockName and warlockName ~= UnitName("player") then
                -- Only log if debug is enabled and it's not the player themselves
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Ignoring summon from " .. warlockName .. " (not in your group/raid)")
            end
        end
        
    elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" then
        -- Check if we have a pending summon failure
        if SUMMON_PENDING and string.find(arg1, "Ritual of Summoning") then
            -- Extract failure reason
            SUMMON_FAIL_REASON = arg1
            
            -- Check for specific failure reasons
            if string.find(string.lower(arg1), "combat") then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : |cffff0000Failed to summon|r - " .. arg1)
                
                -- Always send combat failure message regardless of whisper setting
                if SUMMON_TARGET then
                    SendChatMessage("Summoning failed - You are in combat", "WHISPER", nil, SUMMON_TARGET)
                end
            elseif string.find(string.lower(arg1), "instance") then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : |cffff0000Failed to summon|r - " .. arg1)
                
                -- Always send instance failure message regardless of whisper setting
                if SUMMON_TARGET then
                    SendChatMessage("Summoning failed - You are not in the correct instance yet", "WHISPER", nil, SUMMON_TARGET)
                end
            else
                -- For any other failure reasons
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : |cffff0000Failed to summon|r - " .. arg1)
                end
            end
            
            -- Cancel the pending summon
            SUMMON_PENDING = false
            SUMMON_TARGET = nil
            
            -- Cancel timer if it's running
            if SUMMON_TIMER then
                SUMMON_TIMER = nil
            end
        end
        
        -- Check for soulstone cooldown failures and forward to soulstone module
        if string.find(arg1, "Soulstone") and RaidSummonPlusSoulstone_HandleEvent then
            RaidSummonPlusSoulstone_HandleEvent(event, arg1)
        end
        
    -- Handle Soulstone buff detection - simplified for WoW 1.12.1
    elseif event == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS" or
           event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" or
           event == "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS" or
           event == "UNIT_AURA" then
        
        -- Forward to the soulstone module
        if RaidSummonPlusSoulstone_HandleEvent then
            RaidSummonPlusSoulstone_HandleEvent(event, arg1, arg2, arg3, arg4)
        end
    
    -- Handle UI error messages for cooldowns and other errors
    elseif event == "UI_ERROR_MESSAGE" then
        -- Forward UI errors to the soulstone module
        if RaidSummonPlusSoulstone_HandleEvent then
            RaidSummonPlusSoulstone_HandleEvent(event, arg1)
        end
        
    elseif event == "SPELLCAST_START" then
        -- Add debug message to see what spell is being cast
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : SPELLCAST_START detected: " .. tostring(arg1))
        end
        
        -- Check if this is a manual Ritual of Summoning cast by player
        if arg1 == "Ritual of Summoning" or string.find(string.lower(arg1 or ""), "ritual of summoning") then
            -- First debug message: always show the cast detection (matches other warlock format)
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Detected " .. UnitName("player") .. " casting Ritual of Summoning")
            end

            -- Check if we have a valid target that's in our summon list
            if UnitExists("target") and UnitIsPlayer("target") then
                local targetName = UnitName("target")
                
                -- More specific logic and clearer debug messages (matching other warlock format)
                if RaidSummonPlus_hasValue(RaidSummonPlusDB, targetName) then
                    -- Target found and in our summon list - use same format as for other warlocks
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. UnitName("player") .. " is summoning " .. targetName .. " - removing from your list")
                    
                    -- Set up pending summon flags
                    SUMMON_PENDING = true
                    SUMMON_TARGET = targetName
                    
                    -- Set up messages identical to the click handler
                    local message, base_message, whisper_message, base_whisper_message, zone_message, subzone_message = ""
                    local bag, slot, texture, count = FindItem("Soul Shard")
                    
                    -- Prepare the summon messages
                    base_message = "Summoning <" .. targetName .. ">"
                    base_whisper_message = "Summoning you"
                    zone_message = " @" .. GetZoneText()
                    subzone_message = " @" .. GetSubZoneText()
                    shards_message = " [" .. count .. " shards]"
                    message = base_message
                    whisper_message = base_whisper_message

                    if RaidSummonPlusOptions.zone then
                        if GetSubZoneText() == "" then
                            message = message .. zone_message
                            whisper_message = base_whisper_message .. zone_message
                        else
                            message = message .. subzone_message
                            whisper_message = whisper_message .. subzone_message
                        end
                    end
                    
                    if RaidSummonPlusOptions.shards then
                        message = message .. shards_message
                    end
                    
                    -- Store messages for sending if summon is successful
                    SUMMON_MESSAGES = {
                        raid = message,
                        whisper = whisper_message
                    }
                    
                    -- Schedule a function to check if summon was successful
                    SUMMON_TIMER = true
                    
                    -- Initialize a timer to check for success after a brief delay
                    local startTime = GetTime()
                    local function checkSummonStatus()
                        if not SUMMON_PENDING then
                            -- A failure was already detected by the combat log event
                            return
                        end
                        
                        if GetTime() - startTime < 0.3 then
                            -- Still waiting, check again soon
                            return
                        end
                        
                        -- If we reach here, no failure was detected, so the summon seems successful
                        SUMMON_PENDING = false
                        SUMMON_TIMER = nil
                        
                        -- Send the messages
                        SendChatMessage(SUMMON_MESSAGES.raid, "RAID")
                        
                        if RaidSummonPlusOptions.whisper then
                            SendChatMessage(SUMMON_MESSAGES.whisper, "WHISPER", nil, SUMMON_TARGET)
                        end
                        
                        -- Remove the summoned target
                        for i, v in ipairs(RaidSummonPlusDB) do
                            if v == SUMMON_TARGET then
                                SendAddonMessage(MSG_PREFIX_REMOVE, SUMMON_TARGET, "RAID")
                                table.remove(RaidSummonPlusDB, i)
                                break
                            end
                        end
                        
                        RaidSummonPlus_UpdateList()
                        SUMMON_TARGET = nil
                    end
                    
                    -- Register our function to run on each frame update until the check is complete
                    local frame = CreateFrame("Frame")
                    frame:SetScript("OnUpdate", function()
                        if SUMMON_TIMER then
                            checkSummonStatus()
                        else
                            -- Stop checking once timer is no longer needed
                            frame:SetScript("OnUpdate", nil)
                        end
                    end)
                elseif RaidSummonPlusOptions.debug then
                    -- Target found but not in our summon list - match format for other warlocks
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. UnitName("player") .. " is summoning " .. targetName .. " (not in your summon list)")
                end
            elseif RaidSummonPlusOptions.debug then
                -- Could not determine target at all - match format for other warlocks
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Could not determine " .. UnitName("player") .. "'s target (no target or target not accessible)")
            end
        end
        
        -- Handle Ritual of Souls casting with the new module
        if RaidSummonPlusRitualofSouls_HandleSpellCast then
            if RaidSummonPlusRitualofSouls_HandleSpellCast(arg1) then
                -- Function handled the event, we can return early
                return
            end
        end
        
        -- Also forward the event to the soulstone module
        if RaidSummonPlusSoulstone_HandleEvent then
            RaidSummonPlusSoulstone_HandleEvent(event, arg1)
        end
    end
end

function RaidSummonPlus_hasValue (tab, val)
    for i, v in ipairs (tab) do
        if v == val then
            return true
        end
    end
    return false
end

function RaidSummonPlus_NameListButton_OnClick(button)
    local name = getglobal(this:GetName().."TextName"):GetText()
    local message, base_message, whisper_message, base_whisper_message, whisper_eviltwin_message, zone_message, subzone_message = ""
    local bag,slot,texture,count = FindItem("Soul Shard")
    local eviltwin_debuff = "Spell_Shadow_Charm"
    local has_eviltwin = false
    local UnitID = nil

    if button == "LeftButton" and IsControlKeyDown() then
        -- Target only functionality - unchanged
        RaidSummonPlus_GetRaidMembers()
        if RaidSummonPlus_UnitIDDB then
            for i, v in ipairs(RaidSummonPlus_UnitIDDB) do
                if v.rName == name then
                    UnitID = "raid"..v.rIndex
                end
            end
            if UnitID then
                TargetUnit(UnitID)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : no raid found")
        end
    elseif button == "LeftButton" and not IsControlKeyDown() then
        -- Main summon functionality
        RaidSummonPlus_GetRaidMembers()
        if RaidSummonPlus_UnitIDDB then
            -- Find the raid unit ID for the player
            for i, v in ipairs(RaidSummonPlus_UnitIDDB) do
                if v.rName == name then
                    UnitID = "raid"..v.rIndex
                    break
                end
            end
            
            if not UnitID then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : <" .. tostring(name) .. "> not found in raid.")
                SendAddonMessage(MSG_PREFIX_REMOVE, name, "RAID")
                RaidSummonPlus_UpdateList()
                return
            end
            
            -- Target the player
            TargetUnit(UnitID)
            
            -- Evil Twin check
            for i=1,16 do
                local s = UnitDebuff("target", i)
                if s and string.find(string.lower(s), string.lower(eviltwin_debuff)) then
                    has_eviltwin = true
                    break
                end
            end

            if has_eviltwin then
                whisper_eviltwin_message = "Can't summon you because of Evil Twin Debuff, you need either to die or to run by yourself"
                SendChatMessage(whisper_eviltwin_message, "WHISPER", nil, name)
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : <" .. name .. "> has |cffff0000Evil Twin|r !")
                for i, v in ipairs(RaidSummonPlusDB) do
                    if v == name then
                        SendAddonMessage(MSG_PREFIX_REMOVE, name, "RAID")
                        table.remove(RaidSummonPlusDB, i)
                        break
                    end
                end
                RaidSummonPlus_UpdateList()
                return
            end
            
            if Check_TargetInRange() then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : <" .. name .. "> has been summoned already (|cffff0000in range|r)")
                for i, v in ipairs(RaidSummonPlusDB) do
                    if v == name then
                        SendAddonMessage(MSG_PREFIX_REMOVE, name, "RAID")
                        table.remove(RaidSummonPlusDB, i)
                        break
                    end
                end
                RaidSummonPlus_UpdateList()
                return
            end
            
            -- Prepare the summon messages
            base_message = "Summoning <" .. name .. ">"
            base_whisper_message = "Summoning you"
            zone_message = " @" .. GetZoneText()
            subzone_message = " @" .. GetSubZoneText()
            shards_message = " [" .. count .. " shards]"
            message = base_message
            whisper_message = base_whisper_message

            if RaidSummonPlusOptions.zone then
                if GetSubZoneText() == "" then
                    message = message .. zone_message
                    whisper_message = base_whisper_message .. zone_message
                else
                    message = message .. subzone_message
                    whisper_message = whisper_message .. subzone_message
                end
            end
            
            if RaidSummonPlusOptions.shards then
                message = message .. shards_message
            end
            
            -- Store the messages for sending later if summon is successful
            SUMMON_MESSAGES = {
                raid = message,
                whisper = whisper_message
            }
            
            -- Mark that we're about to cast a summon
            SUMMON_PENDING = true
            SUMMON_TARGET = name
            SUMMON_FAIL_REASON = nil
            
            -- Cast the spell
            CastSpellByName("Ritual of Summoning")
            
            -- Schedule a function to check if summon was successful
            SUMMON_TIMER = true
            
            -- Use a 0.3 second delay to allow the combat log to register any failure
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Attempting to summon " .. name .. "...")
            end
            
            -- Initialize a timer to check for success after a brief delay
            local startTime = GetTime()
            local function checkSummonStatus()
                if not SUMMON_PENDING then
                    -- A failure was already detected by the combat log event
                    return
                end
                
                if GetTime() - startTime < 0.3 then
                    -- Still waiting, check again soon
                    return
                end
                
                -- If we reach here, no failure was detected, so the summon seems successful
                SUMMON_PENDING = false
                SUMMON_TIMER = nil
                
                -- Send the messages
                SendChatMessage(SUMMON_MESSAGES.raid, "RAID")
                
                if RaidSummonPlusOptions.whisper then
                    SendChatMessage(SUMMON_MESSAGES.whisper, "WHISPER", nil, SUMMON_TARGET)
                end
                
                -- Remove the summoned target
                for i, v in ipairs(RaidSummonPlusDB) do
                    if v == SUMMON_TARGET then
                        SendAddonMessage(MSG_PREFIX_REMOVE, SUMMON_TARGET, "RAID")
                        table.remove(RaidSummonPlusDB, i)
                        break
                    end
                end
                
                RaidSummonPlus_UpdateList()
                SUMMON_TARGET = nil
            end
            
            -- Register our function to run on each frame update until the check is complete
            local frame = CreateFrame("Frame")
            frame:SetScript("OnUpdate", function()
                if SUMMON_TIMER then
                    checkSummonStatus()
                else
                    -- Stop checking once timer is no longer needed
                    frame:SetScript("OnUpdate", nil)
                end
            end)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : no raid found")
        end
    elseif button == "RightButton" then
        -- Remove functionality - unchanged
        for i, v in ipairs(RaidSummonPlusDB) do
            if v == name then
                SendAddonMessage(MSG_PREFIX_REMOVE, name, "RAID")
                table.remove(RaidSummonPlusDB, i)
                break
            end
        end
    end
    
    RaidSummonPlus_UpdateList()
end

function RaidSummonPlus_UpdateList()
    RaidSummonPlus_BrowseDB = {}
    
    -- Only continue if player is a Warlock
    if (UnitClass("player") == "Warlock") then
        -- Get raid member data
        local raidnum = GetNumRaidMembers()
        if (raidnum > 0) then
            for raidmember = 1, raidnum do
                local rName, rRank, rSubgroup, rLevel, rClass = GetRaidRosterInfo(raidmember)
                -- Check raid data against summon list
                for i, v in ipairs(RaidSummonPlusDB) do 
                    if v == rName then
                        RaidSummonPlus_BrowseDB[i] = {}
                        RaidSummonPlus_BrowseDB[i].rName = rName
                        RaidSummonPlus_BrowseDB[i].rClass = rClass
                        RaidSummonPlus_BrowseDB[i].rIndex = i
                        if rClass == "Warlock" then
                            RaidSummonPlus_BrowseDB[i].rVIP = true
                        else
                            RaidSummonPlus_BrowseDB[i].rVIP = false
                        end
                    end
                end
            end

            -- Sort warlocks first - simplify sorting for Lua 5.0
            local sortedDB = {}
            -- First add the warlocks
            for i, v in ipairs(RaidSummonPlus_BrowseDB) do
                if v.rVIP then
                    table.insert(sortedDB, v)
                end
            end
            -- Then add the others
            for i, v in ipairs(RaidSummonPlus_BrowseDB) do
                if not v.rVIP then
                    table.insert(sortedDB, v)
                end
            end
            RaidSummonPlus_BrowseDB = sortedDB
        end
        
        -- Update UI elements
        local visibleListItems = 0
        for i=1,10 do
            if RaidSummonPlus_BrowseDB[i] then
                local buttonName = "RaidSummonPlus_NameList"..i
                local button = getglobal(buttonName)
                local textName = getglobal(buttonName.."TextName")
                
                -- Set text and class color
                textName:SetText(RaidSummonPlus_BrowseDB[i].rName)
                
                -- Set class color
                if RaidSummonPlus_BrowseDB[i].rClass == "Druid" then
                    local c = RaidSummonPlus_GetClassColour("DRUID")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Hunter" then
                    local c = RaidSummonPlus_GetClassColour("HUNTER")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Mage" then
                    local c = RaidSummonPlus_GetClassColour("MAGE")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Paladin" then
                    local c = RaidSummonPlus_GetClassColour("PALADIN")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Priest" then
                    local c = RaidSummonPlus_GetClassColour("PRIEST")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Rogue" then
                    local c = RaidSummonPlus_GetClassColour("ROGUE")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Shaman" then
                    local c = RaidSummonPlus_GetClassColour("SHAMAN")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Warlock" then
                    local c = RaidSummonPlus_GetClassColour("WARLOCK")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                elseif RaidSummonPlus_BrowseDB[i].rClass == "Warrior" then
                    local c = RaidSummonPlus_GetClassColour("WARRIOR")
                    textName:SetTextColor(c.r, c.g, c.b, 1)
                end             
                
                button:Show()
                visibleListItems = visibleListItems + 1
            else
                getglobal("RaidSummonPlus_NameList"..i):Hide()
            end
        end
		
		-- Update frame layout now that we've updated all list items
		RaidSummonPlus_FixFrameLayout()
		
		-- Explicitly control frame visibility based on summon list
		if RaidSummonPlus_RequestFrame then
			if not RaidSummonPlusDB or table.getn(RaidSummonPlusDB) == 0 then
				-- No summons needed, hide the frame
				RaidSummonPlus_RequestFrame:Hide()
			else
				-- We have summons, show the frame
				ShowUIPanel(RaidSummonPlus_RequestFrame, 1)
			end
		end
        
        -- Make sure to set up hover effects after updating the list
        RaidSummonPlus_SetupAllButtonHoverEffects()
	else
		-- Not a warlock, always hide the frame
		if RaidSummonPlus_RequestFrame then
			HideUIPanel(RaidSummonPlus_RequestFrame)
		end
	end
end

--Slash Handler
function RaidSummonPlus_SlashCommand(msg)
	if msg == "help" then
		DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus usage:")
		DEFAULT_CHAT_FRAME:AddMessage("/rsp or /raidsummonplus or /rs or /raidsummon { help | show | zone | whisper | shards | ritual | debug | soulstone | addsoulstone }")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9help|r: prints out this help")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9show|r: shows the current summon list")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9zone|r: toggles zoneinfo in /ra and /w")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9whisper|r: toggles the usage of /w")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9shards|r: toggles shards count when you announce a summon in /ra")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9ritual|r: toggles Ritual of Souls announcements")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9debug|r: toggles additional debug messages")
        DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9soulstone|r or |cff9482c9ss|r: scan for active Soulstones")
        DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9addsoulstone|r or |cff9482c9testss|r: adds a debug soulstone (10 sec duration)")
		DEFAULT_CHAT_FRAME:AddMessage("To drag the frame use left mouse button")
	elseif msg == "show" then
		for i, v in ipairs(RaidSummonPlusDB) do
			DEFAULT_CHAT_FRAME:AddMessage(tostring(v))
		end
	elseif msg == "zone" then
		if RaidSummonPlusOptions["zone"] == true then
			RaidSummonPlusOptions["zone"] = false
			DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - zoneinfo: |cffff0000disabled|r")
		elseif RaidSummonPlusOptions["zone"] == false then
			RaidSummonPlusOptions["zone"] = true
			DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - zoneinfo: |cff00ff00enabled|r")
		end
elseif msg == "whisper" then
		if RaidSummonPlusOptions["whisper"] == true then
			RaidSummonPlusOptions["whisper"] = false
			DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - whisper: |cffff0000disabled|r")
		elseif RaidSummonPlusOptions["whisper"] == false then
			RaidSummonPlusOptions["whisper"] = true
			DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - whisper: |cff00ff00enabled|r")
		end
	elseif msg == "shards" then
		if RaidSummonPlusOptions["shards"] == true then
	       RaidSummonPlusOptions["shards"] = false
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - shards: |cffff0000disabled|r")
		elseif RaidSummonPlusOptions["shards"] == false then
	       RaidSummonPlusOptions["shards"] = true
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - shards: |cff00ff00enabled|r")
		end
	elseif msg == "ritual" then
		if RaidSummonPlusOptions["ritual"] == true then
			RaidSummonPlusOptions["ritual"] = false
			DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - Ritual of Souls announcements: |cffff0000disabled|r")
		elseif RaidSummonPlusOptions["ritual"] == false then
			RaidSummonPlusOptions["ritual"] = true
			DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - Ritual of Souls announcements: |cff00ff00enabled|r")
		end
	elseif msg == "debug" then
		if RaidSummonPlusOptions["debug"] == true then
	       RaidSummonPlusOptions["debug"] = false
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - debug: |cffff0000disabled|r")
		elseif RaidSummonPlusOptions["debug"] == false then
	       RaidSummonPlusOptions["debug"] = true
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - debug: |cff00ff00enabled|r")
		end
	elseif msg == "soulstone" or msg == "ss" then
		DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Scanning for active Soulstones...")
		if RaidSummonPlusSoulstone_ScanRaid then
		    RaidSummonPlusSoulstone_ScanRaid(false)
		end
    elseif msg == "addsoulstone" or msg == "testss" then
        -- Add a debug soulstone for testing
        if RaidSummonPlusSoulstone_AddDebugSoulstone then
            RaidSummonPlusSoulstone_AddDebugSoulstone()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Error - Soulstone module not loaded")
        end
    elseif string.find(msg, "^addsoulstone%s+") or string.find(msg, "^testss%s+") then
        -- Add a debug soulstone for a specific player
        if RaidSummonPlusSoulstone_AddDebugSoulstone then
            local _, _, targetName = string.find(msg, "^%S+%s+(.+)")
            RaidSummonPlusSoulstone_AddDebugSoulstone(targetName)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Error - Soulstone module not loaded")
        end
	else
		if RaidSummonPlus_RequestFrame and RaidSummonPlus_RequestFrame:IsVisible() then
			RaidSummonPlus_RequestFrame:Hide()
		else
			RaidSummonPlus_UpdateList()
			if RaidSummonPlus_RequestFrame then
				ShowUIPanel(RaidSummonPlus_RequestFrame, 1)
			end
		end
	end
end

-- Get class color from WoW's global table
function RaidSummonPlus_GetClassColour(class)
	if (class) then
		local color = RAID_CLASS_COLORS[class]
		if (color) then
			return color
		end
	end
	return {r = 0.5, g = 0.5, b = 1}
end

-- Get and store basic raid member data for targeting
function RaidSummonPlus_GetRaidMembers()
    local raidnum = GetNumRaidMembers()
    if (raidnum > 0) then
		RaidSummonPlus_UnitIDDB = {}
		for i = 1, raidnum do
		    local rName, rRank, rSubgroup, rLevel, rClass = GetRaidRosterInfo(i)
			RaidSummonPlus_UnitIDDB[i] = {}
			if (not rName) then 
			    rName = "unknown"..i
			end
			RaidSummonPlus_UnitIDDB[i].rName    = rName
			RaidSummonPlus_UnitIDDB[i].rClass   = rClass
			RaidSummonPlus_UnitIDDB[i].rIndex   = i
	    end
	end
end

-- FindItem function from SuperMacro to get the total number of Soul Shards
function FindItem(item)
	if (not item) then return end
	item = string.lower(ItemLinkToName(item))
	local link
	for i = 1,23 do
       link = GetInventoryItemLink("player",i)
       if (link) then
           if (item == string.lower(ItemLinkToName(link))) then
                return i, nil, GetInventoryItemTexture('player', i), GetInventoryItemCount('player', i)
           end
       end
	end
	local count, bag, slot, texture
	local totalcount = 0
	for i = 0,NUM_BAG_FRAMES do
       for j = 1,MAX_CONTAINER_ITEMS do
           link = GetContainerItemLink(i,j)
           if (link) then
               if (item == string.lower(ItemLinkToName(link))) then
	               bag, slot = i, j
	               texture, count = GetContainerItemInfo(i,j)
	               totalcount = totalcount + count
               end
           end
       end
	end
	return bag, slot, texture, totalcount
end

-- Checks if the target is in range (28 yards)
function Check_TargetInRange()
   if not (GetUnitName("target") == nil) then
       local t = UnitName("target")
       if (CheckInteractDistance("target", 4)) then
           return true
       else
           return false
       end
   end
end