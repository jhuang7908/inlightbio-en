/* InLight Bio — small vanilla JS:
   deal-card details panel, compact top-right filter (news), conference list (sort / range / type / region). */
(function(){
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const esc=t=>String(t==null?'':t).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const MON=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
/* ---------- Deal cards: inline details panel after the row ---------- */
const NEWS=window.NEWS||[]; const KINDS=window.KINDS||{};
let activePanel=null,activeCard=null,activeBtn=null;
function cols(grid){return getComputedStyle(grid).gridTemplateColumns.split(' ').filter(Boolean).length;}
function closePanel(restore){
  if(activePanel){activePanel.remove();activePanel=null;}
  if(activeCard){activeCard.classList.remove('expanded');activeCard=null;}
  if(activeBtn){activeBtn.setAttribute('aria-expanded','false');activeBtn.textContent='Details ↓';if(restore)activeBtn.focus();activeBtn=null;}
}
document.addEventListener('click',e=>{
  if(e.target.closest('.close-btn')){closePanel(true);return;}
  const b=e.target.closest('.expbtn'); if(!b) return;
  const item=b.closest('.item'), grid=item&&item.closest('.feed'); if(!grid) return;
  const open=item.classList.contains('expanded'); const top=item.getBoundingClientRect().top;
  closePanel(open); if(open) return;
  const x=NEWS.find(n=>n.slug===b.dataset.slug); if(!x) return;
  const cards=[...grid.children].filter(c=>!c.classList.contains('feed-details-panel')&&c.offsetParent!==null);
  const i=cards.indexOf(item), c=cols(grid), end=Math.min(Math.ceil((i+1)/c)*c,cards.length)-1;
  const p=document.createElement('div'); p.className='feed-details-panel'; p.setAttribute('role','region'); p.setAttribute('aria-label',x.t);
  p.innerHTML=`<div class="panel-tags">${x.kinds.map(k=>`<span class="kind">${esc(KINDS[k]||k)}</span>`).join('')}</div>
    ${x.ms?`<p class="msline">${esc(x.ms)}</p>`:''}<p>${esc(x.why)}</p>
    <div class="foot"><a href="${esc(x.url)}" target="_blank" rel="noopener">Source: ${esc(x.src)}</a><a href="/news/${esc(x.slug)}.html">Read the brief →</a><button class="close-btn" type="button">Close ↑</button></div>`;
  cards[end].after(p); activePanel=p; activeCard=item; activeBtn=b; item.classList.add('expanded');
  b.setAttribute('aria-expanded','true'); b.textContent='Close ↑';
  window.scrollBy(0,item.getBoundingClientRect().top-top);
});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&activePanel)closePanel(true);});
/* v12: list caps. Filters run first; then the first ~16/20 matches show (rounded up to full grid rows),
   with a "View all" button for the rest. ?cap=N overrides the base (QA). */
const CAPQ=+(new URLSearchParams(location.search).get('cap'))||0;
function applyCap(grid,items,btn,expanded,noun){
  const base=CAPQ||+grid.dataset.cap||16, c=Math.max(1,cols(grid)), cap=Math.ceil(base/c)*c;
  items.forEach((el,i)=>{el.hidden=!expanded&&i>=cap;});
  if(!btn) return;
  const more=items.length>cap;
  btn.hidden=!more;
  btn.textContent=expanded?'Show fewer':`View all ${items.length} ${noun}`;
  btn.setAttribute('aria-expanded',String(!!expanded));
}
/* close any open <details class="confcal"> when clicking outside */
document.addEventListener('click',e=>{$$('details.confcal[open]').forEach(d=>{if(!d.contains(e.target))d.open=false;});});

