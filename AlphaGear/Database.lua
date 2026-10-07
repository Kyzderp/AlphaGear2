if (not AlphaGearUseReworkedData) then return end

local AGD = AlphaGearDatabase

local function IsSkillBarEmpty(tab)
    for _, v in pairs(tab) do
        if (v ~= 0) then return false end
    end
    return true
end

local function IsGearEmpty(tab)
    for _, slot in pairs(tab) do
        for _, v in pairs(slot) do
            if (v ~= 0) then return false end
        end
    end
    return true
end

local function MigrateData()
    if (not AGX2_Character.Default or not AGX2_Character.Default[GetUnitDisplayName("player")]) then return end
    local accTable = AGX2_Character.Default[GetUnitDisplayName("player")]

    -- In-place migration for each known character: this is because we don't know the char IDs or names of the other megaserver
    for charIndex = 1, GetNumCharacters() do
        local name, _, _, _, _, _, charId = GetCharacterInfo(charIndex)

        -- Existing table for this character NAME, meaning it has not yet been migrated
        local charTable = accTable[name]
        if (charTable) then
            -- First, store the currently active set into profiles, because we won't be using currently active sets anymore
            local profileTable = charTable.profiles[charTable.currentProfileId]
            ZO_ClearTable(profileTable)
            for i = 1, 16 do -- the old max
                profileTable.setdata[i] = charTable.setdata[i]
            end
            profileTable.setdata.lastset = charTable.setdata.lastset

            -- Make the new struct. Key will be character ID
            local newData = {
                profiles = {}, -- {[1] = {skillbars = {}, gear = {}, builds = {}}}
                currentProfileId = currentProfileId,
                characterName = name,
            }

            for profileId, profileData in pairs(charTable.profiles) do
                -- We want to remove the last x empty sets of each type, e.g. if there's gear in only slots 1 and 4, we can remove everything from 5 onward. Ignore build sets, because there could be integrations and I don't wanna deal with that. This also means not automatically deleting profiles, because there's too many things to check and I don't want to break users
                local lastNonEmptySkill = 0
                local lastNonEmptyGear = 0
                -- But also don't delete potentially-empty sets if they're linked to build sets
                local usedGearSets = {} -- map
                local usedSkillSets = {}

                -- Do a first pass to determine what is empty until the end, so we can delete excess
                -- The old stuff should be contiguous
                for i = 1, 16 do
                    if (not IsSkillBarEmpty(profileData[i].Skill)) then
                        lastNonEmptySkill = i
                    end

                    if (not IsGearEmpty(profileData[i].Gear)) then
                        lastNonEmptyGear = i
                    end

                    -- Save linked stuff
                    usedGearSets[profileData[i].Set.gear] = true
                    usedSkillSets[profileData[i].Set.skill[1]] = true
                    usedSkillSets[profileData[i].Set.skill[2]] = true
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

                -- Finally can copy everything up until the non-empty ones
                newData.profiles[profileId] = {
                    skillbars = {},
                    gear = {},
                    builds = {},
                }
                local newProfile = newData.profiles[profileId]

                for i = 1, lastNonEmptySkill do
                    newProfile.skillbars[i] = ZO_DeepTableCopy(profileData[i].Skill)
                end
                for i = 1, lastNonEmptyGear do
                    newProfile.gear[i] = ZO_DeepTableCopy(profileData[i].Gear)
                end
                for i = 1, 16 do
                    newProfile.builds[i] = ZO_DeepTableCopy(profileData[i].Set)
                end

                -- TODO: if everything was deleted, add at least 1 empty skillbar / gear set

                accTable[charId] = newData
                accTable[name] = nil
            end
        end
    end
end
AGD.MigrateData = MigrateData

local localAccTable
local function GetCurrentAccountTable()
    if (not localAccTable) then
        localAccTable = AGX2_Character.Default[GetUnitDisplayName("player")]
    end
    return localAccTable
end

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
        localCharTable = GetCurrentAccountTable()[GetCurrentCharacterId()]
    end
    return localCharTable
end

--[[
[3] = {
    skillbars = {},
    gear = {},
    builds = {},
}
]]
local function GetCurrentProfileTable()
    local charTable = GetCurrentCharacterTable()
    return charTable.profiles[charTable]
end
AGD.GetCurrentProfileTable = GetCurrentProfileTable
