--- Minimal test to verify XAML ↔ Lua ViewModel bridge.
-- @module TestViewModel

local TestVM = {}

local vmInstance = nil
local isRegistered = false

--- Item ViewModel type for the collection.
local function RegisterTypes()
    if isRegistered then return end

    -- Register an item type for the collection
    Ext.UI.RegisterType("INVRW_TestItem", {
        Name = { Type = "String", Notify = true },
    })

    -- Register the main panel ViewModel
    Ext.UI.RegisterType("INVRW_TestPanelVM", {
        StatusText = { Type = "String", Notify = true },
        Items = { Type = "Collection" },
        RefreshCommand = { Type = "Command" },
    })

    isRegistered = true
    _P("[BG3InventoryRework] ViewModel types registered")
end

--- Create a test item for the collection.
local function CreateTestItem(name)
    local item = Ext.UI.Instantiate("INVRW_TestItem")
    item.Name = name
    return item
end

--- Initialize the ViewModel and try to bind it.
function TestVM.Init()
    RegisterTypes()

    vmInstance = Ext.UI.Instantiate("INVRW_TestPanelVM")
    vmInstance.StatusText = "ViewModel connected!"

    vmInstance.RefreshCommand:SetHandler(function()
        _P("[BG3InventoryRework] Refresh button clicked from XAML!")
        TestVM.PopulateTestData()
    end)

    TestVM.PopulateTestData()
    _P("[BG3InventoryRework] TestViewModel initialized — VM ready, " .. #vmInstance.Items .. " items")
end

--- Fill the Items collection with sample data.
function TestVM.PopulateTestData()
    if not vmInstance then return end

    local items = vmInstance.Items

    -- Clear by setting length to 0 (remove items from end)
    local len = #items
    for i = len, 1, -1 do
        items[i] = nil
    end

    -- Add test items using numeric index
    local testNames = {
        "Sword of Justice",
        "Shield of Faith",
        "Healing Potion x3",
        "Scroll of Fireball",
        "Ring of Protection",
    }

    for i, name in ipairs(testNames) do
        local item = Ext.UI.Instantiate("INVRW_TestItem")
        item.Name = name
        items[i] = item
    end

    vmInstance.StatusText = "Loaded " .. #testNames .. " items"
    _P("[BG3InventoryRework] Populated " .. #items .. " test items")
end

--- Get the ViewModel instance (for binding to XAML panel).
function TestVM.GetVM()
    return vmInstance
end

--- Try to find and bind to the XAML panel.
function TestVM.TryBind()
    if not vmInstance then
        TestVM.Init()
    end

    local ok, err = pcall(function()
        local root = Ext.UI.GetRoot()
        if root then
            _P("[BG3InventoryRework] UI Root found: " .. tostring(root))
            -- Log available children for debugging
            local contentRoot = root:Find("ContentRoot")
            if contentRoot then
                _P("[BG3InventoryRework] ContentRoot found")
            else
                _P("[BG3InventoryRework] ContentRoot not found — listing root children")
            end
        else
            _P("[BG3InventoryRework] UI Root is nil")
        end
    end)

    if not ok then
        _P("[BG3InventoryRework] TryBind error: " .. tostring(err))
    end
end

-- Export
Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
Mods.BG3InventoryRework.TestVM = TestVM

return TestVM
