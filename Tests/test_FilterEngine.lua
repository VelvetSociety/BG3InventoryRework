--- Tests for FilterEngine module.

-- Shim: no BG3SE environment
Ext = nil

package.path = package.path .. ";../BG3InventoryRework/Mods/BG3InventoryRework/ScriptExtender/Lua/?.lua"

local FilterEngine = require("Client.FilterEngine")
local MockData = require("MockData")
local T = require("TestRunner")

local items = MockData.GetPartyInventory()

T.describe("FilterEngine.Filter — by type", function()
    T.it("filters weapons only", function()
        local result = FilterEngine.Filter(items, { type = "Weapon" })
        for _, item in ipairs(result) do
            T.assertEqual(item.Type, "Weapon", item.Name .. " is a weapon")
        end
        T.assertTrue(#result >= 3, "at least 3 weapons")
    end)

    T.it("filters consumables only", function()
        local result = FilterEngine.Filter(items, { type = "Consumable" })
        for _, item in ipairs(result) do
            T.assertEqual(item.Type, "Consumable", item.Name .. " is consumable")
        end
    end)
end)

T.describe("FilterEngine.Filter — by rarity", function()
    T.it("filters Rare items", function()
        local result = FilterEngine.Filter(items, { rarity = "Rare" })
        for _, item in ipairs(result) do
            T.assertEqual(item.Rarity, "Rare", item.Name .. " is Rare")
        end
    end)

    T.it("filters Legendary items", function()
        local result = FilterEngine.Filter(items, { rarity = "Legendary" })
        T.assertEqual(#result, 1, "exactly 1 Legendary")
        T.assertEqual(result[1].Name, "Knife of the Undermountain King")
    end)
end)

T.describe("FilterEngine.Filter — by owner", function()
    T.it("filters by Gale's UUID", function()
        local result = FilterEngine.Filter(items, { owner = "char-gale" })
        for _, item in ipairs(result) do
            T.assertEqual(item.OwnerUUID, "char-gale", item.Name .. " belongs to Gale")
        end
        T.assertTrue(#result >= 3, "Gale has at least 3 items")
    end)
end)

T.describe("FilterEngine.Filter — by search text", function()
    T.it("finds items by partial name (case-insensitive)", function()
        local result = FilterEngine.Filter(items, { search = "potion" })
        T.assertTrue(#result >= 2, "at least 2 potions found")
        for _, item in ipairs(result) do
            T.assertTrue(item.Name:lower():find("potion"), item.Name .. " contains 'potion'")
        end
    end)

    T.it("search for 'knife' returns 1 result", function()
        local result = FilterEngine.Filter(items, { search = "knife" })
        T.assertEqual(#result, 1)
    end)

    T.it("search for nonexistent returns empty", function()
        local result = FilterEngine.Filter(items, { search = "xyznonexistent" })
        T.assertEqual(#result, 0)
    end)
end)

T.describe("FilterEngine.Filter — by slot", function()
    T.it("filters main hand weapons", function()
        local result = FilterEngine.Filter(items, { slot = "MeleeMainHand" })
        T.assertTrue(#result >= 3, "at least 3 main hand items")
    end)
end)

T.describe("FilterEngine.Filter — combined filters", function()
    T.it("type=Weapon + owner=Astarion", function()
        local result = FilterEngine.Filter(items, { type = "Weapon", owner = "char-astarion" })
        T.assertEqual(#result, 2, "Astarion has 2 weapons")
    end)

    T.it("type=Consumable + search=heal", function()
        local result = FilterEngine.Filter(items, { type = "Consumable", search = "heal" })
        T.assertTrue(#result >= 2, "at least 2 healing consumables")
    end)

    T.it("no filters returns all items", function()
        local result = FilterEngine.Filter(items, {})
        T.assertEqual(#result, #items)
    end)

    T.it("nil filters returns all items", function()
        local result = FilterEngine.Filter(items, nil)
        T.assertEqual(#result, #items)
    end)
end)

T.describe("FilterEngine.Sort — by Name", function()
    T.it("sorts alphabetically ascending", function()
        local copy = {}
        for _, i in ipairs(items) do copy[#copy + 1] = i end
        FilterEngine.Sort(copy, "Name", true)
        for i = 2, #copy do
            T.assertTrue(copy[i-1].Name:lower() <= copy[i].Name:lower(),
                copy[i-1].Name .. " <= " .. copy[i].Name)
        end
    end)

    T.it("sorts alphabetically descending", function()
        local copy = {}
        for _, i in ipairs(items) do copy[#copy + 1] = i end
        FilterEngine.Sort(copy, "Name", false)
        for i = 2, #copy do
            T.assertTrue(copy[i-1].Name:lower() >= copy[i].Name:lower(),
                copy[i-1].Name .. " >= " .. copy[i].Name)
        end
    end)
end)

T.describe("FilterEngine.Sort — by Value", function()
    T.it("sorts by value ascending", function()
        local copy = {}
        for _, i in ipairs(items) do copy[#copy + 1] = i end
        FilterEngine.Sort(copy, "Value", true)
        for i = 2, #copy do
            T.assertTrue(copy[i-1].Value <= copy[i].Value,
                tostring(copy[i-1].Value) .. " <= " .. tostring(copy[i].Value))
        end
    end)
end)

T.describe("FilterEngine.Sort — by Rarity", function()
    T.it("sorts by rarity descending (rarest first)", function()
        local copy = {}
        for _, i in ipairs(items) do copy[#copy + 1] = i end
        FilterEngine.Sort(copy, "Rarity", false)
        T.assertEqual(copy[1].Rarity, "Legendary", "first item is Legendary")
        -- Last should be Common
        T.assertEqual(copy[#copy].Rarity, "Common", "last item is Common")
    end)
end)

T.describe("FilterEngine.FilterAndSort", function()
    T.it("filters weapons and sorts by value descending", function()
        local result = FilterEngine.FilterAndSort(items, { type = "Weapon" }, "Value", false)
        T.assertTrue(#result >= 3)
        -- Most expensive weapon first
        T.assertEqual(result[1].Name, "Knife of the Undermountain King")
        -- All should be weapons
        for _, item in ipairs(result) do
            T.assertEqual(item.Type, "Weapon")
        end
    end)
end)

local allPassed = T.summary()
os.exit(allPassed and 0 or 1)
