-- Client-local stunt-car collisions with STATIC map geometry and locally
-- created empty traffic. Actual local-car explosions occur only in a safe area.
-- Optional destructive network traffic requires a server-verified allowlist.
-- No player-owned, occupied, or mission vehicles are directly manipulated.
local Impact={serial=0,vehicles={},fx={},collisions=0,attempts=0,chains=0,traffic=0,payload=nil}
local models={'asea','emperor','primo','blista','stanier','ingot'}
local function untrack(list,item)
    for i=#list,1,-1 do if list[i]==item then table.remove(list,i);break end end
end
local function clear()
    Impact.serial=Impact.serial+1
    for _,v in ipairs(Impact.vehicles) do
        if DoesEntityExist(v) then SetEntityAsMissionEntity(v,true,true);DeleteEntity(v) end
    end
    for _,fx in ipairs(Impact.fx) do if fx and fx~=0 then pcall(StopParticleFxLooped,fx,false) end end
    Impact.vehicles={};Impact.fx={};Impact.collisions=0;Impact.attempts=0;Impact.chains=0;Impact.traffic=0;Impact.payload=nil
end
local function operator(id)
    local d=Impact.payload
    return d and d.previewOperator and tonumber(d.previewOperator)==GetPlayerServerId(id)
end
local function safeFromOthers(x,y,z,meters)
    for _,id in ipairs(GetActivePlayers()) do
        if not operator(id) then
            local p=GetPlayerPed(id)
            if p~=0 and DoesEntityExist(p) then
                local c=GetEntityCoords(p)
                if (c.x-x)^2+(c.y-y)^2+(c.z-z)^2<meters*meters then return false end
            end
        end
    end
    return true
end
local function validForImpact(x,y,z)
    for _,id in ipairs(GetActivePlayers()) do
        if not operator(id) then
        local ped=GetPlayerPed(id)
        if ped and ped~=0 and DoesEntityExist(ped) then
            local c=GetEntityCoords(ped)
            if (c.x-x)^2+(c.y-y)^2+(c.z-z)^2<45*45 then return false end
        end
        end
    end
    for _,vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and NetworkGetEntityIsNetworked(vehicle) then
            local c=GetEntityCoords(vehicle)
            if (c.x-x)^2+(c.y-y)^2+(c.z-z)^2<16*16 then
                local allowed=false
                local d=Impact.payload
                if d and d.destructiveTraffic==true then
                    local id=NetworkGetNetworkIdFromEntity(vehicle)
                    for _,row in ipairs(d.affectedVehicles or {}) do
                        if row.netId==id and GetEntityModel(vehicle)==row.model and
                           GetVehicleNumberPlateText(vehicle)==row.plate and
                           NetworkHasControlOfEntity(vehicle) and
                           not IsEntityAMissionEntity(vehicle) and not Entity(vehicle).state.vehicleid and
                           IsVehicleSeatFree(vehicle,-1) and GetVehicleNumberOfPassengers(vehicle)==0 then
                            allowed=true;break
                        end
                    end
                end
                if not allowed then return false end
            end
        end
    end
    return true
end
local function findStaticTarget(center,step)
    -- Map-world only (traceFlags=1): no peds, traffic or networked props.
    -- Raycast targets a real collision wall rather than inventing a facade.
    for heightStep=1,2 do
        local z=center.z+(heightStep==1 and 8.5 or 13.0)
        for n=1,10 do
            local a=(n/10)*math.pi*2+step*.47
            local dx,dy=math.cos(a),math.sin(a)
            local handle=StartExpensiveSynchronousShapeTestLosProbe(center.x,center.y,z,
                center.x+dx*102,center.y+dy*102,z,1,0,7)
            local state,hit,point,normal,entity=GetShapeTestResult(handle)
            if state==2 and hit and hit~=0 and point and (not entity or entity==0) then
                local distance=math.sqrt((point.x-center.x)^2+(point.y-center.y)^2)
                if distance>36 and distance<100 and validForImpact(point.x,point.y,point.z) then
                    return {point=point,dirX=dx,dirY=dy,distance=distance,z=z}
                end
            end
        end
    end
    return nil
