-- B42 settlement for the published B41 game. UI, bets, odds and payouts live in
-- the original shared/client files; only the server may mutate money in MP.
if isClient() then return end
require "slotsshared"

local SLOTS = SlotsShared
SlotsServer = SlotsServer or {}
local sessions = setmetatable({}, {__mode = "k"})

local function validRequestId(id)
    return type(id) == "number" and id >= 1 and id < 9007199254740991
        and id == math.floor(id)
end

local function playerIsNearSquare(player, square)
    if math.floor(player:getZ()) ~= square:getZ() then return false end
    local dx = player:getX() - square:getX()
    local dy = player:getY() - square:getY()
    return dx * dx + dy * dy <= SLOTS.maxUseDistance * SLOTS.maxUseDistance
end

function SlotsServer.spin(player, args)
    args = type(args) == "table" and args or {}
    local result = {ok = false, requestId = args.requestId}
    if not player or player:isDead() or not validRequestId(args.requestId) then
        result.reason = "Spin denied"
        return result
    end

    local session = sessions[player]
    if not session then
        session = {nextSpinAt = 0, lastRequestId = 0, results = {}, order = {}}
        sessions[player] = session
    end
    -- Repeated network replies/requests must never pay or charge twice.
    if session.results[args.requestId] then return session.results[args.requestId] end
    if args.requestId <= session.lastRequestId then
        result.reason = "Spin denied"
        return result
    end
    session.lastRequestId = args.requestId

    local function remember()
        session.results[args.requestId] = result
        session.order[#session.order + 1] = args.requestId
        if #session.order > 32 then
            session.results[table.remove(session.order, 1)] = nil
        end
        return result
    end

    local bet = tonumber(args.bet) or SLOTS.getDefaultBetAmount()
    if not SLOTS.isValidBetAmount(bet) then
        result.reason = "Invalid bet"
        return remember()
    end
    local now = getTimestampMs()
    if now < session.nextSpinAt then
        result.reason = "Please wait"
        return remember()
    end
    local square = SLOTS.getSquareFromArgs(args)
    if not square then
        result.reason = "Machine not found"
        return remember()
    end
    if not SLOTS.squareHasSlotMachine(square) then
        result.reason = "That is not a slot machine"
        return remember()
    end
    if not playerIsNearSquare(player, square) then
        result.reason = "Too far away"
        return remember()
    end
    local funds = SLOTS.getMoneyItems(player)
    if #funds < bet then
        result.reason = "Not enough money"
        return remember()
    end

    local reels, payout = SLOTS.roll(bet)
    -- Create winnings before touching the wager so a missing item script cannot
    -- consume money. The client receives the outcome, never authority to pay it.
    local winnings = {}
    for i = 1, payout do
        winnings[i] = instanceItem(SLOTS.moneyFull)
        if not winnings[i] then
            result.reason = "Could not create money"
            return remember()
        end
    end
    local inventory = player:getInventory()
    for i = 1, bet do
        player:removeFromHands(funds[i])
        inventory:Remove(funds[i])
        if isServer() then sendRemoveItemFromContainer(inventory, funds[i]) end
    end
    for _, item in ipairs(winnings) do
        inventory:AddItem(item)
        if isServer() then sendAddItemToContainer(inventory, item) end
    end
    if isServer() then sendEquip(player) end

    result.ok = true
    result.bet = bet
    result.r1, result.r2, result.r3 = reels[1], reels[2], reels[3]
    result.payout = payout
    result.balance = SLOTS.getMoney(player)
    session.nextSpinAt = now + SLOTS.serverSpinCooldownMs
    return remember()
end

if SlotsServer.onClientCommand then
    Events.OnClientCommand.Remove(SlotsServer.onClientCommand)
end
SlotsServer.onClientCommand = function(module, command, player, args)
    if module ~= SLOTS.moduleName or command ~= SLOTS.commands.spinRequest then return end
    if not player then return end
    local result = SlotsServer.spin(player, args)
    sendServerCommand(player, SLOTS.moduleName,
        result.ok and SLOTS.commands.spinResult or SLOTS.commands.spinDenied, result)
end
Events.OnClientCommand.Add(SlotsServer.onClientCommand)
print("[SLOTS] Server loaded (B42)")
