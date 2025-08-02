-- RaidSummonPlus Options Panel
-- Compatible with WoW Vanilla 1.12.1

-- Global variables for UI appearance customization
-- To customize opacity: 0.0 = fully transparent, 1.0 = fully opaque
-- Recommended values: 0.7-0.9 for good visibility with transparency
RAIDSUMMONPLUS_OPTIONS_BACKGROUND_OPACITY = 0.70  -- Main frame background opacity
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
        checkbox:SetScript("OnClick", function()
            local self = this
            -- Use GetChecked() to get current state instead of maintaining separate variable
            local currentState = self:GetChecked()
            local newState = not currentState
            self:SetChecked(newState)
        end)
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
            
            -- DYNAMIC LAYOUT CALCULATION - Everything flows from the variables above
            local currentY = FIRST_HEADER_Y
            
            -- Section 1: Summon Announcements
            local HEADER1_Y = currentY
            local SECTION1_START = HEADER1_Y - HEADER_TO_OPTION_SPACING
            local SECTION1_OPTIONS = 2 -- announce summon toggle + whisper
            local TEXT_FIELD_HEIGHT = 55 -- Label (3 lines) + EditBox + spacing
            local SECTION1_END = SECTION1_START - (SECTION1_OPTIONS * CHECKBOX_HEIGHT) - (TEXT_FIELD_HEIGHT * 2) -- Two text fields now
            
            -- Section 2: Heartstone Announcements  
            local HEADER2_Y = SECTION1_END - SECTION_TO_SECTION_SPACING
            local SECTION2_START = HEADER2_Y - HEADER_TO_OPTION_SPACING
            local SECTION2_OPTIONS = 1 -- ritual checkbox
            local SECTION2_END = SECTION2_START - (SECTION2_OPTIONS * CHECKBOX_HEIGHT) - TEXT_FIELD_HEIGHT
            
            -- Section 3: Miscellaneous
            local HEADER3_Y = SECTION2_END - SECTION_TO_SECTION_SPACING
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
            optionCheckboxes.summonMessage = createTextInput(contentArea, "SummonMessage", "Accepted placeholders:\n{targetName}, {zone}, {subzone}, {shards},\n{raid}, {party}, {say}, {yell}", "", 0, optionCheckboxes.announceSummon, 180)
            if optionCheckboxes.summonMessage then
                optionCheckboxes.summonMessage:SetScript("OnTextChanged", RaidSummonPlusOptions_SummonMessageChanged)
            end
            
            optionCheckboxes.whisper = createCheckboxOption(contentArea, "Whisper", "Use whisper for summon notifications", 0, optionCheckboxes.summonMessage)
            if optionCheckboxes.whisper then
                optionCheckboxes.whisper:SetScript("OnClick", RaidSummonPlusOptions_WhisperToggle)
            end
            
            -- Custom whisper message text field
            optionCheckboxes.whisperMessage = createTextInput(contentArea, "WhisperMessage", "Accepted placeholders:\n{targetName}, {zone}, {subzone}, {shards}", "", 0, optionCheckboxes.whisper, 180)
            if optionCheckboxes.whisperMessage then
                optionCheckboxes.whisperMessage:SetScript("OnTextChanged", RaidSummonPlusOptions_WhisperMessageChanged)
            end
            
            -- HEARTSTONE ANNOUNCEMENTS SECTION
            optionCheckboxes.ritual = createCheckboxOption(contentArea, "Ritual", "Announce Ritual of Souls", SECTION2_START, nil)
            if optionCheckboxes.ritual then
                optionCheckboxes.ritual:SetScript("OnClick", RaidSummonPlusOptions_RitualToggle)
            end
            
            -- Custom message text field
            optionCheckboxes.ritualMessage = createTextInput(contentArea, "RitualMessage", "Accepted placeholders:\n{healValue}, {talentRank}, {masterConjuror},\n{raid}, {party}, {say}, {yell}", "", 0, optionCheckboxes.ritual, 180)
            if optionCheckboxes.ritualMessage then
                optionCheckboxes.ritualMessage:SetScript("OnTextChanged", RaidSummonPlusOptions_RitualMessageChanged)
            end
            
            -- MISCELLANEOUS SECTION
            optionCheckboxes.rangeCheck = createCheckboxOption(contentArea, "RangeCheck", "Auto-remove players in range (40 yd)", SECTION3_START, nil)
            if optionCheckboxes.rangeCheck then
                optionCheckboxes.rangeCheck:SetScript("OnClick", RaidSummonPlusOptions_RangeCheckToggle)
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
        RaidSummonPlusOptions["summonMessage"] = ""  -- Empty means use default
    end
    if RaidSummonPlusOptions["whisperMessage"] == nil then
        RaidSummonPlusOptions["whisperMessage"] = ""  -- Empty means use default
    end
    if RaidSummonPlusOptions["ritual"] == nil then
        RaidSummonPlusOptions["ritual"] = true
    end
    if RaidSummonPlusOptions["ritualMessage"] == nil or RaidSummonPlusOptions["ritualMessage"] == "" then
        RaidSummonPlusOptions["ritualMessage"] = "{yell} {healValue} Cookies"  -- Set actual default
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
    if optionCheckboxes.summonMessage then
        local defaultMessage = "{raid} Summoning {targetName} {zone} {shards}"
        local displayMessage = RaidSummonPlusOptions["summonMessage"]
        if displayMessage == "" then
            displayMessage = defaultMessage
        end
        -- Clear text first to prevent overlapping
        optionCheckboxes.summonMessage:SetText("")
        optionCheckboxes.summonMessage:SetText(displayMessage)
        optionCheckboxes.summonMessage:HighlightText(0, 0) -- Clear any selection
    end
    if optionCheckboxes.whisperMessage then
        local defaultWhisperMessage = "Summoning you to: {subzone}"
        local displayWhisperMessage = RaidSummonPlusOptions["whisperMessage"]
        if displayWhisperMessage == "" then
            displayWhisperMessage = defaultWhisperMessage
        end
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


    if optionCheckboxes.rangeCheck then
        optionCheckboxes.rangeCheck:SetChecked(RaidSummonPlusOptions["rangeCheck"])
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

function RaidSummonPlusOptions_RitualToggle()
    RaidSummonPlusOptions["ritual"] = not RaidSummonPlusOptions["ritual"]
    local status = RaidSummonPlusOptions["ritual"] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    RaidSummonPlusOptions_DebugMessage("Ritual of Souls announcements: " .. status)
end

function RaidSummonPlusOptions_SummonMessageChanged()
    if not this then return end
    local text = this:GetText() or ""
    local defaultMessage = "{raid} Summoning {targetName} {zone} {shards}"
    
    -- Prevent text corruption by validating input
    if string.len(text) > 200 then
        text = string.sub(text, 1, 200)
        this:SetText(text)
    end
    
    -- If the text matches the default, store empty string (means use default)
    if text == defaultMessage then
        RaidSummonPlusOptions["summonMessage"] = ""
    else
        RaidSummonPlusOptions["summonMessage"] = text
    end
end

function RaidSummonPlusOptions_WhisperMessageChanged()
    if not this then return end
    local text = this:GetText() or ""
    local defaultWhisperMessage = "Summoning you to: {subzone}"
    
    -- Prevent text corruption by validating input
    if string.len(text) > 200 then
        text = string.sub(text, 1, 200)
        this:SetText(text)
    end
    
    -- If the text matches the default, store empty string (means use default)
    if text == defaultWhisperMessage then
        RaidSummonPlusOptions["whisperMessage"] = ""
    else
        RaidSummonPlusOptions["whisperMessage"] = text
    end
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