/* ---------- News page: one compact filter button, top-right ---------- */
const feed=$('#newsfeed');
if(feed){
  const groups=[['all','All items'],['lic','Licensing'],['newco','NewCo'],['acq','M&A'],['clin','Clinical'],['inv','Financing']];
  const china=[['all','All companies'],['cn','China-linked only']];
  let g='all', cn='all', nexp=false;
  const q=new URLSearchParams(location.search); if(q.get('type')&&groups.some(x=>x[0]===q.get('type'))) g=q.get('type');
  function render(){
    const match=x=>(g==='all'||x.kinds.includes(g))&&(cn==='all'||x.china);
    closePanel(false);
    const vis=[]; $$('#newsfeed .item').forEach(el=>{const x=NEWS.find(v=>v.slug===el.dataset.slug); const ok=match(x); el.hidden=!ok; if(ok)vis.push(el);});
    const n=vis.length; applyCap(feed,vis,$('#newsmore'),nexp,'items');
    const cnt=k=>NEWS.filter(x=>(k==='all'||x.kinds.includes(k))&&(cn==='all'||x.china)).length;
    $('#nf-type').innerHTML=groups.map(([k,l])=>`<button type="button" data-g="${k}"${g===k?' aria-pressed="true"':''}><span>${l}</span><em>${cnt(k)}</em></button>`).join('');
    $('#nf-cn').innerHTML=china.map(([k,l])=>`<button type="button" data-c="${k}"${cn===k?' aria-pressed="true"':''}><span>${l}</span></button>`).join('');
    $$('#nf-type button').forEach(b=>b.onclick=()=>{g=b.dataset.g;nexp=false;$('#nfcal').open=false;history.replaceState(null,'',g==='all'?location.pathname:'?type='+g);render();});
    $$('#nf-cn button').forEach(b=>b.onclick=()=>{cn=b.dataset.c;nexp=false;$('#nfcal').open=false;render();});
    const lab=(groups.find(x=>x[0]===g)||groups[0])[1]+(cn==='cn'?' · China':'');
    $('#nflabel').textContent=g==='all'&&cn==='all'?'Filter':lab;
    $('#newscount').textContent=`${n} item${n===1?'':'s'}, newest first`;
    $$('.trkcard[data-g]').forEach(t=>t.setAttribute('aria-current',String(t.dataset.g===g)));
  }
  $$('.trkcard[data-g]').forEach(t=>t.addEventListener('click',ev=>{ev.preventDefault();g=g===t.dataset.g?'all':t.dataset.g;nexp=false;history.replaceState(null,'',g==='all'?location.pathname:'?type='+g);render();$('#newsfeedsec').scrollIntoView({block:'start'});}));
  $('#newsmore').addEventListener('click',()=>{nexp=!nexp;render();if(!nexp)$('#newsfeedsec').scrollIntoView({block:'start'});});
  let nw=innerWidth; addEventListener('resize',()=>{if(innerWidth!==nw){nw=innerWidth;render();}});
  render();
}

