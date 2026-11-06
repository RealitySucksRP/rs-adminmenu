local preview,epoch=nil,0
local previewData
local function clearPreview()
    epoch=epoch+1
    if preview and DoesEntityExist(preview) then DeleteEntity(preview) end
    preview=nil
    previewData=nil
    SendNUIMessage({type='builderPreviewState',data={active=false}})
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
    previewData={model=d.model,kind=d.kind}
    SendNUIMessage({type='builderPreviewState',data={active=true,model=d.model,kind=d.kind}})
    return {ok=true,data={model=d.model,kind=d.kind,localOnly=true}}
end
local function finishPreview(cancelled)
    if not preview or not DoesEntityExist(preview) or not previewData then return {ok=false,error='No active placement preview'} end
    local coords=GetEntityCoords(preview)
    local draft={model=previewData.model,kind=previewData.kind,x=coords.x,y=coords.y,z=coords.z,w=GetEntityHeading(preview)}
    clearPreview()
    RSAdmin.SetUiMode('FULL')
    if not cancelled then SendNUIMessage({type='builderPreviewReady',data=draft}) end
    return {ok=true}
end
RSAdmin.LocalActions.entityPreviewFinish=function() return finishPreview(false) end
RSAdmin.LocalActions.entityPreviewCancel=function() return finishPreview(true) end
CreateThread(function()
    while true do
        if preview and DoesEntityExist(preview) and RSAdmin.uiMode=='DOCKED' and not RSAdmin.dockInteracting then
            for _,control in ipairs({10,11,24,25,27,38,44,51,52,172,173,174,175,200,201,202}) do DisableControlAction(0,control,true) end
            local coords=GetEntityCoords(preview)
            local step=(IsControlPressed(0,21) and 3.0 or .7)*math.min(GetFrameTime(),.05)
            local x,y,z=coords.x,coords.y,coords.z
            if IsDisabledControlPressed(0,174) then x=x-step end
            if IsDisabledControlPressed(0,175) then x=x+step end
            if IsDisabledControlPressed(0,172) then y=y+step end
            if IsDisabledControlPressed(0,173) then y=y-step end
            if IsDisabledControlPressed(0,10) then z=z+step end
            if IsDisabledControlPressed(0,11) then z=z-step end
            SetEntityCoordsNoOffset(preview,x,y,z,false,false,false)
            local turn=70.0*math.min(GetFrameTime(),.05)
            if IsDisabledControlPressed(0,44) then SetEntityHeading(preview,GetEntityHeading(preview)+turn) end
            if IsDisabledControlPressed(0,38) then SetEntityHeading(preview,GetEntityHeading(preview)-turn) end
            if IsDisabledControlJustPressed(0,201) then finishPreview(false)
            elseif IsDisabledControlJustPressed(0,202) then finishPreview(true) end
            Wait(0)
        else Wait(150) end
    end
end)
RegisterNUICallback('codeRun',function(d,cb)
    RSAdmin.RPC('code:authorize',{scope=d.scope,code=d.code},function(result)
        if not result or not result.ok or d.scope=='server' then cb(result or {ok=false,error='No authorization response'});return end
        local good,response=pcall(RSAdminLua.Run,d.code,{scope='client',source=GetPlayerServerId(PlayerId())})
        cb(good and response or {ok=false,error=tostring(response):sub(1,1500)})
    end)
end)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then clearPreview() end end)
