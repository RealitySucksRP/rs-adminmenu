local preview,epoch=nil,0
local function clearPreview()
    epoch=epoch+1
    if preview and DoesEntityExist(preview) then DeleteEntity(preview) end
    preview=nil
end
RSAdmin.ClearEntityPreview=clearPreview
RSAdmin.LocalActions.entityPreviewClear=function() clearPreview();return {ok=true} end
RSAdmin.LocalActions.entityPreview=function(d)
    clearPreview();local serial=epoch;local hash=joaat(d.model or '')
    if not IsModelInCdimage(hash) or not IsModelValid(hash) or (d.kind=='ped' and not IsModelAPed(hash)) or (d.kind~='ped' and (IsModelAPed(hash) or IsModelAVehicle(hash))) then return {ok=false,error='Model is unavailable or is the wrong entity type'} end
    RequestModel(hash);local untilAt=GetGameTimer()+5000
    while not HasModelLoaded(hash) and GetGameTimer()<untilAt and epoch==serial do Wait(0) end
    if epoch~=serial then SetModelAsNoLongerNeeded(hash);return {ok=false,error='Preview cancelled'} end
    if not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash);return {ok=false,error='Model loading timed out'} end
    local ped=PlayerPedId();local c=GetOffsetFromEntityInWorldCoords(ped,0.0,2.5,0.0)
    local ent=d.kind=='ped' and CreatePed(4,hash,c.x,c.y,c.z,GetEntityHeading(ped)+180.0,false,false) or CreateObjectNoOffset(hash,c.x,c.y,c.z,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    if not ent or ent==0 then return {ok=false,error='Preview could not be created'} end
    preview=ent;SetEntityAsMissionEntity(ent,true,true);SetEntityCollision(ent,false,false);FreezeEntityPosition(ent,true);SetEntityInvincible(ent,true);SetEntityAlpha(ent,180,false)
    if d.kind=='ped' then SetBlockingOfNonTemporaryEvents(ent,true) end
    return {ok=true,data={model=d.model,kind=d.kind,localOnly=true}}
end
RegisterNUICallback('codeRun',function(d,cb)
    RSAdmin.RPC('code:authorize',{scope=d.scope,code=d.code},function(result)
        if not result or not result.ok or d.scope=='server' then cb(result or {ok=false,error='No authorization response'});return end
        local good,response=pcall(RSAdminLua.Run,d.code,{scope='client',source=GetPlayerServerId(PlayerId())})
        cb(good and response or {ok=false,error=tostring(response):sub(1,1500)})
    end)
end)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then clearPreview() end end)
