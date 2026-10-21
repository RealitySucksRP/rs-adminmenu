RSAdmin.World=RSAdmin.World or {state={},serial=0,disaster=nil}
local W=RSAdmin.World; for k,v in pairs((Config.World and Config.World.defaults) or {}) do W.state[k]=v end
W.state.overrides={}
local claimed={}
local previousWeather,previousWind
local function restoreWeather(hash)
    for _,name in ipairs(Config.WeatherTypes or {}) do if joaat(name)==hash then SetWeatherTypeNow(name);return end end
end
local function controlled(s,key) return type(s.overrides)=='table' and s.overrides[key]==true end
local function clamp(v,a,b) v=tonumber(v) or a; return v<a and a or v>b and b or v end
-- Lightweight, deterministic wind-field track, calculated from the server-approved
-- origin and the elapsed event age. No client invents a new disaster position.
-- Moving the funnel does not modify the world map or network-owned vehicles.
function RSAdmin.StormCenter(data, age)
    local pos=type(data.origin)=='table' and data.origin or GetEntityCoords(PlayerPedId())
    local speed=clamp(data.travelSpeed or 0,0,8)
    local seconds=math.max(0,tonumber(age) or 0)
    local heading=math.rad((tonumber(data.gustDirection) or 0)%360)
    local dx,dy=-math.sin(heading),-math.cos(heading)
    local drift=math.sin(seconds*.075+1.2)*math.min(7.0,speed*2.0)
    return {x=pos.x+dx*speed*seconds-dy*drift,
            y=pos.y+dy*speed*seconds+dx*drift,z=pos.z}
end
-- Deterministic, smooth, irregular hurricane wind field. One server-approved seed
-- makes the same direction/strength available to physics and visual actors;
-- viewers joining late use payload.elapsed to resume the same timeline.
function RSAdmin.StormGust(data, age)
    local base=(tonumber(data.gustDirection) or 0)%360
    if data.name~='hurricane' then
        local a=math.rad(base)
        return {heading=base,x=-math.sin(a),y=-math.cos(a),strength=1,burst=false}
    end
    local seed=(tonumber(data.gustSeed) or 71291)%999983
    local t=math.max(0,tonumber(age) or 0)
    -- Each sustained gust lasts twelve seconds. A 0.75s squall front changes
    -- bearing/power; the rest of the interval remains steady, not oscillating.
    local period=12.0
    local step=math.floor(t/period)
    local function random(k,salt)
        local v=math.sin((k+1)*12.9898+seed*.047+salt*78.233)*43758.5453
        return v-math.floor(v)
    end
    local function sample(k)
        return (base+(random(k,1)*2-1)*125)%360, .75+random(k,2)*.75
    end
    local prevHeading,prevPower=sample(step-1)
    local heading,power=sample(step)
    local fraction=(t-step*period)
    local blend=math.min(1.0,fraction/.75)
    local diff=((heading-prevHeading+180)%360)-180
    heading=(prevHeading+diff*blend)%360
    power=prevPower+(power-prevPower)*blend
    -- A briefly stronger gust accompanies each front; then stable force.
    local burst=fraction<1.25
    local strength=math.min(1.65,power+(burst and .22*(1-math.min(1,fraction/1.25)) or 0))
    local a=math.rad(heading)
    return {heading=heading,x=-math.sin(a),y=-math.cos(a),strength=strength,burst=burst}

end
local function merged()
    local o={overrides={}};for k,v in pairs(W.state) do if k~='overrides' then o[k]=v end end
    for k,v in pairs(W.state.overrides or {}) do o.overrides[k]=v end
    local fallback=W.state.fallback
    if fallback and fallback.enabled then
        for _,key in ipairs({'weather','rain','wind','windDirection'}) do if not controlled(W.state,key) then o[key]=fallback[key];o.overrides[key]=true end end
        if not controlled(W.state,'hour') and not controlled(W.state,'minute') then
            o.hour,o.minute,o.second=fallback.hour,fallback.minute,fallback.second;o.overrides.hour=true;o.overrides.minute=true
        end
    end
    for k,v in pairs((W.disaster and W.disaster.overlay) or {}) do o[k]=v;o.overrides[k]=true end
    return o
