local function openQuick()
    if RSAdmin.open then SendNUIMessage({type='quickOpen'}); return end
    local requestEpoch=RSAdmin.BeginBootstrap()
    RSAdmin.RPC('bootstrap',{},function(res)
        if not RSAdmin.BootstrapCurrent(requestEpoch) then return end
        if not res or not res.ok then if RSAdmin.Notify then RSAdmin.Notify(res and res.error or 'Access denied') end; return end
        if GetResourceState('qbx_core')=='started' and not (LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn==true) then return end
        RSAdmin.permissions=res.data.permissions or {}
        SendNUIMessage({type='bootstrap',data=res.data})
        RSAdmin.SetOpen(true)
        SetTimeout(150,function()
            if RSAdmin.BootstrapCurrent(requestEpoch) and RSAdmin.uiMode=='FULL' then SendNUIMessage({type='quickOpen'}) end
        end)
    end)
end
RegisterCommand((Config.QuickMenu and Config.QuickMenu.command) or 'fadminmenu',openQuick,false)
RegisterKeyMapping((Config.QuickMenu and Config.QuickMenu.command) or 'fadminmenu','Open RS Admin Quick Menu','keyboard',(Config.QuickMenu and Config.QuickMenu.keybind) or 'F10')
RegisterNetEvent('rs-admin:client:duty',function(d) SendNUIMessage({type='dutyState',data=d}) end)
RegisterNetEvent('rs-admin:client:staffChatChannel',function(d)
    SendNUIMessage({type='staffChatChannel',data=d})
    if not RSAdmin.open and RSAdmin.Notify then RSAdmin.Notify(('[%s] %s: %s'):format(d.channel or 'staff',d.name or 'Staff',d.message or '')) end
end)
