--- ViewModel bridge between DataStore and the XAML ArmoryPanel.
-- @module ArmoryPanelVM
--
-- Architecture: same as InventoryPanelVM —
--   Widget found by name "ArmoryPanel" in ContentRoot.Children.
--   Fresh VM created and set as DataContext immediately (prevents Noesis GC).
--   Re-find widget and re-acquire VM every time we need it.

local ArmoryPanelVM = {}

local isRegistered = false
local isBound = false

-- Currently selected equipment slot for filtering
local selectedSlotId = "Helmet"
local selectedSlotLabel = "Helmet"

-- Slot map for equip action: index → UUID
local _slotMap = {}

-- Equip lock: prevents rapid equip clicks from crashing the game
local _equipBusy = false

-- Character change detection
local _lastCharPtr = nil

-- Filter state for the armory panel
local armoryFilterState = {
    rarities    = {},   -- { Rare=true, ... }
    damageDice  = {},   -- { ["1d8"]=true, ... }
    damageTypes = {},   -- { Slashing=true, ... }
    acRanges    = {},   -- { ["10-12"]=true, ... }
    sortBy      = nil,
    sortAscending = true,
}

--- Get the category for a slot ID (Weapons / Armor / Accessories / All).
local function GetSlotCategory(slotId)
    if slotId == "All" then return "All" end
    local weapons = { MeleeMainHand=true, MeleeOffHand=true, RangedMainHand=true }
    local armor   = { Helmet=true, Breast=true, Cloak=true, Gloves=true, Boots=true }
    if weapons[slotId] then return "Weapons" end
    if armor[slotId]   then return "Armor" end
    return "Accessories"
end

--- Parse "1d8 Slashing" style DamageStr into dice and type.
local function ParseDamageStr(damageStr)
    if not damageStr or damageStr == "" then return nil, nil end
    local dice = damageStr:match("(%d+d%d+)")
    local dmgType = damageStr:match("%d+d%d+%s+(%a+)")
    return dice, dmgType
end

--- Check if an AC value matches any selected AC range.
local function MatchACRange(acStr, ranges)
    local ac = tonumber(acStr)
    if not ac then return false end
    for range, _ in pairs(ranges) do
        if range == "16+" and ac >= 16 then return true
        elseif range == "13-15" and ac >= 13 and ac <= 15 then return true
        elseif range == "10-12" and ac >= 10 and ac <= 12 then return true
        end
    end
    return false
end

--- Count active armory filter toggles.
local function CountArmoryFilters()
    local n = 0
    for _ in pairs(armoryFilterState.rarities) do n = n + 1 end
    for _ in pairs(armoryFilterState.damageDice) do n = n + 1 end
    for _ in pairs(armoryFilterState.damageTypes) do n = n + 1 end
    for _ in pairs(armoryFilterState.acRanges) do n = n + 1 end
    return n
end

