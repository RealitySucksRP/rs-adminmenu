-- RealitySucksRP / RS AdminMenu - client-only tornado funnel (v0.15.0).
-- Uses GTA's stock particle assets; no streamed models, external resources, or network entities.
-- Every viewer derives the same moving center from the approved server payload.
local Funnel={generation=0,effects={},lod='off',spawned=0}
local SMOKE_ASSET='core'
local SMOKE_FX='ent_amb_fbi_smoke_fogball'
local function stop()
    Funnel.generation=Funnel.generation+1
    for _,fx in ipairs(Funnel.effects) do
        if fx.handle and fx.handle~=0 then pcall(StopParticleFxLooped,fx.handle,false) end
    end
    Funnel.effects={};Funnel.lod='off';Funnel.spawned=0
end
local function startFx(center,layer,arm,height,baseWidth,topWidth)
    local pct=(layer-1)/7
    local radius=baseWidth+(topWidth-baseWidth)*pct
    local theta=arm*2.39996323+layer*.91
    local x=center.x+math.cos(theta)*radius
    local y=center.y+math.sin(theta)*radius
    local z=center.z+height*pct+1.5
    UseParticleFxAssetNextCall(SMOKE_ASSET)
    local scale=(.8+pct*1.15)*((topWidth>18) and 1.15 or 1.0)
    local h=StartParticleFxLoopedAtCoord(SMOKE_FX,x,y,z,0.0,0.0,0.0,scale,false,false,false,false)
    if h and h~=0 then
        SetParticleFxLoopedColour(h,.26,.285,.32,false)
        SetParticleFxLoopedAlpha(h,math.min(.89,.57+pct*.20))
        return {handle=h,x=x,y=y,z=z,layer=layer,arm=arm,pct=pct}
    end
    return nil
end
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(d)
    if source~=65535 then return end
    stop()
    if type(d)~='table' or d.name~='tornado' or type(d.origin)~='table' then return end
    local token=Funnel.generation
    local eventMs=math.max(5000,(tonumber(d.seconds) or 60)*1000)
    local elapsed=math.max(0,tonumber(d.elapsed) or 0)
    local intensity=math.max(.1,math.min(1,tonumber(d.intensity) or .85))
    local width=math.min(34,math.max(10,(tonumber(d.radius) or 60)*.33*intensity))
    if d.style=='extreme' then width=math.min(43,width*1.4) end
    local baseWidth=d.style=='funny' and 5.0 or 3.1
    local height=math.min(75,39+28*intensity+(d.style=='extreme' and 10 or 0))
    CreateThread(function()
        local began=GetGameTimer()
        RequestNamedPtfxAsset(SMOKE_ASSET)
        local timeout=GetGameTimer()+4000
        while token==Funnel.generation and not HasNamedPtfxAssetLoaded(SMOKE_ASSET) and GetGameTimer()<timeout do Wait(0) end
        if token~=Funnel.generation or not HasNamedPtfxAssetLoaded(SMOKE_ASSET) then return end
        while token==Funnel.generation and GetGameTimer()-began<eventMs do
            local now=GetGameTimer()
            local t=(now-began)*.001+elapsed
            local center=RSAdmin.StormCenter(d,t)
            local viewer=GetEntityCoords(PlayerPedId())
            local dist=(viewer.x-center.x)^2+(viewer.y-center.y)^2
            -- No particles outside 420m. Rebuild only when crossing LOD boundaries.
            local lod=dist<210*210 and 'near' or dist<420*420 and 'mid' or 'off'
            if lod~=Funnel.lod then
                for _,fx in ipairs(Funnel.effects) do pcall(StopParticleFxLooped,fx.handle,false) end
                Funnel.effects={};Funnel.lod=lod;Funnel.spawned=0
            end
            if lod~='off' and #Funnel.effects==0 then
                local layers=lod=='near' and 8 or 5
                local arms=lod=='near' and 4 or 2
                for layer=1,layers do
                    for arm=1,arms do
                        if token~=Funnel.generation then return end
                        local actualLayer=layers==8 and layer or math.floor((layer-1)*7/4)+1
                        local fx=startFx(center,actualLayer,arm,height,baseWidth,width)
                        if fx then Funnel.effects[#Funnel.effects+1]=fx;Funnel.spawned=Funnel.spawned+1 end
                        if #Funnel.effects%6==0 then Wait(0) end
                    end
                end
            end
            if lod~='off' then
                local phase=t*(d.style=='extreme' and 3.1 or 2.45)
                for _,fx in ipairs(Funnel.effects) do
                    local radius=baseWidth+(width-baseWidth)*fx.pct
                    local a=phase*(1.35-fx.pct*.35)+fx.arm*(math.pi*.5)+fx.layer*.68
                    local x=center.x+math.cos(a)*radius
                    local y=center.y+math.sin(a)*radius
                    local z=center.z+height*fx.pct+math.sin(phase+fx.layer)*.85+1.5
                    SetParticleFxLoopedOffsets(fx.handle,x-fx.x,y-fx.y,z-fx.z,0.0,0.0,math.deg(a)%360)
                end
            end
            Wait(lod=='near' and 65 or 115)
        end
        if token==Funnel.generation then stop() end
    end)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function() if source==65535 then stop() end end)
AddEventHandler('onResourceStop',function(resource) if resource==GetCurrentResourceName() then stop() end end)
RSAdmin.StormFunnelStats=function() return {lod=Funnel.lod,particles=#Funnel.effects} end
