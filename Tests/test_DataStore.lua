--- Tests for DataStore module.

-- Shim: no BG3SE environment
Ext = nil

package.path = package.path .. ";../BG3InventoryRework/Mods/BG3InventoryRework/ScriptExtender/Lua/?.lua"

local DataStore = require("Client.DataStore")
local MockData = require("MockData")
local T = require("TestRunner")

T.describe("DataStore.LoadFullInventory", function()
    T.it("loads all mock items", function()
        DataStore.Clear()
        local items = MockData.GetPartyInventory()
        DataStore.LoadFullInventory(items)
        T.assertEqual(DataStore.GetItemCount(), #items, "item count")
    end)

    T.it("replaces previous data on reload", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local count1 = DataStore.GetItemCount()
        -- Load again — should not double
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        T.assertEqual(DataStore.GetItemCount(), count1, "count after reload")
    end)
end)

T.describe("DataStore.GetItem", function()
    T.it("retrieves an item by UUID", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local item = DataStore.GetItem("item-001")
        T.assertTrue(item ~= nil, "item exists")
        T.assertEqual(item.Name, "Spear of Night", "item name")
    end)

    T.it("returns nil for unknown UUID", function()
        T.assertEqual(DataStore.GetItem("nonexistent"), nil, "unknown UUID")
    end)
end)

T.describe("DataStore.SetItem / RemoveItem", function()
    T.it("adds a new item", function()
        DataStore.Clear()
        DataStore.SetItem({
            UUID = "test-new", Name = "Test Sword", Type = "Weapon",
            Rarity = "Common", OwnerUUID = "owner-1"
        })
        T.assertEqual(DataStore.GetItemCount(), 1)
        T.assertEqual(DataStore.GetItem("test-new").Name, "Test Sword")
    end)

    T.it("updates an existing item and re-indexes", function()
        DataStore.Clear()
        DataStore.SetItem({
            UUID = "test-upd", Name = "Old Name", Type = "Weapon",
            Rarity = "Common", OwnerUUID = "owner-1"
        })
        DataStore.SetItem({
            UUID = "test-upd", Name = "New Name", Type = "Armor",
            Rarity = "Rare", OwnerUUID = "owner-2"
        })
        T.assertEqual(DataStore.GetItemCount(), 1, "still 1 item")
        T.assertEqual(DataStore.GetItem("test-upd").Name, "New Name")
        T.assertTableLength(DataStore.GetItemsByType("Weapon"), 0, "old type removed")
        T.assertTableLength(DataStore.GetItemsByType("Armor"), 1, "new type indexed")
    end)

    T.it("removes an item and cleans indexes", function()
        DataStore.Clear()
        DataStore.SetItem({
            UUID = "test-rm", Name = "Throwaway", Type = "Misc",
            Rarity = "Common", OwnerUUID = "owner-1"
        })
        DataStore.RemoveItem("test-rm")
        T.assertEqual(DataStore.GetItemCount(), 0)
        T.assertEqual(DataStore.GetItem("test-rm"), nil)
        T.assertTableLength(DataStore.GetItemsByType("Misc"), 0)
    end)
end)

T.describe("DataStore indexes", function()
    T.it("indexes by owner", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local shItems = DataStore.GetItemsByOwner("char-shadowheart")
        T.assertTrue(#shItems > 0, "Shadowheart has items")
    end)

    T.it("indexes by type", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local weapons = DataStore.GetItemsByType("Weapon")
        T.assertTrue(#weapons >= 3, "at least 3 weapons")
    end)

    T.it("indexes by rarity", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local legendary = DataStore.GetItemsByRarity("Legendary")
        T.assertEqual(#legendary, 1, "exactly 1 legendary")
    end)

    T.it("lists all owners", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local owners = DataStore.GetOwners()
        T.assertEqual(#owners, 4, "4 party members")
    end)

    T.it("lists all types", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local types = DataStore.GetTypes()
        T.assertTrue(#types >= 4, "at least 4 item types")
    end)
end)

T.describe("DataStore.GetItemsByUUIDs", function()
    T.it("resolves UUIDs to items", function()
        DataStore.Clear()
        DataStore.LoadFullInventory(MockData.GetPartyInventory())
        local uuids = {"item-001", "item-010", "nonexistent"}
        local resolved = DataStore.GetItemsByUUIDs(uuids)
        T.assertEqual(#resolved, 2, "2 valid items resolved")
    end)
end)

local allPassed = T.summary()
os.exit(allPassed and 0 or 1)
