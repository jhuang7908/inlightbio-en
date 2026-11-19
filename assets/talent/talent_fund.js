/* 启光英才（#talent）/ 启光资方（#fund）频道交互：筛选、岗位与机构编号带入、简历与联系表单提交 */
(function(){
  var MAXB=10*1024*1024, EMAIL=/^[^\s@]+@[^\s@]+\.[^\s@]+$/, T0=Date.now();
  function say(el,t,ok){ if(!el) return; el.hidden=false; el.textContent=t; el.className='talent-msg '+(ok?'is-ok':'is-err'); }
  function errText(st,j){
    if(j&&j.error) return j.error;
    if(st===413) return '文件超过 10MB，请压缩后重试。';
    if(st===429) return '提交过于频繁，请稍后再试。';
    if(st===400) return '提交内容有误，请检查后重试。';
    return '暂时无法提交，请稍后重试，或发邮件至 contact@inlightbio.com。';
  }
  function post(url,body,isJson){
    var o={method:'POST',body:body,credentials:'same-origin'};
    if(isJson) o.headers={'Content-Type':'application/json'};
    return fetch(url,o).then(function(r){return r.json().catch(function(){return null}).then(function(j){return {st:r.status,j:j}})});
  }

  /* 简历表单 → POST /api/talent/cv（multipart） */
  var form=document.getElementById('talent-cv-form');
  var msg=document.getElementById('talent-cv-msg');
  var file=document.getElementById('talent-cv-file');
  var nameEl=document.getElementById('talent-cv-filename');
  var defaultHint=nameEl?nameEl.textContent:'未选择文件';
  var target=document.getElementById('talent-cv-target');
  if(file) file.addEventListener('change',function(){ if(nameEl) nameEl.textContent=(file.files&&file.files[0])?('已选择：'+file.files[0].name):defaultHint; });
  if(form) form.addEventListener('submit',function(e){
    e.preventDefault(); if(msg){msg.hidden=true;msg.textContent='';}
    var f=file&&file.files&&file.files[0], g=function(n){return ((form.elements[n]||{}).value||'').trim()};
    if(!f) return say(msg,'请选择简历文件（PDF 或 Word）。');
    if(!/\.(pdf|docx?)$/i.test(f.name)) return say(msg,'仅支持 PDF、DOC、DOCX 格式。');
    if(f.size>MAXB) return say(msg,'文件超过 10MB，请压缩后重试。');
    if(!f.size) return say(msg,'文件为空，请重新选择。');
    if(!g('name')) return say(msg,'请填写姓名。');
    if(!EMAIL.test(g('email'))) return say(msg,'邮箱格式不正确。');
    if(!form.elements.consent.checked) return say(msg,'请勾选同意项。');
    var fd=new FormData(form); fd.set('consent','1'); fd.set('elapsed_ms',String(Date.now()-T0));
    var btn=form.querySelector('button[type="submit"]'); if(btn) btn.disabled=true; say(msg,'正在上传…',true);
    post('/api/talent/cv',fd,false).then(function(r){
      if(r.st>=200&&r.st<300&&r.j&&r.j.ok){ say(msg,'已提交，启光专人将尽快联系您。',true); form.reset(); if(nameEl) nameEl.textContent=defaultHint; }
      else say(msg,errText(r.st,r.j));
    },function(){ say(msg,errText(0)); }).then(function(){ if(btn) btn.disabled=false; });
  });
  document.querySelectorAll('.talent-apply[data-job-code]').forEach(function(btn){
    btn.addEventListener('click',function(){
      var code=btn.getAttribute('data-job-code')||'';
      if(target){for(var i=0;i<target.options.length;i++){if(target.options[i].value===code){target.value=code;target.dispatchEvent(new Event('change',{bubbles:true}));break;}}}
      var dest=document.getElementById('talent-cv'); if(dest) dest.scrollIntoView({behavior:'smooth',block:'start'});
      if(target) target.focus({preventScroll:true});
    });
  });

  /* 工作机会：地区筛选 */
  var jt=document.querySelectorAll('#talent-list .talent-tabs .ftab');
  var jc=document.querySelectorAll('#talent-list .talent-grid .talent-card');
  function setRegion(r){
    jt.forEach(function(t){t.setAttribute('aria-selected',t.getAttribute('data-region')===r?'true':'false')});
    jc.forEach(function(c){var l=(c.getAttribute('data-regions')||'').split(',').map(function(s){return s.trim()});c.hidden=!(r==='all'||l.indexOf(r)!==-1);});
  }
  jt.forEach(function(t){t.addEventListener('click',function(){setRegion(t.getAttribute('data-region')||'all')})});

  /* 投资机构：阶段 × 方向，先显示 24 家 */
  var sec=document.getElementById('fund-list');
  if(sec){
    var grid=sec.querySelector('.fund-grid'), cards=[].slice.call(sec.querySelectorAll('.fund-card'));
    var status=document.getElementById('fund-status'), empty=document.getElementById('fund-empty'), more=document.getElementById('fund-more');
    var INIT=parseInt(grid.getAttribute('data-init')||'24',10), st={stage:'all',dir:'all'}, all=false;
    var has=function(c,a,v){return v==='all'||(c.getAttribute(a)||'').split(',').indexOf(v)!==-1};
    var apply=function(){
      var m=cards.filter(function(c){return has(c,'data-stages',st.stage)&&has(c,'data-dirs',st.dir)}), o=0;
      cards.forEach(function(c){c.hidden=true});
      m.forEach(function(c,i){if(all||i<INIT)c.hidden=false; if(/开放/.test(c.querySelector('.fund-win').textContent))o++;});
      var rest=m.length-Math.min(m.length,INIT);
      more.hidden=all||rest<=0; more.textContent='显示更多（还有 '+rest+' 家）'; empty.hidden=m.length>0;
      status.textContent=(st.stage==='all'&&st.dir==='all'?'共 ':'符合条件 ')+m.length+' 家，其中 '+o+' 家递交窗口开放';
    };
    sec.querySelectorAll('.fund-tabs').forEach(function(row){
      var d=row.getAttribute('data-dim');
      row.querySelectorAll('.ftab').forEach(function(t){t.addEventListener('click',function(){
        st[d]=t.getAttribute('data-'+d)||'all'; all=false;
        row.querySelectorAll('.ftab').forEach(function(x){x.setAttribute('aria-selected',x===t?'true':'false')}); apply();
      })});
    });
    more.addEventListener('click',function(){all=true;apply();});
    apply();
    /* 递交 BP：把卡片编号带入 BP 表单「意向机构编号」 */
    sec.querySelectorAll('.fund-apply').forEach(function(a){a.addEventListener('click',function(){
      var code=a.getAttribute('data-fund-code'), bf=document.getElementById('bpform');
      var put=function(){ if(!bf||!bf.elements.vc) return; var v=bf.elements.vc.value.trim(); if(v.split(/[\s,，、]+/).indexOf(code)===-1) bf.elements.vc.value=v?(v+'，'+code):code; };
      setTimeout(put,0); setTimeout(put,400);
    })});
  }

  /* 用人单位 / 投资机构联系 → POST /api/partner-contact（JSON） */
  document.querySelectorAll('.hub-contact-form').forEach(function(f){
    f.addEventListener('submit',function(e){
      e.preventDefault();
      var m=f.querySelector('.talent-msg'), g=function(n){return ((f.elements[n]||{}).value||'').trim()};
      var miss=[]; if(!g('org')) miss.push('机构名称'); if(!g('contact')) miss.push('联系人'); if(!g('email')) miss.push('邮箱'); if(!g('note')) miss.push('简短说明');
      if(miss.length) return say(m,'请填写：'+miss.join('、'));
      if(!EMAIL.test(g('email'))) return say(m,'邮箱格式不正确。');
      if(!f.elements.consent.checked) return say(m,'请勾选同意项。');
      var body=JSON.stringify({kind:g('kind')||f.getAttribute('data-kind'),org:g('org'),contact:g('contact'),email:g('email'),wechat:g('wechat'),note:g('note'),consent:true,website:g('website'),elapsed_ms:Date.now()-T0});
      var btn=f.querySelector('button[type="submit"]'); if(btn) btn.disabled=true; say(m,'正在提交…',true);
      post('/api/partner-contact',body,true).then(function(r){
        if(r.st>=200&&r.st<300&&r.j&&r.j.ok){ say(m,'已提交，启光专人将尽快与您联系。',true); f.reset(); }
        else say(m,errText(r.st,r.j));
      },function(){ say(m,errText(0)); }).then(function(){ if(btn) btn.disabled=false; });
    });
  });
})();
