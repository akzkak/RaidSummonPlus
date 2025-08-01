-- RaidSummonPlus.lua
-- Enhanced version of RaidSummon addon with persistent window position, improved frame visibility, and combat detection
-- WoW 1.12.1 (Vanilla) compatible version

-- Global variables for main frame UI appearance customization
-- To customize opacity: 0.0 = fully transparent, 1.0 = fully opaque
-- Recommended values: 0.7-0.9 for good visibility with transparency
RAIDSUMMONPLUS_MAIN_BACKGROUND_OPACITY = 0.70     -- Main summon frame background opacity
RAIDSUMMONPLUS_TITLE_BACKGROUND_OPACITY = 0.90    -- Title frame background opacity
RAIDSUMMONPLUS_SOULSTONE_BACKGROUND_OPACITY = 0.70 -- Soulstone frame background opacity

-- Variables for tracking summon status
local SUMMON_PENDING = false
local SUMMON_TARGET = nil
local SUMMON_TIMER = nil
local SUMMON_FAIL_REASON = nil
local SUMMON_MESSAGES = {}
local RITUAL_OF_SUMMONING_SPELL_ID = 698 -- Spell ID for Ritual of Summoning

-- Helper function to output messages only when debug is enabled
-- This ensures the addon is completely silent unless debug mode is turned on
function RaidSummonPlus_DebugMessage(message)
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. message)
    end
end

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
    rangeCheck = false, -- New option for auto-removing players in range, off by default
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
    this:RegisterEvent("CHAT_MSG_PARTY")
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
    this:RegisterEvent("PLAYER_ALIVE")  -- Detect when player is resurrected
    
    -- Add UI error event for cooldown detection
    this:RegisterEvent("UI_ERROR_MESSAGE")
    
    -- Commands
    SlashCmdList["RAIDSUMMONPLUS"] = RaidSummonPlus_SlashCommand
    SLASH_RAIDSUMMONPLUS1 = "/rsp"
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
    
    -- Check if range checking is disabled
    if not RaidSummonPlusOptions or not RaidSummonPlusOptions["rangeCheck"] then
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
                    -- Use appropriate unit ID based on group type
                    if GetNumRaidMembers() > 0 then
                        UnitID = "raid"..v.rIndex
                    elseif GetNumPartyMembers() > 0 then
                        if v.rName == UnitName("player") then
                            UnitID = "player"
                        else
                            -- Find the party member index (rIndex - 1 because player is index 1)
                            UnitID = "party"..(v.rIndex - 1)
                        end
                    end
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
                RaidSummonPlus_DebugMessage("<" .. playerName .. "> has been summoned already (|cffff0000in range|r)")
                
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

-- Set up hover effects for all buttons in the addon with per-button hover state tracking
-- This system prevents debug message spam by:
-- 1. Tracking hover state per button (not globally)
-- 2. Only logging one enter/leave message per hover session
-- 3. Including player name in debug messages for better context
-- 4. Cleaning up states when buttons change or become invisible
local BUTTON_HOVER_STATES = {} -- Track hover state per button to prevent spam

-- Function to clean up hover states for buttons that are no longer visible or have changed
function RaidSummonPlus_CleanupHoverStates()
    -- Clean up hover states for buttons that might no longer be relevant
    for buttonName, state in pairs(BUTTON_HOVER_STATES) do
        local button = getglobal(buttonName)
        if not button or not button:IsVisible() then
            -- Button no longer exists or is not visible, remove its hover state
            BUTTON_HOVER_STATES[buttonName] = nil
        else
            -- Reset hover state for visible buttons to ensure clean state
            if state.isHovered then
                state.isHovered = false
            end
        end
    end
