--=============================================================
-- SLOTS MOD - SHARED CONFIG
-- Loaded by both client and server.
--=============================================================

local SlotsShared = _G.SlotsShared or {}
_G.SlotsShared = SlotsShared

SlotsShared.moduleName = "Slots"

SlotsShared.commands = {
    spinRequest = "SpinRequest",
    spinResult = "SpinResult",
    spinDenied = "SpinDenied",
}

SlotsShared.moneyFull = "Base.Money"
SlotsShared.moneyShort = "Money"

SlotsShared.slotMachineItem = "Base.SlotMachine"
SlotsShared.slotMachineSprite = "recreational_01_16"

SlotsShared.betAmount = 5
SlotsShared.betAmounts = {5, 15, 50, 75, 100}
SlotsShared.spinTicks = 45
SlotsShared.maxUseDistance = 3.5
SlotsShared.serverSpinCooldownMs = 750

SlotsShared.enableDebugButtons = false
SlotsShared.enableDebugKey = false
SlotsShared.enableGetMachineButton = false

SlotsShared.symbols = {"cash", "seven", "diamond", "skull"}

SlotsShared.basePayouts = {
    ["cash|skull|cash"] = 2,
    ["cash|cash|skull"] = 5,
    ["cash|cash|cash"] = 8,
    ["seven|cash|seven"] = 15,
    ["seven|seven|seven"] = 30,
    ["diamond|diamond|cash"] = 75,
    ["diamond|diamond|diamond"] = 150,
}

SlotsShared.jackpotKey = "diamond|seven|diamond"

SlotsShared.betTiers = {
    [5] = {
        payoutChancePercent = 50,
        payoutMultiplier = 1,
        jackpotPayout = 500,
    },
    [15] = {
        payoutChancePercent = 49,
        payoutMultiplier = 3,
        jackpotPayout = 2000,
    },
    [50] = {
        payoutChancePercent = 48,
        payoutMultiplier = 10,
        jackpotPayout = 8000,
    },
    [75] = {
        payoutChancePercent = 47,
        payoutMultiplier = 15,
        jackpotPayout = 15000,
    },
    [100] = {
        payoutChancePercent = 46,
        payoutMultiplier = 20,
        jackpotPayout = 25000,
    },
}

SlotsShared.payoutTiers = {
    {result = {"cash", "skull", "cash"}, weight = 300},
    {result = {"cash", "cash", "skull"}, weight = 300},
    {result = {"cash", "cash", "cash"}, weight = 240},
    {result = {"seven", "cash", "seven"}, weight = 100},
    {result = {"seven", "seven", "seven"}, weight = 40},
    {result = {"diamond", "diamond", "cash"}, weight = 15},
    {result = {"diamond", "diamond", "diamond"}, weight = 4},
    {result = {"diamond", "seven", "diamond"}, weight = 1},
}

SlotsShared.symbolDisplay = {
    cash = "$",
    seven = "7",
    diamond = "D",
    skull = "X",
    ["?"] = "?",
}

SlotsShared.symbolTextureCandidates = {
    cash = {
        "Item_Money",
        "media/textures/WorldItems/Money.png",
    },
    seven = {
        "media/ui/ClockAssets/ClockDigitsLarge7.png",
        "media/ui/ClockAssets/ClockDigitsMedium7.png",
    },
    diamond = {
        "Item_Ring_GoldDiamond",
        "Item_Earring_Dangly_Diamond",
        "Item_Necklace_GoldDiamond",
        "media/textures/EarringDiamond.png",
        "media/ui/LootableMaps/map_diamond.png",
    },
    skull = {
        "media/ui/LootableMaps/map_skull.png",
        "media/textures/Body/MakeUp/makeup_0013_skull1.png",
        "media/textures/BodyDmg/M_ZedDmg_FaceSkullLeft.png",
    },
}

SlotsShared.symbolColors = {
    cash = {r = 0.2, g = 1, b = 0.35},
    seven = {r = 1, g = 0.15, b = 0.1},
    diamond = {r = 0, g = 0.8, b = 1},
    skull = {r = 0.8, g = 0.8, b = 0.8},
    ["?"] = {r = 1, g = 1, b = 1},
}

function SlotsShared.getPayoutKey(result)
    return table.concat(result, "|")
end

function SlotsShared.getSymbolDisplay(symbol)
    return SlotsShared.symbolDisplay[symbol] or SlotsShared.symbolDisplay["?"]
end

function SlotsShared.getSymbolTextureCandidates(symbol)
    return SlotsShared.symbolTextureCandidates[symbol]
end

function SlotsShared.getSymbolColor(symbol)
    return SlotsShared.symbolColors[symbol] or SlotsShared.symbolColors["?"]
end

