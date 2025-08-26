-- RaidSummonPlus Options Panel
-- Compatible with WoW Vanilla 1.12.1

-- Global variables for UI appearance customization
-- To customize opacity: 0.0 = fully transparent, 1.0 = fully opaque
-- Recommended values: 0.7-0.9 for good visibility with transparency
RAIDSUMMONPLUS_OPTIONS_BACKGROUND_OPACITY = 0.80  -- Main frame background opacity
RAIDSUMMONPLUS_OPTIONS_TITLE_OPACITY = 0.90       -- Title frame background opacity  
RAIDSUMMONPLUS_OPTIONS_EDITBOX_OPACITY = 1.0      -- EditBox background opacity (keep at 1.0 for readability)

-- Store checkbox references
local optionCheckboxes = {}

-- Spacing configuration
local OPTION_SPACING = 6  -- Space between options in same section

-- Helper function to create a text input field
local function createTextInput(parent, name, labelText, defaultText, yOffset, previousElement, width)
    width = width or 180
    
    -- Create label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if not label then
        return nil
    end
    
    if previousElement then
        label:SetPoint("TOPLEFT", previousElement, "BOTTOMLEFT", 0, -OPTION_SPACING)
    else
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    end
    label:SetText(labelText)
    label:SetTextColor(0.6, 0.6, 0.6, 1.0)  -- Light grey for placeholder helper text
    label:SetWidth(width)  -- Set width to match the text input
    label:SetJustifyH("LEFT")
    
    -- Create EditBox
    local editBox = CreateFrame("EditBox", "RaidSummonPlusOptionsFrame" .. name .. "EditBox", parent)
    if not editBox then
        return label
    end
    
    editBox:SetWidth(width)
    editBox:SetHeight(20)
    editBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    
    -- Set up EditBox appearance to match frame style
    editBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = nil,  -- No border for clean look
        tile = true,
        tileSize = 16,
        insets = { left = 4, right = 4, top = 2, bottom = 2 }
    })
    editBox:SetBackdropColor(1, 1, 1, RAIDSUMMONPLUS_OPTIONS_EDITBOX_OPACITY)  -- Use configurable opacity
    
    -- Set up text properties
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetMaxLetters(200)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(4, 4, 2, 2)  -- Add text padding inside the EditBox
    
    -- Set text after other properties to prevent rendering issues
    local textToSet = defaultText or ""
    editBox:SetText("")  -- Clear first
    editBox:SetText(textToSet)
    editBox:HighlightText(0, 0)  -- Clear any selection
    
    -- Set up scripts (only if not already set)
    if not editBox.scriptsSet then
        editBox:SetScript("OnEnterPressed", function()
            this:ClearFocus()
        end)
        
        editBox:SetScript("OnEscapePressed", function()
            this:ClearFocus()
        end)
        
        editBox:SetScript("OnEditFocusLost", function()
            -- Clear any lingering text rendering issues
            this:HighlightText(0, 0)
        end)
        
        editBox.scriptsSet = true
    end
    
    -- Store references
    editBox.label = label
    
    return editBox
end

-- Helper function to create a checkbox with text label
local function createCheckboxOption(parent, name, text, yOffset, previousCheckbox)
    -- Create the checkbox as a CheckButton (proper type for Vanilla)
    local checkbox = CreateFrame("CheckButton", "RaidSummonPlusOptionsFrame" .. name .. "CheckBox", parent)
    if not checkbox then
        return nil
    end
    
    checkbox:SetWidth(16)
    checkbox:SetHeight(16)
    
    if previousCheckbox then
        checkbox:SetPoint("TOPLEFT", previousCheckbox, "BOTTOMLEFT", 0, -OPTION_SPACING)
    else
        checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOffset)
    end
    
    -- Set up checkbox textures (CheckButton methods)
    checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    checkbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    checkbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    
    -- For CheckButton, we use SetCheckedTexture (this should work)
    if checkbox.SetCheckedTexture then
        checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    if checkbox.SetDisabledCheckedTexture then
        checkbox:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    end
    
    -- Create text label
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if not label then
        return checkbox
    end
    
    label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9, 1.0)
    
    -- Store references
    checkbox.label = label
    
    -- Set up click handler (only if not already set)
    if not checkbox.scriptsSet then
        -- Handlers are assigned by callers (per-option handlers)
        checkbox.scriptsSet = true
    end
    
    return checkbox
end

-- Initialize the options frame
function RaidSummonPlusOptions_OnLoad()
    -- Frame loaded
end

