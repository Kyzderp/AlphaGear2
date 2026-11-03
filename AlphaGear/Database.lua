local AGD = AlphaGearDatabase

local function IsSkillBarEmpty(tab)
    if (not tab) then return true end
    for _, v in pairs(tab) do
        if (v ~= 0) then return false end
    end
    return true
end

local function IsGearEmpty(tab)
    if (not tab) then return true end
    for _, slot in pairs(tab) do
        for _, v in pairs(slot) do
            if (v ~= 0) then return false end
        end
    end
    return true
end

-- TODO: any more things to check?
local function IsBuildEmpty(tab)
    if (not tab) then return true end
    return (tab.gear == nil or tab.gear == 0)
        and (tab.skill == nil or (tab.skill[1] == 0 and tab.skill[2] == 0)) 
        and (tab.outfit == nil or tab.outfit == -1)
        and (tab.AlphaStyleId == nil or tab.AlphaStyleId == AG.plugins.AlphaStyle.STYLE_KEEP)
        and (tab.CPSProfileName == nil or tab.CPSProfileName == "")
        and (tab.CPSHostName == nil or tab.CPSHostName == AG.plugins.CPSlots.CPS_KEEP)
        and (tab.DCPSlotSetGreen == nil or tab.DCPSlotSetGreen == -1)
        and (tab.DCPSlotSetBlue == nil or tab.DCPSlotSetBlue == -1)
        and (tab.DCPSlotSetRed == nil or tab.DCPSlotSetRed == -1)
end
AGD.IsBuildEmpty = IsBuildEmpty

local function IsProfileEmpty(profileId)
    local profile = AGD.GetProfile(profileId)
    if (not profile) then return true end

    for _, build in pairs(profile.builds) do
        if (not IsBuildEmpty(build)) then
            return false
        end
    end
    return true
end
AGD.IsProfileEmpty = IsProfileEmpty


---------------------------------------------------------------------
-- Migration
---------------------------------------------------------------------
-- Adds 1 build, 1 gear, and 2 skillbars to a profile
local function PopulateNewProfile(profileId)
    AGD.CreateBuild(profileId)
    AGD.CreateGear(profileId)
    AGD.CreateSkillbar(profileId)
    AGD.CreateSkillbar(profileId)
end

local function InitEmptyBuild(index)
    return {
        text = {},
        icon = {},
        skill = {},
        outfit = -1,
    }
end

local function InitEmptyProfile(name, sortKey, lastUsedBuild)
    return {
        skillbars = {},
        gear = {},
        builds = {},
        name = name,
        sortKey = sortKey or "",
        lastUsedBuild = lastUsedBuild or false,
    }
end

local function InitEmptyCharacter(name, numBuildButtons)
    return {
        profiles = {}, -- {[1] = {skillbars = {}, gear = {}, builds = {}}}
        currentProfileId = 1,
        characterName = name,
        numBuildButtons = numBuildButtons or 16,
    }
end

