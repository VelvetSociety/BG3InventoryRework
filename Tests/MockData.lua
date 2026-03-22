--- Mock item data for offline testing.
-- @module MockData

local MockData = {}

--- Generate a set of mock items representing a typical BG3 party inventory.
function MockData.GetPartyInventory()
    return {
        -- Shadowheart's items
        { UUID = "item-001", Name = "Spear of Night", Type = "Weapon", Rarity = "VeryRare",
          Weight = 1.8, Value = 960, OwnerUUID = "char-shadowheart", OwnerName = "Shadowheart",
          Icon = "spear_night", StackSize = 1, Slot = "MeleeMainHand", Enchantments = {} },
        { UUID = "item-002", Name = "Shield of Devotion", Type = "Armor", Rarity = "Rare",
          Weight = 2.7, Value = 640, OwnerUUID = "char-shadowheart", OwnerName = "Shadowheart",
          Icon = "shield_devotion", StackSize = 1, Slot = "MeleeOffHand", Enchantments = {} },
        { UUID = "item-003", Name = "Healing Potion", Type = "Consumable", Rarity = "Common",
          Weight = 0.3, Value = 20, OwnerUUID = "char-shadowheart", OwnerName = "Shadowheart",
          Icon = "potion_heal", StackSize = 5, Slot = "", Enchantments = {} },
        { UUID = "item-004", Name = "Adamantine Splint Armour", Type = "Armor", Rarity = "VeryRare",
          Weight = 18.0, Value = 2400, OwnerUUID = "char-shadowheart", OwnerName = "Shadowheart",
          Icon = "armor_adam_splint", StackSize = 1, Slot = "Breast", Enchantments = {} },

        -- Lae'zel's items
        { UUID = "item-010", Name = "Everburn Blade", Type = "Weapon", Rarity = "Uncommon",
          Weight = 2.7, Value = 280, OwnerUUID = "char-laezel", OwnerName = "Lae'zel",
          Icon = "sword_everburn", StackSize = 1, Slot = "MeleeMainHand", Enchantments = {} },
        { UUID = "item-011", Name = "Githyanki Half Plate", Type = "Armor", Rarity = "Uncommon",
          Weight = 12.0, Value = 520, OwnerUUID = "char-laezel", OwnerName = "Lae'zel",
          Icon = "armor_gith_half", StackSize = 1, Slot = "Breast", Enchantments = {} },
        { UUID = "item-012", Name = "Potion of Speed", Type = "Consumable", Rarity = "Uncommon",
          Weight = 0.3, Value = 65, OwnerUUID = "char-laezel", OwnerName = "Lae'zel",
          Icon = "potion_speed", StackSize = 2, Slot = "", Enchantments = {} },
        { UUID = "item-013", Name = "Amulet of Misty Step", Type = "Armor", Rarity = "Uncommon",
          Weight = 0.05, Value = 145, OwnerUUID = "char-laezel", OwnerName = "Lae'zel",
          Icon = "amulet_misty", StackSize = 1, Slot = "Amulet", Enchantments = {} },

        -- Gale's items
        { UUID = "item-020", Name = "Staff of Crones", Type = "Weapon", Rarity = "Rare",
          Weight = 1.8, Value = 480, OwnerUUID = "char-gale", OwnerName = "Gale",
          Icon = "staff_crones", StackSize = 1, Slot = "MeleeMainHand", Enchantments = {} },
        { UUID = "item-021", Name = "Robe of Summer", Type = "Armor", Rarity = "Rare",
          Weight = 1.8, Value = 350, OwnerUUID = "char-gale", OwnerName = "Gale",
          Icon = "robe_summer", StackSize = 1, Slot = "Breast", Enchantments = {} },
        { UUID = "item-022", Name = "Scroll of Fireball", Type = "Scroll", Rarity = "Uncommon",
          Weight = 0.1, Value = 80, OwnerUUID = "char-gale", OwnerName = "Gale",
          Icon = "scroll_fireball", StackSize = 3, Slot = "", Enchantments = {} },
        { UUID = "item-023", Name = "Ring of Protection", Type = "Armor", Rarity = "Rare",
          Weight = 0.05, Value = 290, OwnerUUID = "char-gale", OwnerName = "Gale",
          Icon = "ring_protection", StackSize = 1, Slot = "Ring", Enchantments = {} },
        { UUID = "item-024", Name = "Healing Potion", Type = "Consumable", Rarity = "Common",
          Weight = 0.3, Value = 20, OwnerUUID = "char-gale", OwnerName = "Gale",
          Icon = "potion_heal", StackSize = 3, Slot = "", Enchantments = {} },

        -- Astarion's items
        { UUID = "item-030", Name = "Bow of Awareness", Type = "Weapon", Rarity = "Uncommon",
          Weight = 1.0, Value = 310, OwnerUUID = "char-astarion", OwnerName = "Astarion",
          Icon = "bow_awareness", StackSize = 1, Slot = "RangedMainHand", Enchantments = {} },
        { UUID = "item-031", Name = "Leather Armour +1", Type = "Armor", Rarity = "Uncommon",
          Weight = 5.0, Value = 260, OwnerUUID = "char-astarion", OwnerName = "Astarion",
          Icon = "leather_plus1", StackSize = 1, Slot = "Breast", Enchantments = {} },
        { UUID = "item-032", Name = "Knife of the Undermountain King", Type = "Weapon", Rarity = "Legendary",
          Weight = 0.45, Value = 3200, OwnerUUID = "char-astarion", OwnerName = "Astarion",
          Icon = "dagger_undermtn", StackSize = 1, Slot = "MeleeMainHand", Enchantments = {} },
        { UUID = "item-033", Name = "Thieves' Tools", Type = "Misc", Rarity = "Common",
          Weight = 0.5, Value = 10, OwnerUUID = "char-astarion", OwnerName = "Astarion",
          Icon = "tools_thief", StackSize = 8, Slot = "", Enchantments = {} },
    }
end

return MockData