end

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
                local buttonName = this:GetName()
                local textName = getglobal(buttonName .. "TextName")
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
                    
                    -- Debug message only once per button hover session
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        if not BUTTON_HOVER_STATES[buttonName] or not BUTTON_HOVER_STATES[buttonName].isHovered then
                            -- Get the player name from the button text for more useful debug info
                            local playerName = textName:GetText() or "Unknown"
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hover enter: " .. playerName .. " (" .. buttonName .. ")")
                            
                            -- Mark this button as currently hovered
                            if not BUTTON_HOVER_STATES[buttonName] then
                                BUTTON_HOVER_STATES[buttonName] = {}
                            end
                            BUTTON_HOVER_STATES[buttonName].isHovered = true
                        end
                    end
                end
            end)
            
            button:SetScript("OnLeave", function()
                local buttonName = this:GetName()
                local textName = getglobal(buttonName .. "TextName")
                if textName and this.originalColor then
                    -- Restore original color
                    textName:SetTextColor(
                        this.originalColor.r,
                        this.originalColor.g,
                        this.originalColor.b,
                        this.originalColor.a
                    )
                    
                    -- Debug message only once per button hover session
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        if BUTTON_HOVER_STATES[buttonName] and BUTTON_HOVER_STATES[buttonName].isHovered then
                            -- Get the player name from the button text for more useful debug info
                            local playerName = textName:GetText() or "Unknown"
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hover leave: " .. playerName .. " (" .. buttonName .. ")")
                            
                            -- Mark this button as no longer hovered
                            BUTTON_HOVER_STATES[buttonName].isHovered = false
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
                local buttonName = this:GetName()
                local textName = getglobal(buttonName .. "TextName")
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
                    
                    -- Debug message only once per button hover session
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        if not BUTTON_HOVER_STATES[buttonName] or not BUTTON_HOVER_STATES[buttonName].isHovered then
                            -- Get the player name from the button text for more useful debug info
                            local playerName = textName:GetText() or "Unknown"
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hover enter: " .. playerName .. " (" .. buttonName .. ")")
                            
                            -- Mark this button as currently hovered
                            if not BUTTON_HOVER_STATES[buttonName] then
                                BUTTON_HOVER_STATES[buttonName] = {}
                            end
                            BUTTON_HOVER_STATES[buttonName].isHovered = true
                        end
                    end
                end
            end)
            
            button:SetScript("OnLeave", function()
                local buttonName = this:GetName()
                local textName = getglobal(buttonName .. "TextName")
                if textName and this.originalColor then
                    -- Restore original color
                    textName:SetTextColor(
                        this.originalColor.r,
                        this.originalColor.g,
                        this.originalColor.b,
                        this.originalColor.a
                    )
                    
                    -- Debug message only once per button hover session
                    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                        if BUTTON_HOVER_STATES[buttonName] and BUTTON_HOVER_STATES[buttonName].isHovered then
                            -- Get the player name from the button text for more useful debug info
                            local playerName = textName:GetText() or "Unknown"
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hover leave: " .. playerName .. " (" .. buttonName .. ")")
                            
                            -- Mark this button as no longer hovered
                            BUTTON_HOVER_STATES[buttonName].isHovered = false
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

-- Apply background opacity settings to main frames
function RaidSummonPlus_ApplyFrameOpacity()
    -- Apply opacity to main summon frame
    if RaidSummonPlus_RequestFrame then
        RaidSummonPlus_RequestFrame:SetBackdropColor(1, 1, 1, RAIDSUMMONPLUS_MAIN_BACKGROUND_OPACITY)
    end
    
    -- Apply opacity to title frame
    if RaidSummonPlus_TitleFrame then
        RaidSummonPlus_TitleFrame:SetBackdropColor(1, 1, 1, RAIDSUMMONPLUS_TITLE_BACKGROUND_OPACITY)
    end
    
    -- Apply opacity to soulstone frame
    if RaidSummonPlus_SoulstoneFrame then
        RaidSummonPlus_SoulstoneFrame:SetBackdropColor(1, 1, 1, RAIDSUMMONPLUS_SOULSTONE_BACKGROUND_OPACITY)
    end
    
    -- Apply opacity to soulstone title frame if it exists
    if RaidSummonPlus_SoulstoneTitleFrame then
        RaidSummonPlus_SoulstoneTitleFrame:SetBackdropColor(1, 1, 1, RAIDSUMMONPLUS_TITLE_BACKGROUND_OPACITY)
    end
end

-- Function to handle mouse entering a name list button - brighten the text color
function RaidSummonPlus_NameListButton_OnEnter()
    local buttonName = this:GetName()
    local textName = getglobal(buttonName .. "TextName")
    if textName then
        -- Store original color values
        local r, g, b, a = textName:GetTextColor()
        this.originalColor = {
            r = r,
            g = g,
            b = b,
            a = a or 1.0
        }
        
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
        
        -- Debug message only once per button hover session
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            if not BUTTON_HOVER_STATES[buttonName] or not BUTTON_HOVER_STATES[buttonName].isHovered then
                -- Get the player name from the button text for more useful debug info
                local playerName = textName:GetText() or "Unknown"
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hover enter: " .. playerName .. " (" .. buttonName .. ")")
                
                -- Mark this button as currently hovered
                if not BUTTON_HOVER_STATES[buttonName] then
                    BUTTON_HOVER_STATES[buttonName] = {}
                end
                BUTTON_HOVER_STATES[buttonName].isHovered = true
            end
        end
    end
end

-- Function to handle mouse leaving a name list button - restore original color
function RaidSummonPlus_NameListButton_OnLeave()
    local buttonName = this:GetName()
    local textName = getglobal(buttonName .. "TextName")
    
    -- Restore original color if available
    if textName and this.originalColor then
        textName:SetTextColor(
            this.originalColor.r,
            this.originalColor.g,
            this.originalColor.b,
            this.originalColor.a
        )
        
        -- Debug message only once per button hover session
        if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
            if BUTTON_HOVER_STATES[buttonName] and BUTTON_HOVER_STATES[buttonName].isHovered then
                -- Get the player name from the button text for more useful debug info
                local playerName = textName:GetText() or "Unknown"
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Hover leave: " .. playerName .. " (" .. buttonName .. ")")
                
                -- Mark this button as no longer hovered
                BUTTON_HOVER_STATES[buttonName].isHovered = false
            end
        end
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
                    
                    -- Apply initial frame opacity settings
                    RaidSummonPlus_ApplyFrameOpacity()
                    
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
        
    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_WHISPER" then    
        if string.find(arg1, "^123") then
            -- Debug message to confirm detection
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Detected 123 from player: " .. arg2)
            end
            
            -- Add directly to our own list
            if not RaidSummonPlus_hasValue(RaidSummonPlusDB, arg2) and UnitName("player")~=arg2 then
                table.insert(RaidSummonPlusDB, arg2)
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Added " .. arg2 .. " to summon list")
                end
            else
                if RaidSummonPlusOptions.debug then
                    if RaidSummonPlus_hasValue(RaidSummonPlusDB, arg2) then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : " .. arg2 .. " already in summon list")
                    elseif UnitName("player") == arg2 then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Ignoring self (" .. arg2 .. ")")
                    end
                end
            end
            
            -- Sync with other addon users (RAID channel auto-falls back to PARTY in parties)
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
        elseif RaidSummonPlusCompatibility_HandleMessage and RaidSummonPlusCompatibility_HandleMessage(arg1, arg2, arg4) then
            -- Message was handled by compatibility module
            -- No additional processing needed
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
        -- Check if this is a manual Ritual of Summoning cast by player
        if arg1 == "Ritual of Summoning" or string.find(string.lower(arg1 or ""), "ritual of summoning") then
            -- Debug message only for relevant spells (Ritual of Summoning)
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : SPELLCAST_START detected: " .. tostring(arg1))
            end
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
                    
                    -- Prepare the summon messages using custom message system
                    local message, whisper_message, customChannel = RaidSummonPlus_CreateSummonMessage(targetName, count)
                    
                    -- Store messages for sending if summon is successful
                    SUMMON_MESSAGES = {
                        raid = message,
                        whisper = whisper_message,
                        customChannel = customChannel
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
                        
                        -- Send the messages using appropriate channel
                        if RaidSummonPlusOptions.announceSummon then
                            if SUMMON_MESSAGES.customChannel then
                                -- User specified a custom channel
                                SendChatMessage(SUMMON_MESSAGES.raid, SUMMON_MESSAGES.customChannel)
                            elseif UnitInRaid("player") then
                                -- In raid, use RAID channel
                                SendChatMessage(SUMMON_MESSAGES.raid, "RAID")
                            elseif GetNumPartyMembers() > 0 then
                                -- In party, use PARTY channel
                                SendChatMessage(SUMMON_MESSAGES.raid, "PARTY")
                            else
                                -- Solo, just display in chat frame
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. SUMMON_MESSAGES.raid)
                            end
                        end
                        
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
        
        -- Check if this is a soulstone-related spell for debug purposes
        local SOULSTONE_SPELL_NAMES = {"Soulstone", "soulstone"}
        local isSoulstoneSpell = false
        for _, spellName in ipairs(SOULSTONE_SPELL_NAMES) do
            if string.find(string.lower(arg1 or ""), string.lower(spellName)) then
                isSoulstoneSpell = true
                if RaidSummonPlusOptions.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : SPELLCAST_START detected: " .. tostring(arg1))
                end
                break
            end
        end
        
        -- Also forward the event to the soulstone module
        if RaidSummonPlusSoulstone_HandleEvent then
            RaidSummonPlusSoulstone_HandleEvent(event, arg1)
        end
        
    elseif event == "PLAYER_ALIVE" then
        -- Handle player resurrection (soulstone used)
        if RaidSummonPlusSoulstone_OnPlayerAlive then
            RaidSummonPlusSoulstone_OnPlayerAlive()
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
                    -- Use appropriate unit ID based on group type
                    if GetNumRaidMembers() > 0 then
                        UnitID = "raid"..v.rIndex
                    elseif GetNumPartyMembers() > 0 then
                        if v.rName == UnitName("player") then
                            UnitID = "player"
                        else
                            -- Find the party member index (rIndex - 1 because player is index 1)
                            UnitID = "party"..(v.rIndex - 1)
                        end
                    end
                end
            end
            if UnitID then
                TargetUnit(UnitID)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : no group found")
        end
    elseif button == "LeftButton" and not IsControlKeyDown() then
        -- Main summon functionality
        RaidSummonPlus_GetRaidMembers()
        if RaidSummonPlus_UnitIDDB then
            -- Find the unit ID for the player
            for i, v in ipairs(RaidSummonPlus_UnitIDDB) do
                if v.rName == name then
                    -- Use appropriate unit ID based on group type
                    if GetNumRaidMembers() > 0 then
                        UnitID = "raid"..v.rIndex
                    elseif GetNumPartyMembers() > 0 then
                        if v.rName == UnitName("player") then
                            UnitID = "player"
                        else
                            -- Find the party member index (rIndex - 1 because player is index 1)
                            UnitID = "party"..(v.rIndex - 1)
                        end
                    end
                    break
                end
            end
            
            if not UnitID then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : <" .. tostring(name) .. "> not found in group.")
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
            
            -- Only check range if the option is enabled
            if RaidSummonPlusOptions and RaidSummonPlusOptions["rangeCheck"] and Check_TargetInRange() then
                RaidSummonPlus_DebugMessage("<" .. name .. "> has been summoned already (|cffff0000in range|r)")
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
            
            -- Prepare the summon messages using custom message system
            local message, whisper_message, customChannel = RaidSummonPlus_CreateSummonMessage(name, count)
            
            -- Store the messages for sending later if summon is successful
            SUMMON_MESSAGES = {
                raid = message,
                whisper = whisper_message,
                customChannel = customChannel
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
                
                -- Send the messages using appropriate channel
                if RaidSummonPlusOptions.announceSummon then
                    if SUMMON_MESSAGES.customChannel then
                        -- User specified a custom channel
                        SendChatMessage(SUMMON_MESSAGES.raid, SUMMON_MESSAGES.customChannel)
                    elseif UnitInRaid("player") then
                        -- In raid, use RAID channel
                        SendChatMessage(SUMMON_MESSAGES.raid, "RAID")
                    elseif GetNumPartyMembers() > 0 then
                        -- In party, use PARTY channel
                        SendChatMessage(SUMMON_MESSAGES.raid, "PARTY")
                    else
                        -- Solo, just display in chat frame
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : " .. SUMMON_MESSAGES.raid)
                    end
                end
                
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
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : no group found")
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
        end
        
        -- Also check party members (whether in raid or not)
        local partynum = GetNumPartyMembers()
        if (partynum > 0) then
            for partymember = 1, partynum do
                local rName = UnitName("party"..partymember)
                local rClass = UnitClass("party"..partymember)
                -- Check party data against summon list
                for i, v in ipairs(RaidSummonPlusDB) do 
                    if v == rName then
                        -- Only add if not already added from raid
                        local alreadyExists = false
                        for j, existing in ipairs(RaidSummonPlus_BrowseDB) do
                            if existing and existing.rName == rName then
                                alreadyExists = true
                                break
                            end
                        end
                        if not alreadyExists then
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
				
				-- Apply background opacity settings when frame is shown
				RaidSummonPlus_ApplyFrameOpacity()
			end
		end
        
        -- Clean up hover states for buttons that are no longer visible
        RaidSummonPlus_CleanupHoverStates()
        
        -- Make sure to set up hover effects after updating the list
        RaidSummonPlus_SetupAllButtonHoverEffects()
    end
    
    -- Not a warlock, always hide the frame
    if UnitClass("player") ~= "Warlock" then
        if RaidSummonPlus_RequestFrame then
            HideUIPanel(RaidSummonPlus_RequestFrame)
        end
    end
end

--Slash Handler
function RaidSummonPlus_SlashCommand(msg)
	if msg == "help" then
		DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus usage:")
		DEFAULT_CHAT_FRAME:AddMessage("/rsp { help | options | debug }")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9help|r: prints out this help")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9options|r: opens the options panel")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9debug|r: toggles additional debug messages")
		DEFAULT_CHAT_FRAME:AddMessage("To drag the frame use left mouse button")

	elseif msg == "debug" then
		if RaidSummonPlusOptions["debug"] == true then
	       RaidSummonPlusOptions["debug"] = false
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - debug: |cffff0000disabled|r")
		elseif RaidSummonPlusOptions["debug"] == false then
	       RaidSummonPlusOptions["debug"] = true
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - debug: |cff00ff00enabled|r")
		end
	elseif msg == "options" or msg == "config" then
        if RaidSummonPlusOptions_Show then
            RaidSummonPlusOptions_Show()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Options panel not loaded")
        end
	else
		if RaidSummonPlus_RequestFrame and RaidSummonPlus_RequestFrame:IsVisible() then
			RaidSummonPlus_RequestFrame:Hide()
		else
			RaidSummonPlus_UpdateList()
			if RaidSummonPlus_RequestFrame then
				ShowUIPanel(RaidSummonPlus_RequestFrame, 1)
				-- Apply background opacity settings when frame is shown
				RaidSummonPlus_ApplyFrameOpacity()
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
    local partynum = GetNumPartyMembers()
    
    RaidSummonPlus_UnitIDDB = {}
    
    if (raidnum > 0) then
        -- Handle raid members
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
    elseif (partynum > 0) then
        -- Handle party members (including player)
        -- Add the player first
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")
        RaidSummonPlus_UnitIDDB[1] = {}
        RaidSummonPlus_UnitIDDB[1].rName = playerName
        RaidSummonPlus_UnitIDDB[1].rClass = playerClass
        RaidSummonPlus_UnitIDDB[1].rIndex = 1
        
        -- Add party members
        for i = 1, partynum do
            local partyName = UnitName("party"..i)
            local _, partyClass = UnitClass("party"..i)
            RaidSummonPlus_UnitIDDB[i + 1] = {}
            if (not partyName) then 
                partyName = "unknown"..(i + 1)
            end
            RaidSummonPlus_UnitIDDB[i + 1].rName = partyName
            RaidSummonPlus_UnitIDDB[i + 1].rClass = partyClass
            RaidSummonPlus_UnitIDDB[i + 1].rIndex = i + 1
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
-- Function to create custom summon messages with placeholder support
function RaidSummonPlus_CreateSummonMessage(targetName, shardCount)
    -- Debug output if enabled
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Creating summon message for " .. targetName .. " with " .. shardCount .. " shards")
    end
    
    local message, whisper_message, customChannel
    
    -- Determine default channel
    local defaultChannel
    if UnitInRaid("player") then
        defaultChannel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        defaultChannel = "PARTY"
    else
        defaultChannel = "SAY"
    end
    
    -- Prepare zone and shard info
    local zoneText = GetZoneText()
    local subzoneText = GetSubZoneText()
    local zoneInfo = (subzoneText ~= "" and subzoneText) or zoneText
    local shardsInfo = "[" .. shardCount .. " shards]"
    
    if RaidSummonPlusOptions and RaidSummonPlusOptions["summonMessage"] and RaidSummonPlusOptions["summonMessage"] ~= "" then
        -- Use custom message, replace placeholders
        if RaidSummonPlusOptions.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Using custom message: " .. RaidSummonPlusOptions["summonMessage"])
        end
        message = RaidSummonPlusOptions["summonMessage"]
        message = string.gsub(message, "{targetName}", targetName)
        message = string.gsub(message, "{zone}", zoneText)
        message = string.gsub(message, "{subzone}", subzoneText)
        message = string.gsub(message, "{shards}", shardsInfo)
        
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
        
        -- Create whisper message using custom whisper message if available
        if RaidSummonPlusOptions and RaidSummonPlusOptions["whisperMessage"] and RaidSummonPlusOptions["whisperMessage"] ~= "" then
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Using custom whisper message: " .. RaidSummonPlusOptions["whisperMessage"])
            end
            whisper_message = RaidSummonPlusOptions["whisperMessage"]
            whisper_message = string.gsub(whisper_message, "{targetName}", targetName)
            whisper_message = string.gsub(whisper_message, "{zone}", zoneText)
            whisper_message = string.gsub(whisper_message, "{subzone}", subzoneText)
            whisper_message = string.gsub(whisper_message, "{shards}", shardsInfo)
        else
            if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Using default whisper message")
            end
            -- Use default whisper message format
            whisper_message = "Summoning you to: " .. zoneInfo
        end
    else
        -- Use default message format (legacy behavior with zone and shards always included)
        message = "Summoning <" .. targetName .. "> @" .. zoneInfo .. " " .. shardsInfo
        -- Create whisper message using custom whisper message if available
        if RaidSummonPlusOptions and RaidSummonPlusOptions["whisperMessage"] and RaidSummonPlusOptions["whisperMessage"] ~= "" then
            if RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Using custom whisper message: " .. RaidSummonPlusOptions["whisperMessage"])
            end
            whisper_message = RaidSummonPlusOptions["whisperMessage"]
            whisper_message = string.gsub(whisper_message, "{targetName}", targetName)
            whisper_message = string.gsub(whisper_message, "{zone}", zoneText)
            whisper_message = string.gsub(whisper_message, "{subzone}", subzoneText)
            whisper_message = string.gsub(whisper_message, "{shards}", shardsInfo)
        else
            if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Using default whisper message")
            end
            -- Use default whisper message format
            whisper_message = "Summoning you to: " .. zoneInfo
        end
    end
    
    -- Debug output if enabled
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Final message: " .. message)
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Final whisper message: " .. whisper_message)
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus Debug|r : Custom channel: " .. (customChannel or "nil"))
    end
    
    return message, whisper_message, customChannel
end