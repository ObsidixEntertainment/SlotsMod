--=============================================================
-- SLOTS MOD - CLIENT
-- Client owns UI only.
-- Server owns money, validation, RNG, and payouts in MP.
--=============================================================

if not ISPanel then require "ISUI/ISPanel" end
if not ISButton then require "ISUI/ISButton" end

local SLOTS = _G.SlotsShared
if not SLOTS then
    print("[SLOTS] ERROR: SlotsShared not loaded on client")
    return
end

local SlotsMod = _G.SlotsMod or {}
_G.SlotsMod = SlotsMod

SlotsMod.nextRequestId = SlotsMod.nextRequestId or 0

-------------------------------------------------------------
-- REEL SYMBOL TEXTURES
-------------------------------------------------------------
local symbolTextureCache = {}

local function getSymbolTexture(symbol)
    if symbolTextureCache[symbol] ~= nil then
        return symbolTextureCache[symbol] or nil
    end

    local candidates = SLOTS.getSymbolTextureCandidates and SLOTS.getSymbolTextureCandidates(symbol) or nil
    if candidates and getTexture then
        for _, textureName in ipairs(candidates) do
            local ok, texture = pcall(function()
                return getTexture(textureName)
            end)

            if ok and texture then
                symbolTextureCache[symbol] = texture
                return texture
            end
        end
    end

    symbolTextureCache[symbol] = false
    return nil
end

local function drawReelSymbol(ui, symbol, x, y, reelSize)
    local color = SLOTS.getSymbolColor and SLOTS.getSymbolColor(symbol) or (SLOTS.symbolColors[symbol] or SLOTS.symbolColors["?"])
    local texture = getSymbolTexture(symbol)

    if texture then
        local pad = 14
        ui:drawTextureScaled(texture, x + pad, y + pad, reelSize - (pad * 2), reelSize - (pad * 2), 1, color.r, color.g, color.b)
        return
    end

    local display = SLOTS.getSymbolDisplay and SLOTS.getSymbolDisplay(symbol) or symbol
    ui:drawTextCentre(display, x + (reelSize / 2), y + 18, color.r, color.g, color.b, 1, UIFont.Huge)
end

-------------------------------------------------------------
-- LOCAL FALLBACK MONEY HELPERS
-- Used only outside MP so single-player testing still works.
-------------------------------------------------------------
local function getInventory(player)
    if not player then return nil end

    local ok, inv = pcall(function()
        return player:getInventory()
    end)

    if ok then return inv end
    return nil
end

local function getMoneyItems(inv)
    if not inv then return nil end

    local moneyTypes = {SLOTS.moneyFull, SLOTS.moneyShort}

    for _, itemType in ipairs(moneyTypes) do
        local ok, items = pcall(function()
            return inv:getItemsFromType(itemType)
        end)

        if ok and items and not items:isEmpty() then
            return items
        end
    end

    return nil
end

local function getMoneyItemValue(item)
    if not item then return 0 end

    local ok, value = pcall(function()
        if item.getUseDelta and item:getUseDelta() > 0 then
            return math.floor((1 / item:getUseDelta()) + 0.5)
        end

        if item.getUses and item:getUses() > 0 then
            return item:getUses()
        end

        return 1
    end)

    if ok and value and value > 0 then return value end
    return 1
end

local function setMoneyItemValue(item, value)
    if not item or value <= 0 then return false end

    local ok, changed = pcall(function()
        if item.getUseDelta and item.setUseDelta and item:getUseDelta() > 0 then
            item:setUseDelta(1 / value)
            return true
        end

        if item.setUses then
            item:setUses(value)
            return true
        end

        return false
    end)

    return ok and changed
end

local function getMoney(player)
    local inv = getInventory(player)
    if not inv then return 0 end

    local items = getMoneyItems(inv)
    if not items then return 0 end

    local total = 0
    for i = 0, items:size() - 1 do
        total = total + getMoneyItemValue(items:get(i))
    end

    return total
end

local function giveMoney(player, amount)
    local inv = getInventory(player)
    if not inv or amount <= 0 then return end

    for _ = 1, amount do
        inv:AddItem(SLOTS.moneyFull)
    end
end

