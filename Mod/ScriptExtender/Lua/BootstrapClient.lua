-- BG3 Inventory Rework — Client Entry Point

Ext.Require("Client/DataStore.lua")
Ext.Require("Client/FilterEngine.lua")
Ext.Require("Client/InventoryUI.lua")
Ext.Require("Client/ArmoryUI.lua")
Ext.Require("Client/NetHandlers.lua")
Ext.Require("Client/InventoryPanelVM.lua")
Ext.Require("Client/ArmoryPanelVM.lua")

Ext.Events.SessionLoaded:Subscribe(function()
    _P("[BG3InventoryRework] Client loaded")

    -- Initialize InventoryPanel ViewModel after UI settles
    Ext.Timer.WaitFor(2000, function()
        _P("[BG3InventoryRework] Initializing InventoryPanelVM...")
        local ok, err = pcall(Mods.BG3InventoryRework.InventoryPanelVM.Init)
        if ok then
            pcall(Mods.BG3InventoryRework.InventoryPanelVM.TryBind)
        else
            _P("[BG3InventoryRework] InventoryPanelVM.Init failed: " .. tostring(err))
        end

        _P("[BG3InventoryRework] Initializing ArmoryPanelVM...")
        local ok2, err2 = pcall(Mods.BG3InventoryRework.ArmoryPanelVM.Init)
        if ok2 then
            pcall(Mods.BG3InventoryRework.ArmoryPanelVM.TryBind)
        else
            _P("[BG3InventoryRework] ArmoryPanelVM.Init failed: " .. tostring(err2))
        end
    end)
end)