end
local function protectDynamics(vehicle)
    -- Permit world collision and other local stunt doubles, but never physical
    -- collisions with networked/owned traffic or player characters.
    local count=0
    for _,other in ipairs(GetGamePool('CVehicle')) do
        if other~=vehicle and DoesEntityExist(other) and NetworkGetEntityIsNetworked(other) then
            SetEntityNoCollisionEntity(vehicle,other,false)
            count=count+1
            if count>=90 then break end
        end
    end
    for _,id in ipairs(GetActivePlayers()) do
        local ped=GetPlayerPed(id)
        if ped~=0 and DoesEntityExist(ped) then SetEntityNoCollisionEntity(vehicle,ped,false) end
    end
    count=0
    for _,ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and (IsEntityAMissionEntity(ped) or IsPedAPlayer(ped)) then
            SetEntityNoCollisionEntity(vehicle,ped,false)
            count=count+1
            if count>=75 then break end
        end
    end
end
local function physicalVictims(target,token)
    local victims={}
    local models={'blista','emperor'}
    for i,modelName in ipairs(models) do
        if token~=Impact.serial then break end
        local hash=GetHashKey(modelName)
        if IsModelInCdimage(hash) and IsModelAVehicle(hash) then
            RequestModel(hash)
            local deadline=GetGameTimer()+950
            while token==Impact.serial and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
            if token==Impact.serial and HasModelLoaded(hash) then
                -- Park near the actual wall, inside the incoming car's swept path.
                local perpX,perpY=-target.dirY,target.dirX
                local x=target.point.x-target.dirX*(5+i*3)+perpX*(i==1 and -2.5 or 2.5)
                local y=target.point.y-target.dirY*(5+i*3)+perpY*(i==1 and -2.5 or 2.5)
                local z=target.z-3.0
                local v=CreateVehicle(hash,x,y,z,math.deg(math.atan(target.dirY,target.dirX)),false,false)
                if v and v~=0 and DoesEntityExist(v) then
                    SetEntityAsMissionEntity(v,true,true)
                    SetEntityCollision(v,true,true)
                    FreezeEntityPosition(v,false)
                    SetVehicleEngineOn(v,false,true,true)
                    SetVehicleUndriveable(v,true)
                    SetEntityInvincible(v,false)
                    protectDynamics(v)
                    Impact.vehicles[#Impact.vehicles+1]=v
                    victims[#victims+1]=v
                end
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end
    return victims
end
local function clearVictims(victims)
    for _,v in ipairs(victims) do
        if DoesEntityExist(v) then SetEntityAsMissionEntity(v,true,true);DeleteEntity(v) end
        untrack(Impact.vehicles,v)
    end
end
local function canExplodeHere(pos)
    if not safeFromOthers(pos.x,pos.y,pos.z,55) then return false end
    for _,v in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(v) and NetworkGetEntityIsNetworked(v) then
            local c=GetEntityCoords(v)
            if (c.x-pos.x)^2+(c.y-pos.y)^2+(c.z-pos.z)^2<30*30 then return false end
        end
    end
    return true
end
local function explodeLocalVehicle(v,pos)
    if not DoesEntityExist(v) then return end
    if canExplodeHere(pos) then
        -- Actual GTA vehicle destruction, used ONLY on fresh, non-networked
        -- empty stunt doubles. Previewing operator has temporary protection.
        SetVehicleEngineHealth(v,-4000.0)
        ExplodeVehicle(v,true,false)
    else
        -- No uncontrollable native blast when real players/vehicles are close.
        SetVehicleEngineHealth(v,-4000.0)
    end
end
local function verifiedTrafficCascade(pos,d)
    if not d or d.destructiveTraffic~=true or d.scope~='all' then return end
    if not safeFromOthers(pos.x,pos.y,pos.z,65) then return end
    local verified={}
    for _,row in ipairs(d.affectedVehicles or {}) do verified[tonumber(row.netId) or -1]=row end
    -- Fail closed near an unverified networked car or occupied real traffic.
    for _,v in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(v) and NetworkGetEntityIsNetworked(v) then
            local c=GetEntityCoords(v)
            if (c.x-pos.x)^2+(c.y-pos.y)^2+(c.z-pos.z)^2<24*24 then
                local id=NetworkGetNetworkIdFromEntity(v)
                if not verified[id] then return end
                if not IsVehicleSeatFree(v,-1) or GetVehicleNumberOfPassengers(v)>0 or IsEntityAMissionEntity(v) then return end
            end
        end
    end
    local count=0
    local maxCars=math.max(0,math.min(2,tonumber((Config.Disasters.physics or {}).verifiedTrafficImpacts) or 2))
    for _,row in ipairs(d.affectedVehicles or {}) do
        if count>=maxCars then break end
        if row.netId and NetworkDoesEntityExistWithNetworkId(row.netId) then
            local v=NetworkGetEntityFromNetworkId(row.netId)
            if v and v~=0 and DoesEntityExist(v) and NetworkHasControlOfEntity(v) and
               not IsEntityAMissionEntity(v) and not Entity(v).state.vehicleid and
               GetEntityModel(v)==row.model and GetVehicleNumberPlateText(v)==row.plate and
               IsVehicleSeatFree(v,-1) and GetVehicleNumberOfPassengers(v)==0 then
                local c=GetEntityCoords(v)
                local ds=(c.x-pos.x)^2+(c.y-pos.y)^2+(c.z-pos.z)^2
                if ds<19*19 then
                    -- Real verified unowned empty vehicle, checked immediately
                    -- before the destructive native. Owner must opt in via NUI.
                    ApplyForceToEntityCenterOfMass(v,1,(c.x-pos.x)*4,(c.y-pos.y)*4,12,0,false,false,false)
                    SetVehicleEngineHealth(v,-4000.0)
                    ExplodeVehicle(v,true,false)
                    count=count+1
                    Impact.traffic=Impact.traffic+1
                end
            end
        end
    end
end
local function nonDamagingFire(pos)
    local nearby=validForImpact(pos.x,pos.y,pos.z)
    if nearby then
        -- Native supports ninth "noDamage" flag on supported builds.
        -- Damage scale remains zero even when the optional flag is ignored.
        AddExplosion(pos.x,pos.y,pos.z,7,0.0,true,false,.14,true)
    else
        -- If players / network vehicles entered the impact zone, use FX only.
        RequestNamedPtfxAsset('core')
        if HasNamedPtfxAssetLoaded('core') then
            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedAtCoord('exp_grd_vehicle',pos.x,pos.y,pos.z,0.0,0.0,0.0,1.0,false,false,false)
        end
    end
    if HasNamedPtfxAssetLoaded('core') then
        UseParticleFxAssetNextCall('core')
        local h=StartParticleFxLoopedAtCoord('ent_ray_heli_aprtmnt_l_fire',pos.x,pos.y,pos.z,
            0.0,0.0,0.0,.48,false,false,false,false)
        if h and h~=0 then
            Impact.fx[#Impact.fx+1]=h
            CreateThread(function() Wait(2300);pcall(StopParticleFxLooped,h,false);untrack(Impact.fx,h) end)
        end
    end
end
local function crashCar(center,token,step)
    if token~=Impact.serial then return false end
    local target=findStaticTarget(center,step)
    if not target then return false end -- Open ground: don't fake a building impact.
    local model=GetHashKey(models[1+(step%#models)])
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then return false end
    RequestModel(model)
    local deadline=GetGameTimer()+1300
    while token==Impact.serial and not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(0) end
    if token~=Impact.serial or not HasModelLoaded(model) then return false end
    local distance=math.max(23,target.distance-29)
    local x=center.x+target.dirX*distance
    local y=center.y+target.dirY*distance
    local z=target.z+3.0
    local v=CreateVehicle(model,x,y,z,math.deg(math.atan(target.dirY,target.dirX)),false,false)
    SetModelAsNoLongerNeeded(model)
    if not v or v==0 or not DoesEntityExist(v) then return false end
    Impact.vehicles[#Impact.vehicles+1]=v
    SetEntityAsMissionEntity(v,true,true)
    SetEntityInvincible(v,false)
    SetVehicleEngineOn(v,false,true,true)
    SetVehicleUndriveable(v,true)
    SetEntityCollision(v,true,true) -- Real WORLD collision.
    FreezeEntityPosition(v,false)
    protectDynamics(v)              -- Static wall and local stunt cars are physical.
    local victims=physicalVictims(target,token)
    local approach=math.max(23,math.min(40,target.distance-distance))
    SetEntityVelocity(v,target.dirX*approach,target.dirY*approach,-3.0)
    local untilAt=GetGameTimer()+2300
    local collided=false
    local impactPoint
    local nextProtection=GetGameTimer()+260
    while token==Impact.serial and GetGameTimer()<untilAt and DoesEntityExist(v) do
        if GetGameTimer()>=nextProtection then
            protectDynamics(v) -- new pedestrians/traffic entering during flight
            nextProtection=GetGameTimer()+260
        end
        local p=GetEntityCoords(v)
        local d2=(p.x-target.point.x)^2+(p.y-target.point.y)^2+(p.z-target.point.z)^2
        if HasEntityCollidedWithAnything(v) and d2<17*17 then
            collided=true;impactPoint=p;break
        end
        if d2<3.4*3.4 then
            -- Path met the verified static wall but collision callback may lag.
            collided=true;impactPoint=p;break
        end
        Wait(35)
    end
    if token==Impact.serial and collided and impactPoint then
        Impact.collisions=Impact.collisions+1
        nonDamagingFire(impactPoint)
        for i,victim in ipairs(victims) do
            if DoesEntityExist(victim) then
                -- Chain the physical car collision into further collisions.
                ApplyForceToEntityCenterOfMass(victim,1,target.dirX*(19+i*7),target.dirY*(19+i*7),5+i*3,0,false,false,false)
                Impact.chains=Impact.chains+1
            end
        end
        explodeLocalVehicle(v,impactPoint)
        verifiedTrafficCascade(impactPoint,Impact.payload)
        Wait(650)
        for _,victim in ipairs(victims) do
            if token~=Impact.serial then break end
            if DoesEntityExist(victim) then
                local c=GetEntityCoords(victim)
                nonDamagingFire(c)
                explodeLocalVehicle(victim,c)
            end
            Wait(280)
        end
    end
    if token==Impact.serial then clearVictims(victims) end
    if DoesEntityExist(v) then SetEntityAsMissionEntity(v,true,true);DeleteEntity(v) end
    untrack(Impact.vehicles,v)
    return collided
end
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(d)
    if source~=65535 then return end
    clear()
    if type(d)~='table' or (d.name~='tornado' and d.name~='hurricane') or
       d.scope~='all' or d.cinematicCars~=true or d.cinematicImpacts~=true then return end
    local token=Impact.serial
    Impact.payload=d
    local maxImpacts=math.min(4,math.max(0,tonumber((Config.Disasters.physics or {}).cinematicImpacts) or 3))
    if maxImpacts==0 then return end
    CreateThread(function()
        local started=GetGameTimer()
        local lifetime=math.max(5000,(tonumber(d.seconds) or 30)*1000)
        RequestNamedPtfxAsset('core')
        local countdown=GetGameTimer()+2500
        while token==Impact.serial and not HasNamedPtfxAssetLoaded('core') and GetGameTimer()<countdown do Wait(0) end
        Wait(8000)
        local done=0
        while token==Impact.serial and done<maxImpacts and GetGameTimer()-started<lifetime-2400 do
            local age=(tonumber(d.elapsed) or 0)+(GetGameTimer()-started)*.001
            local center=d.name=='tornado' and RSAdmin.StormCenter(d,age) or {x=GetEntityCoords(PlayerPedId()).x+RSAdmin.StormGust(d,age).x*52,y=GetEntityCoords(PlayerPedId()).y+RSAdmin.StormGust(d,age).y*52,z=GetEntityCoords(PlayerPedId()).z}
            local viewer=GetEntityCoords(PlayerPedId())
            if (viewer.x-center.x)^2+(viewer.y-center.y)^2<165*165 then
                Impact.attempts=Impact.attempts+1
                if crashCar(center,token,Impact.attempts) then done=done+1 end
            end
            Wait(6500)
        end
    end)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function() if source==65535 then clear() end end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then clear() end end)
RSAdmin.StormImpactStats=function() return {impacts=Impact.collisions,attempts=Impact.attempts,chainReactions=Impact.chains,verifiedTrafficExplosions=Impact.traffic,activeVehicles=#Impact.vehicles} end