end
local function apply(s)
    local ownsWeather=controlled(s,'weather');local ownsTime=controlled(s,'hour') or controlled(s,'minute')
    if ownsWeather and not claimed.weather then previousWeather=GetNextWeatherTypeHashName() end
    if controlled(s,'wind') and not claimed.wind then previousWind=GetWindSpeed() end
    if ownsWeather and s.weather then SetWeatherTypePersist(s.weather);SetWeatherTypeNowPersist(s.weather);SetOverrideWeather(s.weather)
    elseif claimed.weather then ClearOverrideWeather();ClearWeatherTypePersist();restoreWeather(previousWeather) end
    if ownsTime then NetworkOverrideClockTime(math.floor(clamp(s.hour,0,23)),math.floor(clamp(s.minute or 0,0,59)),math.floor(clamp(s.second or 0,0,59)))
    elseif claimed.time then NetworkClearClockTimeOverride() end
    if controlled(s,'blackout') then SetArtificialLightsState(s.blackout==true);SetArtificialLightsStateAffectsVehicles(false)
    elseif claimed.blackout then SetArtificialLightsState(false) end
    if controlled(s,'rain') then SetRainLevel(clamp(s.rain,-1,1)) elseif claimed.rain then SetRainLevel(-1) end
    if controlled(s,'wind') then SetWindSpeed(clamp(s.wind,0,12)) elseif claimed.wind then SetWindSpeed(previousWind or 0) end
    if controlled(s,'windDirection') then SetWindDirection(math.rad((tonumber(s.windDirection) or 0)%360))
    elseif claimed.windDirection then SetWindDirection(-1.0) end
    claimed={weather=ownsWeather,time=ownsTime,blackout=controlled(s,'blackout'),rain=controlled(s,'rain'),wind=controlled(s,'wind'),windDirection=controlled(s,'windDirection')}
end
exports('IsWorldControlled',function(key) local s=merged();return controlled(s,key) or (key=='time' and (controlled(s,'hour') or controlled(s,'minute'))) end)
RSAdmin.RegisterServerEvent('rs-admin:client:worldState',function(d) if source~=65535 or type(d)~='table' then return end; for k,v in pairs(d) do W.state[k]=v end; apply(merged()); SendNUIMessage({type='worldState',data=W.state}) end)
-- Clock ticks do not rebuild NUI forms or discard an operator's edits.
RSAdmin.RegisterServerEvent('rs-admin:client:worldFallback',function(d) if source~=65535 or type(d)~='table' then return end;W.state.fallback=d;apply(merged()) end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStatus',function(d)
    if type(d)=='table' then SendNUIMessage({type='disasterStatus',data=d}) end
end)
RSAdmin.LocalActions=RSAdmin.LocalActions or {}
RSAdmin.LocalActions.worldProbe=function()
    local function weatherName(hash)
        for _,name in ipairs(Config.WeatherTypes or {}) do if joaat(name)==hash then return name end end
        return tostring(hash)
    end
    local particles=0;for _,handle in ipairs(W.disaster and W.disaster.particles or {}) do if DoesParticleFxLoopedExist(handle) then particles=particles+1 end end
    return {ok=true,data={desired=W.state,previous=weatherName(GetPrevWeatherTypeHashName()),next=weatherName(GetNextWeatherTypeHashName()),rain=GetRainLevel(),wind=GetWindSpeed(),hour=GetClockHours(),minute=GetClockMinutes(),disaster=W.disaster and W.disaster.name or false,particles=particles,physics={vehicleImpulses=W.disaster and W.disaster.vehicleImpulses or 0,npcRagdolls=W.disaster and W.disaster.npcRagdolls or 0,
        gust=W.disaster and W.disaster.gust or nil,
        props=RSAdmin.StormPhysicalPropStats and RSAdmin.StormPhysicalPropStats() or nil,
        cows=RSAdmin.StormCowStats and RSAdmin.StormCowStats() or nil,verifiedCars=W.disaster and W.disaster.verifiedCars or 0,unverifiedCars=W.disaster and W.disaster.unverifiedCars or 0,center=W.disaster and W.disaster.center or nil,travelSpeed=W.disaster and W.disaster.travelSpeed or 0,funnel=RSAdmin.StormFunnelStats and RSAdmin.StormFunnelStats() or nil,crashes=RSAdmin.StormImpactStats and RSAdmin.StormImpactStats() or nil,meteors=RSAdmin.MeteorVisualStats and RSAdmin.MeteorVisualStats() or nil}}}
