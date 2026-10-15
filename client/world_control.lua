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
local function merged() local o={overrides={}};for k,v in pairs(W.state) do if k~='overrides' then o[k]=v end end;for k,v in pairs(W.state.overrides or {}) do o.overrides[k]=v end;for k,v in pairs((W.disaster and W.disaster.overlay) or {}) do o[k]=v;o.overrides[k]=true end;return o end
local function apply(s)
    local ownsWeather=controlled(s,'weather');local ownsTime=controlled(s,'hour') or controlled(s,'minute')
    if ownsWeather and not claimed.weather then previousWeather=GetNextWeatherTypeHashName() end
    if controlled(s,'wind') and not claimed.wind then previousWind=GetWindSpeed() end
    if ownsWeather and s.weather then SetWeatherTypePersist(s.weather);SetWeatherTypeNowPersist(s.weather);SetOverrideWeather(s.weather)
    elseif claimed.weather then ClearOverrideWeather();ClearWeatherTypePersist();restoreWeather(previousWeather) end
    if ownsTime then NetworkOverrideClockTime(math.floor(clamp(s.hour,0,23)),math.floor(clamp(s.minute or 0,0,59)),0)
    elseif claimed.time then NetworkClearClockTimeOverride() end
    if controlled(s,'blackout') then SetArtificialLightsState(s.blackout==true);SetArtificialLightsStateAffectsVehicles(false)
    elseif claimed.blackout then SetArtificialLightsState(false) end
    if controlled(s,'rain') then SetRainLevel(clamp(s.rain,-1,1)) elseif claimed.rain then SetRainLevel(-1) end
    if controlled(s,'wind') then SetWindSpeed(clamp(s.wind,0,20)) elseif claimed.wind then SetWindSpeed(previousWind or 0) end
    if controlled(s,'windDirection') then SetWindDirection((tonumber(s.windDirection) or 0)%360) end
    claimed={weather=ownsWeather,time=ownsTime,blackout=controlled(s,'blackout'),rain=controlled(s,'rain'),wind=controlled(s,'wind')}
end
exports('IsWorldControlled',function(key) local s=merged();return controlled(s,key) or (key=='time' and (controlled(s,'hour') or controlled(s,'minute'))) end)
RegisterNetEvent('rs-admin:client:worldState',function(d) for k,v in pairs(d or {}) do W.state[k]=v end; apply(merged()); SendNUIMessage({type='worldState',data=W.state}) end)
RSAdmin.LocalActions=RSAdmin.LocalActions or {}
RSAdmin.LocalActions.worldProbe=function()
    local function weatherName(hash)
        for _,name in ipairs(Config.WeatherTypes or {}) do if joaat(name)==hash then return name end end
        return tostring(hash)
    end
    local particles=0;for _,handle in ipairs(W.disaster and W.disaster.particles or {}) do if DoesParticleFxLoopedExist(handle) then particles=particles+1 end end
    return {ok=true,data={desired=W.state,previous=weatherName(GetPrevWeatherTypeHashName()),next=weatherName(GetNextWeatherTypeHashName()),rain=GetRainLevel(),wind=GetWindSpeed(),hour=GetClockHours(),minute=GetClockMinutes(),disaster=W.disaster and W.disaster.name or false,particles=particles}}
end
local function alive(serial) return W.disaster and W.serial==serial end
local function clearDisaster(d)
    if not d then return end
    for _,handle in ipairs(d.fires or {}) do pcall(RemoveScriptFire,handle) end
    for _,handle in ipairs(d.particles or {}) do pcall(StopParticleFxLooped,handle,false) end
