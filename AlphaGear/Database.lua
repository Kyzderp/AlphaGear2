local AGD = AlphaGearDatabase

local function IsEmpty(val)
    return val == nil or val == 0 or val == false
end

local function IsSkillBarEmpty(tab)
    if (not tab) then return true end
    for _, v in pairs(tab) do
        if (not IsEmpty(v)) then return false end
    end
    return true
end

local function IsGearEmpty(tab)
    if (not tab) then return true end
    for _, slot in pairs(tab) do
        for _, v in pairs(slot) do
            if (not IsEmpty(v)) then return false end
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
-- If profile is defined, populates that instead of fetching current character's profileId
local function PopulateNewProfile(profileId, profile)
    AGD.CreateBuild(profileId, profile)
    AGD.CreateGear(profileId, profile)
    AGD.CreateSkillbar(profileId, profile)
    AGD.CreateSkillbar(profileId, profile)
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
        server = GetWorldName(),
        numBuildButtons = numBuildButtons or 16,
    }
end

local function CleanZeroes(profile)
    local numCleaned = 0
    for i, gear in ipairs(profile.gear) do
        for j, slot in ipairs(gear) do
            if (IsEmpty(slot.id) and IsEmpty(slot.link)) then
                gear[j] = nil
                numCleaned = numCleaned + 1
            end
        end
    end

    for i, skillbar in ipairs(profile.skillbars) do
        for k, v in ipairs(skillbar) do
            if (IsEmpty(v)) then
                skillbar[k] = nil
                numCleaned = numCleaned + 1
            end
        end
    end

    AG.alwaysDbg("Cleaned out " .. numCleaned .. " zeroes from profile " .. profile.name)
end

local function CleanAllZeroes(charId)
    local accTable = AGD.GetAccountTable()
    for _, profile in pairs(accTable[charId].profiles) do
        CleanZeroes(profile)
    end
end
AGD.CleanAllZeroes = CleanAllZeroes

local function DeleteNonContiguous(profiles)
    for profileId, profileData in pairs(profiles) do
        -- We want to remove the last x empty sets of each type, e.g. if there's gear in only slots 1 and 4, we can remove everything from 5 onward
        local lastNonEmptySkill = 0
        local lastNonEmptyGear = 0
        local lastNonEmptyBuild = 0
        -- But also don't delete potentially-empty sets if they're linked to build sets
        local usedGearSets = {} -- map
        local usedSkillSets = {}

        -- Do a first pass to determine what is empty until the end, so we can delete excess
        -- Also change completely empty sets to empty tables to cut down on SV
        -- The old stuff should be contiguous
        for i = 1, #profileData.skillbars do
            if (not IsSkillBarEmpty(profileData.skillbars[i])) then
                lastNonEmptySkill = i
            end
        end

        for i = 1, #profileData.gear do
            if (not IsGearEmpty(profileData.gear[i])) then
                lastNonEmptyGear = i
            end
        end

        for i, build in ipairs(profileData.builds) do
            if (not IsBuildEmpty(build)) then
                lastNonEmptyBuild = i
            end

            -- Save linked stuff
            if (build.gear) then
                usedGearSets[build.gear] = true
            end
            if (build.skill and build.skill[1]) then
                usedSkillSets[build.skill[1]] = true
            end
            if (build.skill and build.skill[2]) then
                usedSkillSets[build.skill[2]] = true
            end
        end

        -- Find the last linked gear and skills
        for gearIndex, _ in pairs(usedGearSets) do
            if (gearIndex > lastNonEmptyGear) then
                lastNonEmptyGear = gearIndex
            end
        end

        for skillbarIndex, _ in pairs(usedSkillSets) do
            if (skillbarIndex > lastNonEmptySkill) then
                lastNonEmptySkill = skillbarIndex
            end
        end

        if (lastNonEmptyBuild == 0 and lastNonEmptyGear == 0 and lastNonEmptySkill == 0) then
            AG.alwaysDbg(string.format("Profile \"%s\" (%s) is empty, deleting the profile.", profileData.name, profileId))
            profiles[profileId] = nil
        else
            -- Delete from last non empty + 1 onwards, but always keep the first for gear and builds, and first 2 for skills
            lastNonEmptySkill = math.max(lastNonEmptySkill, 2) + 1 -- keep at least first 2 for skills
            for i = lastNonEmptySkill, #profileData.skillbars do
                profileData.skillbars[i] = nil
            end

            lastNonEmptyGear = math.max(lastNonEmptyGear, 1) + 1 -- keep first for gear
            for i = lastNonEmptyGear, #profileData.gear do
                profileData.gear[i] = nil
            end

            lastNonEmptyBuild = math.max(lastNonEmptyBuild, 1) + 1 -- keep first for build
            for i = lastNonEmptyBuild, #profileData.builds do
                profileData.builds[i] = nil
            end
        end
    end

    -- Add 1 profile if all have been deleted
    if (NonContiguousCount(profiles) == 0) then
        profiles[1] = InitEmptyProfile("Profile 1")
        PopulateNewProfile(1, profiles[1])
    end