end
local function alive(serial) return W.disaster and W.serial==serial end
local function clearDisaster(d)
    if not d then return end
    for _,handle in ipairs(d.fires or {}) do pcall(RemoveScriptFire,handle) end
    for _,handle in ipairs(d.particles or {}) do pcall(StopParticleFxLooped,handle,false) end
    -- Unlike a weather override, changed water quads can survive Stop.
    -- Reset only when this resource actually loaded a tsunami water file.
    if d.previewProtected then
        SetPlayerInvincible(PlayerId(),d.previousInvincible==true)
    end
    if d.waterChanged then
        local ok=pcall(ResetWater)
        if not ok then print('[rs-adminmenu] Water reset failed; inspect tsunami state before using this event again') end
    end
end
local function gustVehicle(e, origin, d, intensity, radius)
    if e==0 or not DoesEntityExist(e) or not NetworkHasControlOfEntity(e) or
       IsEntityAMissionEntity(e) or Entity(e).state.vehicleid or
       GetEntityModel(e)~=d.model or GetVehicleNumberPlateText(e)~=d.plate or
       not IsVehicleSeatFree(e,-1) or GetVehicleNumberOfPassengers(e)~=0 or
       IsEntityAttached(e) or GetEntitySpeed(e)>70 then return end
    local c=GetEntityCoords(e)
    local dx,dy=c.x-origin.x,c.y-origin.y
    local dist=math.sqrt(dx*dx+dy*dy)
    if dist<3 or dist>radius or math.abs(c.z-origin.z)>32 then return end
    local falloff=math.max(.15,1-dist/radius)
    local nx,ny=dx/dist,dy/dist
    local radians=math.rad(d.gustDirection or 0)
    local wx,wy=-math.sin(radians),-math.cos(radians)
    local lift=clamp(d.lift,0,1)
    local styleScale=d.style=='extreme' and 1.65 or d.style=='funny' and 1.30 or 1.0
    local power=intensity*falloff*styleScale*clamp(d.gustPower or 1,.25,1.8)*clamp(d.gustPower or 1,.25,1.8)
    -- Heavy verified vehicles resist launch; light verified vehicles rise first.
    -- Does not alter mass or damage the vehicle; no ownership-control requests.
    -- FiveM exposes vehicle mass through handling data, not GetEntityMass.
    -- Invalid/unsupported readings use neutral mass so storms keep working.
    local ok,mass=pcall(GetVehicleHandlingFloat,e,'CHandlingData','fMass')
    local massFactor=ok and type(mass)=='number' and mass>0 and mass<100000 and
        clamp(math.sqrt(mass/1450.0),.65,2.8) or 1.0
    power=power/massFactor
    -- One owner at a time applies impulses. No teleports or global gravity edits.
    local vortex=d.name=='tornado'
    local side=vortex and 26 or 3
    local pull=vortex and -13 or 0
    local thrust=vortex and 12 or 30
    local up=vortex and (9+34*lift) or (5+20*lift)
    if d.style=='funny' then up=up*1.55 end
    -- A moving storm applies its own acceleration independent of GTA weather cap.
    ApplyForceToEntityCenterOfMass(e,1,
        ((nx*pull-ny*side)+wx*thrust)*power,
        ((ny*pull+nx*side)+wy*thrust)*power,
        up*power,0,false,false,false)
    return true