-- Update the options display when shown
function RaidSummonPlusOptions_OnShow()
    -- Apply background opacity settings
    if RaidSummonPlusOptionsFrame then
        RaidSummonPlusOptionsFrame:SetBackdropColor(1, 1, 1, RAIDSUMMONPLUS_OPTIONS_BACKGROUND_OPACITY)
    end
    if RaidSummonPlusOptionsFrameTitleFrame then
        RaidSummonPlusOptionsFrameTitleFrame:SetBackdropColor(1, 1, 1, RAIDSUMMONPLUS_OPTIONS_TITLE_OPACITY)
    end
    
    -- Create checkboxes if they don't exist yet (use a more reliable check)
    if not optionCheckboxes.announceSummon then
        -- Create checkboxes dynamically
        local contentArea = RaidSummonPlusOptionsFrameContentArea
        if contentArea then
            -- DYNAMIC SPACING CONFIGURATION - CHANGE THESE TO ADJUST ENTIRE LAYOUT
            local FIRST_HEADER_Y = -5             -- Starting position for first header
            local HEADER_TO_OPTION_SPACING = 20   -- Space between header and first option
            local SECTION_TO_SECTION_SPACING = 10 -- Space between end of section and next header
            local CHECKBOX_HEIGHT = 16 + OPTION_SPACING -- Height of checkbox + spacing
            -- Height for the inline channel row added under Summon Message
            local CHANNEL_ROW_HEIGHT = 16
            local CHANNEL_ROW_TO_NEXT_SPACING = OPTION_SPACING -- spacing between channel row and next element (Whisper)
            local SECTION_HEADERS_ADJUST = 20 -- move subsequent section headers up by ~20px
             
             -- DYNAMIC LAYOUT CALCULATION - Everything flows from the variables above
             local currentY = FIRST_HEADER_Y
             
             -- Section 1: Summon Announcements
             local HEADER1_Y = currentY
             local SECTION1_START = HEADER1_Y - HEADER_TO_OPTION_SPACING
             local SECTION1_OPTIONS = 2 -- announce summon toggle + whisper
             local TEXT_FIELD_HEIGHT = 55 -- Label (3 lines) + EditBox + spacing
             -- Include the summon channel row height to keep spacing consistent with other sections
             local SECTION1_END = SECTION1_START - (SECTION1_OPTIONS * CHECKBOX_HEIGHT) - (TEXT_FIELD_HEIGHT * 2) - CHANNEL_ROW_HEIGHT - CHANNEL_ROW_TO_NEXT_SPACING
             
             -- Section 2: Heartstone Announcements  
             local HEADER2_Y = SECTION1_END - SECTION_TO_SECTION_SPACING + SECTION_HEADERS_ADJUST
             local SECTION2_START = HEADER2_Y - HEADER_TO_OPTION_SPACING
             local SECTION2_OPTIONS = 1 -- ritual checkbox
             -- Include ritual channel row height to keep spacing correct before Misc header
             local SECTION2_END = SECTION2_START - (SECTION2_OPTIONS * CHECKBOX_HEIGHT) - TEXT_FIELD_HEIGHT - CHANNEL_ROW_HEIGHT - CHANNEL_ROW_TO_NEXT_SPACING
             
             -- Section 3: Miscellaneous
             local HEADER3_Y = SECTION2_END - SECTION_TO_SECTION_SPACING + SECTION_HEADERS_ADJUST
             local SECTION3_START = HEADER3_Y - HEADER_TO_OPTION_SPACING
             local SECTION3_OPTIONS = 1 -- rangeCheck only
            
            -- Create or update headers dynamically (if they don't exist in XML)
            local function createOrUpdateHeader(name, text, yPos)
                local header = getglobal("RaidSummonPlusOptionsFrameContentArea" .. name)
                if header then
                    -- Update existing header position
                    header:ClearAllPoints()
                    header:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 3, yPos)
                end
            end
            
            -- Update header positions to match our calculations
            createOrUpdateHeader("SummonHeader", "Summon Announcements", HEADER1_Y)
            createOrUpdateHeader("SoulstoneHeader", "Heartstone Announcements", HEADER2_Y)
            createOrUpdateHeader("MiscHeader", "Miscellaneous", HEADER3_Y)
            
            -- SUMMON MESSAGES SECTION
            optionCheckboxes.announceSummon = createCheckboxOption(contentArea, "AnnounceSummon", "Announce Ritual of Summoning", SECTION1_START, nil)
            if optionCheckboxes.announceSummon then
                optionCheckboxes.announceSummon:SetScript("OnClick", RaidSummonPlusOptions_AnnounceSummonToggle)
            end
            
            -- Custom summon message text field
            -- Update helper text to remove channel placeholders (channels are now configured via checkboxes)
            optionCheckboxes.summonMessage = createTextInput(contentArea, "SummonMessage", "Accepted placeholders:\n{targetname}, {zone}, {subzone}, {shards}", "", 0, optionCheckboxes.announceSummon, 180)
            if optionCheckboxes.summonMessage then
                optionCheckboxes.summonMessage:SetScript("OnTextChanged", RaidSummonPlusOptions_SummonMessageChanged)
            end
            
            -- New: Summon announcement channels (you can select multiple)
            -- Create a row container to center the channel checkboxes beneath the input
            local channelRow = CreateFrame("Frame", "RaidSummonPlusOptionsChannelRow", contentArea)
            channelRow:SetHeight(16)
            channelRow:ClearAllPoints()
            channelRow:SetPoint("TOP", optionCheckboxes.summonMessage, "BOTTOM", -2, 0)
            
            optionCheckboxes.summonChannelRaid = createCheckboxOption(contentArea, "SummonChannelRaid", "Raid", 0, optionCheckboxes.summonMessage)
            if optionCheckboxes.summonChannelRaid then
                optionCheckboxes.summonChannelRaid:SetScript("OnClick", RaidSummonPlusOptions_SummonChannelRaidToggle)
                -- Re-anchor into the centered row
                optionCheckboxes.summonChannelRaid:ClearAllPoints()
                optionCheckboxes.summonChannelRaid:SetPoint("TOPLEFT", channelRow, "TOPLEFT", 0, 0)
                -- Tighten label spacing next to checkbox (3px)
                optionCheckboxes.summonChannelRaid.label:ClearAllPoints()
                optionCheckboxes.summonChannelRaid.label:SetPoint("LEFT", optionCheckboxes.summonChannelRaid, "RIGHT", 3, 0)
            end
            optionCheckboxes.summonChannelParty = createCheckboxOption(contentArea, "SummonChannelParty", "party", 0, optionCheckboxes.summonChannelRaid)
            if optionCheckboxes.summonChannelParty then
                optionCheckboxes.summonChannelParty:SetScript("OnClick", RaidSummonPlusOptions_SummonChannelPartyToggle)
                -- Reposition to be inline with Raid, minimal spacing (3px)
                optionCheckboxes.summonChannelParty:ClearAllPoints()
                optionCheckboxes.summonChannelParty:SetPoint("LEFT", optionCheckboxes.summonChannelRaid.label, "RIGHT", 3, 0)
                -- Tighten label spacing next to checkbox (3px)
                optionCheckboxes.summonChannelParty.label:ClearAllPoints()
                optionCheckboxes.summonChannelParty.label:SetPoint("LEFT", optionCheckboxes.summonChannelParty, "RIGHT", 3, 0)
            end
            optionCheckboxes.summonChannelSay = createCheckboxOption(contentArea, "SummonChannelSay", "say", 0, optionCheckboxes.summonChannelParty)
            if optionCheckboxes.summonChannelSay then
                optionCheckboxes.summonChannelSay:SetScript("OnClick", RaidSummonPlusOptions_SummonChannelSayToggle)
                -- Reposition to be inline with previous, minimal spacing (3px)
                optionCheckboxes.summonChannelSay:ClearAllPoints()
                optionCheckboxes.summonChannelSay:SetPoint("LEFT", optionCheckboxes.summonChannelParty.label, "RIGHT", 3, 0)
                -- Tighten label spacing next to checkbox (3px)
                optionCheckboxes.summonChannelSay.label:ClearAllPoints()
                optionCheckboxes.summonChannelSay.label:SetPoint("LEFT", optionCheckboxes.summonChannelSay, "RIGHT", 3, 0)
            end
            optionCheckboxes.summonChannelYell = createCheckboxOption(contentArea, "SummonChannelYell", "yell", 0, optionCheckboxes.summonChannelSay)
            if optionCheckboxes.summonChannelYell then
                optionCheckboxes.summonChannelYell:SetScript("OnClick", RaidSummonPlusOptions_SummonChannelYellToggle)
                -- Reposition to be inline with previous, minimal spacing (3px)
                optionCheckboxes.summonChannelYell:ClearAllPoints()
                optionCheckboxes.summonChannelYell:SetPoint("LEFT", optionCheckboxes.summonChannelSay.label, "RIGHT", 3, 0)
                -- Tighten label spacing next to checkbox (3px)
                optionCheckboxes.summonChannelYell.label:ClearAllPoints()
                optionCheckboxes.summonChannelYell.label:SetPoint("LEFT", optionCheckboxes.summonChannelYell, "RIGHT", 3, 0)
            end
            
            -- Measure total width to center the row container under the input
            if optionCheckboxes.summonChannelRaid and optionCheckboxes.summonChannelParty and optionCheckboxes.summonChannelSay and optionCheckboxes.summonChannelYell then
                local function itemWidth(cb)
                    if not cb then return 0 end
                    local checkboxWidth = 16
                    local labelSpacing = 3
                    local labelWidth = (cb.label and cb.label.GetStringWidth and cb.label:GetStringWidth()) or 0
                    return checkboxWidth + labelSpacing + labelWidth
                end
                local gap = 3
                local totalWidth = itemWidth(optionCheckboxes.summonChannelRaid) + gap + itemWidth(optionCheckboxes.summonChannelParty) + gap + itemWidth(optionCheckboxes.summonChannelSay) + gap + itemWidth(optionCheckboxes.summonChannelYell)
                channelRow:SetWidth(totalWidth)
            end
            optionCheckboxes.whisper = createCheckboxOption(contentArea, "Whisper", "Whisper announce", 0, nil)
            if optionCheckboxes.whisper then
                optionCheckboxes.whisper:SetScript("OnClick", RaidSummonPlusOptions_WhisperToggle)
                -- Keep Whisper on a new row under the channel row, but align to the original left margin
                optionCheckboxes.whisper:ClearAllPoints()
                optionCheckboxes.whisper:SetPoint("TOP", channelRow, "BOTTOM", 0, -OPTION_SPACING)
                optionCheckboxes.whisper:SetPoint("LEFT", contentArea, "LEFT", 15, 0)
            end
            
            -- Custom whisper message text field
            optionCheckboxes.whisperMessage = createTextInput(contentArea, "WhisperMessage", "Accepted placeholders:\n{targetname}, {zone}, {subzone}, {shards}", "", 0, optionCheckboxes.whisper, 180)
            if optionCheckboxes.whisperMessage then
                optionCheckboxes.whisperMessage:SetScript("OnTextChanged", RaidSummonPlusOptions_WhisperMessageChanged)
            end
            
            -- HEARTSTONE ANNOUNCEMENTS SECTION
            optionCheckboxes.ritual = createCheckboxOption(contentArea, "Ritual", "Announce Ritual of Souls", SECTION2_START, nil)
            if optionCheckboxes.ritual then
                optionCheckboxes.ritual:SetScript("OnClick", RaidSummonPlusOptions_RitualToggle)
            end
            
            -- Custom message text field
            optionCheckboxes.ritualMessage = createTextInput(contentArea, "RitualMessage", "Accepted placeholders:\n{healvalue}, {talentrank}, {masterconjuror}", "", 0, optionCheckboxes.ritual, 180)
            if optionCheckboxes.ritualMessage then
                optionCheckboxes.ritualMessage:SetScript("OnTextChanged", RaidSummonPlusOptions_RitualMessageChanged)
            end
            
            -- New: Ritual announcement channels (same styling as Summon channels)
            local ritualChannelRow = CreateFrame("Frame", "RaidSummonPlusOptionsRitualChannelRow", contentArea)
            ritualChannelRow:SetHeight(16)
            ritualChannelRow:ClearAllPoints()
            ritualChannelRow:SetPoint("TOP", optionCheckboxes.ritualMessage, "BOTTOM", -2, 0)
            
            optionCheckboxes.ritualChannelRaid = createCheckboxOption(contentArea, "RitualChannelRaid", "Raid", 0, optionCheckboxes.ritualMessage)
            if optionCheckboxes.ritualChannelRaid then
                optionCheckboxes.ritualChannelRaid:SetScript("OnClick", RaidSummonPlusOptions_RitualChannelRaidToggle)
                optionCheckboxes.ritualChannelRaid:ClearAllPoints()
                optionCheckboxes.ritualChannelRaid:SetPoint("TOPLEFT", ritualChannelRow, "TOPLEFT", 0, 0)
                optionCheckboxes.ritualChannelRaid.label:ClearAllPoints()
                optionCheckboxes.ritualChannelRaid.label:SetPoint("LEFT", optionCheckboxes.ritualChannelRaid, "RIGHT", 3, 0)
            end
            
            optionCheckboxes.ritualChannelParty = createCheckboxOption(contentArea, "RitualChannelParty", "party", 0, optionCheckboxes.ritualChannelRaid)
            if optionCheckboxes.ritualChannelParty then
                optionCheckboxes.ritualChannelParty:SetScript("OnClick", RaidSummonPlusOptions_RitualChannelPartyToggle)
                optionCheckboxes.ritualChannelParty:ClearAllPoints()
                optionCheckboxes.ritualChannelParty:SetPoint("LEFT", optionCheckboxes.ritualChannelRaid.label, "RIGHT", 3, 0)
                optionCheckboxes.ritualChannelParty.label:ClearAllPoints()
                optionCheckboxes.ritualChannelParty.label:SetPoint("LEFT", optionCheckboxes.ritualChannelParty, "RIGHT", 3, 0)
            end
            
            optionCheckboxes.ritualChannelSay = createCheckboxOption(contentArea, "RitualChannelSay", "say", 0, optionCheckboxes.ritualChannelParty)
            if optionCheckboxes.ritualChannelSay then
                optionCheckboxes.ritualChannelSay:SetScript("OnClick", RaidSummonPlusOptions_RitualChannelSayToggle)
                optionCheckboxes.ritualChannelSay:ClearAllPoints()
                optionCheckboxes.ritualChannelSay:SetPoint("LEFT", optionCheckboxes.ritualChannelParty.label, "RIGHT", 3, 0)
                optionCheckboxes.ritualChannelSay.label:ClearAllPoints()
                optionCheckboxes.ritualChannelSay.label:SetPoint("LEFT", optionCheckboxes.ritualChannelSay, "RIGHT", 3, 0)
            end
            
            optionCheckboxes.ritualChannelYell = createCheckboxOption(contentArea, "RitualChannelYell", "yell", 0, optionCheckboxes.ritualChannelSay)
            if optionCheckboxes.ritualChannelYell then
                optionCheckboxes.ritualChannelYell:SetScript("OnClick", RaidSummonPlusOptions_RitualChannelYellToggle)
                optionCheckboxes.ritualChannelYell:ClearAllPoints()
                optionCheckboxes.ritualChannelYell:SetPoint("LEFT", optionCheckboxes.ritualChannelSay.label, "RIGHT", 3, 0)
                optionCheckboxes.ritualChannelYell.label:ClearAllPoints()
                optionCheckboxes.ritualChannelYell.label:SetPoint("LEFT", optionCheckboxes.ritualChannelYell, "RIGHT", 3, 0)
            end
            
            -- Measure total width to center the ritual channel row under the input
            if optionCheckboxes.ritualChannelRaid and optionCheckboxes.ritualChannelParty and optionCheckboxes.ritualChannelSay and optionCheckboxes.ritualChannelYell then
                local function itemWidth2(cb)
                    if not cb then return 0 end
                    local checkboxWidth = 16
                    local labelSpacing = 3
                    local labelWidth = (cb.label and cb.label.GetStringWidth and cb.label:GetStringWidth()) or 0
                    return checkboxWidth + labelSpacing + labelWidth
                end
                local gap = 3
                local totalWidth2 = itemWidth2(optionCheckboxes.ritualChannelRaid) + gap + itemWidth2(optionCheckboxes.ritualChannelParty) + gap + itemWidth2(optionCheckboxes.ritualChannelSay) + gap + itemWidth2(optionCheckboxes.ritualChannelYell)
                ritualChannelRow:SetWidth(totalWidth2)
            end
            
            -- MISCELLANEOUS SECTION
            optionCheckboxes.rangeCheck = createCheckboxOption(contentArea, "RangeCheck", "Auto-remove players in range (40 yd)", SECTION3_START, nil)
            if optionCheckboxes.rangeCheck then
                optionCheckboxes.rangeCheck:SetScript("OnClick", RaidSummonPlusOptions_RangeCheckToggle)
            end

            -- Re-anchor section headers based on actual rendered controls to avoid overlap at high scaling
            do
                local headerSoul = getglobal("RaidSummonPlusOptionsFrameContentAreaSoulstoneHeader")
                local headerMisc = getglobal("RaidSummonPlusOptionsFrameContentAreaMiscHeader")
                local ritualChannelRow = getglobal("RaidSummonPlusOptionsRitualChannelRow")
                local headerSummon = getglobal("RaidSummonPlusOptionsFrameContentAreaSummonHeader")

                -- Place the Ritual section header directly under the last control of the Summon section,
                -- but keep the same left alignment as the Summon header (lock LEFT to contentArea)
                if headerSoul and optionCheckboxes.whisperMessage then
                    headerSoul:ClearAllPoints()
                    headerSoul:SetPoint("LEFT", contentArea, "LEFT", 3, 0)
                    headerSoul:SetPoint("TOP", optionCheckboxes.whisperMessage, "BOTTOM", 0, -SECTION_TO_SECTION_SPACING)
                end

                -- Anchor the first control of the Ritual section under its header using the SAME top-to-top spacing as Summon
                if optionCheckboxes.ritual and headerSoul then
                    optionCheckboxes.ritual:ClearAllPoints()
                    optionCheckboxes.ritual:SetPoint("TOPLEFT", headerSoul, "TOPLEFT", 12, -HEADER_TO_OPTION_SPACING)
                end

                -- Place the Misc header under the last control of the Ritual section (prefer the channel row if present),
                -- and keep the same left alignment as the other headers
                if headerMisc then
                    if ritualChannelRow then
                        headerMisc:ClearAllPoints()
                        headerMisc:SetPoint("LEFT", contentArea, "LEFT", 3, 0)
                        headerMisc:SetPoint("TOP", ritualChannelRow, "BOTTOM", 0, -SECTION_TO_SECTION_SPACING)
                    elseif optionCheckboxes.ritualMessage then
                        headerMisc:ClearAllPoints()
                        headerMisc:SetPoint("LEFT", contentArea, "LEFT", 3, 0)
                        headerMisc:SetPoint("TOP", optionCheckboxes.ritualMessage, "BOTTOM", 0, -SECTION_TO_SECTION_SPACING)
                    end
                end

                -- Anchor the first Misc control under its header using the SAME top-to-top spacing as Summon
                if optionCheckboxes.rangeCheck and headerMisc then
                    optionCheckboxes.rangeCheck:ClearAllPoints()
                    optionCheckboxes.rangeCheck:SetPoint("TOPLEFT", headerMisc, "TOPLEFT", 12, -HEADER_TO_OPTION_SPACING)
                end
            end
        end
    end
    
    -- Always re-apply header alignment and consistent header-to-first-option spacing on every OnShow
    do
        local contentArea = RaidSummonPlusOptionsFrameContentArea
        if contentArea and optionCheckboxes and optionCheckboxes.announceSummon then
            local headerSummon = getglobal("RaidSummonPlusOptionsFrameContentAreaSummonHeader")
            local headerSoul   = getglobal("RaidSummonPlusOptionsFrameContentAreaSoulstoneHeader")
            local headerMisc   = getglobal("RaidSummonPlusOptionsFrameContentAreaMiscHeader")
            local ritualChannelRow = getglobal("RaidSummonPlusOptionsRitualChannelRow")
    
            -- Measure Summon header -> first option visual gap (top-to-top)
            local spacingTop = 20
            if headerSummon and headerSummon.GetTop and optionCheckboxes.announceSummon and optionCheckboxes.announceSummon.GetTop then
                local ht = headerSummon:GetTop()
                local ct = optionCheckboxes.announceSummon:GetTop()
                if ht and ct then
                    local st = ht - ct
                    if st and st > 0 and st < 200 then
                        spacingTop = st
                    end
                end
            end
    
            -- Keep headers aligned to the content left
            if headerSoul and optionCheckboxes.whisperMessage then
                headerSoul:ClearAllPoints()
                headerSoul:SetPoint("LEFT", contentArea, "LEFT", 3, 0)
                headerSoul:SetPoint("TOP", optionCheckboxes.whisperMessage, "BOTTOM", 0, -10)
            end
    
            if optionCheckboxes.ritual and headerSoul then
                optionCheckboxes.ritual:ClearAllPoints()
                optionCheckboxes.ritual:SetPoint("TOPLEFT", headerSoul, "TOPLEFT", 12, -spacingTop)
            end
    
            if headerMisc then
                if ritualChannelRow then
                    headerMisc:ClearAllPoints()
                    headerMisc:SetPoint("LEFT", contentArea, "LEFT", 3, 0)
                    headerMisc:SetPoint("TOP", ritualChannelRow, "BOTTOM", 0, -10)
                elseif optionCheckboxes.ritualMessage then
                    headerMisc:ClearAllPoints()
                    headerMisc:SetPoint("LEFT", contentArea, "LEFT", 3, 0)
                    headerMisc:SetPoint("TOP", optionCheckboxes.ritualMessage, "BOTTOM", 0, -10)
                end
            end
    
            if optionCheckboxes.rangeCheck and headerMisc then
                optionCheckboxes.rangeCheck:ClearAllPoints()
                optionCheckboxes.rangeCheck:SetPoint("TOPLEFT", headerMisc, "TOPLEFT", 12, -spacingTop)
            end
        end
    end
    
    -- Ensure RaidSummonPlusOptions exists
    if not RaidSummonPlusOptions then
        RaidSummonPlusOptions = {}
    end
    
    -- Set default values if they don't exist
    if RaidSummonPlusOptions["announceSummon"] == nil then
        RaidSummonPlusOptions["announceSummon"] = true  -- Default to enabled
    end
    if RaidSummonPlusOptions["whisper"] == nil then
        RaidSummonPlusOptions["whisper"] = true
    end
    if RaidSummonPlusOptions["summonMessage"] == nil then
        RaidSummonPlusOptions["summonMessage"] = "Summoning {targetname}"  -- First install default text
    end
    if RaidSummonPlusOptions["whisperMessage"] == nil then
        RaidSummonPlusOptions["whisperMessage"] = "Summoning you to {zone}"  -- First install default text
    end
    if RaidSummonPlusOptions["ritual"] == nil then
        RaidSummonPlusOptions["ritual"] = true
    end
    if RaidSummonPlusOptions["ritualMessage"] == nil or RaidSummonPlusOptions["ritualMessage"] == "" then
        RaidSummonPlusOptions["ritualMessage"] = "{healvalue} Cookies"  -- Set actual default
    end

    -- New defaults for summon announcement channels
    if RaidSummonPlusOptions["summonChannelRaid"] == nil then
        RaidSummonPlusOptions["summonChannelRaid"] = true  -- Default: Raid only
    end
    if RaidSummonPlusOptions["summonChannelParty"] == nil then
    RaidSummonPlusOptions["summonChannelParty"] = true
    end
    if RaidSummonPlusOptions["summonChannelSay"] == nil then
        RaidSummonPlusOptions["summonChannelSay"] = false
    end
    if RaidSummonPlusOptions["summonChannelYell"] == nil then
        RaidSummonPlusOptions["summonChannelYell"] = false
    end

    -- Defaults for ritual announcement channels
    if RaidSummonPlusOptions["ritualChannelRaid"] == nil then
        RaidSummonPlusOptions["ritualChannelRaid"] = false
    end
    if RaidSummonPlusOptions["ritualChannelParty"] == nil then
        RaidSummonPlusOptions["ritualChannelParty"] = false
    end
    if RaidSummonPlusOptions["ritualChannelSay"] == nil then
        RaidSummonPlusOptions["ritualChannelSay"] = false
    end
    if RaidSummonPlusOptions["ritualChannelYell"] == nil then
        RaidSummonPlusOptions["ritualChannelYell"] = true
    end

    -- Cross-addon compatibility is always enabled
    RaidSummonPlus_CrossAddonCompatibility = true
    if RaidSummonPlusOptions["rangeCheck"] == nil then
        RaidSummonPlusOptions["rangeCheck"] = false  -- Default to disabled
    end
    
    -- Update checkbox states (force refresh to prevent desync)
    if optionCheckboxes.announceSummon then
        optionCheckboxes.announceSummon:SetChecked(RaidSummonPlusOptions["announceSummon"])
    end
    if optionCheckboxes.whisper then
        optionCheckboxes.whisper:SetChecked(RaidSummonPlusOptions["whisper"])
    end
    -- New: update summon channel checkbox states
    if optionCheckboxes.summonChannelRaid then
        optionCheckboxes.summonChannelRaid:SetChecked(RaidSummonPlusOptions["summonChannelRaid"])
    end
    if optionCheckboxes.summonChannelParty then
        optionCheckboxes.summonChannelParty:SetChecked(RaidSummonPlusOptions["summonChannelParty"])
    end
    if optionCheckboxes.summonChannelSay then
        optionCheckboxes.summonChannelSay:SetChecked(RaidSummonPlusOptions["summonChannelSay"])
    end
    if optionCheckboxes.summonChannelYell then
        optionCheckboxes.summonChannelYell:SetChecked(RaidSummonPlusOptions["summonChannelYell"])
    end
    if optionCheckboxes.summonMessage then
        local displayMessage = RaidSummonPlusOptions["summonMessage"] or ""
        -- Clear text first to prevent overlapping
        optionCheckboxes.summonMessage:SetText("")
        optionCheckboxes.summonMessage:SetText(displayMessage)
        optionCheckboxes.summonMessage:HighlightText(0, 0) -- Clear any selection
    end
    if optionCheckboxes.whisperMessage then
        local displayWhisperMessage = RaidSummonPlusOptions["whisperMessage"] or ""
        -- Clear text first to prevent overlapping
        optionCheckboxes.whisperMessage:SetText("")
        optionCheckboxes.whisperMessage:SetText(displayWhisperMessage)
        optionCheckboxes.whisperMessage:HighlightText(0, 0) -- Clear any selection
    end
    if optionCheckboxes.ritual then
        optionCheckboxes.ritual:SetChecked(RaidSummonPlusOptions["ritual"])
    end
    if optionCheckboxes.ritualMessage then
        -- Clear text first to prevent overlapping
        optionCheckboxes.ritualMessage:SetText("")
        optionCheckboxes.ritualMessage:SetText(RaidSummonPlusOptions["ritualMessage"])
        optionCheckboxes.ritualMessage:HighlightText(0, 0) -- Clear any selection
    end

    -- Update ritual channel checkbox states
    if optionCheckboxes.ritualChannelRaid then
        optionCheckboxes.ritualChannelRaid:SetChecked(RaidSummonPlusOptions["ritualChannelRaid"])
    end
    if optionCheckboxes.ritualChannelParty then
        optionCheckboxes.ritualChannelParty:SetChecked(RaidSummonPlusOptions["ritualChannelParty"])
    end
    if optionCheckboxes.ritualChannelSay then
        optionCheckboxes.ritualChannelSay:SetChecked(RaidSummonPlusOptions["ritualChannelSay"])
    end
    if optionCheckboxes.ritualChannelYell then
        optionCheckboxes.ritualChannelYell:SetChecked(RaidSummonPlusOptions["ritualChannelYell"])
    end


    if optionCheckboxes.rangeCheck then
        optionCheckboxes.rangeCheck:SetChecked(RaidSummonPlusOptions["rangeCheck"])
    end
    
    -- Ensure the options frame is wide enough to contain content under UI/text scaling
    do
        local parent = RaidSummonPlusOptionsFrame
        local contentArea = RaidSummonPlusOptionsFrameContentArea
        if parent and contentArea then
            -- Compute symmetric margins to mirror the visually correct left margin
            -- Left margin = content area left offset (10) + inner anchor offset (15)
            local contentLeftPad = 10 + 15
            local contentRightPad = contentLeftPad

            local maxContentWidth = 0

            local function considerWidth(w)
                if w and w > maxContentWidth then maxContentWidth = w end
            end

            local function checkboxTotalWidth(cb)
                if not cb then return 0 end
                local w = 16 + 8 -- checkbox + gap
                if cb.label and cb.label.GetStringWidth then
                    w = w + (cb.label:GetStringWidth() or 0)
                end
                return w
            end

            -- Edit boxes define primary content widths
            considerWidth(optionCheckboxes.summonMessage and optionCheckboxes.summonMessage:GetWidth())
            considerWidth(optionCheckboxes.whisperMessage and optionCheckboxes.whisperMessage:GetWidth())
            considerWidth(optionCheckboxes.ritualMessage and optionCheckboxes.ritualMessage:GetWidth())

            -- Single checkboxes with text
            considerWidth(checkboxTotalWidth(optionCheckboxes.announceSummon))
            considerWidth(checkboxTotalWidth(optionCheckboxes.whisper))
            considerWidth(checkboxTotalWidth(optionCheckboxes.rangeCheck))

            -- Inline channel rows can exceed edit box width
            local channelRow = _G["RaidSummonPlusOptionsChannelRow"]
            if channelRow and channelRow.GetWidth then
                considerWidth(channelRow:GetWidth())
            end
            local ritualChannelRow = _G["RaidSummonPlusOptionsRitualChannelRow"]
            if ritualChannelRow and ritualChannelRow.GetWidth then
                considerWidth(ritualChannelRow:GetWidth())
            end

            -- Desired width uses symmetric padding around the widest content block
            local desiredWidth = maxContentWidth + contentLeftPad + contentRightPad

            -- Also ensure the title fits (account for its own offsets and close button)
            local titleFS = _G["RaidSummonPlusOptionsFrameTitleFrameTitle"]
            if titleFS and titleFS.GetStringWidth then
                local titleExtra = 3 + 5 + 14 + 12  -- left offset + right margin + button size + small buffer
                local titleWidth = (titleFS:GetStringWidth() or 0) + titleExtra
                if titleWidth > desiredWidth then desiredWidth = titleWidth end
            end

            -- Never shrink below current size, only expand when needed
            local currentWidth = parent:GetWidth() or 0
            if desiredWidth > currentWidth then
                parent:SetWidth(desiredWidth)
            end

            -- Keep title frame matching parent width so the close button stays aligned
            if RaidSummonPlusOptionsFrameTitleFrame then
                RaidSummonPlusOptionsFrameTitleFrame:SetWidth(parent:GetWidth())
            end

            -- Calculate desired height so all content fits when fonts/UI are scaled
            -- Calculate desired height so all content fits when fonts/UI are scaled
            local titleHeight = (RaidSummonPlusOptionsFrameTitleFrame and RaidSummonPlusOptionsFrameTitleFrame:GetHeight()) or 18
            local gapTitleToContent = 10 -- matches XML offset
            -- Mirror bottom padding to the same visual padding used at the top of the content
            -- Measure: distance from content area's TOP to the first header's TOP
            local headerSummon = _G["RaidSummonPlusOptionsFrameContentAreaSummonHeader"]
            local contentTop = contentArea.GetTop and contentArea:GetTop() or nil
            -- IMPORTANT: Normalize deltas by the parent scale so we compare/set heights in the same unit space
            local parentScale = 1
            if parent and parent.GetEffectiveScale then
                parentScale = parent:GetEffectiveScale() or 1
            elseif parent and parent.GetScale then
                parentScale = parent:GetScale() or 1
            end
            if parentScale <= 0 then parentScale = 1 end
            
            local topPadWithinContent = 0
            if headerSummon and headerSummon.GetTop and contentTop then
                local ht = headerSummon:GetTop()
                if ht then
                    local pad = (contentTop - ht) / parentScale
                    if pad and pad > 0 and pad < 100 then
                        topPadWithinContent = pad
                    end
                end
            end
            -- Desired bottom padding equals total top padding (external + internal), but never less than 15px
            local MIN_BOTTOM_PADDING = 20
            local bottomPadding = math.max(gapTitleToContent + topPadWithinContent, MIN_BOTTOM_PADDING)
            
            local lowestBottom = nil
            
            local function considerBottom(frame)
                if frame and frame.GetBottom then
                    local b = frame:GetBottom()
                    if b then
                        if not lowestBottom or b < lowestBottom then
                            lowestBottom = b
                        end
                    end
                end
            end
            
            -- New helper to include checkbox label bottoms in lowest-bottom calc
            local function considerLabelBottom(cb)
                if cb and cb.label and cb.label.GetBottom then
                    considerBottom(cb.label)
                end
            end
            
            -- Consider likely lowest UI pieces
            considerBottom(_G["RaidSummonPlusOptionsRitualChannelRow"])   -- ritual channels row
            considerBottom(_G["RaidSummonPlusOptionsChannelRow"])         -- summon channels row
            considerBottom(optionCheckboxes and optionCheckboxes.rangeCheck)
            considerBottom(optionCheckboxes and optionCheckboxes.ritualMessage)
            considerBottom(optionCheckboxes and optionCheckboxes.whisperMessage)
            considerBottom(optionCheckboxes and optionCheckboxes.summonMessage)
            -- Consider headers too, in case of extreme scaling and font metrics
            considerBottom(_G["RaidSummonPlusOptionsFrameContentAreaMiscHeader"]) 
            considerBottom(_G["RaidSummonPlusOptionsFrameContentAreaSoulstoneHeader"]) 
            considerBottom(_G["RaidSummonPlusOptionsFrameContentAreaSummonHeader"]) 
             -- Also include labels which may extend slightly below their checkbox baselines
             considerLabelBottom(optionCheckboxes and optionCheckboxes.rangeCheck)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.whisper)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.announceSummon)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.summonChannelRaid)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.summonChannelParty)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.summonChannelSay)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.summonChannelYell)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.ritualChannelRaid)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.ritualChannelParty)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.ritualChannelSay)
             considerLabelBottom(optionCheckboxes and optionCheckboxes.ritualChannelYell)
             
             if contentTop and lowestBottom then
                local BOTTOM_SAFETY = 8
                -- Normalize delta by parent scale so SetHeight (unscaled) gets correct value
                local contentNeeded = ((contentTop - lowestBottom) / parentScale) + bottomPadding + BOTTOM_SAFETY
                -- Remove explicit contentArea sizing; rely on bottom anchoring + parent height
                -- local currentContentHeight = contentArea:GetHeight() or 0
                -- if contentNeeded > currentContentHeight then
                --     contentArea:SetHeight(math.ceil(contentNeeded))
                -- end
                -- contentArea height is driven by bottom anchoring; we only adjust parent height
                local desiredHeight = titleHeight + gapTitleToContent + contentNeeded
                if desiredHeight > (parent:GetHeight() or 0) then
                   parent:SetHeight(math.ceil(desiredHeight))
               end

               -- Second pass: re-measure after layout changes to catch rounding/font reflow
               local contentTop2 = contentArea.GetTop and contentArea:GetTop() or nil
               local lowestBottom2 = nil
               if contentTop2 then
                   local function consider2(frame)
                       if frame and frame.GetBottom then
                           local b = frame:GetBottom()
                           if b then
                               if not lowestBottom2 or b < lowestBottom2 then
                                   lowestBottom2 = b
                               end
                           end
                       end
                   end
                   local function considerLabel2(cb)
                       if cb and cb.label and cb.label.GetBottom then
                           consider2(cb.label)
                       end
                   end

                   consider2(_G["RaidSummonPlusOptionsRitualChannelRow"])   
                   consider2(_G["RaidSummonPlusOptionsChannelRow"])         
                   consider2(optionCheckboxes and optionCheckboxes.rangeCheck)
                   consider2(optionCheckboxes and optionCheckboxes.ritualMessage)
                   consider2(optionCheckboxes and optionCheckboxes.whisperMessage)
                   consider2(optionCheckboxes and optionCheckboxes.summonMessage)
                   consider2(_G["RaidSummonPlusOptionsFrameContentAreaMiscHeader"]) 
                   consider2(_G["RaidSummonPlusOptionsFrameContentAreaSoulstoneHeader"]) 
                   consider2(_G["RaidSummonPlusOptionsFrameContentAreaSummonHeader"]) 
                   considerLabel2(optionCheckboxes and optionCheckboxes.rangeCheck)
                   considerLabel2(optionCheckboxes and optionCheckboxes.whisper)
                   considerLabel2(optionCheckboxes and optionCheckboxes.announceSummon)
                   considerLabel2(optionCheckboxes and optionCheckboxes.summonChannelRaid)
                   considerLabel2(optionCheckboxes and optionCheckboxes.summonChannelParty)
                   considerLabel2(optionCheckboxes and optionCheckboxes.summonChannelSay)
                   considerLabel2(optionCheckboxes and optionCheckboxes.summonChannelYell)
                   considerLabel2(optionCheckboxes and optionCheckboxes.ritualChannelRaid)
                   considerLabel2(optionCheckboxes and optionCheckboxes.ritualChannelParty)
                   considerLabel2(optionCheckboxes and optionCheckboxes.ritualChannelSay)
                   considerLabel2(optionCheckboxes and optionCheckboxes.ritualChannelYell)

                   if lowestBottom2 then
                       local contentNeeded2 = ((contentTop2 - lowestBottom2) / parentScale) + bottomPadding + BOTTOM_SAFETY
                       -- contentArea height is driven by bottom anchoring; we only adjust parent height
                       local desiredHeight2 = titleHeight + gapTitleToContent + contentNeeded2
                       local currentParentHeight2 = parent:GetHeight() or 0
                       if desiredHeight2 > currentParentHeight2 then
                           parent:SetHeight(math.ceil(desiredHeight2))
                       end
                   end
               end
            end
            end
        end
        -- Ensure the options frame always fits on screen by auto-scaling down if necessary
        do
            local parent = RaidSummonPlusOptionsFrame
            if parent and parent.GetHeight and UIParent then
                local uiW = UIParent:GetWidth() or 1024
                local uiH = UIParent:GetHeight() or 768
                local margin = 30 -- safe padding from edges
                local frameW = parent:GetWidth() or 0
                local frameH = parent:GetHeight() or 0
                local currentScale = parent:GetScale() or 1

                if frameW > 0 and frameH > 0 then
                    -- Compute the maximum allowed scale so both width and height fit
                    local maxScaleW = (uiW - margin) / frameW
                    local maxScaleH = (uiH - margin) / frameH
                    local targetScale = math.min(1, maxScaleW, maxScaleH)

                    -- Only shrink when needed; never upscale above 1
                    if targetScale < currentScale - 0.001 then
                        parent:SetScale(targetScale)
                        -- Keep it centered and fully within the screen after scaling
                        parent:ClearAllPoints()
                        parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                    end
                end
            end
        end
        -- One-frame deferred finalization to catch late font/layout and post-scale positions
        do
            local parent = RaidSummonPlusOptionsFrame
            local contentArea = RaidSummonPlusOptionsFrameContentArea
            if parent and contentArea and parent.SetScript then
                parent:SetScript("OnUpdate", function()
                    -- In WoW 1.12, script handlers don't pass `self`; use `this` or captured `parent`
                    local f = (type(this) ~= "nil" and this) or parent
                    if not f then return end
                    f:SetScript("OnUpdate", nil) -- run this only once
                    local parentScale = (f.GetEffectiveScale and f:GetEffectiveScale()) or (f.GetScale and f:GetScale()) or 1
                    if not parentScale or parentScale <= 0 then parentScale = 1 end

                    local rc = optionCheckboxes and optionCheckboxes.rangeCheck
                    if rc and rc.GetBottom and contentArea and contentArea.GetBottom then
                        local rcBottom = rc:GetBottom()
                        if rc.label and rc.label.GetBottom then
                            local lb = rc.label:GetBottom()
                            if lb and rcBottom then rcBottom = math.min(rcBottom, lb) elseif lb and not rcBottom then rcBottom = lb end
                        end
                        local contentBottom = contentArea:GetBottom()
                        if rcBottom and contentBottom and rcBottom < contentBottom then
                            local extra = ((contentBottom - rcBottom) / parentScale) + 12
                            local newDesiredParent = (f:GetHeight() or 0) + extra
                            f:SetHeight(math.ceil(newDesiredParent))

                            -- Optional: rescale once more if needed
                            if UIParent then
                                local uiW = UIParent:GetWidth() or 1024
                                local uiH = UIParent:GetHeight() or 768
                                local margin = 30
                                local maxScaleW = (uiW - margin) / (f:GetWidth() or 1)
                                local maxScaleH = (uiH - margin) / (f:GetHeight() or 1)
                                local targetScale = math.min(1, maxScaleW, maxScaleH)
                                local currentScale = f:GetScale() or 1
                                if targetScale < currentScale - 0.001 then
                                    f:SetScale(targetScale)
                                    f:ClearAllPoints()
                                    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                                end
                            end
                        end
                    end
                end)
            end
        end
