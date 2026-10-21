local C=RSAdminCore
if not C then error('RSAdminCore unavailable') end
local A=RSAdminServer and RSAdminServer.Adapter
local H,Can,Audit,Clean,Ok,Err=C.Handle,C.Can,C.Audit,C.Clean,C.Ok,C.Err
local RESOURCE=GetCurrentResourceName()

local function load(name,fallback)
    return C.LoadJson(name,fallback)
end
local DUTY_LOGS=load('duty_logs',{})
local CUSTOM_CHANNELS=load('chat_channels',{})
local QUICK=load('quickmenu',{})
local dutyBySource={}
local channelHistory={}
local function save(name,val) C.SaveJson(name,val) end
local function primary(src)
    local ids=C.Identifiers(src); local order={'license:','license2:','fivem:','discord:','steam:'}
    for _,p in ipairs(order) do for _,id in ipairs(ids) do if id:sub(1,#p)==p then return id end end end
    return ids[1]
end
local function actor(src) return src==0 and 'console' or (GetPlayerName(src) or ('#%s'):format(src)) end
local function push(t,row,max) t[#t+1]=row; while #t>(max or 1000) do table.remove(t,1) end end
local function role(src)
    if Can(src,'owner') then return 'owner' end
    if RSAdminServer and RSAdminServer.GetStaffRole then local r=RSAdminServer.GetStaffRole(src); return r or 'staff' end
    return 'staff'
end
local function webhook(channel,title,fields,color)
    if RSAdminServer and RSAdminServer.Webhook then pcall(RSAdminServer.Webhook,channel,title,fields,color) end
end

-- Duty -------------------------------------------------------------------------
local function dutyState(src)
    local d=dutyBySource[src]
    return {on=d and d.on==true or false,since=d and d.since or nil,role=role(src)}
end
local function setDuty(src,on)
    if not Can(src,'open') then return Err('Permission denied') end
    local current=dutyBySource[src]
    if on==nil then on=not (current and current.on) end
    on=on==true
    if on then
        if current and current.on then return Ok(dutyState(src)) end
        dutyBySource[src]={on=true,since=os.time(),identifier=primary(src),name=actor(src),role=role(src)}
        local row={at=os.time(),action='on',name=actor(src),identifier=primary(src),role=role(src)}; push(DUTY_LOGS,row,Config.Duty.maxLogRows or 2500); save('duty_logs',DUTY_LOGS)
        Audit(src,'staff duty on','',actor(src)); if Config.Duty.webhook then webhook('staff','Staff went on duty',{Staff=actor(src),Role=role(src)}) end
    else
        if current and current.on then
            local seconds=math.max(0,os.time()-(current.since or os.time()))
            push(DUTY_LOGS,{at=os.time(),action='off',name=actor(src),identifier=current.identifier,role=current.role,seconds=seconds},Config.Duty.maxLogRows or 2500); save('duty_logs',DUTY_LOGS)
            Audit(src,'staff duty off',('%ss'):format(seconds),actor(src)); if Config.Duty.webhook then webhook('staff','Staff went off duty',{Staff=actor(src),Seconds=seconds}) end
        end
        dutyBySource[src]=nil
    end
    TriggerClientEvent('rs-admin:client:duty',src,dutyState(src)); return Ok(dutyState(src))
end
H('staff:dutyState','open',function(src) return Ok(dutyState(src)) end)
H('staff:dutyToggle','open',function(src,d) return setDuty(src,d.on) end)
H('staff:dutyLogs','staff',function(_,d)
    local page=math.max(1,math.floor(tonumber(d.page) or 1)); local size=math.max(10,math.min(100,math.floor(tonumber(d.pageSize) or 50))); local rows={}
    for i=#DUTY_LOGS,1,-1 do rows[#rows+1]=DUTY_LOGS[i] end; local total=#rows; local first=(page-1)*size+1; local out={}; for i=first,math.min(total,first+size-1) do out[#out+1]=rows[i] end
    return Ok({rows=out,total=total,page=page,pages=math.max(1,math.ceil(total/size))})
end)
RegisterCommand((Config.Duty and Config.Duty.command) or 'aduty',function(src) if src>0 then setDuty(src,nil) end end,false)
AddEventHandler('playerDropped',function()
    local src=source; local d=dutyBySource[src]; if d and d.on then
        local seconds=math.max(0,os.time()-(d.since or os.time())); push(DUTY_LOGS,{at=os.time(),action='disconnect',name=d.name,identifier=d.identifier,role=d.role,seconds=seconds},Config.Duty.maxLogRows or 2500); save('duty_logs',DUTY_LOGS)
    end; dutyBySource[src]=nil
end)

-- Reports ----------------------------------------------------------------------
local function findReport(id) for i,r in ipairs(C.Data.reports or {}) do if tonumber(r.id)==tonumber(id) then return r,i end end end
H('report:list','reports',function(_,d)
    local status=Clean(d.status or '',24):lower(); local q=Clean(d.q or '',120):lower(); local page=math.max(1,math.floor(tonumber(d.page) or 1)); local size=math.max(10,math.min(100,math.floor(tonumber(d.pageSize) or 30))); local rows={}
    for i=#C.Data.reports,1,-1 do local r=C.Data.reports[i]; local hay=('%s %s %s %s'):format(r.id or '',r.reporterName or '',r.message or '',r.status or ''):lower(); if (status=='' or status=='all' or tostring(r.status):lower()==status) and (q=='' or hay:find(q,1,true)) then rows[#rows+1]=r end end
    local total=#rows; local first=(page-1)*size+1; local out={}; for i=first,math.min(total,first+size-1) do out[#out+1]=C.PublicReport(rows[i]) end; return Ok({rows=out,total=total,page=page,pages=math.max(1,math.ceil(total/size))})
end)
H('report:reopen','reports',function(src,d) local r=findReport(d.id); if not r then return Err('Report missing') end; r.status='open';r.updated=os.time();C.SaveJson('reports',C.Data.reports);Audit(src,'reopen report','#'..r.id,r.reporterName);return Ok(C.PublicReport(r)) end)
H('report:delete','reports',function(src,d) if not Can(src,'owner') then return Err('Owner required to delete report history') end; local r,i=findReport(d.id); if not r then return Err('Report missing') end; table.remove(C.Data.reports,i);C.SaveJson('reports',C.Data.reports);Audit(src,'delete report','#'..r.id,r.reporterName);return Ok(true) end)

-- Channel-based staff chat ------------------------------------------------------
local function channelDefs()
    local out={}; for _,c in ipairs((Config.StaffChat and Config.StaffChat.channels) or {}) do out[c.key]=c end; for k,c in pairs(CUSTOM_CHANNELS) do out[k]=c end; return out
end
local function channelAllowed(src,c)
    if Can(src,'owner') then return true end
    if not c then return false end
    if c.permission and Can(src,c.permission) then return true end
    local r=role(src); if not c.roles or #c.roles==0 then return Can(src,'open') end
    for _,x in ipairs(c.roles) do if x==r then return true end end; return false
end
local function visibleChannels(src)
    local out={}; for _,c in pairs(channelDefs()) do if channelAllowed(src,c) then out[#out+1]=c end end; table.sort(out,function(a,b) return tostring(a.label)<tostring(b.label) end); return out
end
H('staffchat:channels','open',function(src) return Ok(visibleChannels(src)) end)
H('staffchat:channelHistory','open',function(src,d) local key=Clean(d.channel or 'staff',32):lower(); local c=channelDefs()[key]; if not channelAllowed(src,c) then return Err('Channel access denied') end; return Ok(channelHistory[key] or {}) end)
H('staffchat:channelSend','open',function(src,d)
    local key=Clean(d.channel or 'staff',32):lower(); local c=channelDefs()[key]; if not channelAllowed(src,c) then return Err('Channel access denied') end; local msg=Clean(d.message or '',Config.StaffChat.maxMessage or 500); if msg=='' then return Err('Message required') end
    local row={at=os.time(),channel=key,source=src,name=actor(src),role=role(src),color=c.color or '#ffffff',message=msg}; channelHistory[key]=channelHistory[key] or {}; push(channelHistory[key],row,Config.StaffChat.maxChannelHistory or 120)
    for _,s in ipairs(GetPlayers()) do local id=tonumber(s); if channelAllowed(id,c) then TriggerClientEvent('rs-admin:client:staffChatChannel',id,row) end end; Audit(src,'staff channel',('%s: %s'):format(key,msg),'staff'); return Ok(row)
end)
H('staffchat:channelCreate','owner',function(src,d)
    if not Config.StaffChat.allowCustomChannels then return Err('Custom channels disabled') end; local count=0; for _ in pairs(CUSTOM_CHANNELS) do count=count+1 end; if count>=(Config.StaffChat.maxChannels or 16) then return Err('Channel limit reached') end
    local key=Clean(d.key or '',32):lower():gsub('[^%w_%-]',''); if key=='' or channelDefs()[key] then return Err('Invalid or existing channel key') end
    local roles={}; for _,r in ipairs(d.roles or {}) do r=Clean(r,32):lower(); if r~='' then roles[#roles+1]=r end end; CUSTOM_CHANNELS[key]={key=key,label=Clean(d.label or key,60),color=Clean(d.color or '#20a9ff',16),roles=roles}; save('chat_channels',CUSTOM_CHANNELS); Audit(src,'create staff channel',key,'staff'); return Ok(CUSTOM_CHANNELS[key])
end)
H('staffchat:channelDelete','owner',function(src,d) local key=Clean(d.key or '',32):lower(); if not CUSTOM_CHANNELS[key] then return Err('Only custom channels can be deleted') end; CUSTOM_CHANNELS[key]=nil;channelHistory[key]=nil;save('chat_channels',CUSTOM_CHANNELS);Audit(src,'delete staff channel',key,'staff');return Ok(true) end)
H('staffchat:channelClear','staff',function(src,d) local key=Clean(d.channel or 'staff',32):lower(); local c=channelDefs()[key]; if not channelAllowed(src,c) then return Err('Channel access denied') end; channelHistory[key]={}; Audit(src,'clear staff channel',key,'staff'); return Ok(true) end)

-- Live map vehicles -------------------------------------------------------------
local ownerCache={at=0,plates={}}
local function rebuildOwnerCache()
    if not (Config.MapVehicles and Config.MapVehicles.ownerLookup) then return {} end
    if GetGameTimer()-ownerCache.at < 30000 then return ownerCache.plates end
    local plates={}; if A and A.GetOwnedVehicles then
        for _,s in ipairs(GetPlayers()) do local id=tonumber(s); local ok,rows=pcall(A.GetOwnedVehicles,id); if ok and type(rows)=='table' then
            for _,v in ipairs(rows) do local plate=tostring(v.plate or (v.props and v.props.plate) or ''):gsub('%s+$',''); if plate~='' then plates[plate:upper()]={owner=GetPlayerName(id),ownerId=id,citizenid=v.citizenid} end end
        end end
    end
    ownerCache={at=GetGameTimer(),plates=plates}; return plates
end
H('map:vehicles','players',function()
    local owned=rebuildOwnerCache(); local out={}; local max=Config.MapVehicles.maxResults or 220
    for _,v in ipairs(GetAllVehicles()) do if #out>=max then break end; if DoesEntityExist(v) then
        local c=GetEntityCoords(v); local plate=''; local model=GetEntityModel(v); pcall(function() plate=GetVehicleNumberPlateText(v) or '' end); plate=tostring(plate):gsub('%s+$','')
        local driver=0; pcall(function() driver=GetPedInVehicleSeat(v,-1) or 0 end); local driverName=nil; local driverId=nil
        if driver and driver~=0 then for _,s in ipairs(GetPlayers()) do local id=tonumber(s); if GetPlayerPed(id)==driver then driverId=id;driverName=GetPlayerName(id);break end end end
        local own=owned[plate:upper()]
        out[#out+1]={netId=NetworkGetNetworkIdFromEntity(v),model=model,plate=plate,x=c.x,y=c.y,z=c.z,driver=driverName,driverId=driverId,owner=own and own.owner or nil,ownerId=own and own.ownerId or nil,occupied=driver~=0}
    end end
    return Ok(out)
end)

-- Resource operations ----------------------------------------------------------
local function resourceDenied(name) return (Config.Resources and Config.Resources.deny and Config.Resources.deny[name]) or false end
H('resource:list','server',function()
    local rows={}; for i=0,GetNumResources()-1 do local name=GetResourceByFindIndex(i); if name then rows[#rows+1]={name=name,state=GetResourceState(name),protected=resourceDenied(name)} end end; table.sort(rows,function(a,b) return a.name<b.name end); return Ok(rows)
end)
H('resource:start','server',function(src,d) if Config.Resources.allowStart==false then return Err('Resource start disabled') end; if Config.Resources.ownerOnlyStartStop and not Can(src,'owner') then return Err('Owner required') end; local name=Clean(d.name,80); if name=='' or resourceDenied(name) then return Err('Resource is protected') end; if GetResourceState(name)=='missing' then return Err('Resource not found') end; CreateThread(function() StartResource(name) end); Audit(src,'start resource',name,''); return Ok(true) end)
H('resource:stop','server',function(src,d) if Config.Resources.allowStop==false then return Err('Resource stop disabled') end; if Config.Resources.ownerOnlyStartStop and not Can(src,'owner') then return Err('Owner required') end; local name=Clean(d.name,80); if name=='' or resourceDenied(name) then return Err('Resource is protected') end; if GetResourceState(name)=='missing' then return Err('Resource not found') end; CreateThread(function() StopResource(name) end); Audit(src,'stop resource',name,''); return Ok(true) end)
H('resource:restart','server',function(src,d) if Config.Resources.allowRestart==false then return Err('Resource restart disabled') end; if Config.Resources.ownerOnlyStartStop and not Can(src,'owner') then return Err('Owner required') end; local name=Clean(d.name,80); if name=='' or resourceDenied(name) then return Err('Resource is protected') end; if GetResourceState(name)=='missing' then return Err('Resource not found') end; CreateThread(function() StopResource(name);Wait(350);StartResource(name) end);Audit(src,'restart resource',name,'');return Ok(true) end)

-- Quick menu / settings / bridge ----------------------------------------------
H('quickmenu:get','open',function(src) local pid=primary(src); return Ok(QUICK[pid] or {mode=Config.QuickMenu.defaultMode,actions=Config.QuickMenu.defaultActions,settings=Config.Settings}) end)
H('quickmenu:save','open',function(src,d)
    local pid=primary(src); if not pid then return Err('Identifier missing') end; local actions={}; for _,a in ipairs(d.actions or {}) do a=Clean(a,32); if Config.QuickMenu.allowedActions[a] then actions[#actions+1]=a end end; QUICK[pid]={mode=(d.mode=='list' and 'list' or 'radial'),actions=actions,settings=type(d.settings)=='table' and d.settings or {}};save('quickmenu',QUICK);return Ok(QUICK[pid])
end)
H('bridge:status','open',function() return Ok(RSAdminBridge and RSAdminBridge.Status() or {}) end)
H('player:properties','players',function(_,d) local t=tonumber(d.target); if not t or not GetPlayerName(t) then return Err('Player not found') end; if not RSAdminBridge then return Err('Bridge unavailable') end; local good,rows=RSAdminBridge.GetProperties(t); return good and Ok(rows) or Err(rows) end)
H('server:time','open',function() return Ok({unix=os.time(),utc=os.date('!%Y-%m-%d %H:%M:%S UTC'),localTime=os.date('%Y-%m-%d %H:%M:%S')}) end)

-- Owned vehicle database tools -------------------------------------------------
H('vehicle:ownerSearch','garage',function(_,d)
    if not A or not A.SearchOwnedVehicles then return Err('Owned vehicle search unavailable') end
    local rows,e=A.SearchOwnedVehicles(Clean(d.q or '',80),d.page,d.pageSize)
    return rows and Ok(rows) or Err(e)
end)
H('vehicle:deleteOwnedByPlate','garage',function(src,d)
    if not Can(src,'owner') then return Err('Owner required to delete an owned vehicle record') end
    local plate=Clean(d.plate or '',16):upper(); if plate=='' then return Err('Plate required') end
    local existing=A and A.FindOwnedVehicleByPlate and select(1,A.FindOwnedVehicleByPlate(plate)) or nil
    if not existing then return Err('Owned vehicle not found') end
    local good,e=A.DeleteOwnedVehicleByPlate(plate); if not good then return Err(e) end
    Audit(src,'delete owned vehicle',plate,existing.ownerName or existing.citizenid or ''); webhook('vehicles','Owned vehicle deleted',{Plate=plate,Owner=existing.ownerName or existing.citizenid or '-',Staff=actor(src)},15158332); return Ok(true)
end)

-- Scheduled world vehicle cleanup ----------------------------------------------
local scheduledCleanups={}
local cleanupSeq=0
local function cleanupRows()
    local out={}; for _,r in pairs(scheduledCleanups) do out[#out+1]=r end
    table.sort(out,function(a,b) return (a.executeAt or 0)<(b.executeAt or 0) end); return out
end
H('vehicle:cleanupSchedule','vehicles',function(src,d)
    if not (Config.VehicleCleanup and Config.VehicleCleanup.allowScheduling) then return Err('Cleanup scheduling disabled') end
    if not Can(src,'owner') then return Err('Owner required to schedule global cleanup') end
    local minutes=math.max(1,math.min(Config.VehicleCleanup.maxScheduledMinutes or 120,math.floor(tonumber(d.minutes) or 5)))
    cleanupSeq=cleanupSeq+1
    local row={id=cleanupSeq,created=os.time(),executeAt=os.time()+minutes*60,minutes=minutes,mode='global',by=actor(src),cancelled=false}
    scheduledCleanups[row.id]=row
    TriggerClientEvent('rs-admin:client:announcement',-1,{text=('World vehicle cleanup scheduled in %d minute%s. Empty non-owned vehicles will be removed.'):format(minutes,minutes==1 and '' or 's')})
    Audit(src,'schedule vehicle cleanup',('%dm'):format(minutes),'global')
    CreateThread(function()
        local warned={}
        while scheduledCleanups[row.id] and not row.cancelled do
            local remain=row.executeAt-os.time(); if remain<=0 then break end
            for _,seconds in ipairs(Config.VehicleCleanup.warningSeconds or {60,30,10}) do
                if remain<=seconds and not warned[seconds] then
                    warned[seconds]=true
                    TriggerClientEvent('rs-admin:client:announcement',-1,{text=('Vehicle cleanup in %d seconds. Store or occupy vehicles you need.'):format(math.max(1,remain))})
                end
            end
            Wait(1000)
        end
        if not scheduledCleanups[row.id] or row.cancelled then return end
        local result,e=RSAdminServer and RSAdminServer.ExecuteVehicleCleanup and RSAdminServer.ExecuteVehicleCleanup(0,{mode='global',radius=Config.VehicleCleanup.maxRadius}) or nil,'Cleanup unavailable'
        scheduledCleanups[row.id]=nil
        if result then
            TriggerClientEvent('rs-admin:client:announcement',-1,{text=('World vehicle cleanup complete: %d empty non-owned vehicles removed.'):format(result.count or 0)})
            webhook('vehicles','Scheduled world vehicle cleanup',{Count=result.count or 0,ScheduledBy=row.by},3447003)
        else print(('[rs-adminmenu] scheduled cleanup failed: %s'):format(e or 'unknown')) end
    end)
    return Ok(row)
end)
H('vehicle:cleanupScheduledList','vehicles',function() return Ok(cleanupRows()) end)
H('vehicle:cleanupCancel','vehicles',function(src,d)
    if not Can(src,'owner') then return Err('Owner required') end
    local id=tonumber(d.id); local row=id and scheduledCleanups[id] or nil; if not row then return Err('Scheduled cleanup not found') end
    row.cancelled=true; scheduledCleanups[id]=nil; Audit(src,'cancel vehicle cleanup','#'..id,'global'); return Ok(true)
end)

-- Tsunami maintenance / evacuation --------------------------------------------
local maintenance={active=false,serial=0}
local function maintenanceState()
    return {active=maintenance.active,serial=maintenance.serial,started=maintenance.started,executeAt=maintenance.executeAt,by=maintenance.by,disconnectAtEnd=maintenance.disconnectAtEnd}
end
H('maintenance:state','server',function() return Ok(maintenanceState()) end)
local function cancelMaintenance(src)
    local wasActive=maintenance.active
    maintenance.serial=maintenance.serial+1; maintenance.active=false
    if maintenance.eventId then RSAdminServer.StopDisaster('Tsunami maintenance cancelled',maintenance.eventId);maintenance.eventId=nil end
    if not wasActive then return Ok(false) end
    TriggerClientEvent('rs-admin:client:announcement',-1,{text='Tsunami evacuation / maintenance sequence cancelled by server owner.'})
    Audit(src,'cancel tsunami maintenance','',actor(src)); return Ok(true)
end
H('maintenance:cancel','owner',cancelMaintenance)
H('maintenance:tsunamiStart','owner',function(src,d)
    if not (Config.Maintenance and Config.Maintenance.tsunamiEvacuation) then return Err('Tsunami maintenance disabled') end
    if maintenance.active then return Err('A maintenance sequence is already active') end
    local seconds=math.max(Config.Maintenance.minCountdownSeconds or 15,math.min(Config.Maintenance.maxCountdownSeconds or 900,math.floor(tonumber(d.seconds) or 120)))
    local disconnect=d.disconnectAtEnd==true and Config.Maintenance.allowDisconnectAtEnd==true
    maintenance.serial=maintenance.serial+1; local serial=maintenance.serial
    maintenance.active=true; maintenance.started=os.time(); maintenance.executeAt=os.time()+seconds; maintenance.by=actor(src); maintenance.disconnectAtEnd=disconnect
    Audit(src,'start tsunami maintenance',('%ss disconnect=%s'):format(seconds,tostring(disconnect)),'server')
    webhook('server','Tsunami maintenance sequence',{Staff=actor(src),Countdown=seconds,DisconnectAtEnd=disconnect},16744192)
    CreateThread(function()
        local checkpoints={300,180,120,60,30,15,10,5,4,3,2,1}; local sent={}; local tsunamiStarted=false
        while maintenance.active and maintenance.serial==serial do
            local remain=maintenance.executeAt-os.time(); if remain<=0 then break end
            if remain<=(Config.Maintenance.tsunamiLeadSeconds or 30) and not tsunamiStarted then
                tsunamiStarted=true
                local event=RSAdminServer.StartDisaster(0,{name='tsunami',scope='all',seconds=math.max(remain,5),intensity=1.0,damage=false})
                if not event.ok then maintenance.active=false;print('[rs-adminmenu] Maintenance tsunami failed: '..tostring(event.error));return end
                maintenance.eventId=event.data.eventId
            end
            for _,n in ipairs(checkpoints) do if remain<=n and not sent[n] then sent[n]=true; TriggerClientEvent('rs-admin:client:announcement',-1,{text=('TSUNAMI EVACUATION: server maintenance in %d second%s.'):format(math.max(1,remain),remain==1 and '' or 's')}) end end
            Wait(1000)
        end
        if not maintenance.active or maintenance.serial~=serial then return end
        maintenance.active=false
        if maintenance.eventId then RSAdminServer.StopDisaster('Maintenance countdown completed',maintenance.eventId);maintenance.eventId=nil end
        TriggerClientEvent('rs-admin:client:announcement',-1,{text='TSUNAMI EVACUATION COMPLETE. Server maintenance window has begun.'})
        if disconnect then
            SetTimeout(1400,function()
                if maintenance.serial~=serial then return end
                for _,sid in ipairs(GetPlayers()) do
                    local id=tonumber(sid)
                    local keep=Config.Maintenance.keepStaffConnected and (Can(id,'open') or Can(id,'owner'))
                    if not keep then DropPlayer(id,Config.Maintenance.disconnectMessage or 'Server maintenance in progress.') end
                end
            end)
        end
    end)
    return Ok(maintenanceState())
end)

-- Duty helpers for dashboard widgets ------------------------------------------
RSAdminOperations=RSAdminOperations or {}
RSAdminOperations.CancelMaintenance=cancelMaintenance
RSAdminOperations.MaintenanceActive=function() return maintenance.active end
function RSAdminOperations.DutyCount()
    local n=0; for _,d in pairs(dutyBySource) do if d.on then n=n+1 end end; return n
end
