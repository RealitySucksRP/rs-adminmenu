/* RS AdminMenu 0.15.13 — purely visual, event-delegated UI layer.
   No intercepting input, no NUI RPCs, no timer when hidden, bounded particles. */
(()=>{
  'use strict';
  const app=document.getElementById('app');
  const screen=app?.querySelector('.tablet-screen');
  if(!app||!screen)return;
  const motionReduced=window.matchMedia?.('(prefers-reduced-motion: reduce)');
  const eligible=()=>!app.classList.contains('hidden') && app.dataset.uiMode==='FULL' &&
    !['off','none','reduced'].includes(app.dataset.motion) && !motionReduced?.matches &&
    !document.hidden;
  const quality=()=>app.dataset.fx||'standard';
  const particles=[];
  const maxParticles=68;
  let raf=0, canvas=null,ctx=null,width=0,height=0,dpr=1,lastTime=0,lastIdle=0,hoverEl=null,lastHover=0;
  let pointerX=-1,pointerY=-1;
  const activeParticles=()=>eligible() && ['standard','high'].includes(quality()) &&
    app.dataset.uiMode==='FULL';
  const origin=()=>screen.getBoundingClientRect();
  const canvasInit=()=>{
    if(canvas)return;
    canvas=document.createElement('canvas');canvas.className='rsui-fx-canvas';
    canvas.setAttribute('aria-hidden','true');screen.appendChild(canvas);
    ctx=canvas.getContext('2d',{alpha:true});
    resize();
  };
  const resize=()=>{
    if(!canvas||!ctx)return;
    const r=origin();width=Math.round(r.width);height=Math.round(r.height);
    dpr=Math.min(1.5,Math.max(1,window.devicePixelRatio||1));
    canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);
    ctx.setTransform(dpr,0,0,dpr,0,0);
  };
  const stop=()=>{if(raf)cancelAnimationFrame(raf);raf=0;particles.length=0;
    if(ctx)ctx.clearRect(0,0,width,height);lastTime=0;lastIdle=0;
  };
  const start=()=>{if(!activeParticles())return;canvasInit();if(!raf)raf=requestAnimationFrame(tick)};
  function add(x,y,n,ambient=false){
    if(!activeParticles())return;
    if(!width||!height)resize();
    if(x<0||y<0||x>width||y>height)return;
    for(let i=0;i<n&&particles.length<maxParticles;i++){
      const angle=Math.random()*Math.PI*2;
      const speed=ambient?.02:.45+Math.random()*1.35;
      particles.push({x,y,vx:ambient?(Math.random()-.5)*.07:Math.cos(angle)*speed,
        vy:ambient?-(.05+Math.random()*.13):Math.sin(angle)*speed-.3,
        radius:ambient?.5+Math.random()*.7:.7+Math.random()*1.35,
        age:0,life:ambient?2800+Math.random()*3100:350+Math.random()*420,
        ambient,blue:Math.random()>.3});
    }
    start();
  }
  function tick(now){
    raf=0;
    if(!activeParticles()){stop();return;}
    if(!width||!height)resize();
    if(lastTime&&now-lastTime<30){raf=requestAnimationFrame(tick);return;} // cap paint to ~30fps
    const dt=Math.min(50,Math.max(1,now-(lastTime||now-32)));lastTime=now;
    const high=quality()==='high';
    if(high&&now-lastIdle>250 && particles.filter(p=>p.ambient).length<14){
      lastIdle=now;add(10+Math.random()*(width-20),20+Math.random()*(height-40),1,true);
    }
    ctx.clearRect(0,0,width,height);
    const blue=getComputedStyle(document.documentElement).getPropertyValue('--accent2').trim()||'#20a9ff';
    const red=getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()||'#ff3f65';
    for(let i=particles.length-1;i>=0;i--){
      const p=particles[i];p.age+=dt;
      if(p.age>=p.life){particles.splice(i,1);continue;}
      p.x+=p.vx*dt/16;p.y+=p.vy*dt/16;
      if(p.ambient && (p.x<-5||p.x>width+5||p.y<-5)){particles.splice(i,1);continue;}
      const alpha=(1-p.age/p.life)*(p.ambient?.16:.76);
      ctx.globalAlpha=alpha;ctx.fillStyle=p.blue?blue:red;
      ctx.beginPath();ctx.arc(p.x,p.y,p.radius,0,Math.PI*2);ctx.fill();
      if(!p.ambient&&p.radius>1.2){ctx.globalAlpha=alpha*.22;ctx.fillRect(p.x-3,p.y-.4,6,.8)}
    }
    ctx.globalAlpha=1;
    if(particles.length||high)raf=requestAnimationFrame(tick);
  }
  const inside=(event)=>{
    const r=origin();return {x:event.clientX-r.left,y:event.clientY-r.top};
  };
  const tileSelector='.content :is(.workspace-tile,.action-tile,.library-card,.card,.world-card,.weapon-card,.theme-card,.prank,.weather-option,.blip-choice,.palette-card,.wall,.native-model-card,.rs-fleet-card),.modal-body :is(.card,.weapon-card,.weather-option,.palette-card,.wall)';
  screen.addEventListener('pointerover',event=>{
    if(!eligible()||event.pointerType==='touch')return;
    const card=event.target.closest(tileSelector);
    if(!card||card===hoverEl||card.contains(event.relatedTarget))return;
    hoverEl=card;
    const now=performance.now();
    if(now-lastHover<130||quality()==='low'||quality()==='off')return;
    lastHover=now;const {x,y}=inside(event);add(x,y,quality()==='high'?5:3);
  },{passive:true});
  screen.addEventListener('pointerout',event=>{
    if(hoverEl&&!hoverEl.contains(event.relatedTarget))hoverEl=null;
  },{passive:true});
  screen.addEventListener('pointermove',event=>{
    if(!eligible()||event.pointerType==='touch')return;
    const hero=event.target.closest('.hero');
    if(hero&&app.dataset.depth!=='off'){
      const r=hero.getBoundingClientRect();
      const x=Math.max(-1,Math.min(1,(event.clientX-r.left)/r.width*2-1));
      const y=Math.max(-1,Math.min(1,(event.clientY-r.top)/r.height*2-1));
      hero.style.setProperty('--rsui-hero-x',`${(x*4).toFixed(1)}px`);
      hero.style.setProperty('--rsui-hero-y',`${(y*4).toFixed(1)}px`);
    }
    pointerX=event.clientX;pointerY=event.clientY;
  },{passive:true});
  screen.addEventListener('pointerdown',event=>{
    if(event.button!==0||!eligible()||quality()==='off')return;
    const el=event.target.closest('button');
    if(!el||el.disabled||!screen.contains(el))return;
    if(el.closest('.map-stage'))return; // no effects on draggable map tools
    const r=el.getBoundingClientRect();
    const ripple=document.createElement('span');ripple.className='rsui-ripple';
    ripple.style.setProperty('--rsui-x',`${event.clientX-r.left}px`);
    ripple.style.setProperty('--rsui-y',`${event.clientY-r.top}px`);
    ripple.setAttribute('aria-hidden','true');el.appendChild(ripple);
    ripple.addEventListener('animationend',()=>ripple.remove(),{once:true});
    // Defensive cleanup if a view re-renders during a click or animations are overridden.
    setTimeout(()=>ripple.remove(),600);
    if(quality()==='standard'||quality()==='high'){
      const {x,y}=inside(event);add(x,y,quality()==='high'?11:7);
    }
  },{passive:true});
  const sync=()=>{
    if(!activeParticles()){stop();return;}
    resize();if(quality()==='high')start();
  };
  new MutationObserver(sync).observe(app,{attributes:true,attributeFilter:['class','data-ui-mode','data-motion','data-fx']});
  window.addEventListener('resize',()=>{if(canvas)resize()});
  window.addEventListener('blur',stop);
  document.addEventListener('visibilitychange',sync);
  motionReduced?.addEventListener?.('change',sync);
  sync();
})();
