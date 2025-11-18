--=============================================================
-- SLOT MACHINE MOD • CLEAN & STABLE CLIENT BUILD (SINGLETON)
--=============================================================

Events.OnGameStart.Add(function()

    ---------------------------------------------------------------
    -- SAFE UI IMPORTS
    ---------------------------------------------------------------
    if not ISPanel then require "ISUI/ISPanel" end
    if not ISButton then require "ISUI/ISButton" end
    print("[SLOTS] Loaded ISUI modules. Initializing…")

    ---------------------------------------------------------------
    -- PAYOUT + RNG
    ---------------------------------------------------------------
    local symbols = {"C", "D", "S", "X"} -- Cherry, Diamond, Shamrock, Skull
    local payouts = { ["CCC"]=20, ["DDD"]=100, ["SSS"]=200, ["XXX"]=0 }

    local function spinReels()
        local res = {
            symbols[ZombRand(1, #symbols + 1)],
            symbols[ZombRand(1, #symbols + 1)],
            symbols[ZombRand(1, #symbols + 1)],
        }
        return res, (payouts[table.concat(res)] or 0)
    end

    ---------------------------------------------------------------
    -- CURRENCY HELPERS
    ---------------------------------------------------------------
    local function getBalance(player, mode)
        if not player then return 0 end
        local inv = player:getInventory()
        if not inv then return 0 end
        local t = (mode == "cash") and "Base.Money" or "Base.CasinoToken"
        local items = inv:getItemsFromType(t)
        if not items or items:isEmpty() then return 0 end
        local total = 0

        for i = 0, items:size() - 1 do
            local itm = items:get(i)
            local ok, val = pcall(function()
                if itm.getUseDelta and itm:getUseDelta() > 0 then
                    return math.floor(1 / itm:getUseDelta())
                elseif itm.getUses and itm:getUses() > 0 then
                    return itm:getUses()
                else
                    return 1
                end
            end)
            if ok and val then total = total + val end
        end
        return total
    end

    local function adjustBalance(player, mode, amount)
        if not player then return end
        local inv = player:getInventory()
        if not inv then return end
        local t = (mode == "cash") and "Base.Money" or "Base.CasinoToken"
        local items = inv:getItemsFromType(t)
        if not items then return end

        local remaining = math.abs(amount)

        if amount < 0 then
            for i = 0, items:size() - 1 do
                local itm = items:get(i)
                if itm and remaining > 0 then
                    local ok = pcall(function()
                        if itm.getUseDelta and itm:getUseDelta() > 0 then
                            local stack = math.floor(1 / itm:getUseDelta())
                            if stack <= remaining then
                                inv:Remove(itm)
                                remaining = remaining - stack
                            else
                                itm:setUseDelta(1 / (stack - remaining))
                                remaining = 0
                            end
                        else
                            inv:Remove(itm)
                            remaining = remaining - 1
                        end
                    end)
                    if not ok then print("[SLOTS] adjustBalance: remove failed, skipping item") end
                end
            end
        else
            for _ = 1, amount do inv:AddItem(t) end
        end
    end

    ---------------------------------------------------------------
    -- SLOT UI DEFINITION
    ---------------------------------------------------------------
    local SlotUI = ISPanel:derive("SlotUI")
    local activeSlotUI = nil -- SINGLETON GUARD

    function SlotUI:new(x, y, w, h, player)
        local o = ISPanel:new(x, y, w, h)
        setmetatable(o, self)
        self.__index = self
        o.player = player
        o.moveWithMouse = true
        o.resizable = false
        o.backgroundColor = {r=0, g=0, b=0, a=0.7}
        o.borderColor = {r=1, g=1, b=1, a=1}
        o.destroyed = false
        return o
    end

    function SlotUI:initialise()
        ISPanel.initialise(self)
        self.spinResult = {"?", "?", "?"}
        self.betMode = "cash"
        self.betAmount = 5
        self.isSpinning = false
    end

    function SlotUI:createChildren()
        local y = 40
        self.modeBtn = ISButton:new(30, y, 100, 25, "Mode: Cash", self, SlotUI.toggleMode)
        self:addChild(self.modeBtn)
        self.spinBtn = ISButton:new(140, y, 100, 25, "SPIN", self, SlotUI.spin)
        self:addChild(self.spinBtn)
        self.exitBtn = ISButton:new((self.width / 2) - 50, self.height - 40, 100, 25, "EXIT", self, SlotUI.onExitPressed)
        self:addChild(self.exitBtn)
    end

    function SlotUI:toggleMode()
        self.betMode = (self.betMode == "cash") and "token" or "cash"
        self.modeBtn:setTitle("Mode: " .. (self.betMode == "cash" and "Cash" or "Token"))
    end

    function SlotUI:_stopSpinTimer()
        if self._spinTimerFn then
            Events.OnTick.Remove(self._spinTimerFn)
            self._spinTimerFn = nil
            self._spinTicks = 0
            self.isSpinning = false
        end
    end

    function SlotUI:spin()
        if self.isSpinning then return end
        local player = self.player
        if not player then return end
        local bal = getBalance(player, self.betMode)
        if bal < self.betAmount then
            player:Say("Not enough " .. self.betMode .. "!")
            return
        end

        adjustBalance(player, self.betMode, -self.betAmount)
        player:Say("Spinning…")
        self.isSpinning = true
        self._spinTicks = 30

        local function tick()
            if not activeSlotUI or activeSlotUI ~= self or self.destroyed or not self.javaObject then
                Events.OnTick.Remove(tick); return
            end
            self._spinTicks = self._spinTicks - 1
            if self._spinTicks <= 0 then
                Events.OnTick.Remove(tick)
                self._spinTimerFn = nil
                local res, payout = spinReels()
                self.spinResult = res
                if payout > 0 then
                    adjustBalance(player, self.betMode, payout)
                    player:Say("You won " .. payout .. " " .. self.betMode .. "!")
                else
                    player:Say("You lost!")
                end
                self.isSpinning = false
            end
        end
        self._spinTimerFn = tick
        Events.OnTick.Add(tick)
    end

    function SlotUI:prerender()
        if not self or self.destroyed or not self.javaObject or not self:getIsVisible() then return end
        local w, h = self.width or 0, self.height or 0
        ISPanel.prerender(self)
        self:drawRect(0, 0, w, h, 0.7, 0, 0, 0)
        self:drawRectBorder(0, 0, w, h, 1, 1, 1, 1)
        local text = table.concat(self.spinResult, " | ")
        self:drawTextCentre(text, w / 2, 120, 1, 1, 1, 1, UIFont.Medium)
        if self.isSpinning then
            self:drawTextCentre("SPINNING...", w / 2, 90, 1, 0.8, 0, 1, UIFont.Small)
        end
    end

    function SlotUI:close()
        if self.destroyed then return end
        self:_stopSpinTimer()
        self.isSpinning = false
        self:setVisible(false)
        self:removeFromUIManager()
        self.destroyed = true
        if activeSlotUI == self then activeSlotUI = nil end
    end

    function SlotUI:onExitPressed() self:close() end

    ---------------------------------------------------------------
    -- SINGLETON OPEN/TOGGLE
    ---------------------------------------------------------------
    local function openSlotUI(player)
        if activeSlotUI and not activeSlotUI.destroyed and activeSlotUI:getIsVisible() then
            activeSlotUI:bringToTop()
            player:Say("Slot Machine already open.")
            return
        end
        if activeSlotUI and activeSlotUI.destroyed then activeSlotUI = nil end
        local ui = SlotUI:new(200, 200, 300, 250, player)
        ui:initialise()
        ui:addToUIManager()
        ui:bringToTop()
        activeSlotUI = ui
        player:Say("Feeling lucky?")
    end

    local function toggleSlotUI(player)
        if activeSlotUI and not activeSlotUI.destroyed and activeSlotUI:getIsVisible() then
            activeSlotUI:close()
        else
            openSlotUI(player)
        end
    end
    _G.toggleSlotUI = toggleSlotUI

    ---------------------------------------------------------------
    -- KEYBIND: 'O' TOGGLE
    ---------------------------------------------------------------
    Events.OnKeyPressed.Add(function(key)
        if key == 24 then
            local player = getSpecificPlayer(0)
            if not player then return end
            toggleSlotUI(player)
        end
    end)
end)

---------------------------------------------------------------
-- WORLD CONTEXT MENU • PLAY SLOTS
---------------------------------------------------------------
local function SlotMachineContextMenu(playerIndex, context, worldobjects)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    local found = false
    for _, obj in ipairs(worldobjects) do
        if obj then
            local name = (obj.getName and obj:getName()) or ""
            local spr = (obj.getSprite and obj:getSprite() and obj:getSprite():getName()) or ""
            local lname = name:lower()
            local low = spr:lower()

            if lname == "slot machine"
            or lname:find("slot", 1, true)
            or low:find("vending", 1, true)
            or low:find("mov_snackvendingmachine", 1, true) then
                found = true
                context:addOption("Play Slots", obj, function() toggleSlotUI(player) end)
                print("[SLOTS][Context] Added option for:", name or spr)
                break
            end
        end
    end

    if not found then
        context:addOption("No SlotMachine detected nearby", nil, function()
            player:Say("No slots here!")
        end)
    end
end
Events.OnFillWorldObjectContextMenu.Add(SlotMachineContextMenu)

---------------------------------------------------------------
-- SLOT MACHINE PLACER • DEV TOOL
---------------------------------------------------------------
local SLOT_SPRITE = "location_business_office_generic_01_16"

local function placeSlotMachine()
    local mX, mY = ISCoordConversion.ToWorld(getMouseX(), getMouseY(), 0)
    mX, mY = math.floor(mX), math.floor(mY)
    local cell = getWorld():getCell()
    local sq = cell:getGridSquare(mX, mY, 0)
    if not sq then return end

    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        if obj and obj:getName() == "SlotMachine" then
            sq:getSpecialObjects():remove(obj)
            sq:getObjects():remove(obj)
            print("[SLOTS] Removed existing SlotMachine at tile.")
            return
        end
    end

    local sprite = getSprite(SLOT_SPRITE)
    if not sprite then print("[SLOTS][ERROR] Sprite not found:", SLOT_SPRITE) return end

    local obj = IsoObject.new(cell, sq, sprite)
    obj:setName("SlotMachine")
    obj:setCanPassThrough(false)
    obj:setBlockAllTheSquare(true)
    obj:setIsMoveAble(false)
    sq:AddSpecialObject(obj)
    print(string.format("[SLOTS] Spawned SlotMachine at %d, %d (%s)", mX, mY, SLOT_SPRITE))
end

local function onFillWorldObjectContextMenu_Place(playerNum, context)
    context:addOption("Place Slot Machine (Dev)", nil, placeSlotMachine)
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu_Place)
