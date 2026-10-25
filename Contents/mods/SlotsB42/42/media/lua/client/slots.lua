--=============================================================
-- SLOTS MOD - CLIENT
-- Client owns UI only.
-- Server owns money, validation, RNG, and payouts in MP.
--=============================================================

if not ISPanel then require "ISUI/ISPanel" end
if not ISButton then require "ISUI/ISButton" end

require "slotsshared"
local SLOTS = _G.SlotsShared
if not SLOTS then
    print("[SLOTS] ERROR: SlotsShared not loaded on client")
    return
end

local SlotsMod = _G.SlotsMod or {}
_G.SlotsMod = SlotsMod

SlotsMod.nextRequestId = SlotsMod.nextRequestId or 0
if SlotsMod.soundEnabled == nil then SlotsMod.soundEnabled = true end

local REVEAL_HOLD_MS = 650
local CREDIT_COUNT_MS = 900
local colors = {
    idle = {r=0.75, g=0.75, b=0.75},
    spinning = {r=1, g=0.78, b=0.3},
    win = {r=0.35, g=1, b=0.55},
    jackpot = {r=1, g=0.84, b=0.25},
    loss = {r=0.9, g=0.62, b=0.6},
}

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
-- B42 MONEY DISPLAY / OPTIONAL SINGLE-PLAYER DEBUG HELPERS
-------------------------------------------------------------
local function getInventory(player)
    return player and player:getInventory() or nil
end

local function getMoney(player)
    return SLOTS.getMoney(player)
end

local function giveMoney(player, amount)
    -- Published debug buttons remain off. Never create money on an MP client.
    if isClient() then return end
    local inv = getInventory(player)
    if inv and amount > 0 then inv:AddItems(SLOTS.moneyFull, amount) end
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
    o.phase = "idle"
    o.stoppedReels = 0
    o.soundHandles = {}

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
    self.soundBtn = ISButton:new(498, 40, 92, 25, SlotsMod.soundEnabled and "SOUND ON" or "SOUND OFF", self, SlotUI.onToggleSound)
    self:addChild(self.soundBtn)
    self:updateBetButtons(true)
end