end
-- Controlled ambient-ped launch, separate from GTA's capped native weather wind.
-- FiveM physics is ownership-sensitive; never seize network ownership or affect mission/player peds.
local function gustPeds(origin, d, intensity, serial)
    local radius=clamp(d.radius,15,80)
    local maxPeds=math.min(20,(Config.Disasters.physics or {}).maxPeds or 18)
    local processed,scanned,reacted=0,0,0
    local radians=math.rad(d.gustDirection or 0)
    local wx,wy=-math.sin(radians),-math.cos(radians)
    local lift=clamp(d.lift,0,1)
    for _,ped in ipairs(GetGamePool('CPed')) do
        if not alive(serial) then return reacted end
        scanned=scanned+1
        if processed>=maxPeds or scanned>220 then break end
        if ped~=PlayerPedId() and DoesEntityExist(ped) and not IsPedAPlayer(ped) and
           not IsPedDeadOrDying(ped,true) and not IsEntityAMissionEntity(ped) and
           not IsPedInAnyVehicle(ped,false) and not IsEntityAttached(ped) and
           GetInteriorFromEntity(ped)==0 and
           (not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped)) then
            local c=GetEntityCoords(ped)
            local dx,dy=c.x-origin.x,c.y-origin.y
            local dist=math.sqrt(dx*dx+dy*dy)
            if dist>1.5 and dist<radius and math.abs(c.z-origin.z)<18 then
                processed=processed+1
                if GetGameTimer()>=(d.pedCooldown[ped] or 0) then
                    d.pedCooldown[ped]=GetGameTimer()+4800+math.random(0,1500)
                    local falloff=.55+.45*(1-dist/radius)
                    local style=(d.style=='extreme' and 1.65 or d.style=='funny' and 1.30 or 1.0)*clamp(d.gustPower or 1,.25,1.8)
                    if math.random() < math.min(.94,(.56+.35*intensity)*falloff) then
                        local nx,ny=dx/dist,dy/dist
                        local vortex=d.name=='tornado'
                        local vx,vy
                        if vortex then
                            vx=(wx*9-nx*5-ny*18)*intensity*style*falloff
                            vy=(wy*9-ny*5+nx*18)*intensity*style*falloff
                        else
                            vx=wx*22*intensity*style*falloff
                            vy=wy*22*intensity*style*falloff
                        end
                        local vz=(vortex and 12 or 7)*intensity*style*falloff+(lift*(vortex and 9 or 5))
                        -- Initial ragdoll, then a short physical flight with repeated
                        -- impulses. Always stop for death, vehicle entry or ownership loss.
                        SetPedToRagdoll(ped,3500,4000,0,false,false,false)
                        reacted=reacted+1
                        local startHeight=c.z
                        CreateThread(function()
                            for i=1,18 do
                                if not alive(serial) or not DoesEntityExist(ped) or IsPedDeadOrDying(ped,true) or
                                   IsPedInAnyVehicle(ped,false) or IsEntityAMissionEntity(ped) or
                                   GetInteriorFromEntity(ped)~=0 or
                                   (NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped)) then break end
                                local now=GetEntityCoords(ped)
                                if now.z>startHeight+26 or math.abs(now.x-c.x)+math.abs(now.y-c.y)>100 then break end
                                local progress=i/18
                                local up=math.max(1.0,vz*(1-progress*.78))
                                local sideways=1-progress*.40
                                local ix,iy=clamp(vx*sideways,-27,27),clamp(vy*sideways,-27,27)
                                -- Velocity gives readable displacement; force supplies
                                -- rotation and engine collision response while ragdolled.
                                SetEntityVelocity(ped,ix,iy,up)
                                ApplyForceToEntityCenterOfMass(ped,1,ix*.65,iy*.65,up*.52,0,false,false,false)
                                Wait(105)
                            end
                        end)
                    end
                end
            end
        end
    end
    return reacted
end
-- Catalog references from rs-animegrab: GTA native stumble + freefall clips.
-- Never request an AnimeGrab scene, interrupt a paired scene, or depend on it.
-- Player characters are *not* forcibly ragdolled by storms. A brief, bounded
-- horizontal push and an optional stumble communicate gust force instead.
local function playerWindReaction(ped,gust,intensity,style,serial)
    if not alive(serial) or not DoesEntityExist(ped) then return end
    local styleBoost=style=='extreme' and 1.25 or style=='funny' and 1.1 or 1.0
    local vx=gust.x*math.min(4.2,1.8+intensity*2.0)*clamp(gust.strength,.3,1.65)*styleBoost
    local vy=gust.y*math.min(4.2,1.8+intensity*2.0)*clamp(gust.strength,.3,1.65)*styleBoost
    local old=GetEntityVelocity(ped)
    SetEntityVelocity(ped,clamp(old.x+vx,-8,8),clamp(old.y+vy,-8,8),clamp(old.z+.25, -6,3.0))
    if IsPedFalling(ped) or IsPedRagdoll(ped) or IsPedUsingAnyScenario(ped) then return end
    if IsEntityPlayingAnim(ped,'misscarsteal4@actor','stumble',3) then return end
    -- Only interrupt free-roaming normal movement, not other scripted animations.
    if GetEntitySpeed(ped)<3.0 then
        local dict='misscarsteal4@actor'
        RequestAnimDict(dict)
        local deadline=GetGameTimer()+420
        while alive(serial) and not HasAnimDictLoaded(dict) and GetGameTimer()<deadline do Wait(0) end
        if alive(serial) and HasAnimDictLoaded(dict) and DoesEntityExist(ped) and
           not IsPedInAnyVehicle(ped,false) and not IsPedFalling(ped) and
           not IsPedDeadOrDying(ped,true) and not IsPedUsingAnyScenario(ped) then
            TaskPlayAnim(ped,dict,'stumble',3.0,2.0,1050,0,0.0,false,false,false)
        end
        RemoveAnimDict(dict)
    end
