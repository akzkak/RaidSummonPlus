-- RaidSummonPlus.lua
-- Enhanced version of RaidSummon addon with persistent window position, improved frame visibility, and combat detection

-- Variables for tracking summon status
local SUMMON_PENDING = false
local SUMMON_TARGET = nil
local SUMMON_TIMER = nil
local SUMMON_FAIL_REASON = nil
local SUMMON_MESSAGES = {}

local RaidSummonPlusOptions_DefaultSettings = {
	whisper = true,
	zone    = true,
    shards  = true,
    debug   = false,
    frameX  = nil,    -- Position coordinates
    frameY  = nil     -- Position coordinates
}

local function RaidSummonPlus_Initialize()
	if not RaidSummonPlusOptions then
		RaidSummonPlusOptions = {}
	end
	for i in RaidSummonPlusOptions_DefaultSettings do
		if (not RaidSummonPlusOptions[i]) then
			RaidSummonPlusOptions[i] = RaidSummonPlusOptions_DefaultSettings[i]
		end
	end
end

-- Save frame position to saved variables
function RaidSummonPlus_SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = RaidSummonPlus_RequestFrame:GetPoint()
    if point and xOfs and yOfs then
        RaidSummonPlusOptions.frameX = xOfs
        RaidSummonPlusOptions.frameY = yOfs
    end
end

-- Restore frame position from saved variables
function RaidSummonPlus_RestoreFramePosition()
    if RaidSummonPlusOptions.frameX and RaidSummonPlusOptions.frameY then
        RaidSummonPlus_RequestFrame:ClearAllPoints()
        RaidSummonPlus_RequestFrame:SetPoint("CENTER", UIParent, "CENTER", RaidSummonPlusOptions.frameX, RaidSummonPlusOptions.frameY)
    end
end

function RaidSummonPlus_EventFrame_OnLoad()
	DEFAULT_CHAT_FRAME:AddMessage(string.format("RaidSummonPlus version %s by %s. Type /rsp or /raidsummonplus to show.", GetAddOnMetadata("RaidSummonPlus", "Version"), GetAddOnMetadata("RaidSummonPlus", "Author")))
    this:RegisterEvent("VARIABLES_LOADED")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("CHAT_MSG_ADDON")
    this:RegisterEvent("CHAT_MSG_RAID")
	this:RegisterEvent("CHAT_MSG_RAID_LEADER")
    this:RegisterEvent("CHAT_MSG_SAY")
    this:RegisterEvent("CHAT_MSG_YELL")
    this:RegisterEvent("CHAT_MSG_WHISPER")
    this:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER") -- Register for spell failure events
    
    -- Commands
	SlashCmdList["RAIDSUMMONPLUS"] = RaidSummonPlus_SlashCommand
	SLASH_RAIDSUMMONPLUS1 = "/raidsummonplus"
	SLASH_RAIDSUMMONPLUS2 = "/rsp"
	-- Maintain compatibility with old commands
	SlashCmdList["RAIDSUMMON"] = RaidSummonPlus_SlashCommand
	SLASH_RAIDSUMMON1 = "/raidsummon"
	SLASH_RAIDSUMMON2 = "/rs"
	MSG_PREFIX_ADD		= "RSPAdd"
	MSG_PREFIX_REMOVE	= "RSPRemove"
	RaidSummonPlusDB = {}
	RaidSummonPlusLoc_Header = "RaidSummonPlus"
    
    -- Force hide frame on load
    RaidSummonPlus_RequestFrame:Hide()
end

