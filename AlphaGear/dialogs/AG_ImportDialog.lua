--[[

Dialog to import from other servers, accounts, or characters

--]]
AGImportDlg = {}
local AGD = AlphaGearDatabase


------------------------------------------------------
--
------------------------------------------------------
local selectedAccount, selectedCharacter, selectedProfile

local function SetUpProfileDropdown(contentControl, accountName, charId)
    local comboParent = contentControl:GetNamedChild("ProfileDropdown")
    local combo = ZO_ComboBox_ObjectFromContainer(comboParent)

    if (not accountName or not charId) then
        asdfdfsf()
        return
    end
    combo:ClearItems()

    local function OnProfileSelected(_, _, entry)
        selectedProfile = entry.profile
    end

    for profileNum, profileData in pairs(AGX2_Character.Default[accountName][charId].profiles) do
        local entry = ZO_ComboBox:CreateItemEntry(profileData.name, OnProfileSelected)
        entry.profile = profileNum
        combo:AddItem(entry, ZO_COMBOBOX_SUPRESS_UPDATE)
    end
    combo:UpdateItems()
end

local function SetUpCharacterDropdown(contentControl, accountName)
    local comboParent = contentControl:GetNamedChild("CharacterDropdown")
    local combo = ZO_ComboBox_ObjectFromContainer(comboParent)

    if (not accountName) then
        asdfdfsf()
        return
    end

    local function OnCharSelected(_, _, entry)
        selectedCharacter = entry.charId
        SetUpProfileDropdown(contentControl, accountName, entry.charId)
    end

    local currentCharacterEntry
    local dupes = AGD.GetDuplicateNameCharIds()
    local hasValidChars = false

    combo:ClearItems()
    for charId, charData in pairs(AGD.GetAccountTable(accountName)) do
        if (charData.characterName) then
            local display = charData.characterName
            if (dupes[charId]) then
                display = string.format("%s (%s)", display, charData.server or "Unknown server")
            end

            local entry = ZO_ComboBox:CreateItemEntry(display, OnCharSelected)
            entry.charId = charId
            combo:AddItem(entry, ZO_COMBOBOX_SUPRESS_UPDATE)

            hasValidChars = true
            if (charId == GetCurrentCharacterId()) then
                currentCharacterEntry = entry
            end
            AG.alwaysDbg("adding " .. charId .. " " .. display)
        else
            AG.alwaysDbg("|cFF0000charId " .. charId .. " doesn't have a character name!")
        end
    end
    combo:SelectItem(currentCharacterEntry)
    combo:UpdateItems()

    if (not hasValidChars) then
        AG.msg("No valid characters found for " .. accountName .. ". You may need to log in to that account once to do the v8.0.0+ data migration.")
    end
end

local function SetUpAccountDropdown(contentControl)
    local comboParent = contentControl:GetNamedChild("AccountDropdown")
    local combo = ZO_ComboBox_ObjectFromContainer(comboParent)

    local function OnAccountSelected(_, _, entry)
        selectedAccount = entry.accName
        SetUpCharacterDropdown(contentControl, entry.accName)
    end

    local currentAccountEntry
    combo:ClearItems()
    for accName, _ in pairs(AGX2_Character.Default) do
        local entry = ZO_ComboBox:CreateItemEntry(accName, OnAccountSelected)
        entry.accName = accName
        combo:AddItem(entry, ZO_COMBOBOX_SUPRESS_UPDATE)

        if (accName == GetUnitDisplayName("player")) then
            currentAccountEntry = entry
        end
    end
    combo:SelectItem(currentAccountEntry)
    combo:UpdateItems()
    -- SetUpCharacterDropdown(contentControl, GetUnitDisplayName("player"))
end


------------------------------------------------------
-- Common Settings
------------------------------------------------------
local function Commit()
    AG.ImportProfile(selectedAccount, selectedCharacter, selectedProfile)
end

local function SetUp()
    local control = AGImportDialog

    SetUpAccountDropdown(GetControl(control, "Content"))
    -- SetUpCharacterDropdown(GetControl(control, "Content"))
    -- SetUpProfileDropdown(GetControl(control, "Content"))
end


function AGImportDlg.Initialize()
    local control = AGImportDialog

    ZO_Dialogs_RegisterCustomDialog("AG_IMPORT_DIALOG", {
        customControl = control,
        title = { text = "Import Profile" },
        setup = SetUp,
        buttons =
        {
            {
                control = GetControl(control, "Accept"),
                text = "Import",
                keybind = "DIALOG_PRIMARY",
                callback = Commit,
            },  
            {
                control = GetControl(control, "Cancel"),
                text = SI_DIALOG_CANCEL,
                keybind = "DIALOG_NEGATIVE",
                callback = function() end,
            },
        },
    })
end
