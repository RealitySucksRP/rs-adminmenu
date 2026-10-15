-- RS Pathways: server-authoritative onboarding / certification progression.
-- Player-facing inventory notes, notifications and GPS are display-only.
local C=RSAdminCore
if not C then return end
RSAdminServer=RSAdminServer or {}
local A=RSAdminServer.Adapter
local RESOURCE=GetCurrentResourceName()
local CFG=Config.Pathways or {}

local function loadJson(name,fallback)
    return C.LoadJson(name,fallback)
end

local STORE=loadJson('pathways',{assignments={},history={}})
STORE.assignments=STORE.assignments or {}
STORE.history=STORE.history or {}
local CUSTOM=loadJson('pathway_tracks',{})
local proximityState={}
local lastTick=os.time()
local lastProgressSave=os.time()
local autoAssign -- forward declaration for analyzer-safe local binding

local function saveStore() C.SaveJson('pathways',STORE) end
local function saveTracks() C.SaveJson('pathway_tracks',CUSTOM) end
local function clean(s,n) return C.Clean(s,n or 120) end
local function actor(src) return src==0 and 'console' or (GetPlayerName(src) or ('#%s'):format(src)) end
local function target(v) v=tonumber(v); return v and GetPlayerName(v) and v or nil end

local function playerData(src)
    return A and A.GetPlayerData and A.GetPlayerData(src) or nil
end

local function primary(src)
    local d=playerData(src)
    if d and d.citizenid then return 'citizenid:'..tostring(d.citizenid),d end
    if d and d.identifier then return tostring(d.identifier),d end
    for _,id in ipairs(GetPlayerIdentifiers(src)) do if id:sub(1,8)=='license:' then return id,d end end
    local ids=GetPlayerIdentifiers(src)
    return ids[1] or ('source:%s'):format(src),d
end