/* ---------- Conferences (sort toggle, time range in calendar button, region dropdown beside it, ended hidden) ---------- */
const CONF_WIN=(()=>{const f=d=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');const n=new Date(),a=new Date(n),b=new Date(n);a.setDate(a.getDate()+7);b.setMonth(b.getMonth()+6);return [f(a),f(b)];})();
const CONFS=(window.CONFS||[]).filter(x=>{if(!x.dates||x.dates==='TBA')return false;const s=x.dates.split(' to ')[0];return s>=CONF_WIN[0]&&s<=CONF_WIN[1];});
if(CONFS&&$('#conflist')){
  let kind='all',order='asc',range='all',region='all',cexp=false;
  /* v8: region filter (compact dropdown next to the calendar button); ?region=us|europe|japan|apac */
  const REGIONS=[['all','All regions'],['us','United States','United States'],['europe','Europe','Europe'],['japan','Japan','Japan'],['apac','Asia-Pacific','Asia-Pacific']];
  const regOf=k=>(REGIONS.find(z=>z[0]===k)||REGIONS[0]);
  /* v9: type filter moved to its own compact pill dropdown (same style) left of the region pill; ?type=<slug> */
  const KINDS2=[['all','All types'],['partnering','Partnering'],['investor','Investor'],['scientific','Scientific'],['cro','CRO & outsourcing'],['regulatory','Regulatory'],['cmc','Manufacturing & CMC'],['digital','Digital Health & AI'],['access','Market Access & HEOR']];
  const kindOf=k=>(KINDS2.find(z=>z[1]===k)||KINDS2[0]);
  {const u=new URLSearchParams(location.search),q=u.get('region'),t=u.get('type'); if(q&&REGIONS.some(z=>z[0]===q)) region=q; const kk=KINDS2.find(z=>z[0]===t); if(kk&&kk[0]!=='all') kind=kk[1];}
  const syncUrl=()=>{const u=new URLSearchParams(); if(kind!=='all') u.set('type',kindOf(kind)[0]); if(region!=='all') u.set('region',region); const q=u.toString(); history.replaceState(null,'',q?'?'+q:location.pathname);};
  const pad=n=>String(n).padStart(2,'0'), ymd=d=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
  const isTbd=x=>!x.dates||x.dates==='TBA';
  const endOf=x=>{const p=x.dates.split(' to ');return p[1]||p[0];};
  function fmt(x){
    if(isTbd(x)) return 'Dates TBA<small>not yet announced</small>';
    const [a,b]=x.dates.split(' to '), pa=a.split('-'), pb=(b||a).split('-');
    const m1=MON[+pa[1]-1], m2=MON[+pb[1]-1];
    const span=(!b||a===b)?`${m1} ${+pa[2]}`:(pa[1]===pb[1]?`${m1} ${+pa[2]}–${+pb[2]}`:`${m1} ${+pa[2]} – ${m2} ${+pb[2]}`);
    return `${pa[0]}<small>${span}</small>`;
  }
  function render(){
    const now=new Date(), today=ymd(now);
    const limit=m=>{const d=new Date(now);d.setMonth(d.getMonth()+m);return ymd(d);};
    const upcoming=CONFS.filter(x=>isTbd(x)||endOf(x)>=today);
    const RANGES=[['1','Next month',1],['3','Next 3 months',3],['all','Next 6 months',0]];
    const inRange=(x,r)=>{if(r==='all')return true; if(isTbd(x))return false; return x.dates.split(' to ')[0]<=limit(RANGES.find(z=>z[0]===r)[2]);};
    const byKind=x=>kind==='all'||x.kind===kind;
    const byReg=(x,r)=>r==='all'||x.region===regOf(r)[2];
    $('#confrange').innerHTML=RANGES.map(([k,l])=>`<button type="button" data-r="${k}"${range===k?' aria-pressed="true"':''}><span>${l}</span><em>${upcoming.filter(x=>inRange(x,k)&&byKind(x)&&byReg(x,region)).length}</em></button>`).join('');
    $('#confkind').innerHTML=KINDS2.map(([,k])=>{k=k==='All types'?'all':k;return `<button type="button" data-k="${k}"${kind===k?' aria-pressed="true"':''}><span>${k==='all'?'All types':k}</span><em>${upcoming.filter(x=>inRange(x,range)&&(k==='all'||x.kind===k)&&byReg(x,region)).length}</em></button>`;}).join('');
    $('#confsort').innerHTML=[['asc','Soonest first'],['desc','Latest first']].map(([k,l])=>`<button type="button" data-o="${k}"${order===k?' aria-pressed="true"':''}><span>${l}</span></button>`).join('');
    $('#confregion').innerHTML=REGIONS.map(([k,l])=>`<button type="button" data-g="${k}"${region===k?' aria-pressed="true"':''}><span>${l}</span><em>${upcoming.filter(x=>inRange(x,range)&&byKind(x)&&byReg(x,k)).length}</em></button>`).join('');
    $$('#confregion button').forEach(b=>b.onclick=()=>{region=b.dataset.g;cexp=false;$('#confreg').open=false;syncUrl();render();});
    $('#confreglabel').textContent=regOf(region)[1];
    $$('#confrange button').forEach(b=>b.onclick=()=>{range=b.dataset.r;cexp=false;$('#confcal').open=false;render();});
    $$('#confkind button').forEach(b=>b.onclick=()=>{kind=b.dataset.k;cexp=false;$('#conftype').open=false;syncUrl();render();});
    {const SHORT={'CRO & outsourcing':'CRO','Manufacturing & CMC':'CMC','Digital Health & AI':'Digital & AI','Market Access & HEOR':'Access & HEOR'};
     const narrow=window.matchMedia&&matchMedia('(max-width:520px)').matches;
     $('#conftypelabel').textContent=kind==='all'?'All types':(narrow&&SHORT[kind])||kind; $('#conftype summary').title=kind==='all'?'All types':kind;}
    $$('#confsort button').forEach(b=>b.onclick=()=>{order=b.dataset.o;$('#confcal').open=false;render();});
    $('#confcallabel').textContent=RANGES.find(z=>z[0]===range)[1];
    const list=upcoming.filter(x=>inRange(x,range)&&byKind(x)&&byReg(x,region));
    const dated=list.filter(x=>!isTbd(x)).sort((a,b)=>a.dates<b.dates?-1:a.dates>b.dates?1:0); if(order==='desc') dated.reverse();
    const rows=[...dated,...list.filter(isTbd)];
    $('#confcount').textContent=`${rows.length} event${rows.length===1?'':'s'}`;
    /* v12: type tiles mirror the type filter; counts follow the current time range + region */
    /* v13: each tile also shows the next upcoming event of its type; the "All conferences" tile (data-k=all) resets the type */
    $$('#ctiles .ctile').forEach(t=>{const k=t.dataset.k,xs=upcoming.filter(x=>inRange(x,range)&&(k==='all'||x.kind===k)&&byReg(x,region)),n=xs.length;
      t.setAttribute('aria-current',String(kind===k)); t.classList.toggle('nil',!n); const em=t.querySelector('em'); if(em) em.textContent=`${n} event${n===1?'':'s'}`;
      const nx=xs.filter(x=>!isTbd(x)).sort((a,b)=>a.dates<b.dates?-1:1)[0], el=t.querySelector('.nx');
      if(el){ if(nx){const p=nx.dates.split(' to ')[0].split('-'); el.textContent=`Next: ${abbrName(nx)} · ${MON[+p[1]-1]} ${+p[2]}`;} else el.textContent='No upcoming event in this view'; }});
    $('#conflist').innerHTML=rows.map(x=>{
      const tbd=isTbd(x);
      const place=[x.city,x.venue].filter(Boolean).map(esc).join(' · ');
      const logo=x.logo?`<span class="conflogo"><img src="${esc(x.logo)}" alt="${esc(x.organizer||x.name)} logo" loading="lazy" decoding="async" data-abbr="${esc(abbr(x))}"></span>`:tile(x);
      return `<article class="confrow" lang="en">${logo}<div class="confbody"><div class="confhead">
        <div class="confdate${tbd?' tba':''}">${fmtLine(x)}</div>
        <h3>${esc(x.name)}${tbd?'<span class="tbabadge">TBA</span>':''}</h3>
        <div class="confmeta">${[place,x.organizer?'Organizer: '+esc(x.organizer):''].filter(Boolean).join(' · ')}</div></div>
        <p class="confsum" lang="en">${esc(x.sum)}</p>
        <div class="conftags"><span class="tag">${esc(x.kind)}</span>${x.region?`<span class="tag reg">${esc(x.region)}</span>`:''}<a href="${esc(x.url)}" target="_blank" rel="noopener">Official site</a></div></div></article>`;
    }).join('')||'<div class="empty">No events match these filters.</div>';
    applyCap($('#conflist'),$$('#conflist .confrow'),$('#confmore'),cexp,'events');
  }
  /* v7: one-line date for the card body, e.g. "Oct 23–27, 2026" */
  function fmtLine(x){
    if(isTbd(x)) return 'Dates TBA · not yet announced';
    const [a,b]=x.dates.split(' to '), pa=a.split('-'), pb=(b||a).split('-');
    const m1=MON[+pa[1]-1], m2=MON[+pb[1]-1];
    const span=(!b||a===b)?`${m1} ${+pa[2]}`:(pa[1]===pb[1]?`${m1} ${+pa[2]}–${+pb[2]}`:`${m1} ${+pa[2]} – ${m2} ${+pb[2]}`);
    return pa[0]===pb[0]?`${span}, ${pa[0]}`:`${m1} ${+pa[2]}, ${pa[0]} – ${m2} ${+pb[2]}, ${pb[0]}`;
  }
  /* v7: generated fallback tile (site green + short acronym) when no logo is available or it fails to load */
  function abbr(x){
    if(x.abbr) return x.abbr;
    const w=String(x.name).replace(/\(.*?\)/g,'').split(/[\s\-–]+/).filter(t=>/^[A-Za-z]/.test(t)&&!/^(of|the|and|for|annual|meeting|congress|conference|global|healthcare|health|care)$/i.test(t));
    const first=w[0]||'';
    if(/^[A-Z]{2,6}$/.test(first.replace(/[^A-Za-z]/g,''))) return first.replace(/[^A-Za-z]/g,'');
    return w.slice(0,3).map(t=>t[0].toUpperCase()).join('');
  }
  function abbrName(x){return x.abbr||String(x.name).replace(/\s*\(.*?\)\s*/g,' ').replace(/\s+\d{4}$/,'').trim();}
  function tile(x){return `<span class="conflogo tile" aria-hidden="true"><b>${esc(abbr(x))}</b></span>`;}
  $('#conflist').addEventListener('error',e=>{
    const im=e.target; if(!im||im.tagName!=='IMG'||!im.closest('.conflogo')) return;
    const box=im.closest('.conflogo'); box.classList.add('tile'); box.setAttribute('aria-hidden','true'); box.innerHTML=`<b>${esc(im.dataset.abbr||'')}</b>`;
  },true);
  /* v10: wide logos get a wider box so they stay readable */
  const markWide=im=>{if(im.naturalWidth&&im.naturalWidth/im.naturalHeight>2.6){const r=im.closest('.confrow');if(r)r.classList.add('wl');}};
  $('#conflist').addEventListener('load',e=>{const im=e.target;if(im&&im.tagName==='IMG'&&im.closest('.conflogo'))markWide(im);},true);
  const _r=render; render=function(){_r.apply(this,arguments);$$('#conflist .conflogo img').forEach(im=>{if(im.complete)markWide(im);});};
  $$('#ctiles .ctile').forEach(t=>t.addEventListener('click',ev=>{ev.preventDefault();kind=kind===t.dataset.k?'all':t.dataset.k;cexp=false;syncUrl();render();$('#confsec').scrollIntoView({block:'start'});}));
  $('#confmore').addEventListener('click',()=>{cexp=!cexp;render();if(!cexp)$('#confsec').scrollIntoView({block:'start'});});
  let cw=innerWidth; addEventListener('resize',()=>{if(innerWidth!==cw){cw=innerWidth;render();}});
  render();
}

/* ---------- Science index: one compact field filter, top-right ---------- */
const sgrid=$('#scigrid');
if(sgrid){
  const FIELDS=window.FIELDS||{}; let f='all', sexp=false;
  const q=new URLSearchParams(location.search); if(q.get('field')&&FIELDS[q.get('field')]) f=q.get('field');
  function render(){
    const vis=[]; $$('#scigrid .scard').forEach(el=>{const ok=f==='all'||el.dataset.f===f; el.hidden=!ok; if(ok)vis.push(el);});
    const n=vis.length; applyCap(sgrid,vis,$('#scimore'),sexp,'articles');
    $$('#ftiles .ftile').forEach(t=>t.setAttribute('aria-current',String(t.dataset.f===f)));
    $$('#sf-field button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.f===f)));
    $('#sflabel').textContent=f==='all'?'All fields':FIELDS[f];
    $('#scicount').textContent=`${n} article${n===1?'':'s'}, newest first`;
    $('#sciempty').hidden=n>0;
  }
  const setF=k=>{f=k;sexp=false;history.replaceState(null,'',f==='all'?location.pathname:'?field='+f);render();};
  $$('#ftiles .ftile').forEach(t=>t.addEventListener('click',ev=>{ev.preventDefault();setF(f===t.dataset.f?'all':t.dataset.f);$('#scisec').scrollIntoView({block:'start'});}));
  $('#scimore').addEventListener('click',()=>{sexp=!sexp;render();if(!sexp)$('#scisec').scrollIntoView({block:'start'});});
  let sw=innerWidth; addEventListener('resize',()=>{if(innerWidth!==sw){sw=innerWidth;render();}});
  $$('#sf-field button').forEach(b=>b.addEventListener('click',()=>{f=b.dataset.f;sexp=false;$('#sfcal').open=false;history.replaceState(null,'',f==='all'?location.pathname:'?field='+f);render();}));
  render();
}
})();
