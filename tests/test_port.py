"""Run with Python + lupa (lua51). Tests use engine boundary doubles, not the game."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
from lupa.lua51 import LuaRuntime

REFERENCE = ROOT / 'tests/reference/published-b41/media/lua'
PORT = ROOT / 'Contents/mods/SlotsB42/42/media/lua'

def runtime(reference=False, client=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / 'tests/support.lua').read_text(encoding='utf-8'))
    files = REFERENCE if reference else PORT
    lua.execute((files / 'shared/slotsshared.lua').read_text(encoding='utf-8-sig'))
    if not reference:
        lua.execute((files / 'server/slotsserver.lua').read_text(encoding='utf-8'))
    if client:
        lua.execute((files / 'client/slots.lua').read_text(encoding='utf-8-sig'))
    return lua

passed = []
def test(name, function):
    function()
    passed.append(name)
    print('PASS:', name)

def lua_test(code):
    def run():
        runtime(client=True).execute(code)
    return run

def payout_parity():
    ref, port = runtime(True), runtime()
    def outcomes(lua):
        return lua.execute(r'''
            local lines={}
            for _,bet in ipairs(SlotsShared.betAmounts) do
                for _=1,2000 do
                    local reels,payout=SlotsShared.roll(bet)
                    lines[#lines+1]=table.concat(reels,"|")..":"..payout
                end
            end
            return table.concat(lines,"\n")
        ''')
    assert outcomes(ref) == outcomes(port), 'Published roll outcomes changed'
    # Every declared win at every wager, including the maximum jackpot.
    for bet in [5,15,50,75,100]:
        for i in range(1,9):
            expr = f'SlotsShared.getPayoutForBet(SlotsShared.payoutTiers[{i}].result, {bet})'
            assert ref.eval(expr) == port.eval(expr)

def ui_parity():
    for textures in [False, True]:
        ref, port = runtime(True,True), runtime(client=True)
        for lua in [ref,port]:
            lua.globals().texturesAvailable = textures
            lua.execute('ui=openUI();')
        for bet in [5,15,50,75,100]:
            for lua in [ref,port]:
                lua.execute(f'ui:setBet({bet}); ui.result={{"cash","seven","diamond"}}')
            original = ref.eval('snapshotUI(ui)').splitlines()
            enhanced = port.eval('snapshotUI(ui)').splitlines()
            # Existing window, buttons, labels and symbol rendering stay in place;
            # result banners, reel highlighting and the sound toggle are additions.
            for line in original:
                if line.startswith(('drawRect',)):
                    continue
                assert line in enhanced, line

test('10,000 rolls and every payout match published B41', payout_parity)
test('published window, controls, labels and texture/fallback symbols retained', ui_parity)
test('all five jackpot tiers debit once, pay once and sync B42 inventory', lua_test('''
    serverMode=true
    for _,bet in ipairs(SlotsShared.betAmounts) do
        local p=makePlayer(1000)
        p.inv:AddItem("Base.WaterBottle")
        rngQueue={0,999}
        packets={add=0,remove=0,equip=0}
        local result=SlotsServer.spin(p,request(1,bet))
        assert(result.ok and result.payout==SlotsShared.betTiers[bet].jackpotPayout)
        assert(SlotsShared.getMoney(p)==1000-bet+result.payout)
        assert(packets.remove==bet and packets.add==result.payout and packets.equip==1)
        local replay=SlotsServer.spin(p,request(1,bet))
        assert(replay==result and packets.remove==bet and packets.add==result.payout)
        assert(p.inv:getItemsFromType("Base.WaterBottle"):size()==1)
    end
'''))
test('invalid wagers, distance, floors, missing machines and funds cannot consume money', lua_test('''
    local function denied(p,args,reason)
        local before=SlotsShared.getMoney(p)
        local result=SlotsServer.spin(p,args)
        assert(not result.ok and result.reason==reason, tostring(result.reason))
        assert(SlotsShared.getMoney(p)==before)
    end
    denied(makePlayer(4),request(),"Not enough money")
    denied(makePlayer(100),request(1,7),"Invalid bet")
    local p=makePlayer(100); p.x=30
    denied(p,request(),"Too far away")
    p=makePlayer(100); p.z=1
    denied(p,request(),"Too far away")
    local args=request(); args.x=10.5
    denied(makePlayer(100),args,"Machine not found")
    args=request(); args.x=0/0
    denied(makePlayer(100),args,"Machine not found")
    denied(makePlayer(100),false,"Spin denied")
    square.objects=list({machine("location_shop_accessories_01_19")})
    denied(makePlayer(100),request(),"That is not a slot machine")
'''))
test('legacy tagged B42 machines still work; missing money script does not eat wager', lua_test('''
    square.objects=list({machine("location_shop_accessories_01_19",true)})
    local p=makePlayer(100)
    rngQueue={0,0}
    assert(SlotsServer.spin(p,request()).ok)
    p=makePlayer(100); missingItem=true; rngQueue={0,0}
    assert(not SlotsServer.spin(p,request()).ok)
    assert(SlotsShared.getMoney(p)==100)
'''))
test('cooldown and expired replay IDs cannot debit twice', lua_test('''
    local p=makePlayer(1000)
    local result=SlotsServer.spin(p,request(1))
    assert(result.ok)
    local blocked=SlotsServer.spin(p,request(2))
    assert(not blocked.ok and blocked.reason=="Please wait")
    now=now+1000
    assert(SlotsServer.spin(p,request(2))==blocked)
    for id=3,38 do now=now+1000; assert(SlotsServer.spin(p,request(id)).ok) end
    local before=SlotsShared.getMoney(p)
    assert(not SlotsServer.spin(p,request(1)).ok)
    assert(SlotsShared.getMoney(p)==before)
'''))
test('MP client never debits or pays and ignores duplicate/unrelated replies', lua_test('''
    clientMode=true
    local ui=openUI(100)
    ui:onSpin()
    assert(#clientRequests==1 and SlotsShared.getMoney(player)==100)
    ui:onSpin(); ui:setBet(100)
    assert(#clientRequests==1 and ui.bet==5)
    ui:onSpinDenied({requestId=999,reason="Invalid bet"})
    assert(ui.pendingRequestId==1 and SlotsShared.getMoney(player)==100)
    clientMode=false; serverMode=true; rngQueue={0,0}
    local result=SlotsServer.spin(player,clientRequests[1].args)
    local balance=SlotsShared.getMoney(player)
    clientMode=true; serverMode=false
    Events.OnServerCommand.fire("Slots","SpinResult",result)
    Events.OnServerCommand.fire("Slots","SpinResult",result)
    assert(SlotsShared.getMoney(player)==balance)
    local callbacks=0; for _ in pairs(Events.OnTick.listeners) do callbacks=callbacks+1 end
    assert(callbacks==1)
    for _=1,45 do Events.OnTick.fire() end
    finishPresentation(ui)
    assert(not ui.spinning and ui.spinBtn.title=="SPIN")
    assert(player.speech[#player.speech]=="You won $2")
'''))

test('winnings stay hidden until rendered payout, then count up without changing inventory', lua_test('''
    local ui=openUI(100)
    rngQueue={0,999}; ui:onSpin()
    assert(SlotsShared.getMoney(player)==595 and ui.serverBalance==95)
    assert(ui.resultPayout==nil)
    for tick=1,45 do
        Events.OnTick.fire()
        assert(ui.serverBalance==95)
        if tick==25 then assert(ui.stoppedReels==1 and ui.result[1]=="diamond") end
        if tick==36 then assert(ui.stoppedReels==2 and ui.result[2]=="seven") end
    end
    assert(ui.phase=="reveal" and ui.resultPayout==500 and ui.spinning)
    -- A stalled renderer must not allow an unseen payout to raise the display.
    now=now+10000; ui:update(); assert(ui.serverBalance==95)
    ui:prerender()
    assert(snapshotUI(ui):find("JACKPOT! $500",1,true))
    now=now+649; ui:update(); assert(ui.serverBalance==95)
    now=now+451; ui:update(); assert(ui.serverBalance==345 and ui.phase=="counting")
    ui:onSpin(); ui:setBet(100); assert(ui.bet==5)
    now=now+450; ui:update()
    assert(ui.serverBalance==595 and not ui.spinning and SlotsShared.getMoney(player)==595)
    assert(player.speech[#player.speech]=="You won $500")
'''))

test('spin, three reel stops and result each cue once; losses and small returns stay clear', lua_test('''
    local ui=openUI(100)
    rngQueue={0,0}; ui:onSpin()
    for _=1,45 do Events.OnTick.fire() end
    assert(#sounds==5 and sounds[1]=="UIActivatePlayButton" and sounds[5]=="CashRegisterOpen")
    for i=2,4 do assert(sounds[i]=="UIActivateButton") end
    local drawing=snapshotUI(ui)
    assert(drawing:find("You won $2",1,true) and drawing:find("Net: -$3",1,true))
    finishPresentation(ui)
    assert(#sounds==5)
    sounds={}; rngQueue={99,0,1,2}; ui:onSpin()
    for _=1,45 do Events.OnTick.fire() end
    assert(ui.resultPayout==0 and sounds[5]=="CashRegisterClose")
    ui:prerender(); now=now+650; ui:update()
    assert(not ui.spinning and ui.phase=="result")
'''))

test('sound toggle and close stop cues; sound failures cannot break settlement', lua_test('''
    local ui=openUI(100)
    rngQueue={0,999}; ui:onSpin()
    ui:onToggleSound()
    assert(#stoppedSounds==1 and not SlotsMod.soundEnabled)
    for _=1,45 do Events.OnTick.fire() end
    assert(#sounds==1 and ui.phase=="reveal")
    ui:onExit()
    assert(next(Events.OnTick.listeners)==nil and SlotsShared.getMoney(player)==595)
    ui=openUI(100)
    ui:onToggleSound()
    function getSoundManager() error("audio unavailable") end
    rngQueue={0,0}; ui:onSpin()
    for _=1,45 do Events.OnTick.fire() end
    finishPresentation(ui)
    assert(not ui.spinning and SlotsShared.getMoney(player)==97)
    ui:onExit()
'''))

test('late MP inventory packets do not expose payout or snap balance back during reveal', lua_test('''
    clientMode=true
    local ui=openUI(100)
    ui:onSpin()
    local result={requestId=ui.pendingRequestId,bet=5,payout=500,balance=595,
        r1="diamond",r2="seven",r3="diamond"}
    ui:onSpinResult(result)
    assert(ui.serverBalance==95 and SlotsShared.getMoney(player)==100)
    for _=1,45 do Events.OnTick.fire() end
    finishPresentation(ui)
    assert(ui.serverBalance==595)
    now=now+1000; ui:update(); assert(ui.serverBalance==595)
    player.inv:AddItems("Base.Money",495)
    ui:update(); assert(ui.serverBalance==nil and SlotsShared.getMoney(player)==595)
'''))
test('MP denials and timeouts never refund money that was not charged', lua_test('''
    clientMode=true
    local ui=openUI(100)
    ui:onSpin()
    Events.OnServerCommand.fire("Slots","SpinDenied",{requestId=1,reason="Too far away"})
    assert(SlotsShared.getMoney(player)==100 and not ui.spinning)
    ui:onSpin()
    local id=ui.pendingRequestId
    for _=1,3 do now=now+15000; ui:update() end
    assert(#clientRequests==4)
    for i=2,4 do assert(clientRequests[i].args.requestId==id) end
    assert(not ui.pendingRequestId and not ui.spinning and SlotsShared.getMoney(player)==100)
'''))
test('closing or dying during animation cannot cancel a settled win or leave tick handlers', lua_test('''
    local ui=openUI(100)
    rngQueue={0,999}; ui:onSpin()
    local balance=SlotsShared.getMoney(player)
    assert(balance==595)
    ui:onExit()
    Events.OnTick.fire()
    assert(SlotsShared.getMoney(player)==balance and next(Events.OnTick.listeners)==nil)
    ui=openUI(100); rngQueue={0,0}; ui:onSpin(); player.dead=true
    Events.OnTick.fire()
    assert(ui.closed and next(Events.OnTick.listeners)==nil)
'''))
print(f'\n{len(passed)} regression groups passed (Lua 5.1 with PZ boundary doubles).')
