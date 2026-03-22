--- Client-side inventory cache with indexes for fast lookup.
-- @module DataStore

local DataStore = {}

-- Master item list keyed by UUID
local items = {}
-- Index tables for fast filtering
local byOwner = {}   -- ownerUUID -> {itemUUID, ...}
local byType = {}    -- itemType -> {itemUUID, ...}
local byRarity = {}  -- rarity -> {itemUUID, ...}

--- Clear all data and indexes.
function DataStore.Clear()
    items = {}
    byOwner = {}
    byType = {}
    byRarity = {}
end

--- Add or update a single item in the store.
-- @param item table with fields: UUID, Name, Type, Rarity, Weight, Value, OwnerUUID, OwnerName, Icon, StackSize, Slot, Enchantments
function DataStore.SetItem(item)
    if not item or not item.UUID then return end

    -- Remove from old indexes if updating
    local old = items[item.UUID]
    if old then
        DataStore._removeFromIndex(byOwner, old.OwnerUUID, old.UUID)
        DataStore._removeFromIndex(byType, old.Type, old.UUID)
        DataStore._removeFromIndex(byRarity, old.Rarity, old.UUID)
    end

    items[item.UUID] = item

    -- Add to indexes
    DataStore._addToIndex(byOwner, item.OwnerUUID, item.UUID)
    DataStore._addToIndex(byType, item.Type, item.UUID)
    DataStore._addToIndex(byRarity, item.Rarity, item.UUID)
end

--- Remove an item by UUID.
function DataStore.RemoveItem(uuid)
    local item = items[uuid]
    if not item then return end

    DataStore._removeFromIndex(byOwner, item.OwnerUUID, uuid)
    DataStore._removeFromIndex(byType, item.Type, uuid)
    DataStore._removeFromIndex(byRarity, item.Rarity, uuid)

    items[uuid] = nil
end

--- Load a full inventory snapshot (replaces all data).
-- @param itemList array of item tables
function DataStore.LoadFullInventory(itemList)
    DataStore.Clear()
    for _, item in ipairs(itemList) do
        DataStore.SetItem(item)
    end
end

--- Get a single item by UUID.
function DataStore.GetItem(uuid)
    return items[uuid]
end

--- Get all items as an array.
function DataStore.GetAllItems()
    local result = {}
    for _, item in pairs(items) do
        result[#result + 1] = item
    end
    return result
end

--- Get item UUIDs by owner.
function DataStore.GetItemsByOwner(ownerUUID)
    return byOwner[ownerUUID] or {}
end

--- Get item UUIDs by type.
function DataStore.GetItemsByType(itemType)
    return byType[itemType] or {}
end

--- Get item UUIDs by rarity.
function DataStore.GetItemsByRarity(rarity)
    return byRarity[rarity] or {}
end

--- Get all unique owner UUIDs.
function DataStore.GetOwners()
    local owners = {}
    for ownerUUID, _ in pairs(byOwner) do
        owners[#owners + 1] = ownerUUID
    end
    return owners
end

--- Get all unique item types.
function DataStore.GetTypes()
    local types = {}
    for t, _ in pairs(byType) do
        types[#types + 1] = t
    end
    return types
end

--- Get all unique rarities.
function DataStore.GetRarities()
    local rarities = {}
    for r, _ in pairs(byRarity) do
        rarities[#rarities + 1] = r
    end
    return rarities
end

--- Get total item count.
function DataStore.GetItemCount()
    local count = 0
    for _ in pairs(items) do
        count = count + 1
    end
    return count
end

--- Retrieve multiple items by UUID list, returning item tables.
function DataStore.GetItemsByUUIDs(uuids)
    local result = {}
    for _, uuid in ipairs(uuids) do
        local item = items[uuid]
        if item then
            result[#result + 1] = item
        end
    end
    return result
end

-- Internal: add uuid to an index bucket
function DataStore._addToIndex(index, key, uuid)
    if not key then return end
    if not index[key] then
        index[key] = {}
    end
    index[key][#index[key] + 1] = uuid
end

-- Internal: remove uuid from an index bucket
function DataStore._removeFromIndex(index, key, uuid)
    if not key or not index[key] then return end
    local bucket = index[key]
    for i = #bucket, 1, -1 do
        if bucket[i] == uuid then
            table.remove(bucket, i)
            break
        end
    end
    if #bucket == 0 then
        index[key] = nil
    end
end

-- Export for BG3SE (Mods.BG3InventoryRework.DataStore) and for testing
if Ext then
    Mods = Mods or {}
    Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
    Mods.BG3InventoryRework.DataStore = DataStore
end

return DataStore
