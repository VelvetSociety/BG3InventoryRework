--- ImGui-based Unified Inventory panel (retained-mode API).
-- @module InventoryUI

local DataStore = Mods.BG3InventoryRework.DataStore
local FilterEngine = Mods.BG3InventoryRework.FilterEngine

local InventoryUI = {}

-- UI references
local window = nil
local itemTable = nil
local searchInput = nil
local typeCombo = nil
local rarityCombo = nil
local ownerTabBar = nil
local statusText = nil

-- State
local searchText = ""
local selectedType = nil
local selectedRarity = nil
local selectedOwner = nil
local sortBy = "Name"
local sortAscending = true

--- Rarity colors (RGBA 0-255 for ImGui).
local RarityColors = {
    Common    = {200, 200, 200, 255},
    Uncommon  = {25, 200, 25, 255},
    Rare      = {50, 100, 255, 255},
    VeryRare  = {150, 50, 230, 255},
    Legendary = {255, 165, 0, 255},
}

--- Build the UI (called once).
function InventoryUI.Build()
    window = Ext.IMGUI.NewWindow("Unified Inventory")
    window.Closeable = true
    window.Open = false

    window.OnClose = function()
        window.Open = false
    end

    -- Search bar
    searchInput = window:AddInputText("Search")
    searchInput.Hint = "Type to search items..."
    searchInput.OnChange = function(el)
        searchText = el.Text
        InventoryUI.RefreshTable()
    end

    -- Filter row
    local filterGroup = window:AddGroup("Filters")

    typeCombo = filterGroup:AddCombo("Type")
    typeCombo.Options = {"All Types"}
    typeCombo.SelectedIndex = 0
    typeCombo.OnChange = function(el)
        if el.SelectedIndex == 0 then
            selectedType = nil
        else
            selectedType = el.Options[el.SelectedIndex + 1]
        end
        InventoryUI.RefreshTable()
    end

    rarityCombo = filterGroup:AddCombo("Rarity")
    rarityCombo.SameLine = true
    rarityCombo.Options = {"All Rarities"}
    rarityCombo.SelectedIndex = 0
    rarityCombo.OnChange = function(el)
        if el.SelectedIndex == 0 then
            selectedRarity = nil
        else
            selectedRarity = el.Options[el.SelectedIndex + 1]
        end
        InventoryUI.RefreshTable()
    end

    -- Sort buttons
    local sortGroup = window:AddGroup("SortGroup")
    sortGroup:AddText("Sort by:")
    for _, field in ipairs({"Name", "Value", "Weight", "Rarity", "Type"}) do
        local btn = sortGroup:AddButton(field)
        btn.SameLine = true
        btn.OnClick = function()
            if sortBy == field then
                sortAscending = not sortAscending
            else
                sortBy = field
                sortAscending = true
            end
            InventoryUI.RefreshTable()
        end
    end

    window:AddSeparator()

    -- Status line
    statusText = window:AddText("No items loaded")

    window:AddSeparator()

    -- Item table placeholder — will be rebuilt on refresh
    itemTable = window:AddGroup("ItemTableGroup")
end

--- Rebuild the item table with current filters.
function InventoryUI.RefreshTable()
    if not itemTable then return end

    -- Clear old table contents
    itemTable:Destroy()
    itemTable = window:AddGroup("ItemTableGroup")

    local allItems = DataStore.GetAllItems()

    -- Update filter dropdowns
    local types = DataStore.GetTypes()
    local typeOpts = {"All Types"}
    for _, t in ipairs(types) do typeOpts[#typeOpts + 1] = t end
    typeCombo.Options = typeOpts

    local rarities = DataStore.GetRarities()
    local rarOpts = {"All Rarities"}
    for _, r in ipairs(rarities) do rarOpts[#rarOpts + 1] = r end
    rarityCombo.Options = rarOpts

    -- Apply filters
    local filters = {
        type = selectedType,
        rarity = selectedRarity,
        owner = selectedOwner,
        search = (searchText ~= "" and searchText or nil),
    }
    local displayItems = FilterEngine.FilterAndSort(allItems, filters, sortBy, sortAscending)

    -- Update status
    if statusText then
        statusText.Label = string.format("Showing %d / %d items", #displayItems, #allItems)
    end

    -- Build table
    local tbl = itemTable:AddTable("Items", 6)

    tbl:AddColumn("Name")
    tbl:AddColumn("Type")
    tbl:AddColumn("Rarity")
    tbl:AddColumn("Value")
    tbl:AddColumn("Weight")
    tbl:AddColumn("Owner")

    -- Limit to 200 items to avoid performance issues
    local limit = math.min(#displayItems, 200)
    for i = 1, limit do
        local item = displayItems[i]
        local row = tbl:AddRow()

        local nameCell = row:AddCell()
        nameCell:AddText(item.Name or "???")

        local typeCell = row:AddCell()
        typeCell:AddText(item.Type or "")

        local rarCell = row:AddCell()
        rarCell:AddText(item.Rarity or "")

        local valCell = row:AddCell()
        valCell:AddText(tostring(item.Value or 0))

        local weightCell = row:AddCell()
        weightCell:AddText(string.format("%.1f", item.Weight or 0))

        local ownerCell = row:AddCell()
        ownerCell:AddText(item.OwnerName or "")
    end

    if #displayItems > 200 then
        itemTable:AddText(string.format("... and %d more items", #displayItems - 200))
    end
end

--- Toggle the inventory window.
function InventoryUI.Toggle()
    if not window then
        InventoryUI.Build()
    end
    window.Open = not window.Open
    if window.Open then
        Mods.BG3InventoryRework.RequestRefresh()
    end
end

-- Keybind toggle (F11)
Ext.Events.SessionLoaded:Subscribe(function()
    _P("[BG3InventoryRework] Press F11 to toggle Unified Inventory, F12 for Armory")
    Mods.BG3InventoryRework.RequestRefresh()
end)

Ext.Events.KeyInput:Subscribe(function(e)
    if e.Key == "F11" and e.Event == "KeyDown" then
        InventoryUI.Toggle()
    end
end)

-- Export
Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
Mods.BG3InventoryRework.InventoryUI = InventoryUI

return InventoryUI