local function MigrateData()
    if (not AGX2_Character) then
        AGX2_Character = {}
    end
    if (not AGX2_Character.Default) then
        AGX2_Character.Default = {}
    end
    if (not AGX2_Character.Default[GetUnitDisplayName("player")]) then
        AGX2_Character.Default[GetUnitDisplayName("player")] = {}
    end

    local accTable = AGX2_Character.Default[GetUnitDisplayName("player")]
    -- TODO: init if empty

    -- In-place migration for each known character: this is because we don't know the char IDs or names of the other megaserver
    for charIndex = 1, GetNumCharacters() do
        local name, _, _, _, _, _, charId = GetCharacterInfo(charIndex)
        name = zo_strformat("<<1>>", name) -- it's returned with ^Mx

        -- Existing table for this character NAME, meaning it has not yet been migrated
        local charTable = accTable[name]
        if (charTable) then
            -- First, store the currently active set into profiles, because we won't be using currently active sets anymore
            local profileTable = charTable.profiles[charTable.currentProfileId]
            for i = 1, 16 do -- the old max
                profileTable.setdata[i] = charTable[i]
            end
            profileTable.setdata.lastset = charTable.lastset

            -- Make the new struct. Key will be character ID
            local newData = InitEmptyCharacter(name, charTable.setamount)

            for profileId, profileData in pairs(charTable.profiles) do
                -- We want to remove the last x empty sets of each type, e.g. if there's gear in only slots 1 and 4, we can remove everything from 5 onward.
                local lastNonEmptySkill = 0
                local lastNonEmptyGear = 0
                local lastNonEmptyBuild = 0
                -- But also don't delete potentially-empty sets if they're linked to build sets
                local usedGearSets = {} -- map
                local usedSkillSets = {}

                -- Could be an uninitialized profile from before
                if (not profileData.setdata) then
                    AG.alwaysDbg(string.format("Profile \"%s\" (%s) is uninitialized, not migrating the data.", profileData.name, profileId))
                else
                    -- Do a first pass to determine what is empty until the end, so we can delete excess
                    -- The old stuff should be contiguous
                    for i = 1, 16 do
                        if (not IsSkillBarEmpty(profileData.setdata[i].Skill)) then
                            lastNonEmptySkill = i
                        end

                        if (not IsGearEmpty(profileData.setdata[i].Gear)) then
                            lastNonEmptyGear = i
                        end

                        if (not IsBuildEmpty(profileData.setdata[i].Set)) then
                            lastNonEmptyBuild = i
                        end

                        -- Save linked stuff
                        usedGearSets[profileData.setdata[i].Set.gear] = true
                        usedSkillSets[profileData.setdata[i].Set.skill[1]] = true
                        usedSkillSets[profileData.setdata[i].Set.skill[2]] = true
                    end

                    -- Find the last linked gear and skills
                    for i = 16, 1, -1 do
                        if (usedGearSets[i] and i > lastNonEmptyGear) then
                            lastNonEmptyGear = i
                        end
                        if (usedSkillSets[i] and i > lastNonEmptySkill) then
                            lastNonEmptySkill = i
                        end
                    end

                    if (lastNonEmptyBuild == 0 and lastNonEmptyGear == 0 and lastNonEmptySkill == 0) then
                        AG.alwaysDbg(string.format("Profile \"%s\" (%s) is empty, not migrating the data.", profileData.name, profileId))
                    else
                        -- Finally can copy everything up until the non-empty ones
                        newData.profiles[profileId] = InitEmptyProfile(profileData.name, profileData.sortKey, profileData.lastset)
                        local newProfile = newData.profiles[profileId]

                        for i = 1, lastNonEmptySkill do
                            newProfile.skillbars[i] = ZO_DeepTableCopy(profileData.setdata[i].Skill)
                        end
                        for i = 1, lastNonEmptyGear do
                            newProfile.gear[i] = ZO_DeepTableCopy(profileData.setdata[i].Gear)
                        end
                        for i = 1, lastNonEmptyBuild do
                            newProfile.builds[i] = ZO_DeepTableCopy(profileData.setdata[i].Set)
                        end

                        -- If everything of a type was deleted, add at least 1 empty set
                        if (lastNonEmptySkill == 0) then
                            newProfile.skillbars[1] = {}
                        end
                        if (lastNonEmptyGear == 0) then
                            newProfile.gear[1] = {}
                        end
                        if (lastNonEmptyBuild == 0) then
                            newProfile.builds[1] = InitEmptyBuild(1)
                        end
                    end
                end
            end
            accTable[charId] = newData
            accTable[name] = nil
        elseif (not accTable[charId]) then
            -- Nothing to migrate, just create empty
            accTable[charId] = InitEmptyCharacter(name)
            local newCharTable = accTable[charId]
            newCharTable.profiles[1] = InitEmptyProfile(1)
            newCharTable.currentProfileId = 1
            PopulateNewProfile(1)
        end
    end
end
AGD.MigrateData = MigrateData

-- Returns the entire account's table. Mostly to be called without accountName
local localAccTable
local function GetAccountTable(accountName)
    if (accountName) then
        return AGX2_Character.Default[accountName]
    end

    if (not localAccTable) then
        localAccTable = AGX2_Character.Default[GetUnitDisplayName("player")]
    end
    return localAccTable
end
AGD.GetAccountTable = GetAccountTable

--[[
["123564352698409324"] = {
    currentProfileId = 3,
    characterName = "sdfksdjfl",
    profiles = {...},
}
]]
local localCharTable
local function GetCurrentCharacterTable()
    if (not localCharTable) then
        localCharTable = GetAccountTable()[GetCurrentCharacterId()]
    end
    return localCharTable
end
AGD.GetCharacter = GetCurrentCharacterTable

--[[
[3] = {
    skillbars = {},
    gear = {},
    builds = {},
    lastUsedBuild = false,
}
]]
local function GetProfileTable(profileId)
    local charTable = GetCurrentCharacterTable()
    return charTable.profiles[profileId or charTable.currentProfileId]
end
AGD.GetProfile = GetProfileTable

local function GetNumProfiles()
    local charTable = GetCurrentCharacterTable()
    return NonContiguousCount(charTable.profiles)
