--- ImGui-based Armory panel for equipment management (retained-mode API).
-- @module ArmoryUI

local DataStore = Mods.BG3InventoryRework.DataStore
local FilterEngine = Mods.BG3InventoryRework.FilterEngine

local ArmoryUI = {}

-- UI references
local window = nil
local charGroup = nil
local slotsGroup = nil
local itemsGroup = nil
local statusText = nil

-- State
local selectedCharUUID = nil
local selectedSlot = nil
local searchText = ""

--- Equipment slot definitions.
local EquipmentSlots = {
    { id = "Helmet",         label = "Helmet" },
    { id = "Breast",         label = "Armor" },
    { id = "Cloak",          label = "Cloak" },
    { id = "MeleeMainHand",  label = "Main Hand" },
    { id = "MeleeOffHand",   label = "Off Hand" },
    { id = "RangedMainHand", label = "Ranged" },
    { id = "Gloves",         label = "Gloves" },
    { id = "Boots",          label = "Boots" },
    { id = "Amulet",         label = "Amulet" },
    { id = "Ring",           label = "Ring 1" },
    { id = "Ring2",          label = "Ring 2" },
}

--- Rarity colors.
local RarityColors = {
    Common    = {200, 200, 200, 255},
    Uncommon  = {25, 200, 25, 255},
    Rare      = {50, 100, 255, 255},
    VeryRare  = {150, 50, 230, 255},
    Legendary = {255, 165, 0, 255},
}

--- Build the UI (called once).
function ArmoryUI.Build()
    window = Ext.IMGUI.NewWindow("Armory")
    window.Closeable = true
    window.Open = false

    window.OnClose = function()
        window.Open = false
    end

    -- Character selector
    charGroup = window:AddGroup("CharacterSelector")
    charGroup:AddText("Select Character:")

    window:AddSeparator()

    -- Slots panel
    slotsGroup = window:AddGroup("EquipmentSlots")
    slotsGroup:AddText("Select a character first")

    window:AddSeparator()

    -- Search for equippable items
    local search = window:AddInputText("Search Equipment")
    search.Hint = "Filter equippable items..."
    search.OnChange = function(el)
        searchText = el.Text
        ArmoryUI.RefreshItems()
    end

    -- Equippable items panel
    statusText = window:AddText("")
    itemsGroup = window:AddGroup("EquippableItems")
end

--- Refresh the character buttons.
function ArmoryUI.RefreshCharacters()
    if not charGroup then return end

    charGroup:Destroy()
    charGroup = window:AddGroup("CharacterSelector")
    charGroup:AddText("Select Character:")

    local owners = DataStore.GetOwners()
    for _, ownerUUID in ipairs(owners) do
        local ownerItems = DataStore.GetItemsByUUIDs(DataStore.GetItemsByOwner(ownerUUID))
        local name = (#ownerItems > 0 and ownerItems[1].OwnerName) or ownerUUID:sub(1, 8)

        local btn = charGroup:AddButton(name)
        btn.SameLine = true
        btn.OnClick = function()
            selectedCharUUID = ownerUUID
            selectedSlot = nil
            ArmoryUI.RefreshSlots()
            ArmoryUI.RefreshItems()
        end
    end

    -- Auto-select first if none selected
    if not selectedCharUUID and #owners > 0 then
        selectedCharUUID = owners[1]
        ArmoryUI.RefreshSlots()
    end
end

--- Refresh the equipment slots for selected character.
function ArmoryUI.RefreshSlots()
    if not slotsGroup then return end

    slotsGroup:Destroy()
    slotsGroup = window:AddGroup("EquipmentSlots")

    if not selectedCharUUID then
        slotsGroup:AddText("No character selected")
        return
    end

    slotsGroup:AddText("Equipment Slots:")

    for _, slot in ipairs(EquipmentSlots) do
        local equipped = ArmoryUI._findEquippedItem(selectedCharUUID, slot.id)
        local label
        if equipped then
            label = slot.label .. ": " .. equipped.Name
        else
            label = slot.label .. ": (empty)"
        end

        local btn = slotsGroup:AddButton(label)
        btn.OnClick = function()
            selectedSlot = slot.id
            ArmoryUI.RefreshItems()
        end
    end
end

--- Refresh the equippable items list.
function ArmoryUI.RefreshItems()
    if not itemsGroup then return end

    itemsGroup:Destroy()
    itemsGroup = window:AddGroup("EquippableItems")

    if not selectedSlot then
        statusText.Label = "Click a slot to see equippable items"
        return
    end

    local allItems = DataStore.GetAllItems()
    local filters = {
        slot = selectedSlot,
        search = (searchText ~= "" and searchText or nil),
    }
    local matching = FilterEngine.FilterAndSort(allItems, filters, "Rarity", false)

    statusText.Label = string.format("Items for %s: %d found", selectedSlot, #matching)

    local limit = math.min(#matching, 100)
    for i = 1, limit do
        local item = matching[i]
        local row = itemsGroup:AddGroup("item_" .. item.UUID)
        row:AddText(item.Name or "???")

        local ownerText = row:AddText(" (" .. (item.OwnerName or "?") .. ")")
        ownerText.SameLine = true

        local equipBtn = row:AddButton("Equip##" .. item.UUID)
        equipBtn.SameLine = true
        equipBtn.OnClick = function()
            Mods.BG3InventoryRework.RequestEquipItem(item.UUID, selectedCharUUID)
        end
    end

    if #matching == 0 then
        itemsGroup:AddText("No equippable items for this slot.")
    end
end

--- Find equipped item for a character + slot.
function ArmoryUI._findEquippedItem(charUUID, slotId)
    local uuids = DataStore.GetItemsByOwner(charUUID)
    for _, uuid in ipairs(uuids) do
        local item = DataStore.GetItem(uuid)
        if item and item.Slot == slotId and item.Equipped then
            return item
        end
    end
    return nil
end

--- Toggle the armory window.
function ArmoryUI.Toggle()
    if not window then
        ArmoryUI.Build()
    end
    window.Open = not window.Open
    if window.Open then
        Mods.BG3InventoryRework.RequestRefresh()
    end
end

--- Called when inventory data is updated.
function ArmoryUI.OnDataUpdated()
    if window and window.Open then
        ArmoryUI.RefreshCharacters()
        ArmoryUI.RefreshSlots()
        ArmoryUI.RefreshItems()
    end
end

-- Keybind toggle (F12)
Ext.Events.KeyInput:Subscribe(function(e)
    if e.Key == "F12" and e.Event == "KeyDown" then
        ArmoryUI.Toggle()
    end
end)

-- Export
Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
Mods.BG3InventoryRework.ArmoryUI = ArmoryUI

return ArmoryUI