local function takeMoney(player, amount)
    if amount <= 0 then return true end

    local inv = getInventory(player)
    if not inv then return false end
    if getMoney(player) < amount then return false end

    local items = getMoneyItems(inv)
    if not items then return false end

    local remaining = amount

    for i = items:size() - 1, 0, -1 do
        if remaining <= 0 then break end

        local item = items:get(i)
        local value = getMoneyItemValue(item)

        if value <= remaining then
            local ok = pcall(function()
                inv:Remove(item)
            end)

            if ok then
                remaining = remaining - value
            end
        else
            local newValue = value - remaining

            if not setMoneyItemValue(item, newValue) then
                local ok = pcall(function()
                    inv:Remove(item)
                end)

                if not ok then return false end

                for _ = 1, newValue do
                    inv:AddItem(SLOTS.moneyFull)
                end
            end

            remaining = 0
        end
    end

    return remaining <= 0
end

-------------------------------------------------------------
-- UI
-------------------------------------------------------------
local SlotUI = ISPanel:derive("SlotUI")

function SlotUI:new(x, y, width, height, player, machineSquare)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.machine = SLOTS.getSquareArgs(machineSquare)
    o.moveWithMouse = true
    o.backgroundColor = {r = 0, g = 0, b = 0, a = 0.85}
    o.borderColor = {r = 1, g = 1, b = 1, a = 1}

    o.bet = SLOTS.getDefaultBetAmount and SLOTS.getDefaultBetAmount() or SLOTS.betAmount
    o.betButtons = {}
    o.serverBalance = nil
    o.result = {"?", "?", "?"}
    o.spinning = false
    o.closed = false
    o.childrenMade = false
    o.spinTick = nil
    o.pendingRequestId = nil
    o.pendingBet = nil

    return o
end

function SlotUI:initialise()
    ISPanel.initialise(self)

    if not self.childrenMade then
        self:createChildren()
    end
end

function SlotUI:createChildren()
    if self.childrenMade then return end
    self.childrenMade = true

    self.spinBtn = ISButton:new(30, 40, 100, 25, "SPIN", self, SlotUI.onSpin)
    self:addChild(self.spinBtn)

    local betAmounts = SLOTS.betAmounts or {SLOTS.betAmount}
    local betX = 145
    for i, amount in ipairs(betAmounts) do
        local betAmount = amount
        local button = ISButton:new(betX + ((i - 1) * 64), 40, 58, 25, "$" .. tostring(betAmount), self, function()
            self:setBet(betAmount)
        end)

        self.betButtons[betAmount] = button
        self:addChild(button)
    end

    if SLOTS.enableGetMachineButton then
        self.machineBtn = ISButton:new(145, 40, 150, 25, "Get Slot Machine", self, SlotUI.onGetMachine)
        self:addChild(self.machineBtn)
    end

    if SLOTS.enableDebugButtons then
        self.money10Btn = ISButton:new(30, 75, 80, 25, "+10", self, function()
            self:addMoney(10)
        end)
        self:addChild(self.money10Btn)

        self.money50Btn = ISButton:new(120, 75, 80, 25, "+50", self, function()
            self:addMoney(50)
        end)
        self:addChild(self.money50Btn)

        self.money100Btn = ISButton:new(210, 75, 90, 25, "+100", self, function()
            self:addMoney(100)
        end)
        self:addChild(self.money100Btn)
    end

    self.exitBtn = ISButton:new((self.width / 2) - 50, self.height - 35, 100, 25, "EXIT", self, SlotUI.onExit)
    self:addChild(self.exitBtn)
    self:updateBetButtons(true)
end

function SlotUI:addMoney(amount)
    giveMoney(self.player, amount)

    if self.player then
        self.player:Say("Added $" .. tostring(amount))
    end
end

function SlotUI:onGetMachine()
    local inv = getInventory(self.player)
    if not inv then return end

    inv:AddItem(SLOTS.slotMachineItem)

    if self.player then
        self.player:Say("Slot Machine added")
    end
end

function SlotUI:setSpinButton(enabled)
    if not self.spinBtn then return end

    self.spinBtn:setEnable(enabled)
    self.spinBtn:setTitle(enabled and "SPIN" or "WAIT")
    self:updateBetButtons(enabled)
end

function SlotUI:updateBetButtons(enabled)
    if not self.betButtons then return end

    for amount, button in pairs(self.betButtons) do
        local title = "$" .. tostring(amount)
        if amount == self.bet then
            title = "[" .. title .. "]"
        end

        button:setTitle(title)
        button:setEnable(enabled and not self.spinning and not self.pendingRequestId)
    end