function SlotUI:playCue(name)
    if not SlotsMod.soundEnabled or not getSoundManager then return end
    -- Audio failure must never interrupt a settled spin. These are B42 sounds.
    local ok, handle = pcall(function() return getSoundManager():playUISound(name) end)
    if ok and handle and handle ~= 0 then self.soundHandles[#self.soundHandles + 1] = handle end
end

function SlotUI:stopCues()
    if getSoundManager then
        for _, handle in ipairs(self.soundHandles) do
            pcall(function() getSoundManager():stopUISound(handle) end)
        end
    end
    self.soundHandles = {}
end

function SlotUI:onToggleSound()
    SlotsMod.soundEnabled = not SlotsMod.soundEnabled
    self.soundBtn:setTitle(SlotsMod.soundEnabled and "SOUND ON" or "SOUND OFF")
    if not SlotsMod.soundEnabled then self:stopCues() end
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
    self.pendingArgs = nil
    self.pendingSince = nil
    self.phase = "idle"
    self.serverBalance = nil
    self.resultShownAt = nil
    self:setSpinButton(true)
end

function SlotUI:playResult(result, payout)
    self.spinning = true
    self.phase = "spinning"
    self.stoppedReels = 0
    self.resultPayout = nil
    self.resultShownAt = nil
    self.creditPayout = payout
    self:setSpinButton(false)

    local elapsed = 0
    local stopTicks = {math.ceil(SLOTS.spinTicks * 0.55), math.ceil(SLOTS.spinTicks * 0.78), SLOTS.spinTicks}
    local finalResult = result

    local function onSpinTick()
        if self.closed or (self.player and self.player:isDead()) then
            self:onExit()
            Events.OnTick.Remove(onSpinTick)
            return
        end

        elapsed = elapsed + 1
        for i = 1, 3 do
            if elapsed < stopTicks[i] then
                self.result[i] = SLOTS.randomSymbol()
            elseif elapsed == stopTicks[i] then
                self.result[i] = finalResult[i]
                self.stoppedReels = i
                self:playCue("UIActivateButton")
            end
        end
        if elapsed < SLOTS.spinTicks then return end

        Events.OnTick.Remove(onSpinTick)
        self.spinTick = nil
        self.result = finalResult
        self.phase = "reveal"
        self.resultPayout = payout
        self.resultKind = payout <= 0 and "loss"
            or (table.concat(finalResult, "|") == SLOTS.jackpotKey and "jackpot" or "win")
        self:playCue(self.resultKind == "jackpot" and "UIAchievement"
            or (payout > 0 and "CashRegisterOpen" or "CashRegisterClose"))

        if self.player then
            if payout > 0 then
                self.player:Say("You won $" .. tostring(payout))
            else
                self.player:Say("You lost")
            end
        end

        -- Keep the post-wager balance until the payout has actually been drawn.
        -- Server settlement is already final; this count-up never mutates money.
    end

    self.spinTick = onSpinTick
    Events.OnTick.Add(onSpinTick)
end

function SlotUI:playSinglePlayerSpin()
    -- SP loads server Lua too, so both modes use the same validated settlement.
    local result = SlotsServer.spin(self.player, self.pendingArgs)
    if result.ok then self:onSpinResult(result) else self:onSpinDenied(result) end
end

function SlotUI:onSpin()
    if self.closed or self.spinning or self.pendingRequestId or not self.player then return end
    if self.player:isDead() then self:onExit(); return end
    if not self.machine then
        self.player:Say("No slot machine selected")
        return
    end
    if getMoney(self.player) < self.bet then
        self.player:Say("Not enough money")
        self.statusMessage = "Not enough money"
        self:playCue("CashRegisterClose")
        return
    end

    SlotsMod.nextRequestId = SlotsMod.nextRequestId + 1
    self.pendingRequestId = SlotsMod.nextRequestId
    self.pendingBet = self.bet
    self.pendingArgs = {
        requestId = self.pendingRequestId,
        bet = self.pendingBet,
        x = self.machine.x,
        y = self.machine.y,
        z = self.machine.z,
    }
    self.pendingSince = getTimestampMs()
    self.requestRetries = 0
    self:stopCues()
    self.spinStartMoney = getMoney(self.player)
    self.serverBalance = self.spinStartMoney
    self.settlementBalance = nil
    self.phase = "waiting"
    self.statusMessage = nil
    self.resultPayout = nil
    self.resultShownAt = nil
    self.stoppedReels = 0
    self.spinning = true
    self:setSpinButton(false)
    self.player:Say("Spinning")
    self:playCue("UIActivatePlayButton")

    if isClient() then
        sendClientCommand(self.player, SLOTS.moduleName, SLOTS.commands.spinRequest, self.pendingArgs)
    else
        self:playSinglePlayerSpin()
    end
end

function SlotUI:onSpinResult(args)
    if self.closed or type(args) ~= "table" or not self.pendingRequestId
        or args.requestId ~= self.pendingRequestId then return end

    self.resultBet = args.bet or self.pendingBet or self.bet
    self.balanceAfterBet = math.max(0, (self.spinStartMoney or getMoney(self.player)) - self.resultBet)
    self.serverBalance = self.balanceAfterBet
    self.settlementBalance = args.balance
    self.pendingRequestId = nil
    self.pendingBet = nil
    self.pendingArgs = nil
    self.pendingSince = nil
    -- The server already settled this wager. The reply only starts animation.
    self:playResult({args.r1 or "?", args.r2 or "?", args.r3 or "?"}, args.payout or 0)
end

function SlotUI:onSpinDenied(args)
    if self.closed or type(args) ~= "table" or not self.pendingRequestId
        or args.requestId ~= self.pendingRequestId then return end

    self.serverBalance = nil
    self:stopSpin()
    self.statusMessage = args.reason or "Spin denied"
    self:playCue("CashRegisterClose")
    if self.player then self.player:Say(args.reason or "Spin denied") end
end

function SlotUI:updatePresentation(now)
    if self.phase == "reveal" and self.resultShownAt and now - self.resultShownAt >= REVEAL_HOLD_MS then
        self.phase = "counting"
    end
    if self.phase == "counting" then
        local progress = self.creditPayout > 0
            and math.min(1, (now - self.resultShownAt - REVEAL_HOLD_MS) / CREDIT_COUNT_MS) or 1
        self.serverBalance = self.balanceAfterBet + math.floor(self.creditPayout * progress)
        if progress >= 1 then
            self.serverBalance = self.settlementBalance or getMoney(self.player)
            self.releaseBalanceAt = now + 5000
            self.phase = "result"
            self.spinning = false
            self:setSpinButton(true)
        end
    elseif self.phase == "result" and self.serverBalance ~= nil then
        -- Inventory replication may arrive after the outcome packet in MP.
        if getMoney(self.player) == self.serverBalance or now >= self.releaseBalanceAt then
            self.serverBalance = nil
        end
    end
end

function SlotUI:update()
    ISPanel.update(self)
    if self.closed then return end
    if self.player and self.player:isDead() then self:onExit(); return end
    self:updatePresentation(getTimestampMs())
    if not self.pendingRequestId or not self.pendingSince then return end
    local now = getTimestampMs()
    if now - self.pendingSince < 15000 then return end
    self.pendingSince = now
    self.requestRetries = self.requestRetries + 1
    if self.requestRetries <= 2 then
        -- Retry the same ID; the server returns its cached outcome without charging.
        sendClientCommand(self.player, SLOTS.moduleName, SLOTS.commands.spinRequest, self.pendingArgs)
    else
        self:onSpinDenied({requestId = self.pendingRequestId,
            reason = "Spin reply timed out. Check your money before trying again."})
    end
end

function SlotUI:prerender()
    ISPanel.prerender(self)

    self:drawRect(0, 0, self.width, self.height, 0.85, 0, 0, 0)
    self:drawRectBorder(0, 0, self.width, self.height, 1, 1, 1, 1)
    self:drawTextCentre("SLOT MACHINE", self.width / 2, 12, 1, 1, 0, 1, UIFont.Large)

    local status = self.statusMessage or "Choose your bet and press SPIN"
    local color = colors.idle
    local revealed = self.resultPayout ~= nil
    if self.statusMessage then
        color = colors.loss
    elseif self.phase == "waiting" then
        status, color = "Waiting for machine...", colors.spinning
    elseif self.phase == "spinning" then
        status, color = "Spinning...", colors.spinning
    elseif revealed then
        color = colors[self.resultKind]
        status = self.resultPayout > 0
            and ((self.resultKind == "jackpot" and "JACKPOT! $" or "You won $") .. tostring(self.resultPayout))
            or "You lost"
        if not self.resultShownAt then self.resultShownAt = getTimestampMs() end
    end
    self:drawRect(30, 78, self.width - 60, 32, 0.13, color.r, color.g, color.b)
    self:drawTextCentre(status, self.width / 2, 82, color.r, color.g, color.b, 1, UIFont.Medium)

    local reelSize = 90
    local gap = 20
    local startX = (self.width - ((reelSize * 3) + (gap * 2))) / 2
    local y = 120

    for i = 1, 3 do
        local symbol = self.result[i] or "?"
        local x = startX + ((i - 1) * (reelSize + gap))

        local reelColor = (revealed or (self.phase == "spinning" and i <= self.stoppedReels)) and color or colors.idle
        local pulse = revealed and self.resultPayout > 0 and self.resultShownAt
            and getTimestampMs() - self.resultShownAt < 2400
            and (0.65 + 0.25 * math.sin((getTimestampMs() - self.resultShownAt) / 220)) or 1
        if revealed then self:drawRect(x, y, reelSize, reelSize, 0.08, reelColor.r, reelColor.g, reelColor.b) end
        self:drawRectBorder(x, y, reelSize, reelSize, pulse, reelColor.r, reelColor.g, reelColor.b)
        drawReelSymbol(self, symbol, x, y, reelSize)
    end

    local balance = self.serverBalance
    if balance == nil then
        balance = getMoney(self.player)
    end

    self:drawText("Bet: $" .. tostring(self.bet), 30, 235, 1, 1, 1, 1, UIFont.Small)
    self:drawText("Money: $" .. tostring(balance), 30, 255, 1, 1, 1, 1, UIFont.Small)
    if revealed then
        local net = self.resultPayout - (self.resultBet or self.bet)
        local netText = (net >= 0 and "+$" or "-$") .. tostring(math.abs(net))
        self:drawText("Payout: $" .. tostring(self.resultPayout), 360, 235, color.r, color.g, color.b, 1, UIFont.Small)
        self:drawText("Net: " .. netText, 360, 255, 1, 1, 1, 1, UIFont.Small)
        if self.phase == "counting" then
            self:drawText("Adding winnings...", 30, 275, color.r, color.g, color.b, 1, UIFont.Small)
        end
    end
end

function SlotUI:onExit()
    if self.closed then return end

    self.closed = true
    self:stopSpin()
    self:stopCues()
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
