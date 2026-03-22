--- Filtering and sorting engine for inventory items (pure logic, no BG3 dependency).
-- @module FilterEngine

local FilterEngine = {}

--- Rarity sort order (higher = rarer).
FilterEngine.RarityOrder = {
    Common    = 1,
    Uncommon  = 2,
    Rare      = 3,
    VeryRare  = 4,
    Legendary = 5,
}

--- Filter a list of items based on criteria.
-- @param items array of item tables
-- @param filters table with optional fields:
--   type (string) — item type to include
--   rarity (string) — rarity to include
--   owner (string) — owner UUID to include
--   search (string) — substring match on item Name (case-insensitive)
--   slot (string) — equipment slot to include
-- @return filtered array of items
function FilterEngine.Filter(items, filters)
    if not filters then return items end

    local result = {}
    local searchLower = filters.search and filters.search:lower() or nil

    for _, item in ipairs(items) do
        local pass = true

        if filters.type and item.Type ~= filters.type then
            pass = false
        end

        if pass and filters.rarity and item.Rarity ~= filters.rarity then
            pass = false
        end

        if pass and filters.owner and item.OwnerUUID ~= filters.owner then
            pass = false
        end

        if pass and filters.slot and item.Slot ~= filters.slot then
            pass = false
        end

        if pass and searchLower then
            local nameLower = (item.Name or ""):lower()
            if not nameLower:find(searchLower, 1, true) then
                pass = false
            end
        end

        if pass then
            result[#result + 1] = item
        end
    end

    return result
end

--- Sort an array of items in place.
-- @param items array of item tables
-- @param sortBy string: "Name", "Value", "Weight", "Rarity", "Type"
-- @param ascending boolean (default true)
-- @return the same array, sorted
function FilterEngine.Sort(items, sortBy, ascending)
    if ascending == nil then ascending = true end

    local comparator

    if sortBy == "Rarity" then
        comparator = function(a, b)
            local ra = FilterEngine.RarityOrder[a.Rarity] or 0
            local rb = FilterEngine.RarityOrder[b.Rarity] or 0
            if ascending then
                return ra < rb
            else
                return ra > rb
            end
        end
    elseif sortBy == "Value" or sortBy == "Weight" then
        comparator = function(a, b)
            local va = a[sortBy] or 0
            local vb = b[sortBy] or 0
            if ascending then
                return va < vb
            else
                return va > vb
            end
        end
    else
        -- Default: sort by Name (or any string field)
        sortBy = sortBy or "Name"
        comparator = function(a, b)
            local va = (a[sortBy] or ""):lower()
            local vb = (b[sortBy] or ""):lower()
            if ascending then
                return va < vb
            else
                return va > vb
            end
        end
    end

    table.sort(items, comparator)
    return items
end

--- Multi-select filter: OR within each category, AND across categories.
-- @param items array of item tables
-- @param filters table with optional set fields:
--   types    (table {Weapon=true, Armor=true, ...}) — item types to include
--   rarities (table {Rare=true, ...}) — rarities to include
--   slots    (table {Helmet=true, ...}) — equipment slots to include
--   owners   (table {ownerUUID=true, ...}) — owner UUIDs to include
--   search   (string) — substring match on item Name (case-insensitive)
-- @return filtered array of items
function FilterEngine.FilterMulti(items, filters)
    if not filters then return items end

    local result = {}
    local searchLower = filters.search and filters.search ~= "" and filters.search:lower() or nil
    local hasTypes = filters.types and next(filters.types)
    local hasRarities = filters.rarities and next(filters.rarities)
    local hasSlots = filters.slots and next(filters.slots)
    local hasOwners = filters.owners and next(filters.owners)

    for _, item in ipairs(items) do
        local pass = true

        if hasTypes then
            if not filters.types[item.Type] then pass = false end
        end

        if pass and hasRarities then
            if not filters.rarities[item.Rarity] then pass = false end
        end

        if pass and hasSlots then
            local itemSlot = item.Slot or ""
            if itemSlot == "" then pass = false
            elseif not filters.slots[itemSlot] then pass = false end
        end

        if pass and hasOwners then
            if not filters.owners[item.OwnerUUID] then pass = false end
        end

        if pass and searchLower then
            local nameLower = (item.Name or ""):lower()
            if not nameLower:find(searchLower, 1, true) then pass = false end
        end

        if pass then result[#result + 1] = item end
    end

    return result
end

--- Convenience: filter then sort.
-- @param items array of item tables
-- @param filters table (see FilterEngine.Filter)
-- @param sortBy string (see FilterEngine.Sort)
-- @param ascending boolean
-- @return filtered and sorted array
function FilterEngine.FilterAndSort(items, filters, sortBy, ascending)
    local filtered = FilterEngine.Filter(items, filters)
    return FilterEngine.Sort(filtered, sortBy, ascending)
end

-- Export for BG3SE and for testing
if Ext then
    Mods = Mods or {}
    Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
    Mods.BG3InventoryRework.FilterEngine = FilterEngine
end

return FilterEngine