end

function SlotUI:setBet(amount)
    if self.spinning or self.pendingRequestId then return end
    if SLOTS.isValidBetAmount and not SLOTS.isValidBetAmount(amount) then return end

    self.bet = amount
    self:updateBetButtons(true)
end

function SlotUI:stopSpin()
    if self.spinTick then
        Events.OnTick.Remove(self.spinTick)
        self.spinTick = nil
    end

    self.spinning = false
    self.pendingRequestId = nil
    self.pendingBet = nil
    self:setSpinButton(true)
end

function SlotUI:playResult(result, payout)
    self.spinning = true
    self:setSpinButton(false)

    local ticksLeft = SLOTS.spinTicks
    local finalResult = result

    local function onSpinTick()
        if self.closed then
            Events.OnTick.Remove(onSpinTick)
            return
        end

        ticksLeft = ticksLeft - 1

        if ticksLeft > 0 then
            self.result = {
                SLOTS.randomSymbol(),
                SLOTS.randomSymbol(),
                SLOTS.randomSymbol(),
            }
            return
        end

        Events.OnTick.Remove(onSpinTick)
        self.spinTick = nil
        self.result = finalResult

        if self.player then
            if payout > 0 then
                self.player:Say("You won $" .. tostring(payout))
            else
                self.player:Say("You lost")
            end
        end

        self.spinning = false
        self.pendingRequestId = nil
        self:setSpinButton(true)
    end

    self.spinTick = onSpinTick
    Events.OnTick.Add(onSpinTick)
end

function SlotUI:playSinglePlayerSpin()
    if getMoney(self.player) < self.bet then
        self.player:Say("Not enough money")
        self:setSpinButton(true)
        self.spinning = false
        return
    end

    if not takeMoney(self.player, self.bet) then
        self.player:Say("Could not take money")
        self:setSpinButton(true)
        self.spinning = false
        return
    end

    local result, payout = SLOTS.roll(self.bet)
    if payout > 0 then
        giveMoney(self.player, payout)
    end

    self:playResult(result, payout)
end

function SlotUI:onSpin()
    if self.spinning or self.pendingRequestId or not self.player then return end

    if not self.machine then
        self.player:Say("No slot machine selected")
        return
    end

    local spinBet = self.bet

    if isClient and isClient() then
        if getMoney(self.player) < spinBet then
            self.player:Say("Not enough money")
            return
        end

        if not takeMoney(self.player, spinBet) then
            self.player:Say("Could not take money")
            return
        end
    end

    self.serverBalance = nil
    self.spinning = true
    self.pendingBet = spinBet
    self:setSpinButton(false)
    self.player:Say("Spinning")

    if isClient and isClient() then
        SlotsMod.nextRequestId = SlotsMod.nextRequestId + 1
        self.pendingRequestId = SlotsMod.nextRequestId

        sendClientCommand(self.player, SLOTS.moduleName, SLOTS.commands.spinRequest, {
            requestId = self.pendingRequestId,
            bet = spinBet,
            x = self.machine.x,
            y = self.machine.y,
            z = self.machine.z,
        })
    else
        self:playSinglePlayerSpin()
    end
end

function SlotUI:onSpinResult(args)
    if not args then return end
    if self.pendingRequestId and args.requestId and self.pendingRequestId ~= args.requestId then return end

    self.serverBalance = nil

    local payout = args.payout or 0
    self.pendingBet = nil

    if payout > 0 then
        giveMoney(self.player, payout)
    end

    local result = {
        args.r1 or "?",
        args.r2 or "?",
        args.r3 or "?",
    }

    self:playResult(result, payout)
end

function SlotUI:onSpinDenied(args)
    if self.pendingRequestId and args and args.requestId and self.pendingRequestId ~= args.requestId then return end

    if isClient and isClient() then
        giveMoney(self.player, self.pendingBet or self.bet)
    end

    self.serverBalance = nil
    self.pendingBet = nil

    self:stopSpin()

    if self.player then
        self.player:Say((args and args.reason) or "Spin denied")
    end
end

