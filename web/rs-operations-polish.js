/* Scoped live-map controls and profile tabs. No RPC, server, or permission changes. */
(()=>{
  'use strict';
  const content=document.getElementById('content');
  if(!content)return;
  const map={zoom:1.48,x:0,y:0};
  const clamp=(v,min,max)=>Math.max(min,Math.min(max,v));
  const activePane=()=>document.querySelector('#modal:not(.hidden) .rs-map-dialog .map-geographic')||content.querySelector('.rs-tactical-view .map-geographic');
  const boundPan=pane=>{
    const stage=pane?.closest('.map-stage');if(!stage)return;
    const limitX=Math.max(0,(pane.offsetWidth-stage.clientWidth)/2)+stage.clientWidth/3;
    const limitY=Math.max(0,(pane.offsetHeight-stage.clientHeight)/2)+stage.clientHeight/3;
    map.x=clamp(map.x,-limitX,limitX);map.y=clamp(map.y,-limitY,limitY);
  };
  const update=()=>{
    const pane=activePane();
    if(!pane)return;
    pane.style.setProperty('--rs-map-zoom',String(map.zoom));
    boundPan(pane);
    pane.style.setProperty('--rs-map-pan-x',`${map.x}px`);
    pane.style.setProperty('--rs-map-pan-y',`${map.y}px`);
  };
  let pending=false;
  const schedule=()=>{if(pending)return;pending=true;requestAnimationFrame(()=>{pending=false;update()})};
  const full=()=>{map.zoom=1;map.x=0;map.y=0;update()};
  const center=()=>{
    const pane=activePane();
    const m=pane?.querySelector('.marker.selected');
    if(!pane||!m){full();return;}
    const x=parseFloat(m.style.left),y=parseFloat(m.style.top);
    if(!Number.isFinite(x)||!Number.isFinite(y)){full();return;}
    map.zoom=Math.max(map.zoom,1.65);
    pane.style.setProperty('--rs-map-zoom',String(map.zoom));
    map.x=(50-x)/100*pane.offsetWidth;
    map.y=(50-y)/100*pane.offsetHeight;
    update();
  };
  document.addEventListener('click',e=>{
    const b=e.target.closest('[data-rsmap]');if(!b)return;
    e.preventDefault();e.stopPropagation();
    if(b.dataset.rsmap==='in')map.zoom=clamp(Number((map.zoom*1.22).toFixed(2)),1,8);
    if(b.dataset.rsmap==='out')map.zoom=clamp(Number((map.zoom/1.22).toFixed(2)),1,8);
    if(b.dataset.rsmap==='reset')full();
    if(b.dataset.rsmap==='expand'){
      const original=content.querySelector('.rs-tactical-view');
      const overlay=document.getElementById('modal');
      const dialog=overlay?.querySelector('.modal');
      if(original&&overlay&&dialog){
        const title=document.getElementById('modalTitle'),body=document.getElementById('modalBody'),actions=document.getElementById('modalActions');
        if(title)title.textContent='LIVE OPERATIONS MAP';
        if(body)body.innerHTML='<div class="rs-map-expanded-host"></div>';
        if(actions)actions.innerHTML='<button class="btn" data-action="modalClose">CLOSE MAP</button>';
        const clone=original.cloneNode(true);
        const label=clone.querySelector('.rs-map-coordinate');if(label)label.textContent='SAN ANDREAS · FLAT HD · LIVE OPERATIONS';
        clone.querySelector('[data-rsmap="expand"]')?.remove();
        body?.querySelector('.rs-map-expanded-host')?.appendChild(clone);
        dialog.classList.remove('rs-profile-dialog');dialog.classList.add('rs-map-dialog');
        overlay.classList.remove('hidden');
      }
    }
    if(b.dataset.rsmap==='focus')center();
    update();
  });
  document.addEventListener('wheel',e=>{
    if(!e.target.closest('.rs-tactical-view .map-stage'))return;
    e.preventDefault();
    map.zoom=clamp(map.zoom*(e.deltaY<0?1.11:1/1.11),1,8);update();
  },{passive:false});
  let drag=null;
  document.addEventListener('pointerdown',e=>{
    const stage=e.target.closest('.rs-tactical-view .map-stage');
    if(!stage||e.target.closest('button'))return;
    if(e.button!==0)return;
    drag={id:e.pointerId,sx:e.clientX,sy:e.clientY,x:map.x,y:map.y,stage};
    stage.classList.add('rs-dragging');
    try{stage.setPointerCapture(e.pointerId)}catch(_){ }
  });
  document.addEventListener('pointermove',e=>{
    if(!drag||e.pointerId!==drag.id)return;
    map.x=drag.x+(e.clientX-drag.sx);
    map.y=drag.y+(e.clientY-drag.sy);update();
  });
  const endDrag=()=>{if(drag){drag.stage.classList.remove('rs-dragging');drag=null}};
  document.addEventListener('pointerup',endDrag);
  document.addEventListener('pointercancel',endDrag);
  // The app redraws live players every refresh; restore map pan/zoom to the new plane.
  new MutationObserver(()=>{
    const src=content.querySelector('.rs-tactical-view .map-geographic');
    const open=document.querySelector('#modal:not(.hidden) .rs-map-dialog .map-geographic');
    if(src&&open&&src!==open){
      syncMapMarkers(open,src);
      const view=open.closest('.rs-tactical-view');
      view.classList.add('flat');
      view.classList.remove('perspective');
    }
    schedule();
  }).observe(content,{childList:true,subtree:false});
  document.addEventListener('click',e=>{
    const b=e.target.closest('[data-rsprofile]');if(!b)return;
    const root=b.closest('.rs-profile-v3');if(!root)return;
    e.stopPropagation();e.preventDefault();
    const key=b.dataset.rsprofile;
    root.querySelectorAll('.rs-profile-tab').forEach(tab=>{
      const active=tab.dataset.rsprofile===key;
      tab.classList.toggle('active',active);tab.setAttribute('aria-selected',String(active));
    });
    root.querySelectorAll('[data-rsprofile-pane]').forEach(pane=>{
      const active=pane.dataset.rsprofilePane===key;
      pane.hidden=!active;pane.classList.toggle('active',active);
    });
    const scroller=root.closest('.modal-body');if(scroller)scroller.scrollTop=0;
  });
  update();
})();
