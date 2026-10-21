-- Visual tree-branch/litter storm field. Static GTA map-tree geometry cannot be
-- moved with ordinary entity forces. These nonnetworked debris props sell gusts
-- while preserving map objects, pedestrians, buildings and owned property.
local serial,objects=0,{}
local function clear()
    serial=serial+1
    for _,item in ipairs(objects) do
        local obj=item.entity
        if obj and DoesEntityExist(obj) then SetEntityAsMissionEntity(obj,true,true);DeleteEntity(obj) end
    end
    objects={}
end
local MODELS={'prop_roadcone02a','prop_bin_05a','prop_rub_binbag_01',
    'prop_tree_branch_01','prop_tree_branch_02','prop_pallet_02a','prop_rub_cardpile_01'}
local function modelFor(i,token)
    for n=1,#MODELS do
        if token~=serial then return nil end
        local hash=GetHashKey(MODELS[((i+n-2)%#MODELS)+1])
        if IsModelInCdimage(hash) and IsModelValid(hash) then
            RequestModel(hash)
            local untilTime=GetGameTimer()+400
            while token==serial and not HasModelLoaded(hash) and GetGameTimer()<untilTime do Wait(0) end
            if HasModelLoaded(hash) then return hash end
        end
    end
    return nil
end
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(d)
    if source~=65535 then return end
    clear()
    if type(d)~='table' or (d.name~='tornado' and d.name~='hurricane') or d.scope~='all' then return end
    local token=serial
    local isTornado=d.name=='tornado'
    local origin=d.origin or GetEntityCoords(PlayerPedId())
    local here=GetEntityCoords(PlayerPedId())
    -- Moving storm may reach a distant viewer later; wait for proximity instead of cancelling.
    local angle=math.rad(tonumber(d.gustDirection) or 90)
    local wx,wy=-math.sin(angle),-math.cos(angle)
    local count=math.max(4,math.min(16,(Config.Disasters.physics or {}).debris or 16))
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
        local initialGust=RSAdmin.StormGust(d,(tonumber(d.elapsed) or 0))
        local hurricaneBase={x=here.x+initialGust.x*45,y=here.y+initialGust.y*45,z=here.z}
        for i=1,count do
            if token~=serial then return end
            local hash=modelFor(i,token)
            if hash then
                local obj=CreateObjectNoOffset(hash,here.x,here.y,here.z+3,false,false,false)
                if obj and obj~=0 and DoesEntityExist(obj) then
                    SetEntityAsMissionEntity(obj,true,true)
                    SetEntityCollision(obj,false,false)
                    FreezeEntityPosition(obj,true)
                    objects[#objects+1]={entity=obj,index=i}
                end
                SetModelAsNoLongerNeeded(hash)
            end
            Wait(85)
        end
        while token==serial and GetGameTimer()-started<eventMs do
            local t=(GetGameTimer()-started)*.001
            local gust=RSAdmin.StormGust(d,(tonumber(d.elapsed) or 0)+t)
            local hx,hy=gust.x,gust.y
            local center=isTornado and movingCenter() or hurricaneBase
            for _,item in ipairs(objects) do
                local obj=item.entity
                if DoesEntityExist(obj) then
                    local i=item.index
                    local phase=t*(isTornado and 2 or 1.2)+i*2.39996
                    local x,y
                    if isTornado then
                        local radius=5+(i%6)*4+math.sin(t*.2+i)*2
                        x=center.x+math.cos(phase)*radius
                        y=center.y+math.sin(phase)*radius
                    else
                        local along=((t*(9+i%4*3+gust.strength*10)+i*7)%90)-45
                        x=center.x+hx*along-hy*math.sin(phase)*(4+i%6*2)
                        y=center.y+hy*along+hx*math.sin(phase)*(4+i%6*2)
                    end
                    local z=center.z+1.5+(i%5)*1.5+math.max(0,math.sin(t*.9+i))*9
                    SetEntityCoordsNoOffset(obj,x,y,z,false,false,false)
                    SetEntityRotation(obj,t*118+i*30,t*47+i*50,t*74+i*9,2,true)
                end
            end
            Wait(85)
        end
        if token==serial then clear() end
    end)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function() if source==65535 then clear() end end)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then clear() end end)