--- Find the ArmoryPanel widget in ContentRoot.
-- MUST be defined before any function that calls GetVM().
local function FindWidget()
    local root = Ext.UI.GetRoot()
    if not root then return nil end

    local contentRoot = nil
    pcall(function() contentRoot = root:Find("ContentRoot") end)
    if not contentRoot then return nil end

    local children = nil
    pcall(function() children = contentRoot.Children end)
    if not children then return nil end

    local count = 0
    pcall(function() count = children.Count or 0 end)
    if count == 0 then pcall(function() count = #children end) end

    for i = 1, count do
        local child = nil
        pcall(function() child = children[i] end)
        if child then
            local name = ""
            pcall(function() name = child.Name or "" end)
            if name == "ArmoryPanel" then
                return child
            end
        end
    end

    return nil
end

--- Get VM by re-finding widget and reading DataContext (fresh each call).
-- MUST be defined before any function that calls GetVM().
local function GetVM()
    if not isBound then return nil end
    local widget = FindWidget()
    if not widget then return nil end
    local vm = nil
    local ok = pcall(function() vm = widget.DataContext end)
    if ok and vm then
        local ok2 = pcall(function() local _ = vm.StatusText end)
        if ok2 then return vm end
    end
    return nil
end

--- Update ActiveFilterCount on the VM.
local function UpdateArmoryFilterCount()
    pcall(function()
        local vm = nil
        vm = GetVM()
        if not vm then return end
        local c = CountArmoryFilters()
        vm.ActiveFilterCount = c > 0 and tostring(c) or ""
    end)
end

--- Update filter section visibility based on current slot category.
local function UpdateFilterSectionVisibility()
    pcall(function()
        local vm = nil
        vm = GetVM()
        if not vm then return end
        local cat = GetSlotCategory(selectedSlotId)
        local showDice = (cat == "Weapons" or cat == "All") and "True" or "False"
        local showDmgType = (cat == "Weapons" or cat == "All") and "True" or "False"
        local showAC = (cat == "Armor" or cat == "All") and "True" or "False"
        pcall(function() vm.FilterSection_DamageDice = showDice end)
        pcall(function() vm.FilterSection_DamageType = showDmgType end)
        pcall(function() vm.FilterSection_AC = showAC end)
    end)
end

--- Clear context-specific filters that don't apply to the current slot category.
--- Wipes tables in-place to preserve references held by toggle handler closures.
local function ClearIrrelevantFilters()
    local cat = GetSlotCategory(selectedSlotId)
    if cat ~= "Weapons" and cat ~= "All" then
        for k in pairs(armoryFilterState.damageDice) do armoryFilterState.damageDice[k] = nil end
        for k in pairs(armoryFilterState.damageTypes) do armoryFilterState.damageTypes[k] = nil end
    end
    if cat ~= "Armor" and cat ~= "All" then
        for k in pairs(armoryFilterState.acRanges) do armoryFilterState.acRanges[k] = nil end
    end
end

--- Update all SortState_* VM properties based on armoryFilterState.
local function UpdateArmorySortIndicators()
    pcall(function()
        local vm = nil
        vm = GetVM()
        if not vm then return end
        local fields = {"Name", "Value", "Weight", "Rarity"}
        for _, f in ipairs(fields) do
            local state = ""
            if armoryFilterState.sortBy == f then
                state = armoryFilterState.sortAscending and "Asc" or "Desc"
            end
            pcall(function() vm["SortState_" .. f] = state end)
        end
    end)
end

--- Sync all filter toggle VM properties from armoryFilterState (e.g. after clear).
local function SyncAllFilterProps()
    pcall(function()
        local vm = nil
        vm = GetVM()
        if not vm then return end

        -- Rarity
        local rarities = {"Common", "Uncommon", "Rare", "VeryRare", "Legendary"}
        for _, r in ipairs(rarities) do
            pcall(function() vm["FilterRarity_" .. r] = armoryFilterState.rarities[r] and "True" or "False" end)
        end

        -- Damage dice
        local diceKeys = {["1d4"]="1d4", ["1d6"]="1d6", ["1d8"]="1d8", ["1d10"]="1d10", ["1d12"]="1d12", ["2d6"]="2d6"}
        for k, _ in pairs(diceKeys) do
            local prop = "FilterDice_" .. k
            pcall(function() vm[prop] = armoryFilterState.damageDice[k] and "True" or "False" end)
        end

        -- Damage types
        local dmgTypes = {"Slashing","Piercing","Bludgeoning","Fire","Cold","Lightning","Thunder","Poison","Acid","Necrotic","Radiant","Force","Psychic"}
        for _, dt in ipairs(dmgTypes) do
            pcall(function() vm["FilterDmgType_" .. dt] = armoryFilterState.damageTypes[dt] and "True" or "False" end)
        end

        -- AC ranges
        local acMap = {["10-12"]="10to12", ["13-15"]="13to15", ["16+"]="16plus"}
        for key, prop in pairs(acMap) do
            pcall(function() vm["FilterAC_" .. prop] = armoryFilterState.acRanges[key] and "True" or "False" end)
        end
    end)
end

--- Factory: create a toggle handler for an armory filter category.
local function MakeArmoryToggleHandler(propName, stateSet, key)
    return function()
        if stateSet[key] then
            stateSet[key] = nil
        else
            stateSet[key] = true
        end
        pcall(function()
            local vm = GetVM()
            if vm then
                vm[propName] = stateSet[key] and "True" or "False"
            end
        end)
        UpdateArmoryFilterCount()
        ArmoryPanelVM.PopulateFilteredItems()
    end
end

--- Factory: create a 3-state sort toggle handler for armory.
local function MakeArmorySortHandler(field)
    return function()
        if armoryFilterState.sortBy == field then
            if not armoryFilterState.sortAscending then
                armoryFilterState.sortAscending = true
            else
                armoryFilterState.sortBy = nil
                armoryFilterState.sortAscending = true
            end
        else
            armoryFilterState.sortBy = field
            armoryFilterState.sortAscending = false
        end
        UpdateArmorySortIndicators()
        ArmoryPanelVM.PopulateFilteredItems()
    end
end

--- Equipment slot definitions.
--- id = DataStore item.Slot value from server's tostring(Equipable.Slot) AND FilterEngine key
local EQ_ICON_BASE = "pack://application:,,,/Core;component/Assets/CharacterPanel/EquipSlots/"
local EquipmentSlots = {
    { id = "Helmet",         label = "Helmet",    vmSuffix = "Helmet",   icon = EQ_ICON_BASE .. "EQ_head.png" },
    { id = "Breast",         label = "Armor",     vmSuffix = "Chest",    icon = EQ_ICON_BASE .. "EQ_chest.png" },
    { id = "Cloak",          label = "Cloak",     vmSuffix = "Cloak",    icon = EQ_ICON_BASE .. "EQ_cloak.png" },
    { id = "MeleeMainHand",  label = "Main Hand", vmSuffix = "MainHand", icon = EQ_ICON_BASE .. "EQ_melee_mainhand.png" },
    { id = "MeleeOffHand",   label = "Off Hand",  vmSuffix = "OffHand",  icon = EQ_ICON_BASE .. "EQ_melee_offhand.png" },
    { id = "RangedMainHand", label = "Ranged",    vmSuffix = "Ranged",   icon = EQ_ICON_BASE .. "EQ_ranged_mainhand.png" },
    { id = "Gloves",         label = "Gloves",    vmSuffix = "Gloves",   icon = EQ_ICON_BASE .. "EQ_gloves.png" },
    { id = "Boots",          label = "Boots",     vmSuffix = "Boots",    icon = EQ_ICON_BASE .. "EQ_feet.png" },
    { id = "Amulet",         label = "Amulet",    vmSuffix = "Amulet",   icon = EQ_ICON_BASE .. "EQ_amulet.png" },
    { id = "Ring",           label = "Ring 1",    vmSuffix = "Ring",     icon = EQ_ICON_BASE .. "EQ_ring01.png" },
    { id = "Ring2",          label = "Ring 2",    vmSuffix = "Ring2",    icon = EQ_ICON_BASE .. "EQ_ring02.png" },
}

--- Register VM types with SE.
local function RegisterTypes()
    if isRegistered then return end

    -- Build properties table for INVRW_ArmoryPanelVM
    local vmProps = {
        PanelVisible   = { Type = "Bool",   Notify = true },
        StatusText     = { Type = "String", Notify = true },
        SelectedChar   = { Type = "Object", Notify = true },
        CharacterName  = { Type = "String", Notify = true },

        EquippedSlots  = { Type = "Collection" },
        FilteredItems  = { Type = "Collection" },
        ActiveSlotLabel = { Type = "String", Notify = true },
        SelectedIndex  = { Type = "Int32",  Notify = true },

        EquipSelectedCommand      = { Type = "Command" },
        EquippedSlotClickCommand  = { Type = "Command" },
        ToggleCommand             = { Type = "Command" },
        RefreshCommand            = { Type = "Command" },
        EquippedSlotIndex         = { Type = "Int32", Notify = true },

        -- "All" slot
        SelectSlot_All = { Type = "Command" },
        SlotActive_All = { Type = "String", Notify = true },

        -- Filter panel
        FilterPanelVisible       = { Type = "Bool",   Notify = true },
        ActiveFilterCount        = { Type = "String", Notify = true },
        ToggleFilterPanelCommand = { Type = "Command" },
        ClearAllFiltersCommand   = { Type = "Command" },

        -- Section visibility (context-sensitive)
        FilterSection_DamageDice = { Type = "String", Notify = true },
        FilterSection_DamageType = { Type = "String", Notify = true },
        FilterSection_AC         = { Type = "String", Notify = true },

        -- Rarity filters
        FilterRarity_Common    = { Type = "String", Notify = true },
        FilterRarity_Uncommon  = { Type = "String", Notify = true },
        FilterRarity_Rare      = { Type = "String", Notify = true },
        FilterRarity_VeryRare  = { Type = "String", Notify = true },
        FilterRarity_Legendary = { Type = "String", Notify = true },
        ToggleRarity_Common    = { Type = "Command" },
        ToggleRarity_Uncommon  = { Type = "Command" },
        ToggleRarity_Rare      = { Type = "Command" },
        ToggleRarity_VeryRare  = { Type = "Command" },
        ToggleRarity_Legendary = { Type = "Command" },

        -- Sort
        SortState_Name    = { Type = "String", Notify = true },
        SortState_Value   = { Type = "String", Notify = true },
        SortState_Weight  = { Type = "String", Notify = true },
        SortState_Rarity  = { Type = "String", Notify = true },
        SortByNameCommand   = { Type = "Command" },
        SortByValueCommand  = { Type = "Command" },
        SortByWeightCommand = { Type = "Command" },
        SortByRarityCommand = { Type = "Command" },

        -- Damage dice filters
        FilterDice_1d4  = { Type = "String", Notify = true },
        FilterDice_1d6  = { Type = "String", Notify = true },
        FilterDice_1d8  = { Type = "String", Notify = true },
        FilterDice_1d10 = { Type = "String", Notify = true },
        FilterDice_1d12 = { Type = "String", Notify = true },
        FilterDice_2d6  = { Type = "String", Notify = true },
        ToggleDice_1d4  = { Type = "Command" },
        ToggleDice_1d6  = { Type = "Command" },
        ToggleDice_1d8  = { Type = "Command" },
        ToggleDice_1d10 = { Type = "Command" },
        ToggleDice_1d12 = { Type = "Command" },
        ToggleDice_2d6  = { Type = "Command" },

        -- Damage type filters
        FilterDmgType_Slashing    = { Type = "String", Notify = true },
        FilterDmgType_Piercing    = { Type = "String", Notify = true },
        FilterDmgType_Bludgeoning = { Type = "String", Notify = true },
        FilterDmgType_Fire        = { Type = "String", Notify = true },
        FilterDmgType_Cold        = { Type = "String", Notify = true },
        FilterDmgType_Lightning   = { Type = "String", Notify = true },
        FilterDmgType_Thunder     = { Type = "String", Notify = true },
        FilterDmgType_Poison      = { Type = "String", Notify = true },
        FilterDmgType_Acid        = { Type = "String", Notify = true },
        FilterDmgType_Necrotic    = { Type = "String", Notify = true },
        FilterDmgType_Radiant     = { Type = "String", Notify = true },
        FilterDmgType_Force       = { Type = "String", Notify = true },
        FilterDmgType_Psychic     = { Type = "String", Notify = true },
        ToggleDmgType_Slashing    = { Type = "Command" },
        ToggleDmgType_Piercing    = { Type = "Command" },
        ToggleDmgType_Bludgeoning = { Type = "Command" },
        ToggleDmgType_Fire        = { Type = "Command" },
        ToggleDmgType_Cold        = { Type = "Command" },
        ToggleDmgType_Lightning   = { Type = "Command" },
        ToggleDmgType_Thunder     = { Type = "Command" },
        ToggleDmgType_Poison      = { Type = "Command" },
        ToggleDmgType_Acid        = { Type = "Command" },
        ToggleDmgType_Necrotic    = { Type = "Command" },
        ToggleDmgType_Radiant     = { Type = "Command" },
        ToggleDmgType_Force       = { Type = "Command" },
        ToggleDmgType_Psychic     = { Type = "Command" },

        -- AC range filters
        FilterAC_10to12 = { Type = "String", Notify = true },
        FilterAC_13to15 = { Type = "String", Notify = true },
        FilterAC_16plus = { Type = "String", Notify = true },
        ToggleAC_10to12 = { Type = "Command" },
        ToggleAC_13to15 = { Type = "Command" },
        ToggleAC_16plus = { Type = "Command" },
    }

    -- Add 11 slot select commands + 11 slot active states
    for _, slot in ipairs(EquipmentSlots) do
        vmProps["SelectSlot_" .. slot.vmSuffix] = { Type = "Command" }
        vmProps["SlotActive_" .. slot.vmSuffix] = { Type = "String", Notify = true }
    end

    Ext.UI.RegisterType("INVRW_ArmoryPanelVM", vmProps)

    isRegistered = true
    _P("[BG3InventoryRework] ArmoryPanelVM types registered")
end

--- Clear a VM collection.
local function ClearCollection(collection)
    for i = #collection, 1, -1 do
        collection[i] = nil
    end
end

--- Count keys in a table.
local function tableCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- Get the selected character VM and UUID from game overlay.
local function getSelectedCharInfo()
    local selectedChar = nil
    local charUUID = nil
    pcall(function()
        local root = Ext.UI.GetRoot()
        if not root then return end
        local contentRoot = root:Find("ContentRoot")
        if not contentRoot then return end

        local overlay = nil
        local children = contentRoot.Children
        for i = 0, 30 do
            pcall(function()
                local c = children[i]
                if c and c.Name == "Overlay" then overlay = c end
            end)
        end
        if not overlay or not overlay.DataContext then return end

        local cp = overlay.DataContext.CurrentPlayer
        if not cp then return end

        pcall(function() selectedChar = cp.SelectedCharacter end)
        if selectedChar then
            local props = {"UniqueId", "UUID", "EntityUUID", "EntityHandle",
                           "CharacterUUID", "Id", "Guid", "Handle", "GuidString"}
            for _, pn in ipairs(props) do
                pcall(function()
                    local val = selectedChar[pn]
                    if val ~= nil and val ~= "" then
                        if not charUUID then charUUID = val end
                    end
                end)
            end
        end
    end)
    return selectedChar, charUUID
end

--- Collect native VMItems from ALL party inventories (same pattern as InventoryPanelVM).
--- Returns map { [entityUUID] = { vmObject=obj, entityHandle=eh } }
local function GetGameVMItems()
    local map = {}
    local selectedChar = nil
    pcall(function()
        local root = Ext.UI.GetRoot()
        if not root then return end
        local contentRoot = root:Find("ContentRoot")
        if not contentRoot then return end

        local overlay = nil
        local children = contentRoot.Children
        for i = 0, 30 do
            pcall(function()
                local c = children[i]
                if c and c.Name == "Overlay" then overlay = c end
            end)
        end
        if not overlay or not overlay.DataContext then return end

        local dc = overlay.DataContext
        local cp = dc.CurrentPlayer
        if not cp then return end

        local function extractSlots(inv)
            if not inv then return end
            pcall(function()
                local slots = inv.Slots
                if not slots then return end
                local slotCount = #slots
                for j = 1, slotCount do
                    pcall(function()
                        local slot = slots[j]
                        if slot and slot.Object then
                            local obj = slot.Object
                            local uuid = obj.EntityUUID
                            if uuid and uuid ~= "" then
                                local eh = nil
                                pcall(function() eh = obj.EntityHandle end)
                                map[uuid] = { vmObject = obj, entityHandle = eh }
                            end
                        end
                    end)
                end
            end)
        end

        pcall(function() selectedChar = cp.SelectedCharacter end)
        if selectedChar then
            -- Collect from SelectedCharacter
            local usedInventories = false
            pcall(function()
                local invs = selectedChar.Inventories
                if invs then
                    local invCount = #invs
                    if invCount > 0 then
                        usedInventories = true
                        for k = 1, invCount do
                            pcall(function() extractSlots(invs[k]) end)
                        end
                    end
                end
            end)
            if not usedInventories then
                extractSlots(selectedChar.Inventory)
            end
        end

        -- Collect from ALL party members
        local partyChars = nil
        pcall(function() partyChars = dc.Data.PartyCharacters end)
        if partyChars then
            local pcCount = 0
            pcall(function() pcCount = #partyChars end)
            local selectedInvPtr = nil
            pcall(function() selectedInvPtr = tostring(cp.SelectedCharacter.Inventories) end)
            for c = 1, pcCount do
                pcall(function()
                    local char = partyChars[c]
                    if not char then return end
                    local thisInvPtr = nil
                    pcall(function() thisInvPtr = tostring(char.Inventories) end)
                    if thisInvPtr and thisInvPtr == selectedInvPtr then return end
                    local usedInvs = false
                    pcall(function()
                        local invs = char.Inventories
                        if invs then
                            local invCount = #invs
                            if invCount > 0 then
                                usedInvs = true
                                for k = 1, invCount do
                                    pcall(function() extractSlots(invs[k]) end)
                                end
                            end
                        end
                    end)
                    if not usedInvs then
                        extractSlots(char.Inventory)
                    end
                end)
            end
        end
    end)
    return map, selectedChar
end

--- Collect native VMItem slot entries as temp array (same pattern as InventoryPanelVM).
--- Returns array of { slot, uuid, name, vmObject, entityHandle, nativeCount }
local function CollectNativeSlots()
    local tempSlots = {}
    local totalCount = 0
    pcall(function()
        local root = Ext.UI.GetRoot()
        if not root then return end
        local contentRoot = root:Find("ContentRoot")
        if not contentRoot then return end

        local overlay = nil
        local children = contentRoot.Children
        for i = 0, 30 do
            pcall(function()
                local c = children[i]
                if c and c.Name == "Overlay" then overlay = c end
            end)
        end
        if not overlay or not overlay.DataContext then return end

        local cp = overlay.DataContext.CurrentPlayer
        if not cp then return end

        local function collectSlotsFrom(inv)
            if not inv then return end
            pcall(function()
                local slots = inv.Slots
                if not slots then return end
                local slotCount = #slots
                for j = 1, slotCount do
                    pcall(function()
                        local slot = slots[j]
                        if slot and slot.Object then
                            totalCount = totalCount + 1
                            local uuid, vmObj, entityH, nativeCount = nil, nil, nil, nil
                            pcall(function()
                                local obj = slot.Object
                                uuid = obj.EntityUUID
                                vmObj = obj
                                entityH = obj.EntityHandle
                                local c = obj.Count
                                if c and type(c) == "number" and c > 1 then
                                    nativeCount = c
                                end
                            end)
                            tempSlots[totalCount] = {
                                slot = slot, uuid = uuid,
                                vmObject = vmObj, entityHandle = entityH,
                                nativeCount = nativeCount,
                            }
                        end
                    end)
                end
            end)
        end

        local function addAllFromChar(char)
            local usedInventories = false
            pcall(function()
                local invs = char.Inventories
                if invs then
                    local invCount = #invs
                    if invCount > 0 then
                        usedInventories = true
                        for k = 1, invCount do
                            pcall(function() collectSlotsFrom(invs[k]) end)
                        end
                    end
                end
            end)
            if not usedInventories then
                collectSlotsFrom(char.Inventory)
            end
        end

        if cp.SelectedCharacter then
            addAllFromChar(cp.SelectedCharacter)
        end

        local dc = overlay.DataContext
        local partyChars = nil
        pcall(function() partyChars = dc.Data.PartyCharacters end)
        if partyChars then
            local pcCount = 0
            pcall(function() pcCount = #partyChars end)
            local selectedInvPtr = nil
            pcall(function() selectedInvPtr = tostring(cp.SelectedCharacter.Inventories) end)
            for c = 1, pcCount do
                pcall(function()
                    local char = partyChars[c]
                    if not char then return end
                    local thisInvPtr = nil
                    pcall(function() thisInvPtr = tostring(char.Inventories) end)
                    if thisInvPtr and thisInvPtr == selectedInvPtr then return end
                    addAllFromChar(char)
                end)
            end
        end
    end)
    return tempSlots, totalCount
end

--- Collect native VMItems from ONLY the SelectedCharacter's inventories.
--- Returns a set { [entityUUID] = { vmObject, entityHandle, slot } }
local function GetSelectedCharVMItems()
    local map = {}
    local selectedChar = nil
    pcall(function()
        local root = Ext.UI.GetRoot()
        if not root then return end
        local contentRoot = root:Find("ContentRoot")
        if not contentRoot then return end

        local overlay = nil
        local children = contentRoot.Children
        for i = 0, 30 do
            pcall(function()
                local c = children[i]
                if c and c.Name == "Overlay" then overlay = c end
            end)
        end
        if not overlay or not overlay.DataContext then return end

        local cp = overlay.DataContext.CurrentPlayer
        if not cp then return end
        pcall(function() selectedChar = cp.SelectedCharacter end)
        if not selectedChar then return end

        local function extractSlots(inv)
            if not inv then return end
            pcall(function()
                local slots = inv.Slots
                if not slots then return end
                local slotCount = #slots
                for j = 1, slotCount do
                    pcall(function()
                        local slot = slots[j]
                        if slot and slot.Object then
                            local obj = slot.Object
                            local uuid = obj.EntityUUID
                            if uuid and uuid ~= "" then
                                local eh = nil
                                pcall(function() eh = obj.EntityHandle end)
                                map[uuid] = { vmObject = obj, entityHandle = eh, slot = slot }
                            end
                        end
                    end)
                end
            end)
        end

        local usedInventories = false
        pcall(function()
            local invs = selectedChar.Inventories
            if invs then
                local invCount = #invs
                if invCount > 0 then
                    usedInventories = true
                    for k = 1, invCount do
                        pcall(function() extractSlots(invs[k]) end)
                    end
                end
            end
        end)
        if not usedInventories then
            extractSlots(selectedChar.Inventory)
        end
    end)
    return map, selectedChar
end

--- Populate the left side: equipped slots for the selected character.
--- Uses INVRW_SlotWrapper (same type as right-side items) for icon grid display.
function ArmoryPanelVM.PopulateEquippedSlots()
    local vm = GetVM()
    if not vm then return end

    local DataStore = Mods.BG3InventoryRework.DataStore
    if not DataStore then return end

    -- Get native items for tooltip binding (all party — we filter by OwnerName below)
    local nativeVMItems, selectedChar = GetSelectedCharVMItems()
    if selectedChar then
        pcall(function() vm.SelectedChar = selectedChar end)
    end

    -- Resolve character name: find the MOST COMMON OwnerName among native inventory
    -- items in DataStore. The native inventory is a shared party view, so the most
    -- frequent owner is the selected character (they have the most items in their view).
    local allItems = DataStore.GetAllItems()
    local ownerCounts = {}  -- { [cleanName] = count }
    local nativeUUIDs = {}
    for uuid, _ in pairs(nativeVMItems) do
        nativeUUIDs[uuid] = true
    end
    for _, item in ipairs(allItems) do
        if item.UUID and nativeUUIDs[item.UUID] and item.OwnerName and item.OwnerName ~= "" then
            local name = item.OwnerName
            name = name:gsub("<LSTag[^>]*>([^<]*)</LSTag>", "%1")
            name = name:gsub("<[^>]+>", "")
            ownerCounts[name] = (ownerCounts[name] or 0) + 1
        end
    end
    local charName = "Unknown"
    local maxCount = 0
    for name, count in pairs(ownerCounts) do
        if count > maxCount then
            maxCount = count
            charName = name
        end
    end
    vm.CharacterName = charName

    -- Find equipped items for THIS character only using OwnerName from DataStore.
    -- This is more reliable than UUID matching because SelectedCharacter.Inventories
    -- in Noesis contains items from ALL party members (shared inventory view).
    -- Key: dsSlot value (server-side Equipable.Slot string)
    local equippedBySlot = {}
    for _, item in ipairs(allItems) do
        if item.Equipped and item.Slot and item.Slot ~= "" then
            local ownerName = item.OwnerName or ""
            ownerName = ownerName:gsub("<LSTag[^>]*>([^<]*)</LSTag>", "%1")
            ownerName = ownerName:gsub("<[^>]+>", "")
            if ownerName == charName then
                equippedBySlot[item.Slot] = item
            end
        end
    end

    -- Build SlotWrapper objects for each equipment slot
    local EQ_BLANK = EQ_ICON_BASE .. "EQ_blank.png"
    ClearCollection(vm.EquippedSlots)
    for i, slot in ipairs(EquipmentSlots) do
        local wrapper = Ext.UI.Instantiate("INVRW_SlotWrapper")
        local equipped = equippedBySlot[slot.id]

        if equipped and equipped.UUID and nativeVMItems[equipped.UUID] then
            local native = nativeVMItems[equipped.UUID]
            pcall(function() wrapper.NativeSlot   = native.slot end)
            pcall(function() wrapper.NativeObject = native.vmObject end)
            pcall(function() wrapper.NativeHandle = native.entityHandle end)
            wrapper.Rarity = equipped.Rarity or "Common"
            wrapper.StackSize = 1
            wrapper.ShowStack = false
            wrapper.HasItem = true
            wrapper.SlotIcon = EQ_BLANK  -- blank border, no slot art
            local iconName = equipped.Icon or "Item_Unknown"
            wrapper.ItemIcon = "pack://application:,,,/Core;component/Assets/ControllerUIIcons/items_png/" .. iconName .. ".DDS"
        else
            -- Empty slot: no native bindings, shows per-slot icon
            wrapper.Rarity = "Common"
            wrapper.StackSize = 1
            wrapper.ShowStack = false
            wrapper.HasItem = false
            wrapper.SlotIcon = slot.icon or ""  -- helmet, armor, etc.
        end

        vm.EquippedSlots[i] = wrapper
    end

    _P("[BG3InventoryRework] Armory equipped slots populated for " .. charName
        .. " (" .. tableCount(equippedBySlot) .. " equipped)")
end

--- Populate the right side: filtered items matching selected slot.
function ArmoryPanelVM.PopulateFilteredItems()
    local vm = GetVM()
    if not vm then return end

    local DataStore = Mods.BG3InventoryRework.DataStore
    local FilterEngine = Mods.BG3InventoryRework.FilterEngine
    if not DataStore or not FilterEngine then return end

    local allItems = DataStore.GetAllItems()

    -- Step 1: Filter by slot (or "All" = any equipment item)
    local filtered
    if selectedSlotId == "All" then
        -- Keep only items that have an equipment slot
        filtered = {}
        for _, item in ipairs(allItems) do
            if item.Slot and item.Slot ~= "" then
                filtered[#filtered + 1] = item
            end
        end
    else
        filtered = FilterEngine.FilterMulti(allItems, { slots = { [selectedSlotId] = true } })
    end

    -- Step 2: Apply rarity filter via FilterEngine
    local hasRarities = next(armoryFilterState.rarities)
    if hasRarities then
        filtered = FilterEngine.FilterMulti(filtered, { rarities = armoryFilterState.rarities })
    end

    -- Step 3: Apply custom context-sensitive filters (second pass)
    local hasDice = next(armoryFilterState.damageDice)
    local hasDmgTypes = next(armoryFilterState.damageTypes)
    local hasAC = next(armoryFilterState.acRanges)

    if hasDice or hasDmgTypes or hasAC then
        local passed = {}
        for _, item in ipairs(filtered) do
            local keep = true
            if hasDice then
                local dice, _ = ParseDamageStr(item.DamageStr)
                if not dice or not armoryFilterState.damageDice[dice] then keep = false end
            end
            if keep and hasDmgTypes then
                local _, dmgType = ParseDamageStr(item.DamageStr)
                if not dmgType or not armoryFilterState.damageTypes[dmgType] then keep = false end
            end
            if keep and hasAC then
                if not MatchACRange(item.ArmorClass, armoryFilterState.acRanges) then keep = false end
            end
            if keep then passed[#passed + 1] = item end
        end
        filtered = passed
    end

    -- Step 4: Sort
    if armoryFilterState.sortBy then
        filtered = FilterEngine.Sort(filtered, armoryFilterState.sortBy, armoryFilterState.sortAscending)
    else
        -- Default: sort by rarity descending (best items first)
        filtered = FilterEngine.Sort(filtered, "Rarity", false)
    end

    -- Build UUID set of passing items
    local passingUUIDs = {}
    for _, item in ipairs(filtered) do
        if item.UUID then passingUUIDs[item.UUID] = true end
    end

    -- Build UUID → DataStore item map
    local dsItemByUUID = {}
    for _, item in ipairs(filtered) do
        if item.UUID then dsItemByUUID[item.UUID] = item end
    end

    -- Build sort order
    local uuidOrder = {}
    for rank, item in ipairs(filtered) do
        if item.UUID then uuidOrder[item.UUID] = rank end
    end

    -- Collect native slots from game
    local tempSlots, totalCount = CollectNativeSlots()

    -- Filter native slots to ones matching our filtered items
    local passingEntries = {}
    for i = 1, totalCount do
        local entry = tempSlots[i]
        if entry and entry.uuid and passingUUIDs[entry.uuid] then
            passingEntries[#passingEntries + 1] = entry
        end
    end

    -- Sort by filter order
    table.sort(passingEntries, function(a, b)
        local oa = a.uuid and uuidOrder[a.uuid] or 999999
        local ob = b.uuid and uuidOrder[b.uuid] or 999999
        return oa < ob
    end)

    -- Build FilteredItems collection (reuses INVRW_SlotWrapper type)
    ClearCollection(vm.FilteredItems)
    _slotMap = {}
    local count = 0

    for _, entry in ipairs(passingEntries) do
        local dsItem = entry.uuid and dsItemByUUID[entry.uuid] or nil
        count = count + 1
        local wrapper = Ext.UI.Instantiate("INVRW_SlotWrapper")
        pcall(function() wrapper.NativeSlot   = entry.slot end)
        pcall(function() wrapper.NativeObject = entry.vmObject end)
        pcall(function() wrapper.NativeHandle = entry.entityHandle end)
        wrapper.Rarity = (dsItem and dsItem.Rarity) or "Common"
        local stack = entry.nativeCount or (dsItem and dsItem.StackSize) or 1
        wrapper.StackSize = stack
        wrapper.ShowStack = stack > 1
        vm.FilteredItems[count] = wrapper
        _slotMap[count] = {
            uuid = entry.uuid,
            name = (dsItem and dsItem.Name) or "Unknown"
        }
    end

    vm.ActiveSlotLabel = selectedSlotLabel
    local filterCount = CountArmoryFilters()
    local filterSuffix = filterCount > 0 and (" (" .. filterCount .. " filters)") or ""
    vm.StatusText = selectedSlotLabel .. ": " .. count .. " items for " .. (vm.CharacterName or "?") .. filterSuffix

    _P("[BG3InventoryRework] Armory filtered: " .. count .. " " .. selectedSlotLabel .. " items")
end

--- Full refresh: both sides.
function ArmoryPanelVM.Refresh()
    ArmoryPanelVM.PopulateEquippedSlots()
    ArmoryPanelVM.PopulateFilteredItems()
end

--- Try to bind by creating a fresh VM and setting as DataContext.
function ArmoryPanelVM.TryBind()
    if isBound then return end
    if not isRegistered then return end

    local widget = FindWidget()
    if not widget then return end

    _P("[INVRW ArmoryBind] Found ArmoryPanel widget: " .. tostring(widget))

    local freshVM = nil
    local createOk, createErr = pcall(function()
        freshVM = Ext.UI.Instantiate("INVRW_ArmoryPanelVM")
    end)
    if not createOk or not freshVM then
        _P("[INVRW ArmoryBind] VM creation failed: " .. tostring(createErr))
        return
    end

    -- Wire ToggleCommand
    pcall(function()
        freshVM.ToggleCommand:SetHandler(function()
            ArmoryPanelVM.Toggle()
        end)
    end)

    -- Wire RefreshCommand
    pcall(function()
        freshVM.RefreshCommand:SetHandler(function()
            _P("[BG3InventoryRework] Armory refresh from XAML")
            ArmoryPanelVM.Refresh()
            Mods.BG3InventoryRework.RequestRefresh()
        end)
    end)

    -- Helper: clear all slot active states (including "All")
    local function ClearSlotActiveStates(vm)
        for _, s in ipairs(EquipmentSlots) do
            pcall(function() vm["SlotActive_" .. s.vmSuffix] = "False" end)
        end
        pcall(function() vm.SlotActive_All = "False" end)
    end

    -- Helper: handle slot change (clear irrelevant filters, update visibility, refresh)
    local function OnSlotChanged()
        ClearIrrelevantFilters()
        SyncAllFilterProps()
        UpdateFilterSectionVisibility()
        UpdateArmoryFilterCount()
        ArmoryPanelVM.PopulateFilteredItems()
    end

    -- Wire "All" slot command
    pcall(function()
        freshVM.SelectSlot_All:SetHandler(function()
            selectedSlotId = "All"
            selectedSlotLabel = "All"
            pcall(function()
                local vm = GetVM()
                if not vm then return end
                ClearSlotActiveStates(vm)
                vm.SlotActive_All = "True"
            end)
            OnSlotChanged()
        end)
    end)

    -- Wire slot selection commands (data-driven)
    for _, slot in ipairs(EquipmentSlots) do
        pcall(function()
            freshVM["SelectSlot_" .. slot.vmSuffix]:SetHandler(function()
                selectedSlotId = slot.id
                selectedSlotLabel = slot.label
                pcall(function()
                    local vm = GetVM()
                    if not vm then return end
                    ClearSlotActiveStates(vm)
                    vm["SlotActive_" .. slot.vmSuffix] = "True"
                end)
                OnSlotChanged()
            end)
        end)
    end

    -- Wire EquippedSlotClickCommand (click equipped slot → switch right-side filter)
    pcall(function()
        freshVM.EquippedSlotClickCommand:SetHandler(function()
            local idx = nil
            pcall(function()
                local vm = GetVM()
                if vm then idx = vm.EquippedSlotIndex end
            end)
            if idx == nil or idx < 0 or idx >= #EquipmentSlots then return end
            local slot = EquipmentSlots[idx + 1]  -- 0-based → 1-based
            if not slot then return end
            selectedSlotId = slot.id
            selectedSlotLabel = slot.label
            pcall(function()
                local vm = GetVM()
                if not vm then return end
                ClearSlotActiveStates(vm)
                vm["SlotActive_" .. slot.vmSuffix] = "True"
            end)
            OnSlotChanged()
            _P("[BG3InventoryRework] Armory: equipped slot click → " .. slot.label)
        end)
    end)

    -- Wire ToggleFilterPanelCommand
    pcall(function()
        freshVM.ToggleFilterPanelCommand:SetHandler(function()
            pcall(function()
                local vm = GetVM()
                if vm then vm.FilterPanelVisible = not vm.FilterPanelVisible end
            end)
        end)
    end)

    -- Wire ClearAllFiltersCommand
    -- IMPORTANT: wipe tables in-place (don't replace with {}) because toggle
    -- handler closures hold references to the original table objects.
    pcall(function()
        freshVM.ClearAllFiltersCommand:SetHandler(function()
            for k in pairs(armoryFilterState.rarities) do armoryFilterState.rarities[k] = nil end
            for k in pairs(armoryFilterState.damageDice) do armoryFilterState.damageDice[k] = nil end
            for k in pairs(armoryFilterState.damageTypes) do armoryFilterState.damageTypes[k] = nil end
            for k in pairs(armoryFilterState.acRanges) do armoryFilterState.acRanges[k] = nil end
            armoryFilterState.sortBy = nil
            armoryFilterState.sortAscending = true
            SyncAllFilterProps()
            UpdateArmorySortIndicators()
            UpdateArmoryFilterCount()
            ArmoryPanelVM.PopulateFilteredItems()
        end)
    end)

    -- Wire rarity toggle commands
    local rarityFilters = {
        {cmd="ToggleRarity_Common",    prop="FilterRarity_Common",    key="Common"},
        {cmd="ToggleRarity_Uncommon",  prop="FilterRarity_Uncommon",  key="Uncommon"},
        {cmd="ToggleRarity_Rare",      prop="FilterRarity_Rare",      key="Rare"},
        {cmd="ToggleRarity_VeryRare",  prop="FilterRarity_VeryRare",  key="VeryRare"},
        {cmd="ToggleRarity_Legendary", prop="FilterRarity_Legendary", key="Legendary"},
    }
    for _, f in ipairs(rarityFilters) do
        local ok, err = pcall(function() freshVM[f.cmd]:SetHandler(MakeArmoryToggleHandler(f.prop, armoryFilterState.rarities, f.key)) end)
        if not ok then
            _P("[INVRW ArmoryBind] FAILED to wire " .. f.cmd .. ": " .. tostring(err))
        else
            _P("[INVRW ArmoryBind] Wired " .. f.cmd .. " OK")
        end
    end

    -- Wire sort commands
    pcall(function() freshVM.SortByNameCommand:SetHandler(MakeArmorySortHandler("Name")) end)
    pcall(function() freshVM.SortByValueCommand:SetHandler(MakeArmorySortHandler("Value")) end)
    pcall(function() freshVM.SortByWeightCommand:SetHandler(MakeArmorySortHandler("Weight")) end)
    pcall(function() freshVM.SortByRarityCommand:SetHandler(MakeArmorySortHandler("Rarity")) end)

    -- Wire damage dice toggle commands
    local diceFilters = {
        {cmd="ToggleDice_1d4",  prop="FilterDice_1d4",  key="1d4"},
        {cmd="ToggleDice_1d6",  prop="FilterDice_1d6",  key="1d6"},
        {cmd="ToggleDice_1d8",  prop="FilterDice_1d8",  key="1d8"},
        {cmd="ToggleDice_1d10", prop="FilterDice_1d10", key="1d10"},
        {cmd="ToggleDice_1d12", prop="FilterDice_1d12", key="1d12"},
        {cmd="ToggleDice_2d6",  prop="FilterDice_2d6",  key="2d6"},
    }
    for _, f in ipairs(diceFilters) do
        pcall(function() freshVM[f.cmd]:SetHandler(MakeArmoryToggleHandler(f.prop, armoryFilterState.damageDice, f.key)) end)
    end

    -- Wire damage type toggle commands
    local dmgTypeFilters = {
        {cmd="ToggleDmgType_Slashing",    prop="FilterDmgType_Slashing",    key="Slashing"},
        {cmd="ToggleDmgType_Piercing",    prop="FilterDmgType_Piercing",    key="Piercing"},
        {cmd="ToggleDmgType_Bludgeoning", prop="FilterDmgType_Bludgeoning", key="Bludgeoning"},
        {cmd="ToggleDmgType_Fire",        prop="FilterDmgType_Fire",        key="Fire"},
        {cmd="ToggleDmgType_Cold",        prop="FilterDmgType_Cold",        key="Cold"},
        {cmd="ToggleDmgType_Lightning",   prop="FilterDmgType_Lightning",   key="Lightning"},
        {cmd="ToggleDmgType_Thunder",     prop="FilterDmgType_Thunder",     key="Thunder"},
        {cmd="ToggleDmgType_Poison",      prop="FilterDmgType_Poison",      key="Poison"},
        {cmd="ToggleDmgType_Acid",        prop="FilterDmgType_Acid",        key="Acid"},
        {cmd="ToggleDmgType_Necrotic",    prop="FilterDmgType_Necrotic",    key="Necrotic"},
        {cmd="ToggleDmgType_Radiant",     prop="FilterDmgType_Radiant",     key="Radiant"},
        {cmd="ToggleDmgType_Force",       prop="FilterDmgType_Force",       key="Force"},
        {cmd="ToggleDmgType_Psychic",     prop="FilterDmgType_Psychic",     key="Psychic"},
    }
    for _, f in ipairs(dmgTypeFilters) do
        pcall(function() freshVM[f.cmd]:SetHandler(MakeArmoryToggleHandler(f.prop, armoryFilterState.damageTypes, f.key)) end)
    end

    -- Wire AC range toggle commands
    local acFilters = {
        {cmd="ToggleAC_10to12", prop="FilterAC_10to12", key="10-12"},
        {cmd="ToggleAC_13to15", prop="FilterAC_13to15", key="13-15"},
        {cmd="ToggleAC_16plus", prop="FilterAC_16plus", key="16+"},
    }
    for _, f in ipairs(acFilters) do
        pcall(function() freshVM[f.cmd]:SetHandler(MakeArmoryToggleHandler(f.prop, armoryFilterState.acRanges, f.key)) end)
    end

    -- Wire EquipSelectedCommand
    pcall(function()
        freshVM.EquipSelectedCommand:SetHandler(function()
            -- Block rapid equip clicks to prevent crashes
            if _equipBusy then
                _P("[BG3InventoryRework] Armory equip: busy, ignoring click")
                return
            end

            local idx = nil
            pcall(function()
                local vm = GetVM()
                if vm then idx = vm.SelectedIndex end
            end)
            if idx == nil or idx < 0 then
                _P("[BG3InventoryRework] Armory equip: no item selected")
                return
            end

            local info = _slotMap[idx + 1]  -- 0-based → 1-based
            if not info or not info.uuid then
                _P("[BG3InventoryRework] Armory equip: no UUID for index " .. tostring(idx))
                return
            end

            local _, charUUID = getSelectedCharInfo()
            if not charUUID then
                _P("[BG3InventoryRework] Armory equip: no selected character")
                return
            end

            _equipBusy = true
            _P("[BG3InventoryRework] Armory equip: " .. (info.name or "?") .. " on char")
            Ext.Net.PostMessageToServer("InvRework_EquipItem",
                Ext.Json.Stringify({ itemUUID = info.uuid, targetCharUUID = charUUID }))

            -- Schedule delayed refresh to catch equipment changes, then unlock
            pcall(function()
                Ext.Timer.WaitFor(800, function()
                    Mods.BG3InventoryRework.RequestRefresh()
                    _equipBusy = false
                end)
            end)
        end)
    end)

    -- Initial property values
    freshVM.PanelVisible = false
    freshVM.StatusText = "Select a slot to browse items"
    freshVM.CharacterName = ""
    freshVM.ActiveSlotLabel = "Helmet"
    freshVM.SelectedIndex = -1
    freshVM.EquippedSlotIndex = -1
    freshVM.FilterPanelVisible = false
    freshVM.ActiveFilterCount = ""
    freshVM.SlotActive_All = "False"

    -- Filter section visibility defaults (Helmet = Armor category)
    freshVM.FilterSection_DamageDice = "False"
    freshVM.FilterSection_DamageType = "False"
    freshVM.FilterSection_AC = "True"

    -- Initialize all filter props to "False"
    local allFilterProps = {
        "FilterRarity_Common", "FilterRarity_Uncommon", "FilterRarity_Rare",
        "FilterRarity_VeryRare", "FilterRarity_Legendary",
        "FilterDice_1d4", "FilterDice_1d6", "FilterDice_1d8",
        "FilterDice_1d10", "FilterDice_1d12", "FilterDice_2d6",
        "FilterDmgType_Slashing", "FilterDmgType_Piercing", "FilterDmgType_Bludgeoning",
        "FilterDmgType_Fire", "FilterDmgType_Cold", "FilterDmgType_Lightning",
        "FilterDmgType_Thunder", "FilterDmgType_Poison", "FilterDmgType_Acid",
        "FilterDmgType_Necrotic", "FilterDmgType_Radiant", "FilterDmgType_Force",
        "FilterDmgType_Psychic",
        "FilterAC_10to12", "FilterAC_13to15", "FilterAC_16plus",
        "SortState_Name", "SortState_Value", "SortState_Weight", "SortState_Rarity",
    }
    for _, prop in ipairs(allFilterProps) do
        pcall(function() freshVM[prop] = "False" end)
    end
    -- Sort state starts as empty string, not "False"
    pcall(function() freshVM.SortState_Name = "" end)
    pcall(function() freshVM.SortState_Value = "" end)
    pcall(function() freshVM.SortState_Weight = "" end)
    pcall(function() freshVM.SortState_Rarity = "" end)

    -- Set default slot active state
    for _, slot in ipairs(EquipmentSlots) do
        pcall(function()
            freshVM["SlotActive_" .. slot.vmSuffix] = slot.vmSuffix == "Helmet" and "True" or "False"
        end)
    end

    -- Set as DataContext
    local setOk, setErr = pcall(function()
        widget.DataContext = freshVM
    end)

    if setOk then
        isBound = true
        pcall(function() widget.Visibility = "Collapsed" end)
        local vm = GetVM()
        if vm then
            vm.StatusText = "Ready — select a slot"
            _P("[INVRW ArmoryBind] SUCCESS! DataContext set and re-acquired OK")
        else
            _P("[INVRW ArmoryBind] SUCCESS! DataContext set but re-acquire failed")
        end

        -- Start character-change polling (checks every 1s while panel is visible)
        local function pollCharChange()
            pcall(function()
                if not isBound then return end
                local curVM = GetVM()
                if not curVM or not curVM.PanelVisible then return end

                local newCharPtr = nil
                pcall(function()
                    local root = Ext.UI.GetRoot()
                    if not root then return end
                    local cr = root:Find("ContentRoot")
                    if not cr then return end
                    local children = cr.Children
                    local overlay = nil
                    for ci = 0, 30 do
                        pcall(function()
                            local c = children[ci]
                            if c and c.Name == "Overlay" then overlay = c end
                        end)
                    end
                    if overlay and overlay.DataContext and overlay.DataContext.CurrentPlayer then
                        newCharPtr = tostring(overlay.DataContext.CurrentPlayer.SelectedCharacter)
                    end
                end)

                if newCharPtr and _lastCharPtr and newCharPtr ~= _lastCharPtr then
                    _lastCharPtr = newCharPtr
                    -- Delay refresh to let Noesis VM settle after character switch
                    _P("[BG3InventoryRework] Armory: character changed, refreshing in 300ms")
                    pcall(function()
                        Ext.Timer.WaitFor(300, function()
                            pcall(ArmoryPanelVM.Refresh)
                        end)
                    end)
                elseif newCharPtr and not _lastCharPtr then
                    _lastCharPtr = newCharPtr
                end
            end)
            pcall(function() Ext.Timer.WaitFor(1000, pollCharChange) end)
        end
        pcall(function() Ext.Timer.WaitFor(2000, pollCharChange) end)

        return
    end

    _P("[INVRW ArmoryBind] DataContext set FAILED: " .. tostring(setErr))
end

--- Initialize the ArmoryPanelVM.
function ArmoryPanelVM.Init()
    RegisterTypes()
    _P("[BG3InventoryRework] ArmoryPanelVM initialized, waiting for widget...")

    local delays = {8000, 10000, 12000, 15000, 20000, 30000}
    for _, delay in ipairs(delays) do
        pcall(function()
            Ext.Timer.WaitFor(delay, function()
                if not isBound then
                    pcall(ArmoryPanelVM.TryBind)
                end
            end)
        end)
    end
end

--- Toggle panel visibility.
function ArmoryPanelVM.Toggle()
    local vm = GetVM()
    if not vm then
        _P("[BG3InventoryRework] Armory Toggle: cannot get VM")
        return
    end
    vm.PanelVisible = not vm.PanelVisible
    _P("[BG3InventoryRework] Armory PanelVisible=" .. tostring(vm.PanelVisible))

    local widget = FindWidget()
    if widget then
        pcall(function()
            widget.Visibility = vm.PanelVisible and "Visible" or "Collapsed"
        end)
    end

    if vm.PanelVisible then
        -- Update char pointer for change detection
        pcall(function()
            local root = Ext.UI.GetRoot()
            if not root then return end
            local cr = root:Find("ContentRoot")
            if not cr then return end
            local children = cr.Children
            local overlay = nil
            for ci = 0, 30 do
                pcall(function()
                    local c = children[ci]
                    if c and c.Name == "Overlay" then overlay = c end
                end)
            end
            if overlay and overlay.DataContext and overlay.DataContext.CurrentPlayer then
                _lastCharPtr = tostring(overlay.DataContext.CurrentPlayer.SelectedCharacter)
            end
        end)

        local DataStore = Mods.BG3InventoryRework.DataStore
        if DataStore and DataStore.GetItemCount() > 0 then
            ArmoryPanelVM.Refresh()
        else
            vm.StatusText = "Loading inventory..."
        end
        Mods.BG3InventoryRework.RequestRefresh()
    end
end

--- Called when fresh data arrives from server.
function ArmoryPanelVM.OnDataUpdated()
    if not isBound then return end
    ArmoryPanelVM.Refresh()
end

-- F11 keybind (overrides SE console — our panel takes priority)
Ext.Events.KeyInput:Subscribe(function(e)
    -- Don't intercept if InventoryPanelVM search typing is active
    if Mods.BG3InventoryRework.InventoryPanelVM
       and Mods.BG3InventoryRework.InventoryPanelVM._searchTyping then
        return
    end
    if tostring(e.Key) == "F11" and tostring(e.Event) == "KeyDown" then
        if not isBound then
            pcall(ArmoryPanelVM.TryBind)
        end
        ArmoryPanelVM.Toggle()
    end
end)

-- Export
Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
Mods.BG3InventoryRework.ArmoryPanelVM = ArmoryPanelVM

return ArmoryPanelVM
