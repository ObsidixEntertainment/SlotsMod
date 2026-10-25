-- Small PZ boundary doubles for deterministic regression tests under Lua 5.1.
clientMode, serverMode, now = false, false, 100000
function isClient() return clientMode end
function isServer() return serverMode end
function getTimestampMs() return now end
sounds, stoppedSounds = {}, {}
function getSoundManager()
    return {
        playUISound=function(_,name)
            sounds[#sounds+1]=name
            return #sounds
        end,
        stopUISound=function(_,handle) stoppedSounds[#stoppedSounds+1]=handle end,
    }
end
function require() end
function print() end
UIFont = {Small="Small", Medium="Medium", Large="Large", Huge="Huge"}

local function event()
    local e = {listeners={}}
    e.Add = function(f) e.listeners[f] = true end
    e.Remove = function(f) e.listeners[f] = nil end
    e.fire = function(...)
        local copy = {}
        for f in pairs(e.listeners) do copy[#copy+1] = f end
        for _, f in ipairs(copy) do f(...) end
    end
    return e
end
Events = {OnTick=event(), OnClientCommand=event(), OnServerCommand=event(),
    OnKeyPressed=event(), OnFillWorldObjectContextMenu=event()}

function list(values)
    local o = {values=values or {}}
    function o:size() return #self.values end
    function o:get(i) return self.values[i+1] end
    function o:isEmpty() return #self.values == 0 end
    return o
end
function instanceItem(fullType)
    if missingItem then return nil end
    return {getFullType=function() return fullType end}
end
function makeInventory(money)
    local inv = {items=list()}
    function inv:getItems() return self.items end
    function inv:AddItem(item)
        if type(item) == "string" then item = instanceItem(item) end
        self.items.values[#self.items.values+1] = item
        return item
    end
    function inv:AddItems(fullType, count)
        for _=1,count do self:AddItem(fullType) end
    end
    function inv:Remove(item)
        for i,v in ipairs(self.items.values) do
            if v == item then table.remove(self.items.values,i); return end
        end
        error("Attempt to remove absent item")
    end
    function inv:getItemsFromType(fullType)
        local items = {}
        for _,v in ipairs(self.items.values) do
            if v:getFullType() == fullType then items[#items+1] = v end
        end
        return list(items)
    end
    inv:AddItems("Base.Money", money or 0)
    return inv
end
function makePlayer(money)
    local p = {inv=makeInventory(money), x=10, y=20, z=0, dead=false, speech={}}
    function p:getInventory() return self.inv end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:isDead() return self.dead end
    function p:removeFromHands() end
    function p:Say(text) self.speech[#self.speech+1] = text end
    return p
end
function machine(spriteName, legacy)
    return {getSprite=function() return {getName=function() return spriteName end} end,
        getModData=function() return {SlotsB42Machine=legacy} end}
end
square = {objects=list({machine("recreational_01_16")})}
function square:getX() return 10 end
function square:getY() return 20 end
function square:getZ() return 0 end
function square:getObjects() return self.objects end
function getCell()
    return {getGridSquare=function(_,x,y,z)
        if x == 10 and y == 20 and z == 0 then return square end
    end}
end
function request(id, bet) return {requestId=id or 1, bet=bet or 5, x=10,y=20,z=0} end
packets = {add=0,remove=0,equip=0}
function sendAddItemToContainer() packets.add=packets.add+1 end
function sendRemoveItemFromContainer() packets.remove=packets.remove+1 end
function sendEquip() packets.equip=packets.equip+1 end
clientRequests, serverReplies = {}, {}
function sendClientCommand(player,module,command,args)
    clientRequests[#clientRequests+1] = {player=player,module=module,command=command,args=args}
end
function sendServerCommand(player,module,command,args)
    serverReplies[#serverReplies+1] = {player=player,module=module,command=command,args=args}
end

rngQueue, rngState = {}, 1234
function ZombRand(bound)
    if #rngQueue > 0 then
        local value = table.remove(rngQueue,1)
        assert(value >= 0 and value < bound, "Invalid test RNG value")
        return value
    end
    rngState = (rngState * 16807) % 2147483647
    return rngState % bound
end

ISPanel = {}
function ISPanel:derive()
    local class = {}
    class.__index = class
    return setmetatable(class,{__index=self})
end
function ISPanel:new(x,y,w,h)
    local o = {x=x,y=y,width=w,height=h,children={},visible=true,draws={}}
    return setmetatable(o,{__index=self})
end
function ISPanel:initialise() self.children = {} end
function ISPanel:createChildren() end
function ISPanel:addChild(child) self.children[#self.children+1] = child end
function ISPanel:addToUIManager() self.javaObject = {} end
function ISPanel:removeFromUIManager() self.removed=true end
function ISPanel:bringToTop() end
function ISPanel:setVisible(v) self.visible=v end
function ISPanel:prerender() end
function ISPanel:update() end
for _,name in ipairs({"drawRect","drawRectBorder","drawTextCentre","drawText","drawTextureScaled"}) do
    ISPanel[name] = function(self,...)
        local values={name}
        for _,v in ipairs({...}) do values[#values+1] = tostring(v) end
        self.draws[#self.draws+1] = table.concat(values, ":")
    end
end
ISButton = ISPanel:derive()
function ISButton:new(x,y,w,h,title,target,callback)
    local o = ISPanel.new(self,x,y,w,h)
    o.title,o.target,o.callback,o.enabled=title,target,callback,true
    return o
end
function ISButton:setEnable(v) self.enabled=v end
function ISButton:setTitle(v) self.title=v end
function getTexture(name) if texturesAvailable then return name end end
function openUI(money)
    player = makePlayer(money or 1000)
    toggleSlotUI(player,square)
    return SlotsMod.activeSlotUI
end
function snapshotUI(ui)
    ui.draws = {}
    ui:prerender()
    local lines = {table.concat({ui.x,ui.y,ui.width,ui.height}, ",")}
    for _,b in ipairs(ui.children) do
        lines[#lines+1] = table.concat({b.title,b.x,b.y,b.width,b.height,tostring(b.enabled)}, ",")
    end
    for _,line in ipairs(ui.draws) do lines[#lines+1]=line end
    return table.concat(lines,"\n")
end
function finishPresentation(ui)
    ui:prerender()
    now = now + 1550
    ui:update()
end
