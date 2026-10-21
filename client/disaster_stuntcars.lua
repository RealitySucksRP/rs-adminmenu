-- Owner-authorized, client-local cinematic stunt doubles. They are never garage
-- vehicles, never networked and have NO collision with people or map geometry.
-- This is how populated storms can show multiple airborne vehicles without
-- touching protected/occupied vehicles. Strict lockdown may reject local creation.
local serial,actors=0,{}
local function clear()
    serial=serial+1
    for _,item in ipairs(actors) do
        local vehicle=item.entity
        if vehicle and DoesEntityExist(vehicle) then SetEntityAsMissionEntity(vehicle,true,true);DeleteEntity(vehicle) end
    end
    actors={}
end
local function loadModel(hash,token)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return false end
    RequestModel(hash)
    local deadline=GetGameTimer()+1800
    while serial==token and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
    return serial==token and HasModelLoaded(hash)
end
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(d)
    if source~=65535 then return end
    clear()
    if type(d)~='table' or (d.name~='tornado' and d.name~='hurricane') or
       d.cinematicCars~=true or d.scope~='all' then return end
    local token=serial
    local origin=d.origin or GetEntityCoords(PlayerPedId())
    local here=GetEntityCoords(PlayerPedId())
    -- Moving storm may reach a distant viewer later; wait for proximity instead of cancelling.
    local count=math.max(3,math.min(8,math.floor(tonumber((Config.Disasters.physics or {}).cinematicCars) or 8)))
    local models={'blista','asea','emperor','primo','stanier','ingot','regina','glendale'}
    local angle=math.rad(tonumber(d.gustDirection) or 90)
    local wx,wy=-math.sin(angle),-math.cos(angle)
    local isTornado=d.name=='tornado'
    local eventMs=math.max(5000,(tonumber(d.seconds) or 30)*1000) -- seconds is already remaining on late join
    CreateThread(function()
        local started=GetGameTimer()
        local function movingCenter()
            return RSAdmin.StormCenter(d,(tonumber(d.elapsed) or 0)+(GetGameTimer()-started)*.001)
        end
        if isTornado then
            while token==serial and GetGameTimer()-started<eventMs do
                local pos=movingCenter()
                local player=GetEntityCoords(PlayerPedId())
                if (player.x-pos.x)^2+(player.y-pos.y)^2<175*175 then break end
                Wait(500)
            end
        end
        if token~=serial or GetGameTimer()-started>=eventMs then return end
        -- For hurricanes every viewer sees a local effect near their own position.
        local firstGust=RSAdmin.StormGust(d,(tonumber(d.elapsed) or 0))
        local base=isTornado and movingCenter() or {x=here.x+firstGust.x*58,y=here.y+firstGust.y*58,z=here.z}
        for i=1,count do
            if token~=serial then break end
            local hash=GetHashKey(models[i])
            if loadModel(hash,token) then
                local x=base.x+(i%4)*5-12
                local y=base.y+math.floor((i-1)/4)*9-10
                local v=CreateVehicle(hash,x,y,base.z+4,0.0,false,false)
                if v and v~=0 and DoesEntityExist(v) then
                    SetEntityAsMissionEntity(v,true,true)
                    SetEntityCollision(v,false,false)
                    SetEntityInvincible(v,true)
                    FreezeEntityPosition(v,true)
                    actors[#actors+1]={entity=v,index=i}
                end
                SetModelAsNoLongerNeeded(hash)
            end
            Wait(110) -- bounded creation; no burst of 8 car models in one frame
        end
        while token==serial and GetGameTimer()-started<eventMs do
            local time=(GetGameTimer()-started)*.001
            local gust=RSAdmin.StormGust(d,(tonumber(d.elapsed) or 0)+time)
            local hx,hy=gust.x,gust.y
            local center=isTornado and movingCenter() or base
            -- Hurricane has a stationary scene anchor; wind travels across it.
            -- Do not create a perpetual orbit/eye above the previewing owner.
            for _,item in ipairs(actors) do
                local v=item.entity
                if DoesEntityExist(v) then
                    local i=item.index
                    local t=time+i*1.45
                    local phase=t*(isTornado and 1.12 or .53)+i*2.39996
                    local radius=(isTornado and 10 or 18)+(i%4)*5
                    local height=7+(i%5)*4+math.max(0,math.sin(t*.47+i))*(isTornado and 35 or 24)
                    local x,y
                    if isTornado then
                        local ejection=math.max(0,math.sin(t*.22+i*.81)-.65)*85
                        x=center.x+math.cos(phase)*radius+math.cos(phase)*ejection
                        y=center.y+math.sin(phase)*radius+math.sin(phase)*ejection
                    else
                        -- Gust lanes sweep cars sideways, not a stationary carousel.
                        local sweep=((t*(15+gust.strength*17)+i*13)%170)-85
                        x=center.x+hx*sweep-hy*math.sin(phase)*radius
                        y=center.y+hy*sweep+hx*math.sin(phase)*radius
                    end
                    SetEntityCoordsNoOffset(v,x,y,center.z+height,false,false,false)
                    SetEntityRotation(v,t*75+i*32,t*51+i*70,t*89+i*17,2,true)
                end
            end
            Wait(50)
        end
        if token==serial then clear() end
    end)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function() if source==65535 then clear() end end)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then clear() end end)