end
local function water(path) if not path or path=='' then return false end; local ok,res=pcall(function() return LoadWaterFromPath(GetCurrentResourceName(),path) end); return ok and res~=false end
local stopDisaster
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(d)
    if source~=65535 or type(d)~='table' or type(d.name)~='string' then return end
    local restore=W.disaster and W.disaster.restore or {weather=GetNextWeatherTypeHashName(),wind=GetWindSpeed()}
    local localStart=GetGameTimer()
    local priorAge=clamp(d.elapsed or 0,0,Config.Disasters.maxSeconds or 600)
    local function tornadoCenter()
        return RSAdmin.StormCenter(d,priorAge+(GetGameTimer()-localStart)*.001)
    end
    clearDisaster(W.disaster)
    W.serial=W.serial+1; local serial=W.serial; local seconds=math.max(1,math.min(Config.Disasters.maxSeconds or 120,math.floor(tonumber(d.seconds) or 30))); local intensity=clamp(d.intensity,.1,1); W.disaster={name=d.name,eventId=d.eventId,untilAt=GetGameTimer()+seconds*1000,overlay={},pedCooldown={},restore=restore,verifiedCars=#(d.affectedVehicles or {}),unverifiedCars=d.unverifiedVehicles or 0,vehicleImpulses=0,npcRagdolls=0,center=d.origin,travelSpeed=d.travelSpeed or 0}
    local operatorPreview=d.previewOperator and GetPlayerServerId(PlayerId())==tonumber(d.previewOperator)
    if operatorPreview and (d.name=='tornado' or d.name=='hurricane') then
        local ok,old=pcall(GetPlayerInvincible,PlayerId())
        W.disaster.previousInvincible=ok and old==true or false
        W.disaster.previewProtected=true
        SetPlayerInvincible(PlayerId(),true)
    end
    local n=d.name; if n=='blackout' then W.disaster.overlay={blackout=true} elseif n=='thunderstorm' then W.disaster.overlay={weather='THUNDER',rain=1,wind=8} elseif n=='hurricane' then W.disaster.overlay={weather='THUNDER',rain=1,wind=12,windDirection=d.gustDirection or 0} elseif n=='tornado' then W.disaster.overlay={weather='THUNDER',rain=.85,wind=12,windDirection=d.gustDirection or 0} elseif n=='blizzard' then W.disaster.overlay={weather='BLIZZARD',rain=0,wind=8+8*intensity} elseif n=='sandstorm' then W.disaster.overlay={weather='SMOG',rain=0,wind=10+8*intensity} elseif n=='toxicfog' then W.disaster.overlay={weather='FOGGY',wind=1} elseif n=='emp' then W.disaster.overlay={blackout=true,weather='OVERCAST'} elseif n=='tsunami' then W.disaster.overlay={weather='THUNDER',rain=1,wind=8,blackout=true} end; apply(merged()); SendNUIMessage({type='disasterState',data={active=true,name=n,seconds=seconds}})
    W.disaster.fires={};W.disaster.particles={}
    W.disaster.restore=restore
    -- The visible vortex is now owned by disaster_funnel.lua. No duplicate smoke stacks.
    if n=='hurricane' and d.surge==true and d.scope=='all' then CreateThread(function()
        -- Optional map-wide water XML: intentionally NOT enabled by default.
        local cfg=Config.Disasters.tsunami or {}
        local elapsed=math.max(0,tonumber(d.elapsed) or 0)*1000
        local rise=math.max(5000,(Config.Disasters.physics or {}).surgeDelayMs or 14000)
        if elapsed<rise then Wait(rise-elapsed) end
        if alive(serial) and water(cfg.floodFile) then
            W.disaster.waterChanged=true
            print('[rs-adminmenu][storm] Hurricane storm-surge XML applied; ResetWater required at stop')
        end
    end) end
    if n=='tsunami' then CreateThread(function()
        local cfg=Config.Disasters.tsunami or {}
        local elapsed=clamp(d.elapsed or 0,0,seconds)*1000
        local rise=cfg.riseDelayMs or 8000
        local high=rise+(cfg.highWaterDelayMs or 12000)
        if elapsed>=high then
            if alive(serial) and water(cfg.highWaterFile) then W.disaster.waterChanged=true end
        else
            if alive(serial) and water(cfg.floodFile) then W.disaster.waterChanged=true end
            if elapsed<rise then Wait(rise-elapsed) end
            if alive(serial) then
                ForceLightningFlash()
                Wait(math.max(0,high-math.max(rise,elapsed)))
                if alive(serial) and water(cfg.highWaterFile) then W.disaster.waterChanged=true end
            end
        end
    end) end
    CreateThread(function()
        if not alive(serial) then return end
        local fires=W.disaster.fires
        while alive(serial) and GetGameTimer()<W.disaster.untilAt do
            local ped=PlayerPedId(); local c=GetEntityCoords(ped)
            if n=='earthquake' then ShakeGameplayCam('LARGE_EXPLOSION_SHAKE',.25+.55*intensity); if math.random()<.12*intensity then SetPedToRagdoll(ped,450,650,0,false,false,false) end; Wait(350)
            elseif n=='meteor' then Wait(750) -- Meteor model, falling path and impact visuals are owned by disaster_meteors.lua
            elseif n=='tornado' or n=='hurricane' then
                local origin=n=='tornado' and tornadoCenter() or (d.origin or c)
                W.disaster.center=origin
                local gust=RSAdmin.StormGust(d,priorAge+(GetGameTimer()-localStart)*.001)
                W.disaster.gust={direction=gust.heading,strength=gust.strength,burst=gust.burst}
                -- Apply weather wind direction on a 1-second budget, not every frame.
                if n=='hurricane' and GetGameTimer()>=(W.disaster.nextWindTick or 0) then
                    W.disaster.nextWindTick=GetGameTimer()+1000
                    W.disaster.overlay.windDirection=gust.heading
                    W.disaster.overlay.wind=clamp(5+7*gust.strength,0,12)
                    SetWindDirection(math.rad(gust.heading))
                    SetWindSpeed(W.disaster.overlay.wind)
                end
                if d.affectEntities==true and d.scope=='all' then
                    for _,candidate in ipairs(d.affectedVehicles or {}) do
                        if alive(serial) and type(candidate)=='table' and candidate.netId and
                           NetworkDoesEntityExistWithNetworkId(candidate.netId) then
                            local e=NetworkGetEntityFromNetworkId(candidate.netId)
                            local applied=gustVehicle(e,origin,{model=candidate.model,plate=candidate.plate,
                                gustDirection=gust.heading,gustPower=gust.strength,lift=d.lift,name=n,style=d.style},intensity,clamp(d.radius,15,80))
                            if applied then W.disaster.vehicleImpulses=W.disaster.vehicleImpulses+1 end
                        end
                    end
                end
                if d.affectPeds==true and d.scope=='all' and GetGameTimer()>=(W.disaster.nextPedTick or 0) then
                    W.disaster.nextPedTick=GetGameTimer()+math.max(400,(Config.Disasters.physics or {}).pedTickMs or 650)
                    local hits=gustPeds(n=='hurricane' and c or origin,{name=n,gustDirection=gust.heading,gustPower=gust.strength,lift=d.lift,radius=d.radius,style=d.style,
                        pedCooldown=W.disaster.pedCooldown},intensity,serial)
                    W.disaster.npcRagdolls=W.disaster.npcRagdolls+(hits or 0)
                end
                if not operatorPreview and d.affectPlayers==true and d.scope=='all' and
                   GetGameTimer()>=(W.disaster.nextPlayerTick or 0) and
                   not IsPedInAnyVehicle(ped,false) and not IsPedDeadOrDying(ped,true) and
                   GetInteriorFromEntity(ped)==0 and not IsPedSwimming(ped) and
                   not IsPedFalling(ped) and n~='meteor' then
                    W.disaster.nextPlayerTick=GetGameTimer()+((Config.Disasters.physics or {}).playerRagdollCooldownMs or 6500)
                    local nearStorm=n=='hurricane'
                    if n=='tornado' then
                        local pos=GetEntityCoords(ped)
                        local vx,vy=pos.x-origin.x,pos.y-origin.y
                        nearStorm=vx*vx+vy*vy < (clamp(d.radius,15,80)^2)
                    end
                    if nearStorm and math.random()<.22+intensity*.24 then
                        -- No fall-over-only ragdoll: gust pushes and a native stumble.
                        -- Animate in a short thread so entity scans never block on streaming.
                        local pedAtTrigger=ped
                        CreateThread(function() playerWindReaction(pedAtTrigger,gust,intensity,d.style,serial) end)
                    end
                end
                if not operatorPreview then ShakeGameplayCam('ROAD_VIBRATION_SHAKE',.1+.2*intensity) end
                if n=='hurricane' and math.random()<.18 then ForceLightningFlash() end
                Wait(math.max(120,(Config.Disasters.physics or {}).vehicleTickMs or 220))
            elseif n=='firestorm' then if #fires<7 then local ok,h=pcall(function() return StartScriptFire(c.x+math.random(-30,30),c.y+math.random(-30,30),c.z,3,d.damage==true) end); if ok and type(h)=='number' and h>0 then fires[#fires+1]=h end end; Wait(1400)
            elseif n=='emp' then if d.scope=='all' then local count=0; for _,v in ipairs(GetGamePool('CVehicle')) do if count>=35 then break end; if NetworkHasControlOfEntity(v) then local ec=GetEntityCoords(v); local dx,dy,dz=c.x-ec.x,c.y-ec.y,c.z-ec.z; if dx*dx+dy*dy+dz*dz<22500 then SetVehicleEngineOn(v,false,true,true); count=count+1 end end end end; Wait(900)
            elseif n=='thunderstorm' or n=='hurricane' or n=='tsunami' then if math.random()<.25 then ForceLightningFlash() end; if n=='hurricane' then ShakeGameplayCam('ROAD_VIBRATION_SHAKE',.1+.15*intensity) end; Wait(900)
            else Wait(900) end
        end
        if alive(serial) then stopDisaster() end
    end)
end)
stopDisaster=function()
    W.serial=W.serial+1
    local old=W.disaster and W.disaster.name
    local restore=W.disaster and W.disaster.restore
    clearDisaster(W.disaster)
    W.disaster=nil
    StopGameplayCamShaking(true)
    local base=merged()
    apply(base)
    if restore then
        if not controlled(base,'weather') then
            for _,name in ipairs(Config.WeatherTypes or {}) do
                if joaat(name)==restore.weather then SetWeatherTypeNow(name);break end
            end
        end
        if not controlled(base,'wind') then SetWindSpeed(restore.wind) end
    end
    SendNUIMessage({type='disasterState',data={active=false,name=old}})