end

-- Checkbox toggle functions
-- Helper function to output messages only when debug is enabled
function RaidSummonPlusOptions_DebugMessage(message)
    if RaidSummonPlusOptions and RaidSummonPlusOptions.debug then
        DEFAULT_CHAT_FRAME:AddMessage("RaidSummonPlus - " .. message)
    end
end

function RaidSummonPlusOptions_AnnounceSummonToggle()
    RaidSummonPlusOptions["announceSummon"] = not RaidSummonPlusOptions["announceSummon"]
    local status = RaidSummonPlusOptions["announceSummon"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("summon announcements: " .. status)
end

function RaidSummonPlusOptions_WhisperToggle()
    RaidSummonPlusOptions["whisper"] = not RaidSummonPlusOptions["whisper"]
    local status = RaidSummonPlusOptions["whisper"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("whisper: " .. status)
end

-- New: Toggle handlers for summon channel checkboxes
function RaidSummonPlusOptions_SummonChannelRaidToggle()
    RaidSummonPlusOptions["summonChannelRaid"] = not RaidSummonPlusOptions["summonChannelRaid"]
    local status = RaidSummonPlusOptions["summonChannelRaid"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("summon channel RAID: " .. status)
end

function RaidSummonPlusOptions_SummonChannelPartyToggle()
    RaidSummonPlusOptions["summonChannelParty"] = not RaidSummonPlusOptions["summonChannelParty"]
    local status = RaidSummonPlusOptions["summonChannelParty"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("summon channel PARTY: " .. status)
end

function RaidSummonPlusOptions_SummonChannelSayToggle()
    RaidSummonPlusOptions["summonChannelSay"] = not RaidSummonPlusOptions["summonChannelSay"]
    local status = RaidSummonPlusOptions["summonChannelSay"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("summon channel SAY: " .. status)
end

function RaidSummonPlusOptions_SummonChannelYellToggle()
    RaidSummonPlusOptions["summonChannelYell"] = not RaidSummonPlusOptions["summonChannelYell"]
    local status = RaidSummonPlusOptions["summonChannelYell"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("summon channel YELL: " .. status)
end

-- Toggle handlers for ritual channel checkboxes
function RaidSummonPlusOptions_RitualChannelRaidToggle()
    RaidSummonPlusOptions["ritualChannelRaid"] = not RaidSummonPlusOptions["ritualChannelRaid"]
    local status = RaidSummonPlusOptions["ritualChannelRaid"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("ritual channel RAID: " .. status)
end

function RaidSummonPlusOptions_RitualChannelPartyToggle()
    RaidSummonPlusOptions["ritualChannelParty"] = not RaidSummonPlusOptions["ritualChannelParty"]
    local status = RaidSummonPlusOptions["ritualChannelParty"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("ritual channel PARTY: " .. status)
end

function RaidSummonPlusOptions_RitualChannelSayToggle()
    RaidSummonPlusOptions["ritualChannelSay"] = not RaidSummonPlusOptions["ritualChannelSay"]
    local status = RaidSummonPlusOptions["ritualChannelSay"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("ritual channel SAY: " .. status)
end

function RaidSummonPlusOptions_RitualChannelYellToggle()
    RaidSummonPlusOptions["ritualChannelYell"] = not RaidSummonPlusOptions["ritualChannelYell"]
    local status = RaidSummonPlusOptions["ritualChannelYell"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("ritual channel YELL: " .. status)
end

function RaidSummonPlusOptions_RitualToggle()
    RaidSummonPlusOptions["ritual"] = not RaidSummonPlusOptions["ritual"]
    local status = RaidSummonPlusOptions["ritual"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("Ritual of Souls announcements: " .. status)
end

function RaidSummonPlusOptions_SummonMessageChanged()
    if not this then return end
    local text = this:GetText() or ""
    
    -- Prevent text corruption by validating input
    if string.len(text) > 200 then
        text = string.sub(text, 1, 200)
        this:SetText(text)
    end
    
    -- Always store the actual text (empty means disabled)
    RaidSummonPlusOptions["summonMessage"] = text
end

function RaidSummonPlusOptions_WhisperMessageChanged()
    if not this then return end
    local text = this:GetText() or ""
    
    -- Prevent text corruption by validating input
    if string.len(text) > 200 then
        text = string.sub(text, 1, 200)
        this:SetText(text)
    end
    
    -- Always store the actual text (empty means disabled)
    RaidSummonPlusOptions["whisperMessage"] = text
end

function RaidSummonPlusOptions_RitualMessageChanged()
    if not this then return end
    local text = this:GetText() or ""
    
    -- Prevent text corruption by validating input
    if string.len(text) > 200 then
        text = string.sub(text, 1, 200)
        this:SetText(text)
    end
    
    -- Always store the actual text, don't try to be smart about defaults
    RaidSummonPlusOptions["ritualMessage"] = text
end





function RaidSummonPlusOptions_RangeCheckToggle()
    RaidSummonPlusOptions["rangeCheck"] = not RaidSummonPlusOptions["rangeCheck"]
    local status = RaidSummonPlusOptions["rangeCheck"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("auto-remove players in range: " .. status)
end



-- Cleanup function to prevent memory leaks
function RaidSummonPlusOptions_OnHide()
    -- Clear focus from any active EditBox to prevent text rendering issues
    for _, element in pairs(optionCheckboxes) do
        if element and element.ClearFocus then
            element:ClearFocus()
        end
        if element and element.HighlightText then
            element:HighlightText(0, 0)
        end
    end
end

-- Function to show the options panel
function RaidSummonPlusOptions_Show()
    if not RaidSummonPlusOptionsFrame then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9RaidSummonPlus|r : Options frame not loaded. Please reload your UI (/reload)")
        return
    end
    
    if RaidSummonPlusOptionsFrame:IsVisible() then
        RaidSummonPlusOptionsFrame:Hide()
    else
        RaidSummonPlusOptionsFrame:Show()
    end
end

-- Add slash command for options
SLASH_RAIDSUMMONPLUSOPTIONS1 = "/rspoptions"
SLASH_RAIDSUMMONPLUSOPTIONS2 = "/rspconfig"
SlashCmdList["RAIDSUMMONPLUSOPTIONS"] = function(msg)
    RaidSummonPlusOptions_Show()
end
