RSAdmin.LocalActions = RSAdmin.LocalActions or {}
local enabled=false
RSAdmin.EntityLaser = RSAdmin.EntityLaser or {}
RSAdmin.EntityLaser.Set=function(v) enabled=v==true end

local function rotToDir(r)
    local rz=math.rad(r.z); local rx=math.rad(r.x); local c=math.abs(math.cos(rx)); return vector3(-math.sin(rz)*c,math.cos(rz)*c,math.sin(rx))
end

RSAdmin.LocalActions.toggleLaser=function()
    if not (RSAdmin.Can('developer') or RSAdmin.Can('owner')) then return {ok=false,error='Permission denied'} end
    enabled=not enabled; return {ok=true,enabled=enabled}
end

CreateThread(function()
    while true do
        if not enabled then Wait(350) else
            local p=PlayerPedId(); local start=GetGameplayCamCoord(); local dir=rotToDir(GetGameplayCamRot(2)); local dest=start+dir*250.0
            local ray=StartShapeTestRay(start.x,start.y,start.z,dest.x,dest.y,dest.z,-1,p,0)
            local _,hit,endCoords,_,ent=GetShapeTestResult(ray)
            if hit==1 then
                DrawLine(start.x,start.y,start.z,endCoords.x,endCoords.y,endCoords.z,60,190,255,220)
                DrawMarker(28,endCoords.x,endCoords.y,endCoords.z,0,0,0,0,0,0,0.12,0.12,0.12,60,190,255,180,false,true,2,false,nil,nil,false)
                if ent and ent~=0 then
                    local net=NetworkGetEntityIsNetworked(ent) and NetworkGetNetworkIdFromEntity(ent) or 0
                    local txt=('ENTITY  model:%s  net:%s  type:%s  [DELETE] remove'):format(GetEntityModel(ent),net,GetEntityType(ent))
                    SetTextFont(0); SetTextScale(0.32,0.32); SetTextCentre(true); SetTextOutline(); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(txt); EndTextCommandDisplayText(0.5,0.88)
                    if IsControlJustPressed(0,178) and net~=0 then RSAdmin.RPC('entity:deleteNet',{netId=net},function(r) if not r.ok then RSAdmin.Notify(r.error or 'Delete failed') end end) end
                end
            end
            Wait(0)
        end
    end
end)
