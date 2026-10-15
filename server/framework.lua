RSAdminServer = RSAdminServer or {}
local A = {}
RSAdminServer.Adapter = A

local itemCache
local weaponCache
local qbcache

local function qb()
    if qbcache then return qbcache end
    if GetResourceState('qb-core') ~= 'started' then return nil end
    local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok then qbcache = core end
    return qbcache
end

function A.Framework()
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

function A.GetPlayerData(src)
    if A.Framework() == 'qbox' then
        local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok and p then return p.PlayerData, p end
    elseif A.Framework() == 'qbcore' then
        local core = qb(); local p = core and core.Functions.GetPlayer(src)
        if p then return p.PlayerData, p end
    elseif A.Framework() == 'esx' then
        local ok, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
        local p = ok and esx and esx.GetPlayerFromId(src)
        if p then return { identifier = p.identifier, source = src }, p end
    end
end

function A.ItemList(refresh)
    if itemCache and not refresh then return itemCache end
    local list, seen = {}, {}
    local function add(name, label, image, weight)
        name = tostring(name or '')
        if name == '' or seen[name] then return end
        seen[name] = true
        list[#list+1] = {name=name, label=tostring(label or name), image=image, weight=tonumber(weight) or 0}
    end

    if GetResourceState('ox_inventory') == 'started' then
        local ok, items = pcall(function() return exports.ox_inventory:Items() end)
        if ok and type(items) == 'table' then
            for name, d in pairs(items) do
                local image=('nui://ox_inventory/web/images/%s.png'):format(name)
                if type(d)=='table' and d.client and d.client.image then image=tostring(d.client.image) end
                add(name, type(d)=='table' and (d.label or d.name) or name, image, type(d)=='table' and d.weight or 0)
            end
        end
    end

    if #list == 0 and A.Framework() == 'qbcore' then
        local core=qb()
        if core and core.Shared and core.Shared.Items then
            for name,d in pairs(core.Shared.Items) do
                local image=type(d)=='table' and d.image or nil
                if image and not tostring(image):match('^https?://') and not tostring(image):match('^nui://') then image=('nui://qb-inventory/html/images/%s'):format(image) end
                image=image or ('nui://qb-inventory/html/images/%s.png'):format(name)
                add(name, type(d)=='table' and (d.label or d.name) or name, image, type(d)=='table' and d.weight or 0)
            end
        end
    end

    if #list == 0 and A.Framework() == 'esx' then
        local ok, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and esx then
            local items
            if esx.GetItems then pcall(function() items = esx.GetItems() end) end
            items = items or esx.Items
            if type(items) == 'table' then
                for name,d in pairs(items) do
                    if type(d) == 'table' then add(d.name or name, d.label or d.name or name) else add(name, name) end
                end
            end
        end
    end

    table.sort(list,function(a,b) return a.label:lower() < b.label:lower() end)
    itemCache = list
    return list
end

function A.ItemExists(name)
    for _, item in ipairs(A.ItemList(false)) do if item.name == name then return true end end
    return false
end

function A.GiveItem(src, item, amount, metadata)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if GetResourceState('ox_inventory') == 'started' then
        local ok, success, response = pcall(function()
            if exports.ox_inventory:CanCarryItem(src, item, amount, metadata) == false then return false, 'inventory_full' end
            return exports.ox_inventory:AddItem(src, item, amount, metadata)
        end)
        if not ok then return false, tostring(success) end
        return success == true, response
    end

    local data, p = A.GetPlayerData(src)
    if not p then return false, 'player not found' end
    if p.Functions and p.Functions.AddItem then
        local ok, result = pcall(function() return p.Functions.AddItem(item, amount, false, metadata) end)
        return ok and result ~= false, ok and nil or tostring(result)
    end
    if p.addInventoryItem then
        if p.canCarryItem then
            local carryOk, canCarry = pcall(function() return p.canCarryItem(item, amount) end)
            if carryOk and canCarry == false then return false, 'inventory_full' end
        end
        local ok, result = pcall(function() return p.addInventoryItem(item, amount, metadata) end)
        return ok and result ~= false, ok and nil or tostring(result)
    end
    return false, 'no supported inventory provider'
end


function A.WeaponList(refresh)
    if weaponCache and not refresh then return weaponCache end
    local list, seen = {}, {}
    local defaults = {}
    for _, w in ipairs(Config.Weapons or {}) do
        local name=tostring(w.name or ''):upper()
        if name~='' then defaults[name]=w end
    end
    local function add(name,label,weapontype)
        name=tostring(name or ''):upper()
        if name=='' or name=='WEAPON_UNARMED' or seen[name] then return end
        -- qbx/qb weapon tables also contain damage pseudo-weapons; keep only usable weapon/gadget names.
        if not (name:match('^WEAPON_') or name:match('^GADGET_')) then return end
        local d=defaults[name]
        if tostring(weapontype or '')=='Miscellaneous' and not d then return end
        seen[name]=true
        list[#list+1]={name=name,label=tostring(label or (d and d.label) or name),ammo=(d and d.ammo) or ((weapontype=='Melee') and 1 or 250)}
    end

    if A.Framework()=='qbox' then
        local ok,weapons=pcall(function() return exports.qbx_core:GetWeapons() end)
        if ok and type(weapons)=='table' then
            for _,w in pairs(weapons) do if type(w)=='table' then add(w.name,w.label,w.weapontype) end end
        end
    elseif A.Framework()=='qbcore' then
        local core=qb()
        if core and core.Shared and core.Shared.Weapons then
            for _,w in pairs(core.Shared.Weapons) do if type(w)=='table' then add(w.name,w.label,w.weapontype) end end
        end
    end

    -- Always include RS defaults, including native weapons not present in the framework table.
    for _,w in ipairs(Config.Weapons or {}) do add(w.name,w.label,w.weapontype) end
    table.sort(list,function(a,b) return a.label:lower()<b.label:lower() end)
    weaponCache=list
    return list
end

function A.VehicleFrameworkList()
    local list, seen = {}, {}
    local function add(model, brand, label, category)
        model=tostring(model or ''):lower()
        if model=='' or seen[model] then return end
        seen[model]=true
        local title=tostring(label or model)
        if brand and tostring(brand)~='' then title=tostring(brand)..' '..title end
        list[#list+1]={model=model,label=title,category=tostring(category or 'Other')}
    end
    if A.Framework() == 'qbox' then
        local ok, vehicles = pcall(function() return exports.qbx_core:GetVehiclesByName() end)
        if ok and type(vehicles)=='table' then
            for spawn,v in pairs(vehicles) do add((type(v)=='table' and v.model) or spawn, type(v)=='table' and v.brand, type(v)=='table' and v.name, type(v)=='table' and v.category) end
        end
    elseif A.Framework() == 'qbcore' then
        local core=qb()
        if core and core.Shared and core.Shared.Vehicles then
            for spawn,v in pairs(core.Shared.Vehicles) do add((type(v)=='table' and v.model) or spawn, type(v)=='table' and v.brand, type(v)=='table' and v.name, type(v)=='table' and v.category) end
        end
    end
    table.sort(list,function(a,b) return a.label:lower() < b.label:lower() end)
    return list
end

function A.Garages()
    local out={}
    for _,provider in ipairs({'rs-garage','rs-zombiegarage'}) do
      if GetResourceState(provider)=='started' then
        local ok,garages=pcall(function() return exports[provider]:getAllGarages() end)
        if ok and type(garages)=='table' then
            for _,g in ipairs(garages) do
                if type(g)=='table' and g.name then out[#out+1]={name=g.name,label=g.label or g.name} end
            end
            table.sort(out,function(a,b) return tostring(a.label):lower()<tostring(b.label):lower() end)
            return out
        end
        return out
      end
    end
    if A.Framework()=='qbox' and GetResourceState('qbx_garages')=='started' then
        local ok, garages=pcall(function() return exports.qbx_garages:GetGarages() end)
        if ok and type(garages)=='table' then
            for name,g in pairs(garages) do
                out[#out+1]={name=name,label=(type(g)=='table' and (g.label or g.name)) or name}
            end
        end
    end
    table.sort(out,function(a,b) return a.label:lower()<b.label:lower() end)
    return out
end

local function genPlate()
    local letters='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local function pick() local i=math.random(1,#letters); return letters:sub(i,i) end
    for _=1,25 do
        local plate=('RS%s%s%03d'):format(pick(),pick(),math.random(0,999)):sub(1,8)
        if GetResourceState('qbx_vehicles') ~= 'started' then return plate end
        local exists=false
        local ok=pcall(function() exists=exports.qbx_vehicles:DoesPlayerVehiclePlateExist(plate)==true end)
        if ok and not exists then return plate end
    end
    return ('RS%06d'):format(math.random(0,999999)):sub(1,8)
end

function A.GiveOwnedVehicle(target, model, garage, props)
    local framework=A.Framework()
    local data=A.GetPlayerData(target)
    if not data then return false,'player not found' end
    model=tostring(model or ''):lower()
    garage=(garage and tostring(garage)~='') and tostring(garage) or Config.DefaultGarage
    props=type(props)=='table' and props or {}
    props.model=props.model or joaat(model)
    props.plate=(props.plate and tostring(props.plate):upper():sub(1,8)) or genPlate()

    if framework=='qbox' and GetResourceState('qbx_vehicles')=='started' then
        local ok, id, er = pcall(function()
            return exports.qbx_vehicles:CreatePlayerVehicle({model=model,citizenid=data.citizenid,garage=garage,props=props})
        end)
        if not ok then return false,tostring(id) end
        if not id then return false,(type(er)=='table' and er.message) or 'qbx_vehicles rejected vehicle' end
        return true,{vehicleId=id,plate=props.plate,garage=garage}
    end

    if framework=='qbcore' then
        if GetResourceState('oxmysql')~='started' then return false,'oxmysql required for QBCore owned vehicles' end
        local license=data.license or data.license2
        local citizenid=data.citizenid
        if not license or not citizenid then return false,'player identifiers missing' end
        local ok, insertId=pcall(function()
            return exports.oxmysql:insert_async(
                'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state, garage, fuel, engine, body) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                {license,citizenid,model,joaat(model),json.encode(props),props.plate,1,garage,100,1000.0,1000.0}
            )
        end)
        if not ok then return false,tostring(insertId) end
        -- An SQL INSERT can return nil/false without throwing. Do not report
        -- a garage vehicle as granted unless the database returned an ID.
        if not insertId or insertId==false or tonumber(insertId)==0 then
            return false,'QBCore garage database did not confirm vehicle creation'
        end
        return true,{vehicleId=insertId,plate=props.plate,garage=garage}
    end

    return false,'owned vehicle provider not configured for '..framework
end

function A.GiveKeys(target, vehicle)
    if GetResourceState('qbx_vehiclekeys')=='started' then
        pcall(function() exports.qbx_vehiclekeys:GiveKeys(target, vehicle, true) end)
        return true
    end
    if GetResourceState('qb-vehiclekeys')=='started' then
        local plate=GetVehicleNumberPlateText(vehicle)
        TriggerClientEvent('vehiclekeys:client:SetOwner',target,plate)
        return true
    end
    return false
end


-- v0.7 player/economy/inventory/job adapters -----------------------------------
function A.GetMoney(src, account)
    account=tostring(account or 'cash')
    local framework=A.Framework()
    if framework=='qbox' then
        local ok,value=pcall(function() return exports.qbx_core:GetMoney(src,account) end)
        return ok and tonumber(value) or nil
    end
    local data,p=A.GetPlayerData(src); if not p then return nil end
    if framework=='qbcore' then return tonumber(data.money and data.money[account]) or 0 end
    if framework=='esx' then
        if account=='cash' and p.getMoney then return tonumber(p.getMoney()) or 0 end
        if p.getAccount then local a=p.getAccount(account); return a and tonumber(a.money) or 0 end
    end
end

function A.ChangeMoney(src, account, mode, amount, reason)
    account=tostring(account or 'cash'); mode=tostring(mode or 'add'); amount=math.floor(tonumber(amount) or 0)
    if amount<0 then return false,'negative amount' end
    local framework=A.Framework()
    if framework=='qbox' then
        local ok,res=pcall(function()
            local why=reason or 'rs-adminmenu'
            if mode=='add' then return exports.qbx_core:AddMoney(src,account,amount,why) end
            if mode=='remove' then return exports.qbx_core:RemoveMoney(src,account,amount,why) end
            if mode=='set' then return exports.qbx_core:SetMoney(src,account,amount,why) end
            return false
        end)
        return ok and res~=false, ok and nil or tostring(res)
    end
    local data,p=A.GetPlayerData(src); if not p then return false,'player not found' end
    if framework=='qbcore' and p.Functions then
        local map={add='AddMoney',remove='RemoveMoney',set='SetMoney'}; local fn=map[mode]
        if fn and p.Functions[fn] then local ok,res=pcall(function() return p.Functions[fn](account,amount,reason or 'rs-adminmenu') end); return ok and res~=false, ok and nil or tostring(res) end
    elseif framework=='esx' then
        local ok,res=pcall(function()
            if account=='cash' then
                if mode=='add' then return p.addMoney(amount,reason) elseif mode=='remove' then return p.removeMoney(amount,reason) else return p.setMoney(amount) end
            end
            if mode=='add' then return p.addAccountMoney(account,amount,reason) elseif mode=='remove' then return p.removeAccountMoney(account,amount,reason) else return p.setAccountMoney(account,amount,reason) end
        end)
        return ok, ok and nil or tostring(res)
    end
    return false,'money provider unavailable'
end

function A.GetInventory(src)
    if GetResourceState('ox_inventory')=='started' then
        local ok,items=pcall(function() return exports.ox_inventory:GetInventoryItems(src) end)
        if ok and type(items)=='table' then
            local out={}
            for _,item in pairs(items) do if type(item)=='table' and item.name and (tonumber(item.count) or 0)>0 then out[#out+1]={slot=item.slot,name=item.name,label=item.label or item.name,count=item.count,weight=item.weight or 0,metadata=item.metadata or {},image=('nui://ox_inventory/web/images/%s.png'):format(item.name)} end end
            table.sort(out,function(a,b) return (a.slot or 999)<(b.slot or 999) end); return out
        end
    end
    local data,p=A.GetPlayerData(src); if not p then return {} end
    if A.Framework()=='qbcore' or A.Framework()=='qbox' then
        local out={}; for _,item in pairs(data.items or {}) do if item and item.name and (tonumber(item.amount or item.count) or 0)>0 then out[#out+1]={slot=item.slot,name=item.name,label=item.label or item.name,count=item.amount or item.count,weight=item.weight or 0,metadata=item.info or item.metadata or {},image=item.image and ('nui://qb-inventory/html/images/%s'):format(item.image) or nil} end end; return out
    end
    if A.Framework()=='esx' and p.getInventory then
        local out={}; for _,item in pairs(p.getInventory() or {}) do if (tonumber(item.count) or 0)>0 then out[#out+1]={name=item.name,label=item.label or item.name,count=item.count,weight=item.weight or 0,metadata=item.metadata or {}} end end; return out
    end
    return {}
end

function A.RemoveItem(src,item,amount,metadata,slot)
    amount=math.max(1,math.floor(tonumber(amount) or 1))
    if GetResourceState('ox_inventory')=='started' then
        local ok,success,response=pcall(function() return exports.ox_inventory:RemoveItem(src,item,amount,metadata,slot) end)
        return ok and success==true, ok and response or tostring(success)
    end
    local _,p=A.GetPlayerData(src); if not p then return false,'player not found' end
    if p.Functions and p.Functions.RemoveItem then local ok,res=pcall(function() return p.Functions.RemoveItem(item,amount,slot) end); return ok and res~=false, ok and nil or tostring(res) end
    if p.removeInventoryItem then local ok,res=pcall(function() return p.removeInventoryItem(item,amount,metadata,slot) end); return ok and res~=false, ok and nil or tostring(res) end
    return false,'remove item provider unavailable'
end

function A.GetOwnedVehicles(src)
    local data=A.GetPlayerData(src); if not data then return {} end
    if A.Framework()=='qbox' and GetResourceState('qbx_vehicles')=='started' and data.citizenid then
        local ok,vehicles=pcall(function() return exports.qbx_vehicles:GetPlayerVehicles({citizenid=data.citizenid}) end)
        if ok and type(vehicles)=='table' then
            local out={}
            for _,vehicle in ipairs(vehicles) do
                local row={};for key,value in pairs(vehicle) do row[key]=value end
                row.plate=row.plate or (type(row.props)=='table' and row.props.plate)
                out[#out+1]=row
            end
            return out
        end
    end
    if A.Framework()=='qbcore' and GetResourceState('oxmysql')=='started' and data.citizenid then
        local ok,rows=pcall(function() return exports.oxmysql:query_async('SELECT id, citizenid, vehicle AS modelName, garage, state, plate, mods AS props FROM player_vehicles WHERE citizenid = ?', {data.citizenid}) end)
        if ok and type(rows)=='table' then return rows end
    end
    return {}
end

function A.JobList()
    local out={}
    if A.Framework()=='qbox' then
        local ok,jobs=pcall(function() return exports.qbx_core:GetJobs() end)
        if ok and type(jobs)=='table' then for name,j in pairs(jobs) do out[#out+1]={name=name,label=j.label or name,grades=j.grades or {}} end end
    elseif A.Framework()=='qbcore' then
        local core=qb(); for name,j in pairs(core and core.Shared and core.Shared.Jobs or {}) do out[#out+1]={name=name,label=j.label or name,grades=j.grades or {}} end
    end
    table.sort(out,function(a,b) return a.label:lower()<b.label:lower() end); return out
end
function A.GangList()
    local out={}
    if A.Framework()=='qbox' then local ok,gangs=pcall(function() return exports.qbx_core:GetGangs() end); if ok and type(gangs)=='table' then for name,g in pairs(gangs) do out[#out+1]={name=name,label=g.label or name,grades=g.grades or {}} end end
    elseif A.Framework()=='qbcore' then local core=qb(); for name,g in pairs(core and core.Shared and core.Shared.Gangs or {}) do out[#out+1]={name=name,label=g.label or name,grades=g.grades or {}} end end
    table.sort(out,function(a,b) return a.label:lower()<b.label:lower() end); return out
end
function A.SetJob(src,name,grade)
    grade=math.max(0,math.floor(tonumber(grade) or 0)); name=tostring(name or '')
    if A.Framework()=='qbox' then local ok,res=pcall(function() return exports.qbx_core:SetJob(src,name,grade) end); return ok and res~=false, ok and nil or tostring(res) end
    local _,p=A.GetPlayerData(src); if p and p.Functions and p.Functions.SetJob then local ok,res=pcall(function() return p.Functions.SetJob(name,grade) end); return ok and res~=false, ok and nil or tostring(res) end
    if p and p.setJob then local ok,res=pcall(function() return p.setJob(name,grade) end); return ok and res~=false, ok and nil or tostring(res) end
    return false,'job provider unavailable'
end
function A.SetGang(src,name,grade)
    grade=math.max(0,math.floor(tonumber(grade) or 0)); name=tostring(name or '')
    if A.Framework()=='qbox' then local ok,res=pcall(function() return exports.qbx_core:SetGang(src,name,grade) end); return ok and res~=false, ok and nil or tostring(res) end
    local _,p=A.GetPlayerData(src); if p and p.Functions and p.Functions.SetGang then local ok,res=pcall(function() return p.Functions.SetGang(name,grade) end); return ok and res~=false, ok and nil or tostring(res) end
    return false,'gang provider unavailable'
end

-- v0.9 owned-vehicle database helpers ------------------------------------------
function A.FindOwnedVehicleByPlate(plate)
    plate=tostring(plate or ''):upper():gsub('^%s+',''):gsub('%s+$','')
    if plate=='' then return nil,'plate required' end
    if A.Framework()=='qbox' and GetResourceState('qbx_vehicles')=='started' then
        local ok,vehicleId=pcall(function() return exports.qbx_vehicles:GetVehicleIdByPlate(plate) end)
        if not ok or not vehicleId then return nil,'vehicle not found' end
        local good,row=pcall(function() return exports.qbx_vehicles:GetPlayerVehicle(vehicleId) end)
        return good and row or nil, good and nil or tostring(row)
    end
    if A.Framework()=='qbcore' and GetResourceState('oxmysql')=='started' then
        local ok,row=pcall(function() return exports.oxmysql:single_async('SELECT id, citizenid, vehicle AS modelName, plate, garage, state, mods AS props FROM player_vehicles WHERE plate = ? LIMIT 1',{plate}) end)
        return ok and row or nil, ok and nil or tostring(row)
    end
    return nil,'owned vehicle lookup provider unavailable'
end

function A.DeleteOwnedVehicleByPlate(plate)
    plate=tostring(plate or ''):upper():gsub('^%s+',''):gsub('%s+$','')
    if plate=='' then return false,'plate required' end
    if A.Framework()=='qbox' and GetResourceState('qbx_vehicles')=='started' then
        local ok,success,err=pcall(function() return exports.qbx_vehicles:DeletePlayerVehicles('plate',plate) end)
        if not ok then return false,tostring(success) end
        return success==true, err and (err.message or tostring(err)) or nil
    end
    if A.Framework()=='qbcore' and GetResourceState('oxmysql')=='started' then
        local ok,res=pcall(function() return exports.oxmysql:update_async('DELETE FROM player_vehicles WHERE plate = ?',{plate}) end)
        return ok and tonumber(res or 0)>0, ok and nil or tostring(res)
    end
    return false,'owned vehicle delete provider unavailable'
end

function A.SearchOwnedVehicles(query,page,pageSize)
    query=tostring(query or ''):sub(1,80); local q=query:lower()
    page=math.max(1,math.floor(tonumber(page) or 1)); pageSize=math.max(10,math.min(100,math.floor(tonumber(pageSize) or 30)))
    if A.Framework()=='qbox' and GetResourceState('qbx_vehicles')=='started' then
        local ok,all=pcall(function() return exports.qbx_vehicles:GetPlayerVehicles({}) end)
        if not ok or type(all)~='table' then return nil,ok and 'qbx_vehicles returned no vehicle list' or tostring(all) end
        local rows={}
        for _,v in ipairs(all) do
            local plate=tostring((v.props and v.props.plate) or v.plate or '')
            local model=tostring(v.modelName or (v.props and v.props.model) or '')
            local citizen=tostring(v.citizenid or '')
            local hay=(plate..' '..model..' '..citizen):lower()
            if q=='' or hay:find(q,1,true) then rows[#rows+1]={id=v.id,citizenid=v.citizenid,modelName=model,plate=plate,garage=v.garage,state=v.state,props=v.props} end
        end
        table.sort(rows,function(a,b) return (tonumber(a.id) or 0)>(tonumber(b.id) or 0) end)
        local total=#rows; local first=(page-1)*pageSize+1; local out={}
        for i=first,math.min(total,first+pageSize-1) do out[#out+1]=rows[i] end
        return {rows=out,page=page,pageSize=pageSize,total=total,pages=math.max(1,math.ceil(total/pageSize))}
    end
    if A.Framework()=='qbcore' and GetResourceState('oxmysql')=='started' then
        local like='%'..query..'%'; local offset=(page-1)*pageSize
        local sql=[[SELECT pv.id,pv.citizenid,pv.vehicle AS modelName,pv.plate,pv.garage,pv.state,pv.mods AS props,p.name AS ownerName
                    FROM player_vehicles pv LEFT JOIN players p ON p.citizenid=pv.citizenid
                    WHERE (?='' OR pv.plate LIKE ? OR pv.vehicle LIKE ? OR pv.citizenid LIKE ? OR p.name LIKE ?)
                    ORDER BY pv.id DESC LIMIT ? OFFSET ?]]
        local countSql=[[SELECT COUNT(*) AS c FROM player_vehicles pv LEFT JOIN players p ON p.citizenid=pv.citizenid
                         WHERE (?='' OR pv.plate LIKE ? OR pv.vehicle LIKE ? OR pv.citizenid LIKE ? OR p.name LIKE ?)]]
        local args={query,like,like,like,like,pageSize,offset}; local cargs={query,like,like,like,like}
        local ok,rows=pcall(function() return exports.oxmysql:query_async(sql,args) end); if not ok then return nil,tostring(rows) end
        local cok,crow=pcall(function() return exports.oxmysql:single_async(countSql,cargs) end); local total=(cok and crow and tonumber(crow.c)) or #rows
        return {rows=rows or {},page=page,pageSize=pageSize,total=total,pages=math.max(1,math.ceil(total/pageSize))}
    end
    return nil,'owned vehicle search provider unavailable'
end