end

local function DeleteAllNonContiguous()
    for charId, charData in pairs(AGD.GetAccountTable()) do
        if (charData.characterName) then
            DeleteNonContiguous(charData.profiles)

            -- If the currently selected profile no longer exists, just pick the first one found
            if (not charData.profiles[charData.currentProfileId]) then
                AGD.alwaysDbg(charData.currentProfileId .. " no longer a profile in " .. charData.characterName)
                charData.currentProfileId = next(charData.profiles)
                AGD.alwaysDbg("currentProfileId now " .. charData.currentProfileId)
            end
        end
    end
    -- TODO: update UI
end
AGD.DeleteAllNonContiguous = DeleteAllNonContiguous
-- /script AlphaGearDatabase.DeleteAllNonContiguous()

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
                -- Could be an uninitialized profile from before. Still delete this though
                if (not profileData.setdata) then
                    AG.alwaysDbg(string.format("Profile \"%s\" (%s) is uninitialized, not migrating the data.", profileData.name, profileId))
                else
                    -- Finally can copy everything up until the non-empty ones
                    newData.profiles[profileId] = InitEmptyProfile(profileData.name, profileData.sortKey, profileData.lastset)
                    local newProfile = newData.profiles[profileId]

                    for i = 1, 16 do
                        newProfile.skillbars[i] = ZO_DeepTableCopy(profileData.setdata[i].Skill)
                        newProfile.gear[i] = ZO_DeepTableCopy(profileData.setdata[i].Gear)
                        newProfile.builds[i] = ZO_DeepTableCopy(profileData.setdata[i].Set)
                    end
                end
            end
            accTable[charId] = newData
            accTable[name] = nil

            CleanAllZeroes(charId)
        elseif (not accTable[charId]) then
            -- Nothing to migrate, just create empty
            accTable[charId] = InitEmptyCharacter(name)
            local newCharTable = accTable[charId]
            newCharTable.profiles[1] = InitEmptyProfile(1)
            newCharTable.currentProfileId = 1
            PopulateNewProfile(1, newCharTable.profiles[1])
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

-- Returns {[charId] = true} when the character has the same recorded name as another character
local function GetDuplicateNameCharIds(accName)
    local accTable = GetAccountTable(accName)
    local names = {}
    local dupes = {}
    for charId, charData in pairs(accTable) do
        if (charData.charName) then
            if (names[charData.charName]) then
                dupes[charId] = true
                dupes[names[charData.charName]] = true
            else
                names[charData.charName] = true
            end
        end
    end
    return dupes
end
AGD.GetDuplicateNameCharIds = GetDuplicateNameCharIds


