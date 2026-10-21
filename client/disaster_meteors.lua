-- RS AdminMenu meteors: angled rocks, GTA world-contact probing, AnimeGrab-style
-- crater and shock-ring, real impacts on eligible NPCs and verified unowned cars.
-- The visible crater is a timed ground overlay; vanilla map geometry is not dug out.
-- Meteor model and fragment entities are LOCAL; never take over owned vehicles.
local M={serial=0,session=nil,objects={},fragments={},fx={},craters={},active=0,impacts=0,seen={},blasts=0}
local function untrack(t,v)
    for i=#t,1,-1 do if t[i]==v then table.remove(t,i);return end end
end
local function clear()
    M.serial=M.serial+1
    for _,h in ipairs(M.fx) do if h and h~=0 then pcall(StopParticleFxLooped,h,false) end end
    for _,t in ipairs({M.objects,M.fragments}) do
        for _,e in ipairs(t) do
            if e and DoesEntityExist(e) then SetEntityAsMissionEntity(e,true,true);DeleteEntity(e) end
        end
    end
    M.objects={};M.fragments={};M.fx={};M.craters={};M.active=0;M.impacts=0;M.seen={};M.session=nil;M.blasts=0
end
local function seeded(seed)
    local state=math.floor(tonumber(seed) or 928735)%2147483647
    if state==0 then state=12345 end
    return function(a,b)
        state=(state*48271)%2147483647
        return a+state%(b-a+1)
    end