end
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function()
    if source~=65535 then return end
    stopDisaster()
end)
CreateThread(function()
    local last=0
    while true do local s=merged();local density=controlled(s,'traffic') or controlled(s,'parked') or controlled(s,'randomVehicles') or controlled(s,'peds') or controlled(s,'scenarios');if density then
        if controlled(s,'traffic') then SetVehicleDensityMultiplierThisFrame(clamp(s.traffic,0,1)) end
        if controlled(s,'randomVehicles') then SetRandomVehicleDensityMultiplierThisFrame(clamp(s.randomVehicles,0,1)) end
        if controlled(s,'parked') then SetParkedVehicleDensityMultiplierThisFrame(clamp(s.parked,0,1)) end
        if controlled(s,'peds') then SetPedDensityMultiplierThisFrame(clamp(s.peds,0,1)) end
        if controlled(s,'scenarios') then SetScenarioPedDensityMultiplierThisFrame(clamp(s.scenarios,0,1),clamp(s.scenarios,0,1)) end
    end;if GetGameTimer()-last>=(Config.World.reassertMs or 2500) then last=GetGameTimer();apply(s) end;Wait(density and 0 or 180) end
end)
AddEventHandler('onResourceStop',function(res) if res~=GetCurrentResourceName() then return end;clearDisaster(W.disaster);W.disaster=nil;StopGameplayCamShaking(true);apply({overrides={}}) end)

CreateThread(function() Wait(1200); TriggerServerEvent('rs-admin:server:disasterSync') end)