---------------------------------------------------------------------
-- Internal data reordering
---------------------------------------------------------------------
-- Update all builds that link to gear or skillbars that have changed
-- func params: (oldValue) should return: newValue
local function UpdateBuildLinks(gearFunc, skillbarFunc)
    local profileTable = GetProfileTable(profileId)
    for _, buildData in pairs(profileTable.builds) do
        if (gearFunc) then
            buildData.gear = gearFunc(buildData.gear)
        end
        if (skillbarFunc) then
            buildData.skill[1] = skillbarFunc(buildData.skill[1])
            buildData.skill[2] = skillbarFunc(buildData.skill[2])
        end
    end
end


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
local function CreateBuild(profileId, profile)
    local profileTable = profile or GetProfileTable(profileId)
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
local function CreateGear(profileId, profile)
    local profileTable = profile or GetProfileTable(profileId)
    table.insert(profileTable.gear, {})
end
AGD.CreateGear = CreateGear

-- Deletes a gear set. If index is nil, deletes the last one. Since gear is contiguous, the rest will shift up. Builds linking to gear will be updated
local function DeleteGear(index)
    local profileTable = GetProfileTable()
    index = index or #profileTable.gear
    local removed = table.remove(profileTable.gear, index)

    -- Update all builds that link to gear that has shifted
    -- If the old index is equal to the removed index, then it should be cleared because the gear no longer exists. If the old index is larger than the removed index, then the index needs to be decremented to account for the shift
    UpdateBuildLinks(function(oldValue)
        if (oldValue == index) then
            return nil
        elseif (oldValue and oldValue > index) then
            return oldValue - 1
        end
    end, nil)

    return index
end
AGD.DeleteGear = DeleteGear

-- Initializes values in new skillbar. Skillbars are always contiguous
local function CreateSkillbar(profileId, profile)
    local profileTable = profile or GetProfileTable(profileId)
    table.insert(profileTable.skillbars, {})
end
AGD.CreateSkillbar = CreateSkillbar

-- Deletes a skill bar. If index is nil, deletes the last one. Since skillbars are contiguous, the rest will shift up. Builds linking to skills will be updated
local function DeleteSkillbar(index)
    local profileTable = GetProfileTable()
    index = index or #profileTable.skillbars
    local removed = table.remove(profileTable.skillbars, index)

    -- Update all builds that link to skillbars that have shifted
    -- If the old index is equal to the removed index, then it should be cleared because the skillbar no longer exists. If the old index is larger than the removed index, then the index needs to be decremented to account for the shift
    UpdateBuildLinks(nil, function(oldValue)
        if (oldValue == index) then
            return nil
        elseif (oldValue and oldValue > index) then
            return oldValue - 1
        end
    end)

    return index
end
AGD.DeleteSkillbar = DeleteSkillbar


---------------------------------------------------------------------
-- Reordering
---------------------------------------------------------------------
local function ReorderBuild(index, offset)
    local profileTable = GetProfileTable()
    local build = table.remove(#profileTable.builds, index)
    table.insert(profileTable.builds, index + offset, build)
end
AGD.ReorderBuild = ReorderBuild

-- Reorder gear set and update any builds that link to either affected gear
local function ReorderGear(index, offset)
    local profileTable = GetProfileTable()
    local newIndex = index + offset
    local gear = table.remove(profileTable.gear, index)
    table.insert(profileTable.gear, newIndex, gear)

    -- Swap the linked
    UpdateBuildLinks(function(oldValue)
        if (oldValue == index) then
            return newIndex
        elseif (oldValue == newIndex) then
            return index
        end
    end, nil)
end
AGD.ReorderGear = ReorderGear

-- Reorder skillbar and update any builds that link to either affected skillbar
local function ReorderSkillbar(index, offset)
    local profileTable = GetProfileTable()
    local newIndex = index + offset
    local skillbar = table.remove(profileTable.skillbars, index)
    table.insert(profileTable.skillbars, newIndex, skillbar)

    -- Swap the linked
    UpdateBuildLinks(nil, function(oldValue)
        if (oldValue == index) then
            return newIndex
        elseif (oldValue == newIndex) then
            return index
        end
    end)
end
AGD.ReorderSkillbar = ReorderSkillbar