function SlotUI:prerender()
    ISPanel.prerender(self)

    self:drawRect(0, 0, self.width, self.height, 0.85, 0, 0, 0)
    self:drawRectBorder(0, 0, self.width, self.height, 1, 1, 1, 1)
    self:drawTextCentre("SLOT MACHINE", self.width / 2, 12, 1, 1, 0, 1, UIFont.Large)

    local reelSize = 90
    local gap = 20
    local startX = (self.width - ((reelSize * 3) + (gap * 2))) / 2
    local y = 120

    for i = 1, 3 do
        local symbol = self.result[i] or "?"
        local x = startX + ((i - 1) * (reelSize + gap))

        self:drawRectBorder(x, y, reelSize, reelSize, 1, 1, 1, 1)
        drawReelSymbol(self, symbol, x, y, reelSize)
    end

    local balance = self.serverBalance
    if balance == nil then
        balance = getMoney(self.player)
    end

    self:drawText("Bet: $" .. tostring(self.bet), 30, 235, 1, 1, 1, 1, UIFont.Small)
    self:drawText("Money: $" .. tostring(balance), 30, 255, 1, 1, 1, 1, UIFont.Small)
end

function SlotUI:onExit()
    if self.closed then return end

    self.closed = true
    self:stopSpin()
    self:setVisible(false)
    self:removeFromUIManager()

    if SlotsMod.activeSlotUI == self then
        SlotsMod.activeSlotUI = nil
    end
end

-------------------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------------------
local function openSlotUI(player, machineSquare)
    if SlotsMod.activeSlotUI then
        SlotsMod.activeSlotUI.machine = SLOTS.getSquareArgs(machineSquare) or SlotsMod.activeSlotUI.machine
        SlotsMod.activeSlotUI:bringToTop()
        return
    end

    local ui = SlotUI:new(200, 200, 620, 340, player, machineSquare)
    ui:initialise()
    ui:addToUIManager()
    ui:bringToTop()

    SlotsMod.activeSlotUI = ui
end

local function toggleSlotUI(player, machineSquare)
    if SlotsMod.activeSlotUI then
        SlotsMod.activeSlotUI:onExit()
    else
        openSlotUI(player, machineSquare)
    end
end

_G.toggleSlotUI = toggleSlotUI

-------------------------------------------------------------
-- WORLD OBJECT HELPERS
-------------------------------------------------------------
local function findSlotMachineSquare(worldobjects)
    if not worldobjects then return nil end

    for _, obj in ipairs(worldobjects) do
        if SLOTS.isSlotMachineObject(obj) then
            local ok, square = pcall(function()
                return obj:getSquare()
            end)

            if ok and square then return square end
        end

        local ok, square = pcall(function()
            if obj and obj.getSquare then
                return obj:getSquare()
            end
            return nil
        end)

        if ok and square and SLOTS.squareHasSlotMachine(square) then
            return square
        end
    end

    return nil
end

-------------------------------------------------------------
-- EVENTS
-------------------------------------------------------------
if SlotsMod.onKeyPressed then
    Events.OnKeyPressed.Remove(SlotsMod.onKeyPressed)
end

SlotsMod.onKeyPressed = function(key)
    if key ~= 24 then return end

    local player = getSpecificPlayer(0)
    if player then
        openSlotUI(player, nil)
    end
end

if SLOTS.enableDebugKey then
    Events.OnKeyPressed.Add(SlotsMod.onKeyPressed)
end

if SlotsMod.onServerCommand then
    Events.OnServerCommand.Remove(SlotsMod.onServerCommand)
end

SlotsMod.onServerCommand = function(module, command, args)
    if module ~= SLOTS.moduleName then return end

    local ui = SlotsMod.activeSlotUI
    if not ui then return end

    if command == SLOTS.commands.spinResult then
        ui:onSpinResult(args)
    elseif command == SLOTS.commands.spinDenied then
        ui:onSpinDenied(args)
    end
end

Events.OnServerCommand.Add(SlotsMod.onServerCommand)

if SlotsMod.onFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Remove(SlotsMod.onFillWorldObjectContextMenu)
end

SlotsMod.onFillWorldObjectContextMenu = function(playerIndex, context, worldobjects, test)
    if test then return end

    local machineSquare = findSlotMachineSquare(worldobjects)
    if not machineSquare then return end

    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    context:addOption("Play Slots", player, function(p)
        openSlotUI(p, machineSquare)
    end)
end

Events.OnFillWorldObjectContextMenu.Add(SlotsMod.onFillWorldObjectContextMenu)

print("[SLOTS] Client loaded")