end
local function loadedModel(list,index,token)
    for n=1,#list do
        if token~=M.serial then return nil end
        local name=list[((index+n-2)%#list)+1]
        local hash=GetHashKey(name)
        if IsModelInCdimage(hash) and IsModelValid(hash) and not IsModelAVehicle(hash) and not IsModelAPed(hash) then
            RequestModel(hash)
            local untilAt=GetGameTimer()+950
            while token==M.serial and not HasModelLoaded(hash) and GetGameTimer()<untilAt do Wait(0) end
            if HasModelLoaded(hash) then return hash end
        end
    end
    return nil
end
local function fxLoop(name,x,y,z,size,obj)
    if not HasNamedPtfxAssetLoaded('core') then return nil end
    UseParticleFxAssetNextCall('core')
    local h
    if obj then h=StartParticleFxLoopedOnEntity(name,obj,x,y,z,0,0,0,size,false,false,false)
    else h=StartParticleFxLoopedAtCoord(name,x,y,z,0,0,0,size,false,false,false,false) end
    if h and h~=0 then M.fx[#M.fx+1]=h;return h end
end
local function stopFx(h)
    if h and h~=0 then pcall(StopParticleFxLooped,h,false);untrack(M.fx,h) end
end
local function timedFx(h,ms,token)
    if not h then return end
    CreateThread(function()
        Wait(ms)
        if token==M.serial then stopFx(h) end
    end)
end
local function oneShot(name,pos,scale)
    if not HasNamedPtfxAssetLoaded('core') then return end
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord(name,pos.x,pos.y,pos.z+.16,0,0,0,scale,false,false,false)
end
local function distance2(a,b)
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2
end
local function fragmentBurst(pos,token,index)
    -- Low actor budget; fragments can collide, fall and roll instead of freezing.
    local cfg=(Config.Disasters or {}).meteor or {}
    if #M.fragments>=14 then return end
    CreateThread(function()
        local models={'prop_rock_4_e','prop_rock_4_d','prop_rock_3_c'}
        local hash=loadedModel(models,index,token)
        if token~=M.serial or not hash then return end
        local created={}
        for j=1,math.min(4,14-#M.fragments) do
            if token~=M.serial then break end
            local phase=j*2.4+index*.41
            local o=CreateObjectNoOffset(hash,pos.x+math.cos(phase)*.8,pos.y+math.sin(phase)*.8,
                pos.z+1.2,false,false,false)
            if o and o~=0 and DoesEntityExist(o) then
                SetEntityAsMissionEntity(o,true,true)
                SetEntityCollision(o,true,true)
                -- Fragments hit world geometry and ambient entities but cannot
                -- physically injure a player or push registered network traffic.
                for _,id in ipairs(GetActivePlayers()) do
                    local playerPed=GetPlayerPed(id)
                    if playerPed~=0 then SetEntityNoCollisionEntity(o,playerPed,false) end
                end
                for _,vehicle in ipairs(GetGamePool('CVehicle')) do
                    if DoesEntityExist(vehicle) and NetworkGetEntityIsNetworked(vehicle) then
                        SetEntityNoCollisionEntity(o,vehicle,false)
                    end
                end
                FreezeEntityPosition(o,false)
                SetEntityHasGravity(o,true)
                ActivatePhysics(o)
                local v=8+(j%3)*3
                SetEntityVelocity(o,math.cos(phase)*v,math.sin(phase)*v,7+(j%3)*2)
                M.fragments[#M.fragments+1]=o
                created[#created+1]=o
            end
        end
        SetModelAsNoLongerNeeded(hash)
        Wait(4500)
        for _,o in ipairs(created) do
            if DoesEntityExist(o) then SetEntityAsMissionEntity(o,true,true);DeleteEntity(o) end
            untrack(M.fragments,o)
        end
    end)
end
local function isAmbient(ped)
    return DoesEntityExist(ped) and not IsPedAPlayer(ped) and
        not IsEntityAMissionEntity(ped) and not IsPedDeadOrDying(ped,true) and
        GetInteriorFromEntity(ped)==0 and
        (not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped))
end
local function damageAmbient(pos)
    local cfg=(Config.Disasters or {}).meteor or {}
    if cfg.damageNPCs==false then return end
    local scanned=0
    for _,ped in ipairs(GetGamePool('CPed')) do
        scanned=scanned+1
        if scanned>120 then break end
        if isAmbient(ped) then
            local c=GetEntityCoords(ped)
            local dx,dy,dz=c.x-pos.x,c.y-pos.y,c.z-pos.z
            local ds=math.sqrt(dx*dx+dy*dy)
            if ds<13 and math.abs(dz)<8 then
                local strength=math.max(.16,1-ds/13)
                ApplyDamageToPed(ped,math.floor(95*strength),false)
                SetPedToRagdoll(ped,600,1200,0,false,false,false)
                if ds>.25 then
                    ApplyForceToEntityCenterOfMass(ped,1,dx/ds*13*strength,dy/ds*13*strength,4.2*strength,0,false,false,false)
                end
            end
        end
    end
end
local function safeCarExplosion(v,pos)
    -- Explode real empty unowned traffic only when no player or other networked
    -- car is within the blast vicinity. All other hits still cause real damage.
    for _,id in ipairs(GetActivePlayers()) do
        local ped=GetPlayerPed(id)
        if ped and ped~=0 and DoesEntityExist(ped) and distance2(GetEntityCoords(ped),pos)<35*35 then
            return false
        end
    end
    local scanned=0
    for _,other in ipairs(GetGamePool('CVehicle')) do
        scanned=scanned+1
        if scanned>180 then return false end -- fail closed on dense streamed scenes
        if other~=v and DoesEntityExist(other) and NetworkGetEntityIsNetworked(other) and
            distance2(GetEntityCoords(other),pos)<30*30 then return false end
    end
    return true
end
local function damageEligibleTraffic(pos,rows)
    local cfg=(Config.Disasters or {}).meteor or {}
    if cfg.damageUnownedTraffic==false then return end
    local reviewed=0
    for _,row in ipairs(rows or {}) do
        if reviewed>=5 then break end
        reviewed=reviewed+1
        if row.netId and NetworkDoesEntityExistWithNetworkId(row.netId) then
            local v=NetworkGetEntityFromNetworkId(row.netId)
            if v and v~=0 and DoesEntityExist(v) and NetworkHasControlOfEntity(v) and
                not IsEntityAMissionEntity(v) and not Entity(v).state.vehicleid and
                GetEntityModel(v)==row.model and GetVehicleNumberPlateText(v)==row.plate and
                IsVehicleSeatFree(v,-1) and GetVehicleNumberOfPassengers(v)==0 then
                local c=GetEntityCoords(v)
                local dx,dy,dz=c.x-pos.x,c.y-pos.y,c.z-pos.z
                local dist=math.sqrt(dx*dx+dy*dy)
                if dist<12 and math.abs(dz)<7 then
                    local strength=math.max(.1,1-dist/12)
                    SetVehicleBodyHealth(v,math.max(0,GetVehicleBodyHealth(v)-950*strength))
                    SetVehicleEngineHealth(v,math.max(-4000,GetVehicleEngineHealth(v)-1100*strength))
                    if dist>.25 then
                        ApplyForceToEntityCenterOfMass(v,1,dx/dist*25*strength,dy/dist*25*strength,8*strength,0,false,false,false)
                    end
                    if dist<4.5 then
                        -- Destroy an EMPTY, specifically preverified unowned car.
                        -- A native explosive splash is deliberately avoided near players.
                        SetVehicleEngineHealth(v,-4000.0)
                        SetVehicleUndriveable(v,true)
                        if M.blasts<(tonumber(cfg.maxCarExplosions) or 3) and safeCarExplosion(v,pos) then
                            M.blasts=M.blasts+1
                            ExplodeVehicle(v,true,false)
                        end
                    end
                end
            end
        end
    end
end
local function localTraffic(pos)
    local cfg=(Config.Disasters or {}).meteor or {}
    if cfg.damageUnownedTraffic==false then return end
    local count=0
    for _,v in ipairs(GetGamePool('CVehicle')) do
        if count>=70 then break end
        count=count+1
        -- Never touch networked, mission, occupied or player-controlled cars
        -- unless they were expressly certified by the server list above.
        if DoesEntityExist(v) and not NetworkGetEntityIsNetworked(v) and
           not IsEntityAMissionEntity(v) and IsVehicleSeatFree(v,-1) and
           GetVehicleNumberOfPassengers(v)==0 then
            local c=GetEntityCoords(v)
            local d=distance2(c,pos)
            if d<10*10 and math.abs(c.z-pos.z)<6 then
                SetVehicleBodyHealth(v,math.max(0,GetVehicleBodyHealth(v)-760))
                SetVehicleEngineHealth(v,-3800)
                SetVehicleUndriveable(v,true)
                if M.blasts<(tonumber(cfg.maxCarExplosions) or 3) and safeCarExplosion(v,pos) then
                    M.blasts=M.blasts+1
                    ExplodeVehicle(v,true,false)
                end
            end
        end
    end
end
local function contactVisual(hit)
    local pos={x=hit.x,y=hit.y,z=hit.z}
    local here=GetEntityCoords(PlayerPedId())
    if distance2(here,pos)>265*265 then return end
    local token=M.serial
    local cfg=(Config.Disasters or {}).meteor or {}
    local now=GetGameTimer()
    M.craters[#M.craters+1]={pos=pos,born=now,expires=now+math.floor(math.min(25,tonumber(cfg.craterSeconds) or 12)*1000),
        radius=math.min(15,math.max(4,tonumber(cfg.craterRadius) or 9))}
    if #M.craters>10 then table.remove(M.craters,1) end
    -- Exactly the RS AnimeGrab approach: large concrete burst, dark flat marker
    -- and rapidly expanding ring. No fake claim of destructible GTA roads.
    oneShot('ent_dst_concrete_large',pos,3.5)
    oneShot('exp_grd_grenade_smoke',pos,1.4)
    oneShot('exp_grd_vehicle',pos,1.2)
    -- Audible VFX explosion has 0 damage; precise damage is verified separately.
    AddExplosion(pos.x,pos.y,pos.z,4,0.0,true,false,.35,true)
    local fire=fxLoop('ent_ray_heli_aprtmnt_l_fire',pos.x,pos.y,pos.z+.15,.72,nil)
    timedFx(fire,2600,token)
    fragmentBurst(pos,token,hit.index or 1)
    damageAmbient(pos)
    damageEligibleTraffic(pos,hit.verifiedVehicles)
    localTraffic(pos)
    if distance2(here,pos)<100*100 then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE',.19) end
end
-- Render the crater only while in view. AnimeGrab-style ground disc + shock ring.
CreateThread(function()
    while true do
        local waitMs=700
        local now=GetGameTimer()
        local here=GetEntityCoords(PlayerPedId())
        for i=#M.craters,1,-1 do
            local crater=M.craters[i]
            if now>=crater.expires then table.remove(M.craters,i)
            elseif distance2(here,crater.pos)<115*115 then
                waitMs=0
                local p=crater.pos
                DrawMarker(1,p.x,p.y,p.z+.025,0,0,0,0,0,0,
                    crater.radius,crater.radius,.28,18,18,18,160,false,false,2,false,nil,nil,false)
                local t=(now-crater.born)/480
                if t<1 then
                    local r=.25+(crater.radius*1.3)*t
                    DrawMarker(28,p.x,p.y,p.z+.25,0,0,0,0,0,0,
                        r,r,r,255,228,190,math.floor(190*(1-t)),false,false,2,false,nil,nil,false)
                end
            end
        end
        Wait(waitMs)
    end
end)
local function flight(d,plan,token,models,trails,fxReady,cfg)
    if token~=M.serial or M.active>=3 then return end
    local model=loadedModel(models,plan.index,token)
    if token~=M.serial or not model then return end
    local st,fn=plan.start,plan.target
    local rock=CreateObjectNoOffset(model,st.x,st.y,st.z,false,false,false)
    SetModelAsNoLongerNeeded(model)
    if not rock or rock==0 or not DoesEntityExist(rock) then return end
    M.active=M.active+1
    M.objects[#M.objects+1]=rock
    SetEntityAsMissionEntity(rock,true,true)
    SetEntityCollision(rock,false,false)
    FreezeEntityPosition(rock,true)
    local trailA,trailB,smoke
    if fxReady then
        trailA=fxLoop(trails[((plan.index-1)%#trails)+1],0,0,.2,.65,rock)
        trailB=fxLoop(trails[(plan.index%#trails)+1],0,0,-.95,.4,rock)
        smoke=fxLoop('ent_amb_fbi_smoke_fogball',0,0,.7,.40,rock)
    end
    local began=GetGameTimer()
    local duration=math.max(1800,math.min(5200,tonumber(cfg.fallMs) or 3200))
    local impact=nil
    local previous=st
    local ray=nil
    local emberTick=began+250
    while token==M.serial and DoesEntityExist(rock) and GetGameTimer()-began<duration do
        -- Async shape probes must complete before hit/end coordinates are valid.
        if ray then
            local result,hit,point=GetShapeTestResult(ray)
            if result==2 then
                ray=nil
                if hit and hit~=0 and point then impact={x=point.x,y=point.y,z=point.z};break end
            elseif result==0 then ray=nil end
        end
        local t=math.min(1,(GetGameTimer()-began)/duration)
        local now={x=st.x+(fn.x-st.x)*t,y=st.y+(fn.y-st.y)*t,
            z=st.z+(fn.z-st.z)*t}
        -- Probe upcoming space BEFORE moving the simulated rock; includes
        -- concrete/ground/building, never peds/vehicles (handled via blast).
        if not ray then
            ray=StartShapeTestLosProbe(previous.x,previous.y,previous.z,
                now.x+(fn.x-st.x)*.03,now.y+(fn.y-st.y)*.03,
                now.z+(fn.z-st.z)*.03,1,rock,7)
        end
        SetEntityCoordsNoOffset(rock,now.x,now.y,now.z,false,false,false)
        SetEntityRotation(rock,t*700,t*520,t*300,2,true)
        if fxReady and GetGameTimer()>=emberTick then
            oneShot(trails[(plan.index%#trails)+1],{x=now.x-(fn.x-st.x)*.02,
                y=now.y-(fn.y-st.y)*.02,z=now.z-(fn.z-st.z)*.02},.20)
            emberTick=GetGameTimer()+420
        end
        previous=now
        Wait(35)
    end
    if token==M.serial and not impact and ray then
        for _=1,3 do
            local status,hit,point=GetShapeTestResult(ray)
            if status==2 then
                if hit and hit~=0 and point then impact={x=point.x,y=point.y,z=point.z} end
                break
            end
            if status==0 then break end
            Wait(0)
        end
    end
    stopFx(trailA);stopFx(trailB);stopFx(smoke)
    if DoesEntityExist(rock) then SetEntityAsMissionEntity(rock,true,true);DeleteEntity(rock) end
    untrack(M.objects,rock)
    M.active=math.max(0,M.active-1)
    if token~=M.serial then return end
    if not impact then impact=fn end -- fallback if world collision is not streamed
    M.impacts=M.impacts+1
    if tonumber(d.meteorController)==GetPlayerServerId(PlayerId()) and d.meteorSession then
        TriggerServerEvent('rs-admin:server:meteorImpact',{
            x=impact.x,y=impact.y,z=impact.z,index=plan.index,session=d.meteorSession
        })
    end
end
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(d)
    if source~=65535 then return end
    clear()
    if type(d)~='table' or d.name~='meteor' then return end
    M.session=d.meteorSession
    local token=M.serial
    CreateThread(function()
        local cfg=(Config.Disasters or {}).meteor or {}
        local models=cfg.models or {'prop_rock_4_d'}
        local trails=cfg.trails or {'ent_ray_heli_aprtmnt_l_fire'}
        if #models==0 then models={'prop_rock_4_d'} end
        if #trails==0 then trails={'ent_ray_heli_aprtmnt_l_fire'} end
        local origin=d.origin or GetEntityCoords(PlayerPedId())
        local here=GetEntityCoords(PlayerPedId())
        if distance2(here,origin)>600*600 then return end
        RequestNamedPtfxAsset('core')
        local limit=GetGameTimer()+2500
        while token==M.serial and not HasNamedPtfxAssetLoaded('core') and GetGameTimer()<limit do Wait(0) end
        local fxReady=HasNamedPtfxAssetLoaded('core')
        local count=math.max(1,math.min(48,math.floor(tonumber(cfg.count) or 28)))
        local cadence=math.max(1100,math.floor(tonumber(cfg.spawnIntervalMs) or 1850))
        local eventMs=math.max(2000,(tonumber(d.seconds) or 180)*1000)
        local rand=seeded(d.meteorSeed or 98765)
        local plans={}
        -- Generate before creating workers so all clients use identical random
        -- targets and headings regardless of how quickly their models stream.
        for i=1,count do
            local a=rand(0,6283)/1000
            local dist=rand(12,math.floor(math.max(25,math.min(110,tonumber(cfg.radius) or 88))))
            local x=origin.x+math.cos(a)*dist
            local y=origin.y+math.sin(a)*dist
            local found,z=GetGroundZFor_3dCoord(x,y,origin.z+105,false)
            if not found then z=origin.z end
            local dz=rand(80,135)
            local side=rand(95,math.floor(math.max(100,math.min(220,tonumber(cfg.approachDistance) or 155))))
            local heading=rand(0,6283)/1000
            -- A minority of rocks come steeply down; most cross the skyline.
            if i%5==0 then side=rand(20,55) end
            plans[i]={index=i,
                start={x=x-math.cos(heading)*side,y=y-math.sin(heading)*side,z=z+dz},
                target={x=x,y=y,z=z+.15}}
        end
        local began=GetGameTimer()
        for _,plan in ipairs(plans) do
            if token~=M.serial or GetGameTimer()-began+5500>eventMs then break end
            if M.active<3 then
                CreateThread(function() flight(d,plan,token,models,trails,fxReady,cfg) end)
            end
            Wait(cadence)
        end
    end)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:meteorImpact',function(hit)
    if source~=65535 or type(hit)~='table' or not M.session or
       hit.session~=M.session or type(hit.x)~='number' or
       type(hit.y)~='number' or type(hit.z)~='number' or
       M.seen[hit.index] then return end
    M.seen[hit.index]=true
    contactVisual(hit)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function()
    if source==65535 then clear() end
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then clear() end
end)
RSAdmin.MeteorVisualStats=function()
    return {active=M.active,impacts=M.impacts,fragments=#M.fragments,craters=#M.craters,carExplosions=M.blasts}
end
