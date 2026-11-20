/* 栏目浏览与点击计数：每个事件请求一次 1×1 空白图片 /assets/ev/px，只记录事件名与公开编号（岗位号 / 机构编号），
   不写 Cookie、不读本地存储、不收集表单内容，不调用任何第三方。请求失败不影响页面。 */
(function(){
  'use strict';
  var URL='/assets/ev/px', H=[], Q=[], ready=false;
  function rnd(){ return Math.random().toString(36).slice(2,9); }
  function send(e,k){
    try{
      var u=URL+'?e='+encodeURIComponent(e)+(k?'&k='+encodeURIComponent(String(k).slice(0,40)):'')+'&r='+rnd();
      var i=new Image(1,1);
      i.onload=i.onerror=function(){ var j=H.indexOf(i); if(j>=0) H.splice(j,1); };
      H.push(i); i.src=u;
    }catch(_){}
  }
  /* 页面加载期间产生的自动事件排队，等页面图片加载完（最多 4 秒）再发，不和首屏图片抢连接 */
  function flush(){ if(ready) return; ready=true; var q=Q.splice(0); for(var n=0;n<q.length;n++) send(q[n][0],q[n][1]); }
  function auto(e,k){ if(ready) send(e,k); else Q.push([e,k]); }
  if(document.readyState==='complete') setTimeout(flush,300);
  else { addEventListener('load',function(){ setTimeout(flush,300); }); setTimeout(flush,4000); }
  window.inlightPx=function(e,k){ send(e,k); };

  /* 进入 #fund / #talent / #bp 路由：每次进入记一次，k = 来自哪个路由 */
  var WATCH={fund:'v_fund',talent:'v_talent',bp:'v_bp','bp-form':'v_bp'};
  function base(){ var h=(location.hash||'#home').slice(1); var i=h.indexOf('?'); if(i>=0) h=h.slice(0,i); return h||'home'; }
  var prev=null;
  function onRoute(){
    var b=base();
    if(b===prev) return;
    var from=prev===null?'land':(prev.indexOf('p-')===0?'paper':prev);
    var ev=WATCH[b], pev=prev!==null?WATCH[prev]:null;
    prev=b;
    if(ev && ev!==pev) auto(ev,from.slice(0,20));
  }
  addEventListener('hashchange',onRoute);
  onRoute();

  /* 区块进入视口至少一半（或占满半屏）：每次打开页面每个区块只记一次 */
  var SEEN={'home-fund':'sv_fund','home-talent':'sv_talent','bp-home':'sv_bp_bar','cv-home':'sv_cv_bar','talent-cv':'open_cv','bp-form-sec':'open_bp'};
  if('IntersectionObserver' in window){
    var th=[]; for(var t=0;t<=20;t++) th.push(t/20);
    var io=new IntersectionObserver(function(es){
      es.forEach(function(x){
        if(!x.isIntersecting) return;
        var vh=(x.rootBounds&&x.rootBounds.height)||innerHeight||1;
        if(x.intersectionRatio>=0.5 || x.intersectionRect.height>=vh*0.5){
          io.unobserve(x.target);
          auto(SEEN[x.target.id]);
        }
      });
    },{threshold:th});
    Object.keys(SEEN).forEach(function(id){ var el=document.getElementById(id); if(el) io.observe(el); });
  }

  /* 点击：捕获阶段监听，不改变原有按钮行为 */
  document.addEventListener('click',function(ev){
    try{
      var t=ev.target; if(!t||!t.closest) return;
      var a;
      if((a=t.closest('#talent-list .talent-add'))){ if(!a.classList.contains('is-on')) send('add_job',a.getAttribute('data-job-code')); return; }
      if((a=t.closest('.talent-apply[data-job-code]'))){ send('apply_job',a.getAttribute('data-job-code')); return; }
      if((a=t.closest('.fund-apply[data-fund-code]'))){ send('add_fund_bp',a.getAttribute('data-fund-code')); return; }
      if((a=t.closest('#bp-home a'))){ send('click_bp_bar'); return; }
      if((a=t.closest('#cv-home a'))){ send('click_cv_bar'); return; }
      if((a=t.closest('a[href^="mailto:bd@"]'))){ send('mail_bp',/BP/i.test(decodeURIComponent(a.getAttribute('href')||''))?'bp':'other'); return; }
    }catch(_){}
  },true);

  /* 展开岗位卡 / 机构卡 / 联系表单（toggle 不冒泡，用捕获阶段） */
  document.addEventListener('toggle',function(ev){
    try{
      var d=ev.target; if(!d||!d.open||!d.getAttribute) return;
      var jc=d.getAttribute('data-job-code'), fc=d.getAttribute('data-fund-code');
      if(jc && d.closest('#talent-list')) send('open_job',jc);
      else if(fc && d.closest('#fund-list')) send('open_fund',fc);
      else if(d.id==='contact-investor'||d.id==='contact-employer') send('open_contact',d.id.slice(8));
    }catch(_){}
  },true);

  /* 表单：BP 递交窗口只生成邮件，不上传；这里只记是否通过了必填检查 */
  document.addEventListener('submit',function(ev){
    try{
      var f=ev.target;
      if(f && f.id==='bpform'){
        setTimeout(function(){
          var note=document.getElementById('bpnote'), err=document.getElementById('bperr');
          var ok=note && !note.hidden && !(err && err.textContent);
          send(ok?'submit_bp_ok':'submit_bp_err');
        },0);
      } else if(f && f.id==='talent-cv-form'){ send('try_cv'); }
    }catch(_){}
  },true);
})();