function RaidSummonPlus_EventFrame_OnEvent()
	if event == "VARIABLES_LOADED" then
		this:UnregisterEvent("VARIABLES_LOADED")
		RaidSummonPlus_Initialize()
        -- Restore frame position after variables are loaded
        RaidSummonPlus_RestoreFramePosition()
        
        -- Ensure frame is hidden at startup
        RaidSummonPlus_RequestFrame:Hide()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Additional check to ensure frame stays hidden until needed
        if next(RaidSummonPlusDB) == nil then
            RaidSummonPlus_RequestFrame:Hide()
        else
            -- Only update list if we actually have something to show
            RaidSummonPlus_UpdateList()
        end
	elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_WHISPER" then	
		if string.find(arg1, "^123") then
			SendAddonMessage(MSG_PREFIX_ADD, arg2, "RAID")
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
					end
				end
			end
		end
    elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" then
        -- Check if we have a pending summon
        if SUMMON_PENDING and string.find(arg1, "Ritual of Summoning") then
            -- Extract failure reason
            SUMMON_FAIL_REASON = arg1
            
            -- If failure mentions combat, notify the player
            if string.find(string.lower(arg1), "combat") then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : |cffff0000Failed to summon|r - " .. arg1)
                
                -- Whisper the target that they're in combat
                if SUMMON_TARGET and RaidSummonPlusOptions.whisper then
                    SendChatMessage("Cannot summon you - you are in combat", "WHISPER", nil, SUMMON_TARGET)
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
                if s and strfind(strlower(s), strlower(eviltwin_debuff)) then
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

			-- Sort warlocks first
			table.sort(RaidSummonPlus_BrowseDB, function(a,b) return tostring(a.rVIP) > tostring(b.rVIP) end)
		end
		
		-- Update UI elements
		for i=1,10 do
			if RaidSummonPlus_BrowseDB[i] then
				getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetText(RaidSummonPlus_BrowseDB[i].rName)
				
				-- Set class color
				if RaidSummonPlus_BrowseDB[i].rClass == "Druid" then
					local c = RaidSummonPlus_GetClassColour("DRUID")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Hunter" then
					local c = RaidSummonPlus_GetClassColour("HUNTER")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Mage" then
					local c = RaidSummonPlus_GetClassColour("MAGE")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Paladin" then
					local c = RaidSummonPlus_GetClassColour("PALADIN")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Priest" then
					local c = RaidSummonPlus_GetClassColour("PRIEST")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Rogue" then
					local c = RaidSummonPlus_GetClassColour("ROGUE")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Shaman" then
					local c = RaidSummonPlus_GetClassColour("SHAMAN")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Warlock" then
					local c = RaidSummonPlus_GetClassColour("WARLOCK")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				elseif RaidSummonPlus_BrowseDB[i].rClass == "Warrior" then
					local c = RaidSummonPlus_GetClassColour("WARRIOR")
					getglobal("RaidSummonPlus_NameList"..i.."TextName"):SetTextColor(c.r, c.g, c.b, 1)
				end				
				
				getglobal("RaidSummonPlus_NameList"..i):Show()
			else
				getglobal("RaidSummonPlus_NameList"..i):Hide()
			end
		end
		
		-- Explicitly control frame visibility based on summon list
		if next(RaidSummonPlusDB) == nil then
			-- No summons needed, hide the frame
			HideUIPanel(RaidSummonPlus_RequestFrame)
		else
			-- We have summons, show the frame
			ShowUIPanel(RaidSummonPlus_RequestFrame, 1)
		end
	else
		-- Not a warlock, always hide the frame
		HideUIPanel(RaidSummonPlus_RequestFrame)
	end
end

--Slash Handler
function RaidSummonPlus_SlashCommand(msg)
	if msg == "help" then
		DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus usage:")
		DEFAULT_CHAT_FRAME:AddMessage("/rsp or /raidsummonplus or /rs or /raidsummon { help | show | zone | whisper | shards | debug }")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9help|r: prints out this help")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9show|r: shows the current summon list")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9zone|r: toggles zoneinfo in /ra and /w")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9whisper|r: toggles the usage of /w")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9shards|r: toggles shards count when you announce a summon in /ra")
		DEFAULT_CHAT_FRAME:AddMessage(" - |cff9482c9debug|r: toggles additional debug messages")
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
		elseif msg == "debug" then
		if RaidSummonPlusOptions["debug"] == true then
	       RaidSummonPlusOptions["debug"] = false
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - debug: |cffff0000disabled|r")
		elseif RaidSummonPlusOptions["debug"] == false then
	       RaidSummonPlusOptions["debug"] = true
	       DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - debug: |cff00ff00enabled|r")
		end
	else
		if RaidSummonPlus_RequestFrame:IsVisible() then
			RaidSummonPlus_RequestFrame:Hide()
		else
			RaidSummonPlus_UpdateList()
			ShowUIPanel(RaidSummonPlus_RequestFrame, 1)
		end
	end
end

--class color
function RaidSummonPlus_GetClassColour(class)
	if (class) then
		local color = RAID_CLASS_COLORS[class]
		if (color) then
			return color
		end
	end
	return {r = 0.5, g = 0.5, b = 1}
end

--raid member
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
   if not (GetUnitName("target")==nil) then
       local t = UnitName("target")
       if (CheckInteractDistance("target", 4)) then
           return true
       else
           return false
       end
   end
end