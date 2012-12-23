CollectMe = LibStub("AceAddon-3.0"):NewAddon("CollectMe", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0")

local addon_name = "CollectMe"
local MOUNT_FILTERS = { "nlo", "tcg", "pvp", "are", "bsm", "rfm", "ptm" }

local GROUND = 1
local FLY = 2
local SWIM = 3
local AQUATIC = 4

local defaults = {
    profile = {
        ignored = {
            mounts = {},
            titles = {},
            companions = {}
        },
        filters = {
            mounts = {
                nlo = false,
                tcg = false,
                pvp = false,
                are = false,
                bsm = false,
                rfm = false,
                ptm = false
            },
            titles = {
                nlo = false,
                pvp = false,
                are = false
            }
        },
        missing_message = {
            mounts = false,
            titles = false
        },
        hide_ignore = {
            mounts = false,
            titles = false
        },
        random = {
            companions = {},
            mounts = {}
        },
        summon = {
            companions = {
                auto = false,
                disable_pvp = false
            },
            mounts = {
                flying_in_water = false,
                flying_on_ground = false,
                no_dismount = false,
                macro_left = 1,
                macro_right = 2,
                macro_shift_left = 3
            }
        },
        tooltip = {
            companions = {
                hide = false,
                quality_check = true
            }
        }
    }
}

local options = {
    name = addon_name,
    type = "group",
    childGroups = "tab",
    args = { }
}

function CollectMe:OnInitialize()
    self.ADDON_NAME = addon_name
    self.VERSION = GetAddOnMetadata("CollectMe", "Version")
    self.L = LibStub("AceLocale-3.0"):GetLocale("CollectMe", true)

    self.MOUNT = 1
    self.TITLE = 2
    self.RANDOM_COMPANION = 3
    self.RANDOM_MOUNT = 4
    self.COMPANION = 5

    self.FACTION = UnitFactionGroup("player")
    LocalizedPlayerRace, self.RACE = UnitRace("player")
    LocalizedPlayerClass, self.CLASS = UnitClass("player")

    LibStub("AceConfig-3.0"):RegisterOptionsTable(addon_name, options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addon_name)

    self.db = LibStub("AceDB-3.0"):New("CollectMeDB", defaults)
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

    self:BuildMountDB()

    self.filter_db = self.db.profile.filters.mounts
    self.ignored_db = self.db.profile.ignored.mounts
    self.item_list = self.MOUNTS
    self.filter_list = MOUNT_FILTERS
    self.gametooltip_visible = false

    self.display_creature = false

    self:RegisterChatCommand("collectme", "SlashProcessor")
    self:RegisterChatCommand("cm", "SlashProcessor")

    self:Hook("DressUpItemLink", true)
    self:HookScript(DressUpFrameResetButton, "OnClick", "DressUpFrameResetButton")

    self:SecureHook("MoveForwardStart", "AutoSummonCompanion")
    self:SecureHook("ToggleAutoRun", "AutoSummonCompanion")

    self:SecureHookScript(GameTooltip, "OnShow", "TooltipHook")
    self:RegisterEvent("PET_BATTLE_OPENING_START", "ResetEnemyTable")
    self:RegisterEvent("PET_BATTLE_PET_CHANGED", "CheckEnemyQuality")

end

function CollectMe:OnEnable()
    self:UpdateMacros()

    if self.professions == nil then
        self:UpdateProfessions()
    end
end

function CollectMe:UpdateMacros()
    self:InitMacro("CollectMeRC", "INV_PET_BABYBLIZZARDBEAR", '/script CollectMe:HandlePetMacro();')
    if self.CLASS == 'DRUID' then
        self:InitMacro("CollectMeRM", "ABILITY_MOUNT_BIGBLIZZARDBEAR", '/cancelform\n/script CollectMe:HandleMountMacro();')
    else
        self:InitMacro("CollectMeRM", "ABILITY_MOUNT_BIGBLIZZARDBEAR", '/script CollectMe:HandleMountMacro();')
    end
end

function CollectMe:UpdateProfessions()
    local first, second = GetProfessions()
    self.professions = {}
    if(first ~= nil) then
        self:SetProfession(first)
    end
    if(second ~= nil) then
        self:SetProfession(second)
    end
end

function CollectMe:SetProfession(index)
    local _, icon, skill = GetProfessionInfo(index)
    local name
    if string.find(icon, "Trade_Tailoring") ~= nil then
        name = 'tai'
    elseif string.find(icon, "Trade_Engineering") ~= nil then
        name = 'eng'
    end
    if name ~= nil then
        table.insert(self.professions, { name = name, skill = skill} )
    end
end

function CollectMe:InitMacro(name, icon, body)
    local index = GetMacroIndexByName(name)
    if index == 0 then
        local id = CreateMacro(name, icon, body, nil);
    else
        EditMacro(index, nil, nil, body)
    end
end

function CollectMe:BuildData(no_filters)
    if self.UI.active_group == self.MOUNT then
        self.filter_db = self.db.profile.filters.mounts
        self.ignored_db = self.db.profile.ignored.mounts
        self.item_list = self.MOUNTS
        self.filter_list = MOUNT_FILTERS
        self:BuildList()
        if not no_filters then
            self:BuildFilters()
        end
    elseif self.UI.active_group == self.TITLE then
        self.filter_db = self.db.profile.filters.titles
        self.ignored_db = self.db.profile.ignored.titles
        self.item_list = self.TitleDB:Get()
        self.filter_list = self.TitleDB.filters
        self:BuildList()
        if not no_filters then
            self:BuildFilters()
        end

    elseif self.UI.active_group == self.COMPANION then
        self.ignored_db = self.db.profile.ignored.companions
        self:BuildMissingCompanionList()
        if not no_filters then
            self:BuildMissingCompanionFilters()
        end
    elseif self.UI.active_group == self.RANDOM_COMPANION then
        self:BuildRandomPetList()
        self.UI:ShowCheckButtons()
    elseif self.UI.active_group == self.RANDOM_MOUNT then
        self:BuildRandomList()
        self.UI:ShowCheckButtons()
    end

    if not no_filters then
        self:BuildOptions()
    end
end


function CollectMe:BuildRandomPetList(listcontainer)
    local companions = self.CompanionDB:GetCompanions()
    local random_db =  self.db.profile.random.companions

    listcontainer:AddChild(self:CreateHeading(self.L["Available companions"] ..  " - " .. #companions))
    for i,v in ipairs(companions) do
        if C_PetJournal.PetIsSummonable(v.pet_id) then
            local f = AceGUI:Create("CheckBox")
            local name = v.name
            if v.custom_name ~= nil then
                name = name .. " - " .. v.custom_name
            end
            f:SetLabel(self:ColorizeByQuality(name .." - " .. v.level, v.color))
            f:SetFullWidth(true)
            local value = ((random_db[v.pet_id] ~= nil and random_db[v.pet_id] ~= false) and true or false)
            f:SetValue(value)
            f:SetCallback("OnValueChanged", function (container, event, val) random_db[v.pet_id] = val end)
            listcontainer:AddChild(f)
        end
    end
end


function CollectMe:BuildRandomList(listcontainer)
    local type, random_db, title = "MOUNT", self.db.profile.random.mounts, self.L["Available mounts"]

    local count = GetNumCompanions(type)
    listcontainer:AddChild(self:CreateHeading(title ..  " - " .. count))

    for i = 1, count, 1 do
        local _, name, spell_id = GetCompanionInfo(type, i)
        local f = AceGUI:Create("CheckBox")
        f:SetLabel(name)
        f:SetFullWidth(true)
        local value = ((random_db[spell_id] ~= nil and random_db[spell_id] ~= false) and true or false)
        f:SetValue(value)
        f:SetCallback("OnValueChanged", function (container, event, val) random_db[spell_id] = val end)

        listcontainer:AddChild(f)
    end
end

function CollectMe:SummonRandomCompanion()
    local summonable = {};

    for i,v in pairs(self.db.profile.random.companions) do
        if v == true and C_PetJournal.PetIsSummonable(i) then
            table.insert(summonable, i)
        end
    end

    if (#summonable > 0) then
        local call = math.random(1, #summonable)
        C_PetJournal.SummonPetByGUID(summonable[call])
    else
        self:Print(self.L["You haven't configured your companion priorities yet. Please open the random companion tab"])
    end
end

function CollectMe:GetCurrentZone()
    SetMapToCurrentZone()
    return GetCurrentMapAreaID()
end

function CollectMe:SummonRandomMount(type)
    if not IsMounted() then
        local zone_mounts, type_mounts, fallback_mounts = {}, {}, {}
        local zone_id, is_swimming, is_flyable_area = self:GetCurrentZone(), IsSwimming(), IsFlyableArea()
        local profession_count = #self.professions
        for i = 1, GetNumCompanions("MOUNT") do
            local _, name, spell_id = GetCompanionInfo("MOUNT", i);

            -- check if current mount is in priority pool and if it is usable here
            if self.db.profile.random.mounts[spell_id] ~= nil and self.db.profile.random.mounts[spell_id] ~= false and IsUsableSpell(spell_id) ~= nil then

                -- get info table from mount db
                local info = self:GetMountInfo(spell_id)
                if info == nil then
                    info = {
                        type = GROUND, --mount not known, assuming it' is a ground mount
                        name    = name,
                        id      = spell_id
                    }
                end

                if info.professions == nil or self:ProfessionMount(info) == true then
                    -- setting up zone table (aquatic handled by that too currently)
                    if(info.zones ~= nil and self:IsInTable(info.zones, zone_id)) then
                        table.insert(zone_mounts, i)
                    end

                    if #zone_mounts == 0 then
                        -- swimming mounts
                        if is_swimming == 1 then
                            if info.type == SWIM or (self.db.profile.summon.mounts.flying_in_water == true and info.type == FLY and is_flyable_area == 1) then
                                table.insert(type_mounts, i)
                            end
                        -- flying mounts
                        elseif is_flyable_area == 1 then
                            if info.type == FLY then
                                table.insert(type_mounts, i)
                            end
                        end
                    end
                    if info.type == GROUND or (self.db.profile.summon.mounts.flying_on_ground  == true and info.type == FLY) then
                        table.insert(fallback_mounts, i)
                    end
                end
            end
        end


        if type == GROUND and #fallback_mounts > 0 then
            self:Mount(fallback_mounts)
        elseif #zone_mounts > 0 then
            self:Mount(zone_mounts)
        elseif #type_mounts > 0 then
            self:Mount(type_mounts)
        elseif #fallback_mounts > 0 then
            self:Mount(fallback_mounts)
        else
            if IsIndoors() == nil and UnitAffectingCombat("player") == nil then
                self:Print(self.L["You haven't configured your mount priorities yet. Please open the random mount tab"])
            end
        end

    elseif self.db.profile.summon.mounts.no_dismount == false then
        Dismount()
    end
end

function CollectMe:ProfessionMount(info)
    for i,v in pairs(info.professions) do
        for j, v1 in pairs(self.professions) do
            if i == v1.name and v1.skill >= v then
                return true
            end
        end
    end
    return false
end

function CollectMe:Mount(t)
    local call = math.random(1, #t);
    CallCompanion("MOUNT", t[call]);
end

function CollectMe:BuildList()

    if self.UI.active_group == self.MOUNT then
        self:RefreshKnownMounts()
    elseif self.UI.active_group == self.TITLE and self.db.profile.missing_message.titles == false then
        self.TitleDB:PrintUnkown()
    end

    local active, ignored = {}, {}
    local all_count, known_count, filter_count = #self.item_list, 0, 0

    for i,v in ipairs(self.item_list) do
        if (self.UI.active_group == self.MOUNT and not self:IsInTable(self.known_mounts, v.id)) or (self.UI.active_group == self.TITLE and IsTitleKnown(v.id) ~= 1) then
            if self:IsInTable(self.ignored_db, v.id) then
                table.insert(ignored, v)
            else
                if not self:IsFiltered(v.filters) then
                    table.insert(active, v)
                else
                    filter_count = filter_count + 1
                end
            end
        else
            known_count = known_count +1
        end
    end

    self:AddMissingRows(active, ignored, all_count, known_count, filter_count)
end

function CollectMe:AddMissingRows(active, ignored, all_count, known_count, filter_count)
    self.UI:AddToScroll(self.UI:CreateHeading(self.L["Missing"] .. " - " .. #active))
    self:BuildItemRow(active)

    local hide_ignore = (self.UI.active_group == self.MOUNT and self.db.profile.hide_ignore.mounts or self.db.profile.hide_ignore.titles )
    if hide_ignore == false then
        self.UI:AddToScroll(self.UI:CreateHeading(self.L["Ignored"] .. " - " .. #ignored))
        self:BuildItemRow(ignored)
    end

    all_count = all_count - #self.ignored_db - filter_count
    self.UI:UpdateStatusBar(all_count, known_count)
end

function CollectMe:BuildItemRow(items)
    for i,v in ipairs(items) do
        local callbacks = {
            OnClick = function (container, event, group) CollectMe:ItemRowClick(group, v.id) end,
            OnEnter = function (container, event, group) CollectMe:ItemRowEnter(v) end ,
            OnLeave = function (container, event, group) CollectMe:ItemRowLeave(v) end ,
        }
        self.UI:CreateScrollLabel(v.name, v.icon, callbacks)
    end
end

function CollectMe:BuildMissingCompanionList(listcontainer)
    listcontainer:ReleaseChildren()
    local collected_filter = not C_PetJournal.IsFlagFiltered(LE_PET_JOURNAL_FLAG_NOT_COLLECTED)
    C_PetJournal.SetSearchFilter("")
    C_PetJournal.SetFlagFilter(LE_PET_JOURNAL_FLAG_NOT_COLLECTED, true)
    local total = C_PetJournal.GetNumPets(false)
    local active, ignored, owned_db = {}, {}, {}

    for i = 1,total do
        local pet_id, _, owned, _, _, _, _, name, icon, _, creature_id, source = C_PetJournal.GetPetInfoByIndex(i, false)
        if owned ~= true then
            local f = self:CreateItemRow()
            f:SetImage(icon)
            f:SetImageSize(20, 20)
            f:SetText(name)
            f:SetCallback("OnClick", function (container, event, group) CollectMe:ItemRowClick(group, creature_id) end)
            f:SetCallback("OnEnter", function (container, event, group) CollectMe:ItemRowEnter({ creature_id = creature_id, source = source, name = name }) end)
            f:SetCallback("OnLeave", function (container, event, group) CollectMe:ItemRowLeave() end)

            if self:IsInTable(self.ignored_db, creature_id) then
                table.insert(ignored, f)
            else
                table.insert(active, f)
            end
        else
            if not self:IsInTable(owned_db, creature_id) then
                table.insert(owned_db, creature_id)
            end
        end
    end

    C_PetJournal.SetFlagFilter(LE_PET_JOURNAL_FLAG_NOT_COLLECTED, collected_filter)
    self:AddMissingRows(listcontainer, active, ignored, #active + #ignored + #owned_db, #owned_db, 0)
end

function CollectMe:IsFiltered(filters)
    if filters ~= nil then
        for k,v in pairs(filters) do
            if v == 1 then
                for i = 1, #self.filter_list, 1 do
                    if self.filter_list[i] == k and self.filter_db[self.filter_list[i]] == true then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function CollectMe:BuildFilters()
    self.UI:AddToFilter(self.UI:CreateHeading(self.L["Filters"]))

    for i = 1, #self.filter_list, 1 do
        self.UI:CreateFilterCheckbox(self.L["filters_" .. self.filter_list[i]], self.filter_db[self.filter_list[i]], { OnValueChanged = function (container, event, value) CollectMe:ToggleFilter(self.filter_list[i], value) end })
    end
end

function CollectMe:BuildMissingCompanionFilters(container)
    container:AddChild(self:CreateHeading(self.L["Source Filter"]))
    local numSources = C_PetJournal.GetNumPetSources();
    for i=1,numSources do
        local f = AceGUI:Create("CheckBox")
        f:SetLabel(_G["BATTLE_PET_SOURCE_"..i])
        f:SetValue(C_PetJournal.IsPetSourceFiltered(i))
        f:SetCallback("OnValueChanged", function (container, event, value)
            value = not value
            C_PetJournal.SetPetSourceFilter(i, value)
            CollectMe:BuildMissingCompanionList(self.scroll)
        end)
        container:AddChild(f)
    end

    container:AddChild(self:CreateHeading(self.L["Family Filter"]))
    local numTypes = C_PetJournal.GetNumPetTypes();
    for i=1,numTypes do
        local f = AceGUI:Create("CheckBox")
        f:SetLabel(_G["BATTLE_PET_NAME_"..i])
        f:SetValue(C_PetJournal.IsPetTypeFiltered(i))
        f:SetCallback("OnValueChanged", function (container, event, value)
            value = not value
            C_PetJournal.SetPetTypeFilter(i, value)
            CollectMe:BuildMissingCompanionList(self.scroll)
        end)
        container:AddChild(f)
    end
end

function CollectMe:BuildOptions()
    self.UI:AddToFilter(self.UI:CreateHeading(self.L["Options"]))

    if self.UI.active_group == self.MOUNT then
        self.UI:CreateFilterCheckbox(self.L["Disable missing mount message"], self.db.profile.missing_message.mounts, { OnValueChanged = function (container, event, value)  self.db.profile.missing_message.mounts = value end })
        self.UI:CreateFilterCheckbox(self.L["Hide ignored list"], self.db.profile.hide_ignore.mounts, { OnValueChanged = function (container, event, value)  self.db.profile.hide_ignore.mounts = value; self.UI:ReloadScroll() end })
    elseif self.UI.active_group == self.TITLE then
        self.UI:CreateFilterCheckbox(self.L["Disable missing title message"], self.db.profile.missing_message.titles, { OnValueChanged = function (container, event, value)  self.db.profile.missing_message.titles = value end })
        self.UI:CreateFilterCheckbox(self.L["Hide ignored list"], self.db.profile.hide_ignore.titles, { OnValueChanged = function (container, event, value)  self.db.profile.hide_ignore.titles = value; self.UI:ReloadScroll() end })
    --[[
    elseif self.UI.active_group == self.COMPANION then
        local f = self:GetCheckboxOption(self.L["Disable tooltip notice for missing companions"], self.db.profile.tooltip.companions.hide)
        f:SetCallback("OnValueChanged", function (container, event, value)  self.db.profile.tooltip.companions.hide = value end)
        container:AddChild(f)
        local f = self:GetCheckboxOption(self.L["Perform quality check in pet battles"],  self.db.profile.tooltip.companions.quality_check)
        f:SetCallback("OnValueChanged", function (container, event, value)  self.db.profile.tooltip.companions.quality_check = value; self:BuildList(self.scroll) end)
        container:AddChild(f)
    elseif self.UI.active_group == self.RANDOM_COMPANION then
        local f = self:GetCheckboxOption(self.L["Auto summon on moving forward"], self.db.profile.summon.companions.auto)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.companions.auto = value end)
        container:AddChild(f)
        local f = self:GetCheckboxOption(self.L["Disable auto summon in pvp"], self.db.profile.summon.companions.disable_pvp)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.companions.disable_pvp = value end)
        container:AddChild(f)
    elseif self.UI.active_group == self.RANDOM_MOUNT then
        local f = self:GetCheckboxOption(self.L["Don't dismount when left-clicking on macro"], self.db.profile.summon.mounts.no_dismount)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.mounts.no_dismount = value end)
        container:AddChild(f)
        local f = self:GetCheckboxOption(self.L["Use flying mounts in water"], self.db.profile.summon.mounts.flying_in_water)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.mounts.flying_in_water = value end)
        container:AddChild(f)
        local f = self:GetCheckboxOption(self.L["Use flying mounts for ground"], self.db.profile.summon.mounts.flying_on_ground)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.mounts.flying_on_ground = value end)
        container:AddChild(f)

        container:AddChild(self:CreateHeading(self.L["Macro"]))

        local f = self:CreateMacroDropdown(self.L["Left Click"], self.db.profile.summon.mounts.macro_left)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.mounts.macro_left = value end)
        container:AddChild(f)
        local f = self:CreateMacroDropdown(self.L["Right Click"], self.db.profile.summon.mounts.macro_right)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.mounts.macro_right = value end)
        container:AddChild(f)
        local f = self:CreateMacroDropdown(self.L["Shift + Left Click"], self.db.profile.summon.mounts.macro_shift_left)
        f:SetCallback("OnValueChanged", function (container, event, value) self.db.profile.summon.mounts.macro_shift_left = value end)
        container:AddChild(f)]]
    end
end

function CollectMe:BatchCheck(value)
    if self.UI.active_group == self.RANDOM_MOUNT then
        local random_db = self.db.profile.random.mounts
        local count = GetNumCompanions("MOUNT")
        for i = 1, count, 1 do
            local _, name, spell_id = GetCompanionInfo("MOUNT", i)
            random_db[spell_id] = value
        end
        self:SelectGroup(self.tabs, RANDOM_MOUNT)
    elseif self.UI.active_group == self.RANDOM_COMPANION then
        local count, owned = C_PetJournal.GetNumPets(false)
        local random_db =  self.db.profile.random.companions

        for i = 1,count do
            local id, _, owned, my_name, level, _, _, name = C_PetJournal.GetPetInfoByIndex(i, false)
            if name ~= nil and owned == true and C_PetJournal.PetIsSummonable(id) then
                random_db[id] = value
            end
        end
        self:SelectGroup(self.tabs, RANDOM_COMPANION)
    end
end

function CollectMe:HandleMountMacro()
    if GetMouseButtonClicked() == "RightButton" then
        value = self.db.profile.summon.mounts.macro_right
    elseif IsShiftKeyDown() then
        value = self.db.profile.summon.mounts.macro_shift_left
    else
        value = self.db.profile.summon.mounts.macro_left
    end

    if value == 1 then
        self:SummonRandomMount()
    elseif value == 2 then
        if IsMounted() then
            Dismount()
        end
    elseif value == 3 then
        self:SummonRandomMount(1)
    end
end

function CollectMe:HandlePetMacro()
    if GetMouseButtonClicked() == "RightButton" then
        self:DismissPet()
    else
        self:SummonRandomCompanion()
    end
end

function CollectMe:DismissPet()
    local active = C_PetJournal.GetSummonedPetGUID()
    if active ~= nil then
        C_PetJournal.SummonPetByGUID(active)
    end
end

function CollectMe:CreateMacroDropdown(label, value)
    local list = {}
    list[1] = self.L["Mount / Dismount"]
    list[2] = self.L["Dismount"]
    list[3] = self.L["Ground Mount / Dismount"]

    local f = AceGUI:Create("Dropdown")
    f:SetLabel(label)
    f:SetList(list)
    f.label:ClearAllPoints()
    f.label:SetPoint("LEFT", 10, 15)
    f.dropdown:ClearAllPoints()
    f.dropdown:SetPoint("TOPLEFT",f.frame,"TOPLEFT",-10,-15)
    f.dropdown:SetPoint("BOTTOMRIGHT",f.frame,"BOTTOMRIGHT",17,0)
    f:SetValue(value)
    return f
end

function CollectMe:ToggleFilter(filter, value)
    self.filter_db[filter] = value
    self.UI:ReloadScroll()
end

function CollectMe:ItemRowClick(group, spell_id)
    if self.UI.active_group == self.MOUNT and group == "LeftButton" then
        local mount = self:GetMountInfo(spell_id)
        if mount ~= nil then
            if IsShiftKeyDown() == 1 and mount.link ~= nil then
                ChatEdit_InsertLink(mount.link)
            elseif mount.display_id ~= nil then
                self:PreviewCreature(mount.display_id)
            end
        end
    elseif self.UI.active_group == self.COMPANION and group == "LeftButton" then
        if spell_id ~= nil then
            self:PreviewCreature(spell_id)
        end
    elseif group == "RightButton" and IsControlKeyDown() then
        local ignored_table = self.ignored_db

        local position = self:IsInTable(ignored_table, spell_id)
        if position ~= false then
            table.remove(ignored_table, position)
        else
            table.insert(ignored_table, spell_id)
        end

        self.UI:ReloadScroll()
    end
end

function CollectMe:PreviewCreature(display_id)
    if display_id ~= nil then
        self.display_creature = true
        DressUpBackgroundTopLeft:SetTexture(nil);
        DressUpBackgroundTopRight:SetTexture(nil);
        DressUpBackgroundBotLeft:SetTexture(nil);
        DressUpBackgroundBotRight:SetTexture(nil);
        if self.UI.active_group == self.COMPANION then
            DressUpModel:SetCreature(display_id)
        else
            DressUpModel:SetDisplayInfo(display_id)
        end
        if not DressUpFrame:IsShown() then
            ShowUIPanel(DressUpFrame);
        end
    end
end

function CollectMe:ItemRowEnter(v)
    local tooltip = self.UI.frame.tooltip
    tooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    if self.UI.active_group == self.MOUNT then
        tooltip:SetHyperlink(v.link)
        tooltip:AddLine(" ")
        tooltip:AddLine(self.L["mount_" .. v.id], 0, 1, 0, 1)
    elseif self.UI.active_group == self.COMPANION then
        tooltip:AddLine(v.name, 1, 1 ,1)
        tooltip:AddLine(" ")
        tooltip:AddLine(v.source, 0, 1, 0, 1)
        local info = self.L["companion_" .. v.creature_id]
        if string.find(info, "companion_") == nil then
            tooltip:AddLine(" ")
            tooltip:AddLine(info, 0, 1, 0, 1)
        end
    else
        tooltip:AddLine(v.name)
        tooltip:AddLine(" ")
        tooltip:AddLine(self.L["title_" .. v.id], 0, 1, 0, 1)
    end

    if v.filters ~= nil then
        tooltip:AddLine(" ")
        for k,value in pairs(v.filters) do
            tooltip:AddLine(self.L["filters_" .. k], 0, 0.5, 1, 1)
        end
    end

    tooltip:AddLine(" ")
    if self.UI.active_group == self.MOUNT then
        tooltip:AddLine(self.L["tooltip_preview"], 0.65, 0.65, 0)
        tooltip:AddLine(self.L["tooltip_link"], 0.65, 0.65, 0)
    elseif self.UI.active_group == self.COMPANION then
        tooltip:AddLine(self.L["tooltip_preview"], 0.65, 0.65, 0)
    end
    tooltip:AddLine(self.L["tooltip_toggle"], 0.65, 0.65, 0)
    tooltip:Show()
end

function CollectMe:ItemRowLeave()
    self.UI.frame.tooltip:Hide()
end

function CollectMe:GetMountInfo(spell_id)
    for i,v in ipairs(self.MOUNTS) do
        if v.id == spell_id then
            return v
        end
    end
    return nil
end

function CollectMe:RefreshKnownMounts()
    self.known_mount_count = GetNumCompanions("Mount")
    self.known_mounts = {}

    for i = 1, self.known_mount_count, 1 do
        local _, name, spell_id = GetCompanionInfo("Mount", i)
        table.insert(self.known_mounts, spell_id);
        if self.db.profile.missing_message.mounts == false then
            if not self:IsInTable(self.MOUNT_SPELLS, spell_id) then
                self:Print(self.L["Mount"] .. " " .. name .. "("..spell_id..") " .. self.L["is missing"] .. ". " .. self.L["Please inform the author"])
            end
        end
    end
end

function CollectMe:GetActive(type)
    for i = 1, GetNumCompanions(type) do
        local _, _, spell_id, _, summoned = GetCompanionInfo("CRITTER", i);
        if (summoned ~= nil) then
            return spell_id
        end
    end
    return nil;
end

-- checks is element is in table returns position if true, false otherwise
function CollectMe:IsInTable(t, spell_id)
    for i = 1, #t do
        if t[i] == spell_id then
            return i
        end
    end

    return false
end

-- no round in math library? seriously????
function CollectMe:round(num, idp)
    local mult = 10^(idp or 0)
    return math.floor(num * mult + 0.5) / mult
end

function CollectMe:SortTable(tbl)
    table.sort(tbl, function(a, b) return (string.lower(a.name) < string.lower(b.name)) end)
end

function CollectMe:PrintProfessions()
    for i,v in ipairs(self.professions) do
        self:Print(v.name ..' - '.. v.skill)
    end
end

 -- CONSOLE COMMAND HANDLER
function CollectMe:SlashProcessor(input)
    if input == "rc" or input == "randomcompanion" then
        self:SummonRandomCompanion()
    elseif input == "rm" or input == "randommount" then
        self:SummonRandomMount()
    elseif input == "options" then
        InterfaceOptionsFrame_OpenToCategory(addon_name)
    elseif input == "companion zone" then
        self:CompanionsInZone()
    elseif input == "debug zone" then
        self:Print(self:GetCurrentZone())
    elseif input == "debug title" then
        self.TitleDB:PrintAll()
    elseif input == "debug profession" then
        self:PrintProfessions()
    elseif input == "macro" then
        self:UpdateMacros()
    else
        self.tabs:SelectTab(self.UI.active_group)
        self.frame:Show()
    end
end

 -- HOOKS
function CollectMe:DressUpItemLink(link)
    local spell = tonumber(link:match("spell:(%d+)"));
    if spell ~= nil then
        local info = self:GetMountInfo(spell)
        if info ~= nil then
            self:PreviewCreature(info.display_id)
            return true
        end
    end
    if self.display_creature == true then
        SetDressUpBackground(DressUpFrame, self.RACE);
        DressUpModel:SetUnit("player")
        self.display_creature = false
    end
end

function CollectMe:DressUpFrameResetButton()
     SetDressUpBackground(DressUpFrame, self.RACE);
     DressUpModel:SetUnit("player");
end

function CollectMe:AutoSummonCompanion()
    if UnitAffectingCombat("player") == nil and IsMounted() == nil and IsStealthed() == nil and self.db.profile.summon.companions.auto == true then
        if (not (UnitIsPVP("player") == 1 and self.db.profile.summon.companions.disable_pvp == true)) then
            local active = C_PetJournal.GetSummonedPetGUID()
            if (active == nil) then
                self:SummonRandomCompanion()
            end
        end
    end
    if (UnitIsPVP("player") == 1 and self.db.profile.summon.companions.disable_pvp == true) then
        self:DismissPet()
    end
end

function CollectMe:ColorizeByQuality(text, quality)
    local color = "|C" .. select(4, GetItemQualityColor(quality))
    return color .. text .. FONT_COLOR_CODE_CLOSE;
end

function CollectMe:TooltipHook(tooltip)
    if self.gametooltip_visible == true or self.db.profile.tooltip.companions.hide == true then
        return
    end

    self.gametooltip_visible = true
    if (tooltip and tooltip.GetUnit) then
        local _, unit = tooltip:GetUnit()
        if (unit and UnitIsWildBattlePet(unit)) then
            local creature_id = tonumber(strsub(UnitGUID(unit), 7, 10), 16)
            local line
            for i,v in ipairs(self.CompanionDB:GetCompanions()) do
                if(creature_id == v.creature_id) then
                    if line == nil then
                        line = self.L["My companions"] .. ": "
                    else
                        line = line .. ", "
                    end
                    line = line .. self:ColorizeByQuality(_G["BATTLE_PET_BREED_QUALITY" .. v.quality] .. " (" .. v.level .. ")" , v.color)
                end
            end
            if line ~= nil then
                tooltip:AddLine(line)
            else
                tooltip:AddLine(RED_FONT_COLOR_CODE .. self.L["Missing companion"] .. FONT_COLOR_CODE_CLOSE)
            end
            tooltip:Show()
        end
    end
    self.gametooltip_visible = false
end

function CollectMe:ResetEnemyTable()
    self.enemyTable = {}
end

function CollectMe:IsInEnemyTable(id, quality)
    for i = 1, #self.enemyTable do
        if self.enemyTable[i].enemy_species_id == id and self.enemyTable[i].enemy_quality == quality then
            return i
        end
    end

    return false
end

function CollectMe:CheckEnemyQuality()
    if self.db.profile.tooltip.companions.quality_check == true then
        local trapable, trap_error = C_PetBattles.IsTrapAvailable()
        if trap_error == 6 or trap_error == 7 then
            return
        end
        for i=1, C_PetBattles.GetNumPets(2) do
            local enemy_species_id = C_PetBattles.GetPetSpeciesID(LE_BATTLE_PET_ENEMY, i)
            local enemy_quality = C_PetBattles.GetBreedQuality(LE_BATTLE_PET_ENEMY,i)
            local quality = -1

            local index = CollectMe:IsInEnemyTable(enemy_species_id, enemy_quality)
            if index == false then
                tinsert(self.enemyTable, {
                    enemy_species_id = enemy_species_id,
                    enemy_quality = enemy_quality,
                    already_printed = false
                })

                index = CollectMe:IsInEnemyTable(enemy_species_id, enemy_quality)
            end

            for j,v in ipairs(self.CompanionDB:GetCompanions()) do
                if v.species_id == enemy_species_id then
                    if quality < v.quality then
                        quality = v.quality
                    end
                end
            end

            if self.enemyTable[index].already_printed == false then
                if quality == -1 then
                    self:Print(C_PetBattles.GetName(2,i).." - " .. self:ColorizeByQuality(_G["BATTLE_PET_BREED_QUALITY" .. enemy_quality], enemy_quality - 1) .. " - " .. RED_FONT_COLOR_CODE .. self.L["Missing companion"] .. FONT_COLOR_CODE_CLOSE)
                elseif quality < enemy_quality then
                    self:Print(C_PetBattles.GetName(2,i).." - " .. self:ColorizeByQuality(_G["BATTLE_PET_BREED_QUALITY" .. enemy_quality], enemy_quality - 1) .. " - " .. RED_FONT_COLOR_CODE .. self.L["This companion has a higher quality than yours"] .. FONT_COLOR_CODE_CLOSE)
                end

                self.enemyTable[index].already_printed = true
            end
        end
    end
end

function CollectMe:CompanionsInZone()
    local zone = self:GetCurrentZone()
    local known, unknown = self.CompanionDB:GetCompanionsInZone(zone)
    for i,v in ipairs(known) do
        self:Print("known "..v.name)
    end
    for i,v in ipairs(unknown) do
        self:Print("unknown "..v.name)
    end
end