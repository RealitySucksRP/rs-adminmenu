RSAdminLua={}
-- CfxLua omits debug.sethook. Instrument executable loop/function boundaries
-- while leaving quoted strings and comments intact. goto is deliberately denied.
local function boundedSource(source)
    local out,i,parameters,depth={},1,false,0
    local function longEnd(at)
        local eq=source:sub(at):match('^%[(=*)%[')
        if eq==nil then return nil end
        local _,last=source:find(']'..eq..']',at+#eq+2,true)
        return last or #source
    end
    while i<=#source do
        local c=source:sub(i,i);local last
        if source:sub(i,i+1)=='--' then
            last=longEnd(i+2) or ((source:find('\n',i+2,true) or (#source+1))-1)
        elseif c=='"' or c=="'" then
            last=i+1
            while last<=#source do local q=source:sub(last,last);if q=='\\' then last=last+2 elseif q==c then break else last=last+1 end end
        elseif c=='[' then last=longEnd(i) end
        if last then out[#out+1]=source:sub(i,last);i=last+1
        elseif c:match('[%a_]') then
            local word=source:sub(i):match('^[%a_][%w_]*');i=i+#word
            if word=='goto' or word=='_RS_OWNER_BUDGET' then return nil,'goto and reserved budget identifiers are not supported' end
            out[#out+1]=word
            if word=='do' or word=='repeat' then out[#out+1]=' _RS_OWNER_BUDGET(); '
            elseif word=='function' then parameters=true;depth=0 end
        else
            out[#out+1]=c;i=i+1
            if parameters then
                if c=='(' then depth=depth+1 elseif c==')' and depth>0 then depth=depth-1;if depth==0 then out[#out+1]=' _RS_OWNER_BUDGET(); ';parameters=false end end
            end
        end
    end
    return table.concat(out)
end
-- Runs text-only Lua against an explicit native API. No file/process access,
-- network callbacks, resource control, dynamic loading or asynchronous threads.
function RSAdminLua.Run(code,context)
    if type(code)~='string' or #code==0 or #code>8192 then return {ok=false,error='Enter 1â€“8192 bytes of Lua'} end
    local output={};local env={context=context or {},assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,tonumber=tonumber,tostring=tostring,type=type,select=select}
    env.print=function(...)
        if #output>=32 then error('Output limit reached',0) end
        local parts={};for i=1,select('#',...) do parts[i]=tostring(select(i,...)):sub(1,256) end
        output[#output+1]=table.concat(parts,'\t'):sub(1,1024)
    end
    env.math={};for k,v in pairs(math) do env.math[k]=v end
    env.string={};for _,key in ipairs({'byte','char','find','len','lower','match','sub','upper'}) do env.string[key]=string[key] end
    env.table={insert=table.insert,remove=table.remove,sort=table.sort}
    env.table.concat=function(t,sep) local bytes=0;if #t>512 then error('Table limit reached',0) end;for _,value in ipairs(t) do bytes=bytes+#tostring(value)+#(sep or '');if bytes>8192 then error('String limit reached',0) end end;return table.concat(t,sep) end
    local names={'GetGameTimer','GetPlayers','GetPlayerName','GetPlayerPed','GetPlayerPing','GetPlayerRoutingBucket','GetAllVehicles','GetAllPeds','GetEntityCoords','GetEntityHeading','GetEntityModel','GetEntityHealth','DoesEntityExist','GetEntityRoutingBucket','GetVehicleNumberPlateText','GetVehiclePedIsIn','GetPedInVehicleSeat','NetworkGetNetworkIdFromEntity','PlayerPedId','PlayerId','GetPlayerServerId','GetClockHours','GetClockMinutes','GetRainLevel','GetWindSpeed','GetNextWeatherTypeHashName','GetPrevWeatherTypeHashName','GetEntityMaxHealth','GetPedArmour','IsModelInCdimage','IsModelValid','IsModelAPed','IsModelAVehicle','joaat','vector3','SetEntityHealth','SetPedArmour','SetEntityCoords','SetEntityHeading','FreezeEntityPosition','SetPlayerRoutingBucket'}
    for _,name in ipairs(names) do if type(_G[name])=='function' then env[name]=_G[name] end end
    local started=GetGameTimer();local count=0
    env._RS_OWNER_BUDGET=function() count=count+1;if count>10000 or GetGameTimer()-started>150 then error('Execution budget exceeded',0) end end
    local bounded,problem=boundedSource(code)
    if not bounded then return {ok=false,error=problem,output=output} end
    local chunk,why=load(bounded,'RS owner '..tostring(context and context.scope or 'console'),'t',env)
    if not chunk then return {ok=false,error=tostring(why):sub(1,1500),output=output} end
    local thread=coroutine.create(chunk)
    local good,result=coroutine.resume(thread)
    if coroutine.status(thread)~='dead' then good=false;result='Yielding is not supported' end
    return {ok=good,error=not good and tostring(result):sub(1,1500) or nil,output=output,result=good and tostring(result):sub(1,2048) or nil,elapsedMs=GetGameTimer()-started}
end
