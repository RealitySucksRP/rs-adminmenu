local RESOURCE = GetCurrentResourceName()
local audit -- forward declaration; DATA.audit below is a table field, not this function
local DATA = {
    bans = {}, reports = {}, presets = {}, audit = {}
}
local rate = {}
local inFlight={}
local rejectedLogAt = {}
local handlers = {}
local privateBuckets = {}
local reportSeq = 0
local banSeq = 0
local Adapter = RSAdminServer and RSAdminServer.Adapter
local spectateSessions = {}
local reportCooldown = {}
local recoveredJson={}
local saveJson

local function loadJson(name, fallback)
    local raw = LoadResourceFile(RESOURCE, ('data/%s.json'):format(name))
    if raw and raw~='' then local good,parsed=pcall(json.decode,raw);if good and type(parsed)=='table' then return parsed end end
    local recovery=LoadResourceFile(RESOURCE,('data/%s.recovery.json'):format(name))
    if recovery and recovery~='' then
        local good,parsed=pcall(json.decode,recovery)
        if good and type(parsed)=='table' then recoveredJson[name]=parsed;if saveJson then saveJson(name,parsed) end;print(('[rs-adminmenu] Recovered %s from last valid snapshot'):format(name));return parsed end
    end
    return fallback
end

local dirtyJson = {}
local jsonRevision=0
local lastPersistenceWarning=0
local function writeVerified(path,value)
    local good=pcall(SaveResourceFile,RESOURCE,path,value,#value)
    if not good then return false end
    local readable,stored=pcall(LoadResourceFile,RESOURCE,path)
    return readable and stored==value
end
local function flushJson()
    local failed={}
    for name,entry in pairs(dirtyJson) do
        local good,encoded=pcall(json.encode,entry.value)
        local written,result=false,false
        if good then
            local path=('data/%s.json'):format(name);local previous=LoadResourceFile(RESOURCE,path);local backupGood=true
            if previous and previous~='' and previous~=encoded then
                local valid,parsed=pcall(json.decode,previous)
                if valid and type(parsed)=='table' then
                    backupGood=writeVerified(('data/%s.recovery.json'):format(name),previous)
                end
            end
            if backupGood then written=true;result=writeVerified(path,encoded) end
        end
        if good and written and result==true then
            if dirtyJson[name]==entry then dirtyJson[name]=nil end
        else failed[#failed+1]=name end
    end
    if #failed>0 and GetGameTimer()-lastPersistenceWarning>=10000 then
        lastPersistenceWarning=GetGameTimer();print(('[rs-adminmenu] Persistence pending; retrying: %s'):format(table.concat(failed,', ')))
    end
    return #failed==0,failed
end
saveJson=function(name,value)
    jsonRevision=jsonRevision+1;dirtyJson[name]={value=value,revision=jsonRevision}
    -- Critical state is written immediately. Audit/stats batches also flush
    -- before RPC acknowledgement, with the timer retaining failed writes.
    if name~='audit' and name~='stats' and name~='activity' then return flushJson() end
    return true
end
CreateThread(function() while true do Wait(1000); flushJson() end end)

DATA.bans = loadJson('bans', {})
DATA.reports = loadJson('reports', {})
DATA.presets = loadJson('presets', {})
DATA.audit = loadJson('audit', {})
for _, r in ipairs(DATA.reports) do reportSeq = math.max(reportSeq, tonumber(r.id) or 0) end
for _, b in ipairs(DATA.bans) do banSeq = math.max(banSeq, tonumber(b.id) or 0) end
for name,value in pairs(recoveredJson) do saveJson(name,value) end

local function clean(s, maxLen)
    s = tostring(s or ''):gsub('[\r\n\0]', ' ')
    return s:sub(1, maxLen or Config.Security.maxString)
end

local function identifiers(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src)) do out[#out+1] = id end
    return out
end

local function hasOwnerIdentifier(src)
    local ids = identifiers(src)
    for _, allowed in ipairs(Config.OwnerIdentifiers or {}) do
        for _, id in ipairs(ids) do if id == allowed then return true end end
    end
    return false
end

local function frameworkFallback(src)
    if not Config.FrameworkPermissionFallback then return false end
    if GetResourceState('qbx_core') == 'started' then
        return IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'god') or IsPlayerAceAllowed(src, 'group.admin')
    end
    if GetResourceState('qb-core') == 'started' then
        local ok, qb = pcall(function() return exports['qb-core']:GetCoreObject({'Functions'}) end)
        if ok and qb and qb.Functions and qb.Functions.HasPermission then
            local good = false
            pcall(function() good = qb.Functions.HasPermission(src, 'god') or qb.Functions.HasPermission(src, 'admin') end)
            if good then return true end
        end
    end
    if GetResourceState('es_extended') == 'started' then
        local ok, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and esx and esx.GetPlayerFromId then
            local x = esx.GetPlayerFromId(src)
            if x and x.getGroup then
                local g = x.getGroup()
                return g == 'superadmin' or g == 'admin'
            end
        end
    end
    return false
end

local function can(src, node)
    if src == 0 then return true end
    if hasOwnerIdentifier(src) then return true end
    if IsPlayerAceAllowed(src, Config.Ace.owner) then return true end
    if IsPlayerAceAllowed(src, 'rsadmin.all') then return true end
    if node and RSAdminServer and RSAdminServer.RoleAllows and RSAdminServer.RoleAllows(src,node) then return true end
    if node and Config.Ace[node] and IsPlayerAceAllowed(src, Config.Ace[node]) then return true end
    if node == 'chat' and Config.Ace.open and IsPlayerAceAllowed(src, Config.Ace.open) then return true end
    if (node == 'open' or node == 'chat') and frameworkFallback(src) then return true end
    return false
end

local function targetProtected(src, target)
    if src == 0 or can(src, 'owner') or not Config.ProtectOwnerFromControl then return false end
    return can(target, 'owner') or IsPlayerAceAllowed(target, 'rsadmin.all')
end

local function isPlayerPedEntity(ent)
    if not ent or ent == 0 then return false end
    for _, s in ipairs(GetPlayers()) do
        if GetPlayerPed(tonumber(s)) == ent then return true end
    end
    return false
end

local function entityWithinRange(src, ent, maxDistance)
    local ped=GetPlayerPed(src)
    if ped==0 or ent==0 then return false end
    local a=GetEntityCoords(ped); local b=GetEntityCoords(ent)
    local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
    return (dx*dx+dy*dy+dz*dz) <= (maxDistance*maxDistance)
end
local function protectedVehicleOccupant(src,vehicle)
    for _,id in ipairs(GetPlayers()) do
        local player=tonumber(id);local ped=GetPlayerPed(player)
        if ped and ped~=0 and GetVehiclePedIsIn(ped,false)==vehicle and targetProtected(src,player) then return true end
    end
    return false
end
local function entityAccess(src,ent)
    if GetEntityRoutingBucket(ent)~=GetPlayerRoutingBucket(src) then return false,'Entity is in another routing bucket' end
    if GetEntityType(ent)==2 and protectedVehicleOccupant(src,ent) then return false,'Owner-protected player is inside this vehicle' end
    return true
end

local function permissionMap(src)
    local out = {}
    for k in pairs(Config.Ace) do out[k] = can(src, k) end
    out.all = IsPlayerAceAllowed(src, 'rsadmin.all') or can(src, 'owner')
    return out
end

audit = function(src, action, detail, target)
    local row = {
        at = os.time(), source = src, staff = src > 0 and GetPlayerName(src) or 'console',
        action = clean(action, 80), detail = clean(detail, 300), target = clean(target, 128)
    }
    DATA.audit[#DATA.audit+1] = row
    while #DATA.audit > Config.Security.auditLimit do table.remove(DATA.audit, 1) end
    saveJson('audit', DATA.audit)
    if RSAdminServer and RSAdminServer.OnAudit then pcall(RSAdminServer.OnAudit,row) end
    print(('[rs-adminmenu] %s -> %s %s'):format(row.staff or '?', row.action, row.detail))
end

local function ok(data) return {ok=true, data=data} end
local function err(msg) return {ok=false, error=msg} end

local function allowRate(src)
    local now = GetGameTimer()
    local b = rate[src]
    if not b or now >= b.untilAt then
        rate[src] = {count=1, untilAt=now + Config.Security.windowMs}
        return true
    end
    b.count = b.count + 1
    return b.count <= Config.Security.maxRequests
end

-- Bound the complexity of untrusted client RPC tables before calling handlers.
-- This also bounds recursion/serialization work for forged nested payloads.
local function validRpcPayload(root)
    local stack={{value=root,depth=0}}
    local fields,bytes=0,0
    local seen={}
    local security=Config.Security or {}
    while #stack>0 do
        local entry=table.remove(stack)
        local v=entry.value
        if type(v)=='table' then
            if seen[v] or entry.depth>=(security.maxRpcDepth or 10) then return false end
            seen[v]=true
            for k,item in pairs(v) do
                fields=fields+1
                if fields>(security.maxRpcFields or 2048) then return false end
                if type(k)=='string' then
                    if #k>128 then return false end
                    bytes=bytes+#k
                elseif type(k)~='number' or k~=k or k==math.huge or k==-math.huge then return false end
                local kind=type(item)
                if kind=='string' then
                    if #item>(security.maxRpcStringBytes or 16384) then return false end
                    bytes=bytes+#item
                elseif kind=='table' then
                    stack[#stack+1]={value=item,depth=entry.depth+1}
                elseif kind=='number' and (item~=item or item==math.huge or item==-math.huge) then
                    return false
                elseif kind~='number' and kind~='boolean' and kind~='nil' then
                    return false
                end
                if bytes>(security.maxRpcTotalBytes or 65536) then return false end
            end
        end
    end
    return true
end

-- A malicious client may keep sending RPCs after exceeding the rate limit.
-- Log and webhook only the first rejected attempt per interval per player.
local function auditRejected(src,category,name)
    local now=GetGameTimer()
    if rejectedLogAt[src] and now-rejectedLogAt[src]<(Config.Security.rejectedAuditIntervalMs or 10000) then return end
    rejectedLogAt[src]=now
    audit(src,'SECURITY '..category,name,'')
    if RSAdminServer and RSAdminServer.Advanced and RSAdminServer.Advanced.Webhook then
        pcall(RSAdminServer.Advanced.Webhook,'security','Admin RPC rejected',
            {Player=GetPlayerName(src) or src,Action=name,Reason=category},15158332)
    end
end

local function handle(name, perm, fn)
    handlers[name] = {perm=perm, fn=fn}
end

local function relay(target, event, payload)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false end
    TriggerClientEvent(event, target, payload or {})
    return true
end

RSAdminCore = {
    Handle=handle, Can=can, TargetProtected=targetProtected, Audit=audit, Clean=clean,
    Ok=ok, Err=err, Relay=relay, Data=DATA, SaveJson=saveJson, FlushJson=flushJson,
    SaveCriticalJson=function(name,value) saveJson(name,value);return dirtyJson[name]==nil end,
    Identifiers=identifiers, PermissionMap=permissionMap, PlayerSummary=nil,LoadJson=loadJson
}
RSAdminCore.ProtectedVehicleOccupant=protectedVehicleOccupant

local function reportIdentity(src)
    local data=Adapter and Adapter.GetPlayerData(src)
    local account
    for _,prefix in ipairs({'license2:','license:','fivem:'}) do
        for _,id in ipairs(identifiers(src)) do if id:sub(1,#prefix)==prefix then account=id;break end end
        if account then break end
    end
    if not account then return end
    return {account=account,character=data and (data.citizenid or data.identifier) or nil}
end
local function reportSource(r)
    local saved=r.reporterIdentity
    if type(saved)~='table' or not saved.account then return end
    for _,id in ipairs(GetPlayers()) do
        local src=tonumber(id);local current=reportIdentity(src)
        if current and current.account==saved.account and current.character==saved.character then return src end
    end
end
local function publicReport(r)
    local out={};for k,v in pairs(r) do if k~='reporterIdentity' then out[k]=v end end
    out.reporter=reportSource(r) or 0;out.reporterOnline=out.reporter>0
    return out
end
RSAdminCore.PublicReport=publicReport

local function playerSummary()
    local list = {}
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        local ped = GetPlayerPed(id)
        local c = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0,0,0)
        local data=Adapter and Adapter.GetPlayerData(id);local char=data and data.charinfo or {}
        list[#list+1] = {
            id=id, name=GetPlayerName(id) or ('Player %s'):format(id), ping=GetPlayerPing(id),
            characterName=char.firstname and clean((char.firstname or '')..' '..(char.lastname or ''),80) or nil,
            bucket=GetPlayerRoutingBucket(id), x=c.x, y=c.y, z=c.z
        }
    end
    table.sort(list, function(a,b) return a.id < b.id end)
    return list
end
RSAdminCore.PlayerSummary=playerSummary

local function activeBans()
    local now = os.time()
    local out = {}
    for _, b in ipairs(DATA.bans) do
        if not b.revoked and (not b.expires or b.expires == 0 or b.expires > now) then out[#out+1] = b end
    end
    return out
end

local function currentWeapons()
    local candidates=Adapter and Adapter.WeaponList(false) or Config.Weapons or {}
    if GetResourceState('ox_inventory')~='started' then return candidates end
    -- Do not offer Qbox native/pseudo-weapons that ox_inventory cannot grant.
    -- Its registered weapon items are the source of truth while ox is active.
    local available={}
    for _,weapon in ipairs(candidates) do
        local good,details=pcall(function() return exports.ox_inventory:Items(weapon.name) end)
        if good and type(details)=='table' and details.weapon then available[#available+1]=weapon end
    end
    return available
end

local function weaponAllowed(name)
    name = clean(name, 64):upper()
    for _, w in ipairs(currentWeapons()) do if tostring(w.name):upper() == name then return true, w end end
    return false
end

handle('bootstrap', 'open', function(src)
    if GetResourceState('qbx_core') == 'started' then
        local playerState = Player(src) and Player(src).state
        if not playerState or playerState.isLoggedIn ~= true then
            return err('Character is not loaded yet')
        end
    end
    local perms=permissionMap(src)
    local advanced=RSAdminServer and RSAdminServer.Advanced
    local prankAnimations={}
    for _,a in ipairs((Config.Pranks and Config.Pranks.Animations) or {}) do prankAnimations[#prankAnimations+1]=a end
    for _,a in ipairs((Config.Pranks and Config.Pranks.CustomAnimations) or {}) do prankAnimations[#prankAnimations+1]=a end
    return ok({
        operator={id=src,name=GetPlayerName(src)},
        permissions=perms,
        players=(perms.players or perms.moderate or perms.spectate or perms.owner or perms.all) and playerSummary() or {},
        weapons=(perms.weapons or perms.owner or perms.all) and currentWeapons() or {},
        weaponDelivery=GetResourceState('ox_inventory')=='started' and 'inventory' or 'native',
        weather=Config.WeatherTypes,
        reports={}, reportSummary=(perms.reports or perms.owner or perms.all) and {total=#DATA.reports} or {total=0},
        bans=(perms.moderate or perms.owner or perms.all) and activeBans() or {},
        presets=(perms.vehicles or perms.garage or perms.owner or perms.all) and DATA.presets or {},
        garages=(perms.garage or perms.owner or perms.all) and (Adapter and Adapter.Garages() or {}) or {},
        adminVehicles=Config.AdminVehicleDefaults or {}, defaultGarage=Config.DefaultGarage,
        languages=Config.Languages, language=Config.Language, widgets=Config.Widgets,
        pathwaysEnabled=Config.Pathways and Config.Pathways.Enabled==true,
        staffRoles=Config.StaffRoles, prankAnimations=prankAnimations,
        jailConfig={defaultMinutes=Config.Jail.defaultMinutes,maxMinutes=Config.Jail.maxMinutes},
        economyConfig={accounts=Config.Economy.accounts,maxAdminAdjustment=Config.Economy.maxAdminAdjustment,maxPlayerTransfer=Config.Economy.maxPlayerTransfer,dailyPlayerTransferLimit=Config.Economy.dailyPlayerTransferLimit,highValueThreshold=Config.Economy.highValueThreshold,extremeValueThreshold=Config.Economy.extremeValueThreshold},
        rpcTimeout=Config.RpcTimeoutMs or 12000,
        summary=advanced and advanced.DashboardSummary and advanced.DashboardSummary(src) or nil,
        framework=Adapter and Adapter.Framework() or 'standalone'
    })
end)

-- Every newly exposed operator action rechecks current server permissions.
local OPERATOR_ACTIONS={togglePower=true,fullGod=true,resetAdminState=true,setArmor=true,setWanted=true,teleportWaypoint=true,toggleNoclip=true,noclipSpeed=true,toggleLaser=true,operatorCoords=true,stopSpectate=true}
handle('operator:authorize','developer',function(_,d)
    if not OPERATOR_ACTIONS[d.action] then return err('Unknown operator action') end
    return ok(true)
end)

local function medicalAction(src,target,action)
    if GetResourceState('qbx_medical')=='started' then
        local data=Adapter and Adapter.GetPlayerData(target)
        local meta=data and data.metadata or {}
        local revive=action=='revive' or meta.isdead==true or meta.inlaststand==true
        local good,result=pcall(function()
            if revive then return exports.qbx_medical:Revive(target) end
            return exports.qbx_medical:Heal(target)
        end)
        if not good or result==false then return err('Medical provider failed') end
        -- qbx_medical Heal clears wounds; it does not restore native HP.
        if not revive then relay(target,'rs-admin:client:heal',{}) end
    elseif GetResourceState('qbx_core')=='started' then
        return err('Qbox medical provider unavailable')
    else
        relay(target,action=='revive' and 'rs-admin:client:revive' or 'rs-admin:client:heal',{})
    end
    audit(src,action,'medical provider',GetPlayerName(target))
    return ok(true)
end
handle('operator:heal','developer',function(src) return medicalAction(src,src,'heal') end)
handle('operator:revive','developer',function(src) return medicalAction(src,src,'revive') end)

handle('players:refresh', 'open', function(src) return ok(playerSummary()) end)

handle('player:kick', 'moderate', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    if targetProtected(src,t) then return err('Owner-protected player') end
    local reason=clean(d.reason or 'Removed by staff', 180)
    audit(src,'kick',reason,GetPlayerName(t)); DropPlayer(t, reason); return ok(true)
end)

-- Ban creation/removal is registered once by server/advanced.lua.

local OWNER_PROTECTED_ACTIONS={freeze=true,kill=true,bring=true}
for action,event in pairs({
    freeze='rs-admin:client:freeze', heal='rs-admin:client:heal', revive='rs-admin:client:revive',
    kill='rs-admin:client:kill', bring='rs-admin:client:bringTo', message='rs-admin:client:message'
}) do
    handle('player:'..action, action=='message' and 'moderate' or 'players', function(src,d)
        local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
        if OWNER_PROTECTED_ACTIONS[action] and targetProtected(src,t) then return err('Owner-protected player') end
        if action=='heal' or action=='revive' then return medicalAction(src,t,action) end
        local payload={by=GetPlayerName(src), text=clean(d.text or '',300)}
        if action=='bring' then
            local ped=GetPlayerPed(src); if ped==0 then return err('Staff ped missing') end
            local c=GetEntityCoords(ped); payload.x,payload.y,payload.z=c.x,c.y,c.z
        end
        relay(t,event,payload); audit(src,action,payload.text or '',GetPlayerName(t)); return ok(true)
    end)
end

handle('player:armor', 'players', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    local amount=math.max(0,math.min(100,math.floor(tonumber(d.amount) or 100)))
    relay(t,'rs-admin:client:armor',{amount=amount,by=GetPlayerName(src)})
    audit(src,'armor',tostring(amount),GetPlayerName(t)); return ok(true)
end)

handle('player:clearTasks', 'players', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    relay(t,'rs-admin:client:clearTasks',{by=GetPlayerName(src)})
    audit(src,'clear tasks','',GetPlayerName(t)); return ok(true)
end)

handle('player:goto', 'players', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    local ped=GetPlayerPed(t); if ped==0 then return err('Target ped missing') end
    local c=GetEntityCoords(ped); TriggerClientEvent('rs-admin:client:teleport',src,{x=c.x,y=c.y,z=c.z})
    audit(src,'goto','',GetPlayerName(t)); return ok(true)
end)

handle('announce', 'server', function(src,d)
    local msg=clean(d.text,300); if #msg<1 then return err('Message required') end
    TriggerClientEvent('rs-admin:client:announcement',-1,{text=msg,by=GetPlayerName(src)})
    audit(src,'announce',msg,'all'); return ok(true)
end)

local function useOxWeapons()
    return GetResourceState('ox_inventory')=='started'
end

local function oxWeaponDetails(name)
    local good,details=pcall(function() return exports.ox_inventory:Items(name) end)
    if good and type(details)=='table' and details.weapon then return details end
    return nil
end

local function deliverWeapon(targetId,weapon,ammo)
    if useOxWeapons() then
        local details=oxWeaponDetails(weapon.name)
        if not details then return false, ('%s is not a registered ox_inventory weapon'):format(weapon.name) end
        local metadata={}
        -- ox_inventory equips weapon items and reads their cartridge count
        -- from metadata. A native GiveWeaponToPed would not create the item.
        if details.ammoname then metadata.ammo=math.floor(math.min(9999,math.max(0,tonumber(ammo) or weapon.ammo or 0))) end
        return Adapter.GiveItem(targetId,weapon.name,1,metadata)
    end
    relay(targetId,'rs-admin:client:weapon',{action='give',weapon=weapon.name,ammo=math.floor(math.min(9999,math.max(1,tonumber(ammo) or weapon.ammo or 250)))})
    return true
end

handle('weapon:give', 'weapons', function(src,d)
    local good,w=weaponAllowed(d.weapon); if not good then return err('Weapon not allowed') end
    local success,reason=deliverWeapon(src,w,d.ammo)
    if not success then return err(reason or 'Could not give weapon') end
    audit(src,'give weapon',w.name,GetPlayerName(src))
    return ok({weapon=w.name,delivery=useOxWeapons() and 'inventory' or 'native'})
end)

handle('weapon:all', 'weapons', function(src)
    if useOxWeapons() then
        local count,skipped=0,0
        for _,w in ipairs(currentWeapons()) do
            if oxWeaponDetails(w.name) then
                local success=deliverWeapon(src,w,w.ammo)
                if success then count=count+1 else skipped=skipped+1 end
            else skipped=skipped+1 end
        end
        if count==0 then return err(('No weapons added; %d unavailable or blocked by inventory capacity'):format(skipped)) end
        audit(src,'give registered weapons',('%d added, %d skipped'):format(count,skipped),GetPlayerName(src))
        return ok({count=count,skipped=skipped,delivery='inventory'})
    end
    TriggerClientEvent('rs-admin:client:weapon',src,{action='all',weapons=currentWeapons()})
    audit(src,'all weapons','native',GetPlayerName(src))
    return ok(true)
end)

local function removePlayerWeapons(targetId)
    local session=RSAdminCore.SessionIdentity(targetId)
    if not session then return nil,'Target character is not loaded' end
    if useOxWeapons() then
        local readable,items=pcall(function() return exports.ox_inventory:GetInventoryItems(targetId) end)
        if not readable or type(items)~='table' then return nil,'Inventory provider unavailable; no weapons removed' end
        local count,failed=0,0
        local weapons={}
        for _,item in pairs(items) do
            if type(item)=='table' and oxWeaponDetails(item.name) then
                weapons[#weapons+1]={name=item.name,count=item.count,metadata=item.metadata,slot=item.slot}
            end
        end
        for _,item in ipairs(weapons) do
            if RSAdminCore.SessionIdentity(targetId)~=session then return nil,('Target session changed; %d weapon(s) removed before disconnect'):format(count) end
            local amount=math.max(0,math.floor(tonumber(item.count) or 0))
            if amount>0 then
                local success=Adapter.RemoveItem(targetId,item.name,amount,item.metadata,item.slot)
                if success then count=count+amount else failed=failed+amount end
            end
        end
        if RSAdminCore.SessionIdentity(targetId)~=session then return nil,'Target session changed during removal' end
        TriggerClientEvent('ox_inventory:disarm',targetId,true)
        if failed>0 then return nil,('%d weapon(s) removed, %d could not be removed'):format(count,failed) end
        return {count=count,delivery='inventory'}
    end
    TriggerClientEvent('rs-admin:client:weapon',targetId,{action='removeAll'})
    return {delivery='native'}
end
RSAdminServer.RemovePlayerWeapons=removePlayerWeapons
handle('weapon:removeAll', 'weapons', function(src)
    local result,e=removePlayerWeapons(src)
    audit(src,'remove inventory weapons',result and ('delivery '..result.delivery) or e,GetPlayerName(src))
    return result and ok(result) or err(e)
end)

handle('weapon:maxAmmo', 'weapons', function(src)
    if useOxWeapons() then
        local count,failed=0,0
        for _,item in ipairs(Adapter.GetInventory(src)) do
            local details=oxWeaponDetails(item.name)
            if details and details.ammoname then
                local metadata={};for k,v in pairs(item.metadata or {}) do metadata[k]=v end
                metadata.ammo=9999
                local success,result=pcall(function() return exports.ox_inventory:SetMetadata(src,item.slot,metadata) end)
                if success and result~=false then count=count+1 else failed=failed+1 end
            end
        end
        if failed>0 then return err(('Ammo updated for %d weapon(s), failed for %d'):format(count,failed)) end
        audit(src,'max inventory weapon ammo',('%d slots'):format(count),GetPlayerName(src))
        return ok({count=count,delivery='inventory'})
    end
    TriggerClientEvent('rs-admin:client:weapon',src,{action='maxAmmo',weapons=currentWeapons()})
    return ok(true)
end)

handle('vehicle:spawn', 'vehicles', function(src,d)
    local model=clean(d.model,64):lower(); if model=='' or not model:match('^[%w_%-]+$') then return err('Invalid model') end
    local ped=GetPlayerPed(src); if ped==0 then return err('Ped unavailable') end
    local c=GetEntityCoords(ped); local h=GetEntityHeading(ped)
    local v=CreateVehicle(joaat(model), c.x+2.0, c.y, c.z, h, true, true)
    if not v or v==0 then return err('Vehicle spawn failed') end
    local timeout=GetGameTimer()+5000
    while not DoesEntityExist(v) and GetGameTimer()<timeout do Wait(25) end
    if not DoesEntityExist(v) then return err('Vehicle did not materialize') end
    SetEntityOrphanMode(v,2)
    SetEntityRoutingBucket(v,GetPlayerRoutingBucket(src))
    local net=NetworkGetNetworkIdFromEntity(v)
    if Adapter then Adapter.GiveKeys(src,v) end
    TriggerClientEvent('rs-admin:client:vehicleSpawned',src,{netId=net,model=model,admin=d.admin==true})
    audit(src,d.admin==true and 'spawn admin vehicle' or 'spawn vehicle',model,GetPlayerName(src)); return ok({netId=net})
end)

handle('vehicle:deleteNet', 'vehicles', function(src,d)
    local net=tonumber(d.netId); if not net then return err('Invalid entity') end
    local ent=NetworkGetEntityFromNetworkId(net)
    if ent==0 or not DoesEntityExist(ent) then return err('Entity not found') end
    if GetEntityType(ent)~=2 then return err('Target is not a vehicle') end
    if not entityWithinRange(src,ent,Config.Security.maxEntityDistance or 300.0) then return err('Vehicle is too far away') end
    local allowed,reason=entityAccess(src,ent);if not allowed then return err(reason) end
    if GetResourceState('qbx_core')=='started' then
        pcall(function() exports.qbx_core:DisablePersistence(ent) end)
        local done=false
        pcall(function() done=exports.qbx_core:DeleteVehicle(ent)==true end)
        if not done and DoesEntityExist(ent) then local safe=entityAccess(src,ent);if safe then DeleteEntity(ent) else return err('Vehicle access changed during deletion') end end
    else
        DeleteEntity(ent)
    end
    audit(src,'delete vehicle',('net:%s'):format(net),''); return ok(true)
end)

handle('entity:deleteNet', 'developer', function(src,d)
    local net=tonumber(d.netId); if not net then return err('Invalid entity') end
    local ent=NetworkGetEntityFromNetworkId(net)
    if ent==0 or not DoesEntityExist(ent) then return err('Entity not found') end
    if isPlayerPedEntity(ent) then return err('Player peds cannot be deleted') end
    if not entityWithinRange(src,ent,Config.Security.maxEntityDistance or 300.0) then return err('Entity is too far away') end
    local allowed,reason=entityAccess(src,ent);if not allowed then return err(reason) end
    DeleteEntity(ent)
    audit(src,'delete world entity',('net:%s type:%s'):format(net,GetEntityType(ent)),'')
    return ok(true)
end)

handle('preset:save', 'vehicles', function(src,d)
    if type(d.props)~='table' then return err('Invalid preset') end
    local model=clean(d.model,64); local name=clean(d.name,48)
    if model=='' or name=='' then return err('Model and name required') end
    DATA.presets[model]=DATA.presets[model] or {}
    DATA.presets[model][name]={name=name,model=model,props=d.props,by=GetPlayerName(src),at=os.time()}
    saveJson('presets',DATA.presets); audit(src,'save vehicle preset',model..' / '..name,''); return ok(DATA.presets)
end)

handle('preset:delete', 'vehicles', function(src,d)
    local model=clean(d.model,64); local name=clean(d.name,48)
    if DATA.presets[model] then DATA.presets[model][name]=nil; if next(DATA.presets[model])==nil then DATA.presets[model]=nil end end
    saveJson('presets',DATA.presets); audit(src,'delete vehicle preset',model..' / '..name,''); return ok(DATA.presets)
end)

handle('lab:enter', 'developer', function(src)
    if privateBuckets[src] then return ok({bucket=GetPlayerRoutingBucket(src), already=true}) end
    local prev=GetPlayerRoutingBucket(src); local bucket=Config.PrivateLab.baseBucket+src
    privateBuckets[src]=prev
    if Config.PrivateLab.strict then SetRoutingBucketEntityLockdownMode(bucket,'strict') end
    SetRoutingBucketPopulationEnabled(bucket,not Config.PrivateLab.disablePopulation)
    SetPlayerRoutingBucket(src,bucket)
    audit(src,'enter private lab',('bucket %s'):format(bucket),''); return ok({bucket=bucket})
end)

handle('lab:exit', 'developer', function(src)
    local current=GetPlayerRoutingBucket(src)
    local prev=privateBuckets[src] or 0
    SetPlayerRoutingBucket(src,prev)
    if current >= (Config.PrivateLab.baseBucket or 700000) then
        SetRoutingBucketPopulationEnabled(current,true)
        SetRoutingBucketEntityLockdownMode(current,'inactive')
    end
    privateBuckets[src]=nil
    audit(src,'exit private lab',('bucket %s'):format(prev),''); return ok({bucket=prev})
end)



handle('items:refresh', 'inventory', function(src)
    return ok(Adapter and Adapter.ItemList(true) or {})
end)

handle('item:give', 'inventory', function(src,d)
    if not Adapter then return err('Framework adapter unavailable') end
    local t=tonumber(d.target) or src
    if not GetPlayerName(t) then return err('Player not found') end
    local item=clean(d.item,80)
    local amount=math.max(1,math.min(Config.MaxGiveItemAmount or 5000,math.floor(tonumber(d.amount) or 1)))
    if item=='' or not Adapter.ItemExists(item) then return err('Unknown item') end
    local success,reason=Adapter.GiveItem(t,item,amount,type(d.metadata)=='table' and d.metadata or nil)
    if not success then return err(reason or 'Could not give item') end
    local adminReason=clean(d.reason or '',180)
    audit(src,'give item',('%sx %s%s'):format(amount,item,adminReason~='' and (' · '..adminReason) or ''),GetPlayerName(t))
    TriggerClientEvent('rs-admin:client:message',t,{by='RS Admin',text=('You received %sx %s.'):format(amount,item)})
    return ok(true)
end)

handle('vehicle:giveOwned', 'garage', function(src,d)
    if not Adapter then return err('Framework adapter unavailable') end
    local t=tonumber(d.target) or src
    if not GetPlayerName(t) then return err('Player not found') end
    local model=clean(d.model,64):lower()
    if model=='' or not model:match('^[%w_%-]+$') then return err('Invalid model') end
    local garage=clean(d.garage or Config.DefaultGarage,64)
    local props=type(d.props)=='table' and d.props or {}
    local success,result=Adapter.GiveOwnedVehicle(t,model,garage,props)
    if not success then return err(result or 'Could not give vehicle') end
    audit(src,'give owned vehicle',('%s | %s | %s'):format(model,result.plate or '?',result.garage or garage),GetPlayerName(t))
    TriggerClientEvent('rs-admin:client:message',t,{by='RS Admin',text=('Vehicle added to garage: %s [%s]'):format(model,result.plate or 'plate pending')})
    return ok(result)
end)

handle('vehicle:fixFor', 'vehicles', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    relay(t,'rs-admin:client:fixVehicle',{by=GetPlayerName(src)})
    audit(src,'fix player vehicle','',GetPlayerName(t)); return ok(true)
end)

handle('weapon:giveTarget', 'weapons', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    local good,w=weaponAllowed(d.weapon); if not good then return err('Weapon not allowed') end
    local success,reason=deliverWeapon(t,w,d.ammo)
    if not success then return err(reason or 'Could not give weapon to player') end
    audit(src,'give player weapon',w.name,GetPlayerName(t))
    return ok({weapon=w.name,delivery=useOxWeapons() and 'inventory' or 'native'})
end)

local PRANKS={drunk=true,ragdoll=true,spin=true,fakeExplosion=true,screenShake=true,wanted5=true,clearWanted=true,launch=true,stumble=true,vehicleSpin=true}
handle('player:prank', 'pranks', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    if targetProtected(src,t) then return err('Owner-protected player') end
    local action=clean(d.action,40)
    if not PRANKS[action] then return err('Unknown prank') end
    local seconds=math.max(1,math.min(Config.PrankMaxSeconds or 30,math.floor(tonumber(d.seconds) or 8)))
    relay(t,'rs-admin:client:prank',{action=action,seconds=seconds,by=GetPlayerName(src)})
    audit(src,'prank '..action,('%ss'):format(seconds),GetPlayerName(t)); return ok(true)
end)

handle('spectate:start', 'spectate', function(src,d)
    local t=tonumber(d.target); if not t or not GetPlayerName(t) then return err('Player not found') end
    if t==src then return err('Cannot spectate yourself') end
    if targetProtected(src,t) then return err('Owner-protected player') end
    local ped=GetPlayerPed(t); if ped==0 then return err('Target ped unavailable') end
    if not spectateSessions[src] then spectateSessions[src]={bucket=GetPlayerRoutingBucket(src)} end
    spectateSessions[src].target=t
    local targetBucket=GetPlayerRoutingBucket(t)
    SetPlayerRoutingBucket(src,targetBucket)
    local c=GetEntityCoords(ped)
    TriggerClientEvent('rs-admin:client:spectateStart',src,{target=t,x=c.x,y=c.y,z=c.z})
    audit(src,'spectate start','',GetPlayerName(t)); return ok({target=t,bucket=targetBucket})
end)

handle('spectate:stop', 'spectate', function(src)
    local s=spectateSessions[src]
    local old=s and s.bucket or 0
    SetPlayerRoutingBucket(src,old)
    spectateSessions[src]=nil
    TriggerClientEvent('rs-admin:client:spectateStop',src,{})
    audit(src,'spectate stop','',''); return ok({bucket=old})
end)

handle('world:set', 'world', function(src,d)
    local typ=clean(d.type,24):upper(); local valid=false
    for _,v in ipairs(Config.WeatherTypes) do if v==typ then valid=true break end end
    if not valid then return err('Invalid weather') end
    local result,e=RSAdminServer.PatchWorld(src,{weather=typ})
    return result and ok(true) or err(e)
end)
handle('world:time', 'world', function(src,d)
    local h=math.max(0,math.min(23,math.floor(tonumber(d.hour) or 12))); local m=math.max(0,math.min(59,math.floor(tonumber(d.minute) or 0)))
    local result,e=RSAdminServer.PatchWorld(src,{hour=h,minute=m})
    return result and ok(true) or err(e)
end)
handle('world:blackout', 'world', function(src,d) local result,e=RSAdminServer.PatchWorld(src,{blackout=d.enabled==true}); return result and ok(true) or err(e) end)

handle('report:create', nil, function(src,d)
    local nowMs=GetGameTimer()
    if reportCooldown[src] and nowMs < reportCooldown[src] then return err('Please wait before sending another report') end
    local msg=clean(d.message,900); if #msg<3 then return err('Please describe the issue') end
    -- Keep the report store bounded without silently deleting open tickets.
    local maxReports=math.max(1,tonumber(Config.Security.maxReports) or 1000)
    while #DATA.reports>=maxReports do
        local removable
        for i,r in ipairs(DATA.reports) do
            if r.status=='closed' then removable=i;break end
        end
        if not removable then return err('Report inbox is full. Ask staff to close old reports.') end
        table.remove(DATA.reports,removable)
    end
    reportCooldown[src]=nowMs+10000
    reportSeq=reportSeq+1
    local r={id=reportSeq, reporter=src, reporterIdentity=reportIdentity(src), reporterName=GetPlayerName(src), message=msg, status='open', claimedBy=nil, replies={}, created=os.time(), updated=os.time()}
    DATA.reports[#DATA.reports+1]=r; saveJson('reports',DATA.reports)
    for _,player in ipairs(GetPlayers()) do
        local staff=tonumber(player)
        if staff and can(staff,'reports') then
            TriggerClientEvent('rs-admin:client:reportAlert',staff,{id=r.id,name=r.reporterName,message=msg})
        end
    end
    audit(src,'create report',msg,r.reporterName); return ok(publicReport(r))
end)

local function findReport(id)
    for _,r in ipairs(DATA.reports) do if tonumber(r.id)==tonumber(id) then return r end end
end

handle('report:claim', 'reports', function(src,d)
    local r=findReport(d.id); if not r then return err('Report missing') end
    r.status='claimed'; r.claimedBy=GetPlayerName(src); r.updated=os.time(); saveJson('reports',DATA.reports); audit(src,'claim report','#'..r.id,r.reporterName); return ok(publicReport(r))
end)
handle('report:close', 'reports', function(src,d)
    local r=findReport(d.id); if not r then return err('Report missing') end
    r.status='closed'; r.updated=os.time(); saveJson('reports',DATA.reports); audit(src,'close report','#'..r.id,r.reporterName); return ok(publicReport(r))
end)
handle('report:reply', 'reports', function(src,d)
    local r=findReport(d.id); if not r then return err('Report missing') end
    local msg=clean(d.message,500); if msg=='' then return err('Message required') end
    r.replies=r.replies or {}; r.replies[#r.replies+1]={by=GetPlayerName(src),message=msg,at=os.time()}; r.updated=os.time(); saveJson('reports',DATA.reports)
    local recipient=reportSource(r)
    if recipient then TriggerClientEvent('rs-admin:client:message',recipient,{by=GetPlayerName(src),text=('Report #%s: %s'):format(r.id,msg)}) end
    audit(src,'reply report',msg,r.reporterName); return ok(publicReport(r))
end)

-- Resource lifecycle handlers are registered once by server/operations.lua.

RegisterNetEvent('rs-admin:server:rpc', function(name,reqId,data)
    local src=source
    if type(name)~='string' or #name>80 or type(reqId)~='string' or #reqId>64 or type(data)~='table' then return end
    if not allowRate(src) then
        auditRejected(src,'RATE LIMIT',name)
        TriggerClientEvent('rs-admin:client:rpc',src,reqId,err('Rate limited')); return
    end
    local h=handlers[name]; if not h then
        auditRejected(src,'UNKNOWN ACTION',name)
        TriggerClientEvent('rs-admin:client:rpc',src,reqId,err('Unknown action')); return
    end
    if h.perm and not can(src,h.perm) then
        auditRejected(src,'DENIED',name)
        TriggerClientEvent('rs-admin:client:rpc',src,reqId,err('Permission denied')); return
    end
    if not validRpcPayload(data) then
        auditRejected(src,'INVALID PAYLOAD',name)
        TriggerClientEvent('rs-admin:client:rpc',src,reqId,err('Invalid request payload')); return
    end
    local session=RSAdminCore.SessionIdentity(src)
    if not session then TriggerClientEvent('rs-admin:client:rpc',src,reqId,err('Character is not loaded yet'));return end
    local pending=inFlight[src]
    if not pending or pending.session~=session then pending={session=session,count=0,ids={},completed={},order={}};inFlight[src]=pending end
    local completed=pending.completed[reqId]
    if completed and GetGameTimer()<completed.expires then
        TriggerClientEvent('rs-admin:client:rpc',src,reqId,completed.name==name and completed.response or err('Request ID was already used'));return
    end
    if pending.ids[reqId] or pending.count>=4 then
        TriggerClientEvent('rs-admin:client:rpc',src,reqId,err('Another request is still running'));return
    end
    pending.ids[reqId]=true;pending.count=pending.count+1
    local good,res=pcall(h.fn,src,data)
    pending.ids[reqId]=nil;pending.count=pending.count-1
    if not good then print(('[rs-adminmenu] handler %s error: %s'):format(name,res)); res=err('Internal error') end
    local persisted,failed=flushJson()
    if not persisted and res and res.ok then res.persistenceWarning='Action applied; disk save pending for '..table.concat(failed,', ') end
    if RSAdminCore.SessionIdentity(src)==session then
        local response=res or ok(true)
        if not pending.completed[reqId] then pending.order[#pending.order+1]=reqId end
        pending.completed[reqId]={name=name,response=response,expires=GetGameTimer()+15000}
        while #pending.order>32 do pending.completed[table.remove(pending.order,1)]=nil end
        TriggerClientEvent('rs-admin:client:rpc',src,reqId,response)
    end
end)

RegisterCommand(Config.Command,function(src,args)
    if src==0 then
        local target=tonumber(args[1]);if target and GetPlayerName(target) and can(target,'open') then TriggerClientEvent('rs-admin:client:open',target) end
        return
    end
    if can(src,'open') then TriggerClientEvent('rs-admin:client:open',src) else TriggerClientEvent('rs-admin:client:message',src,{by='RS Admin',text='You do not have permission.'}) end
end,false)

RegisterCommand(Config.ReportCommand,function(src,args)
    if src==0 then return end
    local msg=table.concat(args,' ')
    if msg=='' then TriggerClientEvent('rs-admin:client:promptReport',src); return end
    local res=handlers['report:create'].fn(src,{message=msg})
    if res.ok then TriggerClientEvent('rs-admin:client:message',src,{by='RS Admin',text=('Report #%s submitted.'):format(res.data.id)}) end
end,false)

AddEventHandler('playerConnecting',function(name,setKickReason)
    if RSAdminServer and RSAdminServer.AdvancedBanReady then return end
    local src=source; local ids=identifiers(src); local now=os.time()
    for _,b in ipairs(DATA.bans) do
        local active=(not b.expires or b.expires==0 or b.expires>now)
        if active then
            for _,bid in ipairs(b.identifiers or {}) do
                for _,id in ipairs(ids) do
                    if bid==id then setKickReason(('Banned: %s'):format(b.reason or 'No reason')); CancelEvent(); return end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped',function()
    inFlight[source]=nil
    rate[source]=nil
    rejectedLogAt[source]=nil
    reportCooldown[source]=nil
    if privateBuckets[source] then
        local current=GetPlayerRoutingBucket(source)
        if current >= (Config.PrivateLab.baseBucket or 700000) then
            SetRoutingBucketPopulationEnabled(current,true)
            SetRoutingBucketEntityLockdownMode(current,'inactive')
        end
        privateBuckets[source]=nil
    end
    spectateSessions[source]=nil
    for admin,session in pairs(spectateSessions) do
        if session.target==source then
            SetPlayerRoutingBucket(admin,session.bucket or 0)
            spectateSessions[admin]=nil
            TriggerClientEvent('rs-admin:client:spectateStop',admin,{reason='Target disconnected'})
        end
    end
end)

AddEventHandler('onResourceStop',function(res)
    if res~=RESOURCE then return end
    for src,session in pairs(spectateSessions) do
        if GetPlayerName(src) then SetPlayerRoutingBucket(src,(session and session.bucket) or 0); TriggerClientEvent('rs-admin:client:spectateStop',src,{reason='Admin resource restarting'}) end
    end
    for src,previous in pairs(privateBuckets) do
        if GetPlayerName(src) then SetPlayerRoutingBucket(src,previous or 0) end
    end
    for _,src in ipairs(GetPlayers()) do TriggerClientEvent('rs-admin:client:forceCleanup',tonumber(src),{reason='resource_stop'}) end
    spectateSessions={}; privateBuckets={}
    flushJson()
end)

exports('HasPermission',function(src,node) return can(src,node) end)
exports('CreateReport',function(src,message) return handlers['report:create'].fn(src,{message=message}) end)