end
AGD.GetNumProfiles = GetNumProfiles


---------------------------------------------------------------------
-- Creation / deletion
---------------------------------------------------------------------
local function FindUnusedProfileId()
    local charTable = GetCurrentCharacterTable()
    local i = 1
    while (charTable.profiles[i] ~= nil) do
        i = i + 1
    end
    return i
end

-- Initializes values in profile. profileId can be nil
local function CreateProfile(profileId)
    profileId = profileId or FindUnusedProfileId()

    local charTable = GetCurrentCharacterTable()
    charTable.profiles[profileId] = InitEmptyProfile("Profile " .. profileId)
    PopulateNewProfile(profileId)
    return profileId
end
AGD.CreateProfile = CreateProfile

-- If profileId is nil, uses the current profile
local function DeleteProfile(profileId)
    local charTable = GetCurrentCharacterTable()
    profileId = profileId or charTable.currentProfileId

    if (not charTable.profiles[profileId]) then
        AG.msg("|cFF0000Could not delete profile because it doesn't exist: " .. tostring(profileId))
        return
    end
    charTable.profiles[profileId] = nil
end
AGD.DeleteProfile = DeleteProfile

-- Initializes values in new build. Builds are always contiguous
local function CreateBuild(profileId)
    local profileTable = GetProfileTable(profileId)
    table.insert(profileTable.builds, InitEmptyBuild(#profileTable.builds + 1))
end
AGD.CreateBuild = CreateBuild

-- Deletes a build. If index is nil, deletes the last one. Since builds are contiguous, the rest will shift up
local function DeleteBuild(index)
    local profileTable = GetProfileTable()
    local removed = table.remove(profileTable.builds, index)
    return removed.text[1]
end
AGD.DeleteBuild = DeleteBuild

-- Initializes values in new gear set. Gear is always contiguous
local function CreateGear(profileId)
    local profileTable = GetProfileTable(profileId)
    table.insert(profileTable.gear, {
        -- TODO: do 1~16 need to be inited or is nil ok?
    })
end
AGD.CreateGear = CreateGear

-- Deletes a gear set. If index is nil, deletes the last one. Since gear is contiguous, the rest will shift up. Builds linking to gear will be updated
local function DeleteGear(index)
    local profileTable = GetProfileTable()
    index = index or #profileTable.gear
    local removed = table.remove(profileTable.gear, index)

    -- Update all builds that link to gear that has shifted
    -- If the old index is equal to the removed index, then it should be cleared because the gear no longer exists. If the old index is larger than the removed index, then the index needs to be decremented to account for the shift
    for _, buildData in pairs(profileTable.builds) do
        if (buildData.gear == index) then
            buildData.gear = nil -- TODO: is nil ok?
        elseif (buildData.gear and buildData.gear > index) then
            buildData.gear = buildData.gear - 1
        end
    end

    return index
end
AGD.DeleteGear = DeleteGear

-- Initializes values in new skillbar. Skillbars are always contiguous
local function CreateSkillbar(profileId)
    local profileTable = GetProfileTable(profileId)
    table.insert(profileTable.skillbars, {
        -- TODO: do 1~6 need to be inited or is nil ok?
    })
end
AGD.CreateSkillbar = CreateSkillbar

-- Deletes a skill bar. If index is nil, deletes the last one. Since skillbars are contiguous, the rest will shift up. Builds linking to skills will be updated
local function DeleteSkillbar(index)
    local profileTable = GetProfileTable()
    index = index or #profileTable.skillbars
    local removed = table.remove(profileTable.skillbars, index)

    -- Update all builds that link to skillbars that have shifted
    -- If the old index is equal to the removed index, then it should be cleared because the skillbar no longer exists. If the old index is larger than the removed index, then the index needs to be decremented to account for the shift
    for _, buildData in pairs(profileTable.builds) do
        if (buildData.skill[1] == index) then
            buildData.skill[1] = nil -- TODO: is nil ok?
        elseif (buildData.skill[1] and buildData.skill[1] > index) then
            buildData.skill[1] = buildData.skill[1] - 1
        end
        if (buildData.skill[2] == index) then
            buildData.skill[2] = nil -- TODO: is nil ok?
        elseif (buildData.skill[2] and buildData.skill[2] > index) then
            buildData.skill[2] = buildData.skill[2] - 1
        end
    end
    -- TODO: prob refactor some common code

    return index
end
AGD.DeleteSkillbar = DeleteSkillbar


---------------------------------------------------------------------
---------------------------------------------------------------------