local function normalizedSteps(steps)
    local out={}
    for i,s in ipairs(type(steps)=='table' and steps or {}) do
        if type(s)=='table' and i<=64 then
            local key=clean((s.key and tostring(s.key):lower():gsub('[^%w_%-]','')) or ('step_'..i),48)
            if key~='' then
                local row={
                    key=key,
                    label=clean(s.label or key,100),
                    type=clean((s.type or 'event'):lower(),32),
                    event=clean(s.event or '',64),
                    points=math.max(0,math.min(10000,math.floor(tonumber(s.points) or 0))),
                    required=s.required~=false,
                    seconds=math.max(0,math.min(86400,math.floor(tonumber(s.seconds) or 0))),
                    radius=math.max(1.0,math.min(1000.0,tonumber(s.radius) or 12.0)),
                    uniquePlayers=math.max(1,math.min(50,math.floor(tonumber(s.uniquePlayers) or 1))),
                    value=clean(s.value or '',80),
                    account=clean(s.account or 'bank',24),
                    amount=math.max(0,math.floor(tonumber(s.amount) or 0)),
                    count=math.max(1,math.floor(tonumber(s.count) or 1)),
                    x=tonumber(s.x),y=tonumber(s.y),z=tonumber(s.z),
                    description=clean(s.description or '',220),
                }
                out[#out+1]=row
            end
        end
    end
    return out
end

local function normalizedTrack(key,t,source)
    if type(t)~='table' then return nil end
    key=clean((key or t.key or ''):lower():gsub('[^%w_%-]',''),48)
    if key=='' then return nil end
    local requires={}
    for _,r in ipairs(type(t.Requires)=='table' and t.Requires or type(t.requires)=='table' and t.requires or {}) do
        r=clean(tostring(r):lower():gsub('[^%w_%-]',''),48); if r~='' then requires[#requires+1]=r end
    end
    return {
        key=key,
        label=clean(t.Label or t.label or key,100),
        description=clean(t.Description or t.description or '',240),
        enabled=(t.Enabled~=false and t.enabled~=false),
        requiredPoints=math.max(0,math.min(100000,math.floor(tonumber(t.RequiredPoints or t.requiredPoints) or 0))),
        forcedDefault=(t.ForcedDefault==true or t.forcedDefault==true),
        autoAssign=(t.AutoAssign==true or t.autoAssign==true),
        ordered=(t.Ordered~=false and t.ordered~=false),
        requires=requires,
        guideItem=(t.GuideItem or t.guideItem),
        rewards=type(t.Rewards)=='table' and t.Rewards or type(t.rewards)=='table' and t.rewards or {},
        tracking=type(t.Tracking)=='table' and t.Tracking or type(t.tracking)=='table' and t.tracking or {},
        steps=normalizedSteps(t.Steps or t.steps),
        source=source or 'config'
    }
end

local function tracks()
    local out,map={},{}
    for key,t in pairs(CFG.Tracks or {}) do local n=normalizedTrack(key,t,'config'); if n then map[n.key]=n end end
    for key,t in pairs(CUSTOM) do local n=normalizedTrack(key,t,'custom'); if n then map[n.key]=n end end
    for _,t in pairs(map) do out[#out+1]=t end
    table.sort(out,function(a,b) return a.label:lower()<b.label:lower() end)
    return out,map
end

local function track(key)
    local _,m=tracks(); return m[tostring(key or ''):lower()]
end

local function bucketFor(identifier)
    STORE.assignments[identifier]=STORE.assignments[identifier] or {}
    return STORE.assignments[identifier]
end

local function certification(identifier,key)
    local b=STORE.assignments[identifier]
    local a=b and b[key]
    return a and a.status=='certified' and true or false
end

local function requirementsMet(identifier,t)
    for _,r in ipairs(t.requires or {}) do if not certification(identifier,r) then return false,r end end
    return true
end

local function currentStep(t,a)
    for i,s in ipairs(t.steps or {}) do
        if not (a.completed and a.completed[s.key]) then return s,i end
    end
    return nil,#(t.steps or {})+1
end

local function eligibleSteps(t,a)
    if t.ordered~=false then local s=currentStep(t,a); return s and {s} or {} end
    local out={}
    for _,s in ipairs(t.steps or {}) do if not (a.completed and a.completed[s.key]) then out[#out+1]=s end end
    return out
end

local function requiredDone(t,a)
    for _,s in ipairs(t.steps or {}) do if s.required~=false and not (a.completed and a.completed[s.key]) then return false end end
    return true
end

local function displayState(t,a)
    local completedCount=0
    for _ in pairs(a.completed or {}) do completedCount=completedCount+1 end
    local step,index=currentStep(t,a)
    local percent=#(t.steps or {})>0 and math.floor((completedCount/#t.steps)*100) or 100
    return {
        track=t.key,label=t.label,description=t.description,status=a.status or 'active',forced=a.forced==true,
        points=tonumber(a.points) or 0,requiredPoints=t.requiredPoints or 0,completedCount=completedCount,totalSteps=#(t.steps or {}),percent=percent,
        currentStep=step,currentIndex=index,startedAt=a.startedAt,completedAt=a.completedAt,assignedBy=a.assignedBy,
        rewardsClaimed=a.rewardsClaimed==true
    }
end

local function metadataFor(t,a)
    local d=displayState(t,a)
    local step=d.currentStep
    local lines={}
    local maxLines=16
    for i,s in ipairs(t.steps or {}) do
        if i>maxLines then break end
        local done=a.completed and a.completed[s.key]
        lines[#lines+1]=('%s %s'):format(done and '✓' or '○',s.label)
    end
    if #(t.steps or {})>maxLines then lines[#lines+1]=('… +%s more steps'):format(#t.steps-maxLines) end
    local description=('%s\n%s / %s points · %s / %s steps'):format(t.label,d.points,d.requiredPoints,d.completedCount,d.totalSteps)
    if #lines>0 then description=description..'\n\n'..table.concat(lines,'\n') end
    if step then description=description..('\n\nNext: %s'):format(step.label) end
    return {
        pathway=t.key,
        pathwayLabel=t.label,
        status=d.status,
        progress=('%s / %s'):format(d.completedCount,d.totalSteps),
        points=('%s / %s'):format(d.points,d.requiredPoints),
        nextObjective=step and step.label or 'Certification complete',
        issuedTo=a.playerName,
        issuedAt=a.startedAt,
        description=description,
    }
end

local function guideItemName(t)
    if t.guideItem and tostring(t.guideItem)~='' then return tostring(t.guideItem) end
    return tostring((CFG.GuideItem and CFG.GuideItem.ItemName) or 'citizen_guide')
end

local function syncGuideItem(src,t,a,allowGive)
    if not CFG.Enabled or not (CFG.Tracking and CFG.Tracking.InventoryItem) or (t.tracking and t.tracking.InventoryItem==false) then return end
    local g=CFG.GuideItem or {}; if g.Enabled==false then return end
    local name=guideItemName(t)
    if not A or not A.ItemExists or not A.ItemExists(name) then return end
    local meta=metadataFor(t,a)
    local inv=A.GetInventory and A.GetInventory(src) or {}
    local found=nil
    for _,it in ipairs(inv) do if it.name==name and (not it.metadata or not it.metadata.pathway or it.metadata.pathway==t.key) then found=it break end end
    if not found and allowGive and g.GiveOnAssignment~=false then
        A.GiveItem(src,name,1,meta)
        return
    end
    if found and GetResourceState('ox_inventory')=='started' and found.slot and g.UpdateMetadata~=false then
        pcall(function() exports.ox_inventory:SetMetadata(src,found.slot,meta) end)
    end
end

local function removeGuideItem(src,t)
    local g=CFG.GuideItem or {}; if g.RemoveOnCompletion~=true or not A or not A.RemoveItem then return end
    local name=guideItemName(t); local inv=A.GetInventory and A.GetInventory(src) or {}
    for _,it in ipairs(inv) do if it.name==name and it.metadata and it.metadata.pathway==t.key then A.RemoveItem(src,name,1,it.metadata,it.slot); break end end
end

local function notify(src,title,message,kind,t)
    if not (CFG.Tracking and CFG.Tracking.Notifications) or (t and t.tracking and t.tracking.Notifications==false) then return end
    TriggerClientEvent('rs-admin:client:pathwayNotify',src,{title=title,message=message,kind=kind or 'info'})
end

local function routeCurrent(src,t,a,force)
    local tracking=t.tracking or {}; local global=CFG.Tracking or {}
    if global.GPS==false or tracking.GPS==false then return end
    local s=currentStep(t,a)
    if s and s.x and s.y and s.z then
        if force or (CFG.GPS and CFG.GPS.AutoRouteNextLocation) then
            TriggerClientEvent('rs-admin:client:pathwayRoute',src,{label=s.label,x=s.x,y=s.y,z=s.z,radius=s.radius or 12.0})
        else
            TriggerClientEvent('rs-admin:client:pathwayObjective',src,{track=t.key,label=t.label,step=s})
        end
    end
end

local function grantReward(src,reward,reason)
    if type(reward)~='table' or not A then return end
    if tonumber(reward.cash)>0 then A.ChangeMoney(src,'cash','add',math.floor(reward.cash),reason) end
    if tonumber(reward.bank)>0 then A.ChangeMoney(src,'bank','add',math.floor(reward.bank),reason) end
    if type(reward.item)=='table' and reward.item.name then A.GiveItem(src,tostring(reward.item.name),math.max(1,math.floor(tonumber(reward.item.amount) or 1)),reward.item.metadata) end
    if type(reward.items)=='table' then for _,it in ipairs(reward.items) do if type(it)=='table' and it.name then A.GiveItem(src,tostring(it.name),math.max(1,math.floor(tonumber(it.amount) or 1)),it.metadata) end end end
    if type(reward.vehicle)=='table' and reward.vehicle.model and A.GiveOwnedVehicle then A.GiveOwnedVehicle(src,reward.vehicle.model,reward.vehicle.garage,reward.vehicle.props or {}) end
end

local function finishIfReady(src,t,a)
    if a.status=='certified' then return true end
    if not requiredDone(t,a) then return false end
    if (tonumber(a.points) or 0) < (tonumber(t.requiredPoints) or 0) then return false end
    a.status='certified'; a.completedAt=os.time(); a.updatedAt=os.time()
    local online=src and src>0 and GetPlayerName(src)~=nil
    if not a.rewardsClaimed and online then grantReward(src,t.rewards,'RS Pathways: '..t.label); a.rewardsClaimed=true end
    STORE.history[#STORE.history+1]={at=os.time(),action='certified',identifier=a.identifier,track=t.key,name=a.playerName}
    while #STORE.history>5000 do table.remove(STORE.history,1) end
    saveStore()
    if online then
        syncGuideItem(src,t,a,false); removeGuideItem(src,t)
        notify(src,'CERTIFICATION COMPLETE',('%s complete · %s points'):format(t.label,a.points or 0),'complete',t)
    end
    C.Audit(0,'pathway certified',t.key,a.playerName)
    return true
end

local function completeStep(src,t,a,s,evidence)
    a.completed=a.completed or {}; a.progress=a.progress or {}
    if a.completed[s.key] then return false,'already complete' end
    a.completed[s.key]={at=os.time(),points=s.points or 0,evidence=clean(evidence or '',180)}
    a.progress[s.key]=nil
    a.points=(tonumber(a.points) or 0)+(tonumber(s.points) or 0)
    a.updatedAt=os.time()
    STORE.history[#STORE.history+1]={at=os.time(),action='step',identifier=a.identifier,track=t.key,step=s.key,points=s.points or 0,name=a.playerName}
    while #STORE.history>5000 do table.remove(STORE.history,1) end
    saveStore(); syncGuideItem(src,t,a,false)
    notify(src,'PATHWAY UPDATED',('%s complete · +%s points'):format(s.label,s.points or 0),'step',t)
    local finished=finishIfReady(src,t,a)
    if not finished then routeCurrent(src,t,a,false) end
    return true
end

local function assignmentsFor(src)
    local id=primary(src); local b=STORE.assignments[id] or {}; local out={}
    for key,a in pairs(b) do local t=track(key); if t then out[#out+1]=displayState(t,a) end end
    table.sort(out,function(a,b) return (a.startedAt or 0)>(b.startedAt or 0) end)
    return out,id
end

local function showStatus(src,requested,route)
    if not CFG.Enabled then return end
    local rows=assignmentsFor(src); local chosen=nil
    if requested and requested~='' then for _,r in ipairs(rows) do if r.track==requested then chosen=r break end end end
    chosen=chosen or rows[1]
    if not chosen then notify(src,'PATHWAYS','No active pathway assignments.','info'); return end
    local t=track(chosen.track); local id=primary(src); local a=STORE.assignments[id] and STORE.assignments[id][chosen.track]
    if not t or not a then return end
    local step=currentStep(t,a)
    TriggerClientEvent('rs-admin:client:pathwayStatus',src,{state=displayState(t,a),steps=t.steps,completed=a.completed or {}})
    if route and step and step.x and (not CFG.GPS or CFG.GPS.AllowPlayerRoute~=false) then routeCurrent(src,t,a,true) end
end

local function assign(src,targetId,key,forced)
    if not CFG.Enabled then return false,'Pathways disabled' end
    local t=track(key); if not t or not t.enabled then return false,'Pathway unavailable' end
    local identifier=primary(targetId)
    local met,missing=requirementsMet(identifier,t); if not met then return false,('Requires certification: %s'):format(missing) end
    local b=bucketFor(identifier); local a=b[t.key]
    if a and a.status=='active' then return false,'Pathway already active' end
    a={identifier=identifier,track=t.key,playerName=GetPlayerName(targetId),points=0,completed={},progress={},status='active',forced=forced==true or t.forcedDefault==true,startedAt=os.time(),updatedAt=os.time(),assignedBy=actor(src),rewardsClaimed=false}
    b[t.key]=a; saveStore(); syncGuideItem(targetId,t,a,true); routeCurrent(targetId,t,a,false)
    notify(targetId,'PATHWAY ASSIGNED',t.label,'assigned',t); C.Audit(src,'pathway assign',t.key,GetPlayerName(targetId)); return true,a
end

local function findOnlineByIdentifier(identifier)
    for _,s in ipairs(GetPlayers()) do local id=tonumber(s); if primary(id)==identifier then return id end end
end

local function safeTrackPayload(t)
    local o={}; for k,v in pairs(t) do if k~='rewards' then o[k]=v end end; o.rewards=t.rewards or {}; return o
end

C.Handle('pathways:tracks','pathways',function() if not CFG.Enabled then return C.Ok({enabled=false,rows={}}) end; local rows=tracks(); local out={}; for _,t in ipairs(rows) do out[#out+1]=safeTrackPayload(t) end; return C.Ok({enabled=true,rows=out}) end)
C.Handle('pathways:list','pathways',function()
    local rows={}; for identifier,b in pairs(STORE.assignments) do for key,a in pairs(b) do local t=track(key); if t then local d=displayState(t,a); d.identifier=identifier; d.name=a.playerName; d.onlineId=findOnlineByIdentifier(identifier); rows[#rows+1]=d end end end
    table.sort(rows,function(a,b) return (a.startedAt or 0)>(b.startedAt or 0) end); return C.Ok(rows)
end)
C.Handle('pathways:player','pathways',function(_,d) local t=target(d.target); if not t then return C.Err('Player not found') end; local rows=assignmentsFor(t); return C.Ok(rows) end)
C.Handle('pathways:assign','pathways',function(src,d) local t=target(d.target); if not t then return C.Err('Player not found') end; local good,res=assign(src,t,clean(d.track,48),d.forced==true); return good and C.Ok(res) or C.Err(res) end)
C.Handle('pathways:reset','pathways',function(src,d)
    local t=target(d.target); local identifier=t and primary(t) or clean(d.identifier,180); local key=clean(d.track,48); local tr=track(key); local b=STORE.assignments[identifier]; local old=b and b[key]; if not tr or not old then return C.Err('Assignment not found') end
    b[key]={identifier=identifier,track=key,playerName=t and GetPlayerName(t) or old.playerName,points=0,completed={},progress={},status='active',forced=old.forced,startedAt=os.time(),updatedAt=os.time(),assignedBy=actor(src),rewardsClaimed=false}; saveStore(); if t then syncGuideItem(t,tr,b[key],true); routeCurrent(t,tr,b[key],false) end; C.Audit(src,'pathway reset',key,old.playerName); return C.Ok(displayState(tr,b[key]))
end)
C.Handle('pathways:revoke','pathways',function(src,d)
    local t=target(d.target); local identifier=t and primary(t) or clean(d.identifier,180); local key=clean(d.track,48); local b=STORE.assignments[identifier]; local a=b and b[key]; if not a then return C.Err('Assignment not found') end; a.status='revoked';a.revokedAt=os.time();a.revokedBy=actor(src);a.updatedAt=os.time();saveStore();C.Audit(src,'pathway revoke',key,a.playerName);if t then local tr=track(key); if tr then syncGuideItem(t,tr,a,false) end; notify(t,'PATHWAY REVOKED',tr and tr.label or key,'warn',tr) end;return C.Ok(true)
end)
C.Handle('pathways:certify','pathways',function(src,d)
    local t=target(d.target); local identifier=t and primary(t) or clean(d.identifier,180); local key=clean(d.track,48); local tr=track(key); local b=STORE.assignments[identifier]; local a=b and b[key]; if not tr or not a then return C.Err('Assignment not found') end
    for _,s in ipairs(tr.steps) do if not a.completed[s.key] then a.completed[s.key]={at=os.time(),points=s.points or 0,evidence='staff certification'};a.points=(a.points or 0)+(s.points or 0) end end
    if a.points<tr.requiredPoints then a.points=tr.requiredPoints end; a.status='active'; finishIfReady(t or 0,tr,a); C.Audit(src,'pathway certify',key,a.playerName); return C.Ok(displayState(tr,a))
end)
C.Handle('pathways:advance','pathways',function(src,d)
    local t=target(d.target); if not t then return C.Err('Player not found') end; local identifier=primary(t);local key=clean(d.track,48);local tr=track(key);local a=STORE.assignments[identifier] and STORE.assignments[identifier][key];if not tr or not a then return C.Err('Assignment not found') end;local s=currentStep(tr,a);if not s then return C.Err('No incomplete step') end;local good,e=completeStep(t,tr,a,s,'staff advance: '..actor(src));if good then C.Audit(src,'pathway advance',key..':'..s.key,a.playerName);return C.Ok(displayState(tr,a)) end;return C.Err(e)
end)

local function validateTrackInput(d)
    local key=clean((d.key or ''):lower():gsub('[^%w_%-]',''),48); if key=='' then return nil,'Key required' end
    local row={label=clean(d.label or key,100),description=clean(d.description or '',240),enabled=d.enabled~=false,requiredPoints=math.max(0,math.min(100000,math.floor(tonumber(d.requiredPoints) or 0))),forcedDefault=d.forcedDefault==true,autoAssign=d.autoAssign==true,ordered=d.ordered~=false,requires=type(d.requires)=='table' and d.requires or {},guideItem=clean(d.guideItem or '',64),steps=normalizedSteps(d.steps),rewards=type(d.rewards)=='table' and d.rewards or {},tracking=type(d.tracking)=='table' and d.tracking or {}}
    return key,row
end
C.Handle('pathways:trackSave','owner',function(src,d) local key,row=validateTrackInput(d);if not key then return C.Err(row) end;CUSTOM[key]=row;saveTracks();C.Audit(src,'pathway track save',key,key);return C.Ok(normalizedTrack(key,row,'custom')) end)
C.Handle('pathways:trackDelete','owner',function(src,d) local key=clean(d.key,48);if not CUSTOM[key] then return C.Err('Only custom/overridden tracks can be deleted') end;CUSTOM[key]=nil;saveTracks();C.Audit(src,'pathway track delete',key,key);return C.Ok(true) end)
C.Handle('pathways:trackClone','owner',function(src,d) local from=track(d.from);if not from then return C.Err('Source track not found') end;local key=clean((d.key or ''):lower():gsub('[^%w_%-]',''),48);if key=='' or track(key) then return C.Err('Unique key required') end;CUSTOM[key]={label=clean(d.label or (from.label..' Copy'),100),description=from.description,enabled=true,requiredPoints=from.requiredPoints,forcedDefault=from.forcedDefault,autoAssign=false,ordered=from.ordered~=false,requires=from.requires,guideItem=from.guideItem,steps=from.steps,rewards=from.rewards,tracking=from.tracking};saveTracks();C.Audit(src,'pathway track clone',from.key..' -> '..key,key);return C.Ok(normalizedTrack(key,CUSTOM[key],'custom')) end)

local function evaluateImmediate(src,t,a,s)
    if s.type=='job' then local d=playerData(src); return d and d.job and tostring(d.job.name)==s.value
    elseif s.type=='gang' then local d=playerData(src); return d and d.gang and tostring(d.gang.name)==s.value
    elseif s.type=='item' then for _,it in ipairs(A.GetInventory(src) or {}) do if it.name==s.value and (tonumber(it.count) or 0)>=s.count then return true end end
    elseif s.type=='money' then local v=A.GetMoney(src,s.account or 'bank'); return v~=nil and v>=s.amount
    elseif s.type=='owned_vehicle' then return #(A.GetOwnedVehicles(src) or {})>=s.count
    end
    return false
end

local function reportEvent(src,eventName,data,invoking)
    if not CFG.Enabled or not GetPlayerName(src) then return false,'player not found' end
    eventName=clean(eventName,64); local identifier=primary(src); local b=STORE.assignments[identifier] or {}; local changed=false
    for key,a in pairs(b) do
        if a.status=='active' then local t=track(key); if t then for _,s in ipairs(eligibleSteps(t,a)) do if s.type=='event' and s.event==eventName then local good=completeStep(src,t,a,s,('server event %s via %s'):format(eventName,invoking or 'server'));changed=good or changed; if t.ordered~=false then break end end end end
    end end
    return changed, changed and nil or 'no matching active step'
end

exports('ReportPathwayEvent',function(src,eventName,data) return reportEvent(tonumber(src),eventName,data,GetInvokingResource()) end)
exports('HasPathwayCertification',function(src,key)
    if not CFG.Enabled then return true end
    local identifier=type(src)=='number' and primary(src) or tostring(src or ''); return certification(identifier,tostring(key or ''):lower())
end)
exports('GetPathwayStatus',function(src) return assignmentsFor(tonumber(src)) end)
exports('AssignPathway',function(src,key,forced) local t=tonumber(src); if not t then return false,'player required' end; return assign(0,t,key,forced) end)

RegisterNetEvent('rs-admin:pathways:guide',function(trackKey,route)
    local src=source; if not GetPlayerName(src) then return end; showStatus(src,clean(trackKey or '',48),route==true)
end)

RegisterCommand((CFG.Command or 'pathway'),function(src,args)
    if src<=0 or not CFG.Enabled or not (CFG.Tracking and CFG.Tracking.ChatCommand) then return end
    showStatus(src,clean(args[1] or '',48),false)
end,false)

-- Internal authoritative validators. These never trust a generic client completion event.
CreateThread(function()
    while true do
        Wait(math.max(2000,math.floor((CFG.ValidationSeconds or 5)*1000)))
        if CFG.Enabled then
            local now=os.time(); local delta=math.max(1,math.min(30,now-lastTick)); lastTick=now
            local progressDirty=false
            local online=GetPlayers()
            for _,sid in ipairs(online) do
                local src=tonumber(sid); local identifier=primary(src); local b=STORE.assignments[identifier] or {}
                for key,a in pairs(b) do if a.status=='active' then
                    local t=track(key)
                    if t then for _,s in ipairs(eligibleSteps(t,a)) do
                        local done=false; local evidence='server validator'
                        if s.type=='location' and s.x and s.y and s.z then
                            local ped=GetPlayerPed(src); if ped and ped~=0 then local c=GetEntityCoords(ped);local dx,dy,dz=c.x-s.x,c.y-s.y,c.z-s.z;local inside=(dx*dx+dy*dy+dz*dz)<=((s.radius or 12)^2);a.progress=a.progress or {};local p=a.progress[s.key] or {seconds=0};p.seconds=inside and ((p.seconds or 0)+delta) or 0;a.progress[s.key]=p;progressDirty=true;done=inside and p.seconds>=math.max(0,s.seconds or 0);evidence=('location %.1fm'):format(math.sqrt(dx*dx+dy*dy+dz*dz)) end
                        elseif s.type=='online_time' then a.progress=a.progress or {};local p=a.progress[s.key] or {seconds=0};p.seconds=(p.seconds or 0)+delta;a.progress[s.key]=p;progressDirty=true;done=p.seconds>=math.max(1,s.seconds);evidence=('online %ss'):format(p.seconds)
                        elseif s.type=='interaction_time' then
                            local ped=GetPlayerPed(src);if ped and ped~=0 then local c=GetEntityCoords(ped);local near={};for _,oid in ipairs(online) do local other=tonumber(oid);if other~=src then local op=GetPlayerPed(other);if op and op~=0 then local oc=GetEntityCoords(op);local dx,dy,dz=c.x-oc.x,c.y-oc.y,c.z-oc.z;if (dx*dx+dy*dy+dz*dz)<=((s.radius or 5)^2) then near[#near+1]=primary(other) end end end end;a.progress=a.progress or {};local p=a.progress[s.key] or {seconds=0,unique={}};if #near>0 then p.seconds=(p.seconds or 0)+delta;for _,id in ipairs(near) do p.unique[id]=true end end;a.progress[s.key]=p;progressDirty=true;local uc=0;for _ in pairs(p.unique or {}) do uc=uc+1 end;done=p.seconds>=math.max(1,s.seconds) and uc>=math.max(1,s.uniquePlayers or 1);evidence=('proximity %ss / %s unique'):format(p.seconds,uc) end
                        elseif s.type=='job' or s.type=='gang' or s.type=='item' or s.type=='money' or s.type=='owned_vehicle' then
                            a.progress=a.progress or {}; local p=a.progress[s.key] or {}; local interval=math.max(5,math.floor(tonumber(CFG.ProviderValidationSeconds) or 15)); if not p.lastProviderCheck or now-p.lastProviderCheck>=interval then p.lastProviderCheck=now; a.progress[s.key]=p; done=evaluateImmediate(src,t,a,s) end
                        end
                        if done then completeStep(src,t,a,s,evidence); if t.ordered~=false then break end end
                    end end
                end end
            end
            local checkpoint=math.max(10,math.floor(tonumber(CFG.ProgressSaveSeconds) or 30))
            if progressDirty and now-lastProgressSave>=checkpoint then saveStore(); lastProgressSave=now end
        end
    end
end)

autoAssign=function(src)
    if not CFG.Enabled then return end
    for _,t in ipairs(tracks()) do if t.enabled and t.autoAssign then
        local identifier=primary(src); local b=bucketFor(identifier); if not b[t.key] then assign(0,src,t.key,t.forcedDefault) end
    end end
end
AddEventHandler('playerJoining',function()
    local src=source
    SetTimeout(8000,function()
        if not GetPlayerName(src) then return end
        autoAssign(src)
        local rows=assignmentsFor(src)
        local identifier=primary(src)
        for _,r in ipairs(rows) do
            local t=track(r.track)
            local a=STORE.assignments[identifier] and STORE.assignments[identifier][r.track]
            if t and a then
                if a.status=='active' then
                    syncGuideItem(src,t,a,false)
                    routeCurrent(src,t,a,false)
                elseif a.status=='certified' and not a.rewardsClaimed then
                    grantReward(src,t.rewards,'RS Pathways: '..t.label)
                    a.rewardsClaimed=true
                    a.updatedAt=os.time()
                    saveStore()
                    syncGuideItem(src,t,a,false)
                    removeGuideItem(src,t)
                    notify(src,'CERTIFICATION REWARD',('%s reward delivered.'):format(t.label),'complete',t)
                end
            end
        end
    end)
end)

RSAdminPathways={
    Enabled=function() return CFG.Enabled==true end,
    HasCertification=function(src,key) if not CFG.Enabled then return true end; local id=type(src)=='number' and primary(src) or tostring(src or '');return certification(id,key) end,
    ReportEvent=reportEvent,
    Assign=assign,
    Tracks=tracks,
    Store=STORE,
}