end
local function water(path) if not path or path=='' then return false end; local ok,res=pcall(function() return LoadWaterFromPath(GetCurrentResourceName(),path) end); return ok and res~=false end
RegisterNetEvent('rs-admin:client:disaster',function(d)
    local restore=W.disaster and W.disaster.restore or {weather=GetNextWeatherTypeHashName(),wind=GetWindSpeed()}
    clearDisaster(W.disaster)
    W.serial=W.serial+1; local serial=W.serial; local seconds=math.max(5,math.min(Config.Disasters.maxSeconds or 120,math.floor(tonumber(d.seconds) or 30))); local intensity=clamp(d.intensity,.1,1); W.disaster={name=d.name,untilAt=GetGameTimer()+seconds*1000,overlay={}}
    local n=d.name; if n=='blackout' then W.disaster.overlay={blackout=true} elseif n=='thunderstorm' then W.disaster.overlay={weather='THUNDER',rain=1,wind=8} elseif n=='hurricane' then W.disaster.overlay={weather='THUNDER',rain=1,wind=12+8*intensity} elseif n=='tornado' then W.disaster.overlay={weather='THUNDER',rain=.6,wind=20} elseif n=='blizzard' then W.disaster.overlay={weather='BLIZZARD',rain=0,wind=8+8*intensity} elseif n=='sandstorm' then W.disaster.overlay={weather='SMOG',rain=0,wind=10+8*intensity} elseif n=='toxicfog' then W.disaster.overlay={weather='FOGGY',wind=1} elseif n=='emp' then W.disaster.overlay={blackout=true,weather='OVERCAST'} elseif n=='tsunami' then W.disaster.overlay={weather='THUNDER',rain=1,wind=8,blackout=true} end; apply(merged()); SendNUIMessage({type='disasterState',data={active=true,name=n,seconds=seconds}})
    W.disaster.fires={};W.disaster.particles={}
    W.disaster.restore=restore
    if n=='tornado' then CreateThread(function()
        RequestNamedPtfxAsset('core');local timeout=GetGameTimer()+3000
        while not HasNamedPtfxAssetLoaded('core') and GetGameTimer()<timeout and alive(serial) do Wait(0) end
        if not alive(serial) or not HasNamedPtfxAssetLoaded('core') then return end
        local origin=d.origin or GetEntityCoords(PlayerPedId());local handles={}
        for i=1,8 do
            UseParticleFxAssetNextCall('core');local handle=StartParticleFxLoopedAtCoord('ent_amb_fbi_smoke_fogball',origin.x,origin.y,origin.z+i*3.0,0.0,0.0,0.0,.35+i*.2,false,false,false,false)
            if handle and handle~=0 then handles[#handles+1]={handle=handle,layer=i};W.disaster.particles[#W.disaster.particles+1]=handle;SetParticleFxLoopedColour(handle,.2,.23,.26,false) end
        end
        while alive(serial) do local phase=GetGameTimer()*.0018;for _,fx in ipairs(handles) do local radius=fx.layer*.65;SetParticleFxLoopedOffsets(fx.handle,math.cos(phase+fx.layer*.7)*radius,math.sin(phase+fx.layer*.7)*radius,0.0,0.0,0.0,phase*30.0) end;Wait(80) end
    end) end
    if n=='tsunami' then CreateThread(function() local cfg=Config.Disasters.tsunami or {}; water(cfg.floodFile); Wait(cfg.riseDelayMs or 8000); if alive(serial) then ForceLightningFlash(); Wait(cfg.highWaterDelayMs or 12000); if alive(serial) then water(cfg.highWaterFile) end end end) end
    CreateThread(function()
        if not alive(serial) then return end
        local fires=W.disaster.fires
        while alive(serial) and GetGameTimer()<W.disaster.untilAt do
            local ped=PlayerPedId(); local c=GetEntityCoords(ped)
            if n=='earthquake' then ShakeGameplayCam('LARGE_EXPLOSION_SHAKE',.25+.55*intensity); if math.random()<.12*intensity then SetPedToRagdoll(ped,450,650,0,false,false,false) end; Wait(350)
            elseif n=='meteor' then AddExplosion(c.x+math.random(-55,55),c.y+math.random(-55,55),c.z+math.random(8,25),2,d.damage and intensity or 0.0,true,false,.6+intensity); Wait(math.floor(1500-800*intensity))
            elseif n=='tornado' then
                local origin=d.origin or c
                for _,candidate in ipairs(d.affectedVehicles or {}) do local e=NetworkGetEntityFromNetworkId(candidate.netId)
                    if e~=0 and DoesEntityExist(e) and NetworkHasControlOfEntity(e) and not Entity(e).state.vehicleid and GetEntityModel(e)==candidate.model and GetVehicleNumberPlateText(e)==candidate.plate and IsVehicleSeatFree(e,-1) and GetVehicleNumberOfPassengers(e)==0 then
                        local ec=GetEntityCoords(e);local dx,dy,dz=origin.x-ec.x,origin.y-ec.y,origin.z-ec.z;local ds=dx*dx+dy*dy+dz*dz
                        if ds<6400 and ds>9 then local inv=1/math.sqrt(ds);ApplyForceToEntityCenterOfMass(e,1,dx*inv*intensity*3,dy*inv*intensity*3,2.5+4*intensity,0,false,true,true,false) end
                    end
                end
                ShakeGameplayCam('ROAD_VIBRATION_SHAKE',.1+.2*intensity);Wait(220)
            elseif n=='firestorm' then if #fires<7 then local ok,h=pcall(function() return StartScriptFire(c.x+math.random(-30,30),c.y+math.random(-30,30),c.z,3,d.damage==true) end); if ok and h then fires[#fires+1]=h end end; Wait(1400)
            elseif n=='emp' then local count=0; for _,v in ipairs(GetGamePool('CVehicle')) do if count>=35 then break end; local ec=GetEntityCoords(v); local dx,dy,dz=c.x-ec.x,c.y-ec.y,c.z-ec.z; if dx*dx+dy*dy+dz*dz<22500 then SetVehicleEngineOn(v,false,true,true); count=count+1 end end; Wait(900)
            elseif n=='thunderstorm' or n=='hurricane' or n=='tsunami' then if math.random()<.25 then ForceLightningFlash() end; if n=='hurricane' then ShakeGameplayCam('ROAD_VIBRATION_SHAKE',.1+.15*intensity) end; Wait(900)
            else Wait(900) end
        end
        for _,h in ipairs(fires) do pcall(RemoveScriptFire,h) end; if alive(serial) then TriggerEvent('rs-admin:client:disasterStop',{}) end
    end)
end)
RegisterNetEvent('rs-admin:client:disasterStop',function()
    W.serial=W.serial+1;local old=W.disaster and W.disaster.name;local restore=W.disaster and W.disaster.restore
    clearDisaster(W.disaster);W.disaster=nil;StopGameplayCamShaking(true);apply(W.state)
    if restore then
        if not controlled(W.state,'weather') then for _,name in ipairs(Config.WeatherTypes or {}) do if joaat(name)==restore.weather then SetWeatherTypeNow(name);break end end end
        if not controlled(W.state,'wind') then SetWindSpeed(restore.wind) end
    end
    SendNUIMessage({type='disasterState',data={active=false,name=old}})
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