function SlotsShared.randomSymbol()
    return SlotsShared.symbols[ZombRand(#SlotsShared.symbols) + 1]
end

function SlotsShared.getDefaultBetAmount()
    return SlotsShared.betAmount
end

function SlotsShared.normalizeBetAmount(betAmount)
    local normalized = tonumber(betAmount) or SlotsShared.getDefaultBetAmount()
    if SlotsShared.betTiers[normalized] then
        return normalized
    end

    return SlotsShared.getDefaultBetAmount()
end

function SlotsShared.isValidBetAmount(betAmount)
    local normalized = tonumber(betAmount)
    return normalized ~= nil and SlotsShared.betTiers[normalized] ~= nil
end

function SlotsShared.getBetTier(betAmount)
    return SlotsShared.betTiers[SlotsShared.normalizeBetAmount(betAmount)]
end

function SlotsShared.rollPaysOut(betTier)
    local chance = math.max(0, math.min(100, betTier.payoutChancePercent or 0))
    return ZombRand(100) < chance
end

function SlotsShared.randomPayoutTier()
    local totalWeight = 0
    for _, entry in ipairs(SlotsShared.payoutTiers) do
        totalWeight = totalWeight + math.max(0, entry.weight or 0)
    end

    if totalWeight <= 0 then return nil end

    local roll = ZombRand(totalWeight) + 1
    local runningWeight = 0

    for _, entry in ipairs(SlotsShared.payoutTiers) do
        runningWeight = runningWeight + math.max(0, entry.weight or 0)
        if roll <= runningWeight then
            return entry
        end
    end

    return SlotsShared.payoutTiers[#SlotsShared.payoutTiers]
end

function SlotsShared.getPayout(result)
    local key = SlotsShared.getPayoutKey(result)
    local betTier = SlotsShared.getBetTier(SlotsShared.getDefaultBetAmount())

    if key == SlotsShared.jackpotKey then
        return betTier.jackpotPayout or 0
    end

    return (SlotsShared.basePayouts[key] or 0) * (betTier.payoutMultiplier or 1)
end

function SlotsShared.getPayoutForBet(result, betAmount)
    local key = SlotsShared.getPayoutKey(result)
    local betTier = SlotsShared.getBetTier(betAmount)

    if key == SlotsShared.jackpotKey then
        return betTier.jackpotPayout or 0
    end

    return (SlotsShared.basePayouts[key] or 0) * (betTier.payoutMultiplier or 1)
end

function SlotsShared.copyResult(result)
    return {result[1], result[2], result[3]}
end

function SlotsShared.rollPayoutResult(betAmount)
    local tier = SlotsShared.randomPayoutTier()
    if not tier then return {"cash", "cash", "cash"}, SlotsShared.getPayoutForBet({"cash", "cash", "cash"}, betAmount) end

    local result = SlotsShared.copyResult(tier.result)
    return result, SlotsShared.getPayoutForBet(result, betAmount)
end

function SlotsShared.rollLosingResult()
    for _ = 1, 12 do
        local result = {
            SlotsShared.randomSymbol(),
            SlotsShared.randomSymbol(),
            SlotsShared.randomSymbol(),
        }

        if SlotsShared.getPayout(result) <= 0 then
            return result, 0
        end
    end

    return {"skull", "cash", "seven"}, 0
end

function SlotsShared.roll(betAmount)
    betAmount = SlotsShared.normalizeBetAmount(betAmount)

    local betTier = SlotsShared.getBetTier(betAmount)

    if SlotsShared.rollPaysOut(betTier) then
        return SlotsShared.rollPayoutResult(betAmount)
    end

    return SlotsShared.rollLosingResult()
end

function SlotsShared.getSpriteName(obj)
    if not obj then return nil end

    local ok, spriteName = pcall(function()
        local sprite = obj:getSprite()
        if not sprite then return nil end
        return sprite:getName()
    end)

    if ok then return spriteName end
    return nil
end

function SlotsShared.isSlotMachineObject(obj)
    if SlotsShared.getSpriteName(obj) == SlotsShared.slotMachineSprite then return true end
    -- Keep machines placed with the earlier B42 test build usable in existing saves.
    return obj ~= nil and obj:getModData().SlotsB42Machine == true
end

function SlotsShared.squareHasSlotMachine(square)
    if not square then return false end

    local ok, objects = pcall(function()
        return square:getObjects()
    end)

    if not ok or not objects then return false end

    for i = 0, objects:size() - 1 do
        if SlotsShared.isSlotMachineObject(objects:get(i)) then
            return true
        end
    end

    return false
end

function SlotsShared.getSquareArgs(square)
    if not square then return nil end

    local ok, x, y, z = pcall(function()
        return square:getX(), square:getY(), square:getZ()
    end)

    if not ok then return nil end

    return {
        x = x,
        y = y,
        z = z,
    }
end

function SlotsShared.getSquareFromArgs(args)
    if type(args) ~= "table" then return nil end
    for _, key in ipairs({"x", "y", "z"}) do
        local value = args[key]
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge
            or value ~= math.floor(value) then
            return nil
        end
    end

    local ok, square = pcall(function()
        return getCell():getGridSquare(args.x, args.y, args.z)
    end)

    if ok then return square end
    return nil
end

-- B42 Base.Money is a normal item: each item represents one dollar.
-- Take a snapshot before removing items so inventory indexes cannot skip money.
function SlotsShared.getMoneyItems(player)
    local result = {}
    if not player then return result end
    local inventory = player:getInventory()
    if not inventory then return result end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == SlotsShared.moneyFull then
            result[#result + 1] = item
        end
    end
    return result
end

function SlotsShared.getMoney(player)
    return #SlotsShared.getMoneyItems(player)
end

print("[SLOTS] Shared loaded")
