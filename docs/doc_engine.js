/* Shared by the architecture docs: draws a DATA object (boxes, arrows, tabs, tables) into the page.
   Box helper B(id,col,row,style,title,sub,tip,confirm), arrow helper A(from,fromSide,to,toSide,style,{label,fa,ta}).
   Tip: {i: intro, t: [[key,value]..], b: [bullet..]}. Inline marks: {{code}} **bold** [n] = link to Sources item n.
   DATA.styleLabels = {box:{style:label}, arrow:{style:label}} renames legend entries. */
function B(id,col,row,style,title,sub,tip,confirm){return {id:id,col:col,row:row,style:style,title:title,sub:sub,tip:tip,confirm:confirm||null};}
function A(from,fs,to,ts,style,o){o=o||{};return {from:from,fs:fs,to:to,ts:ts,style:style,label:o.label||null,fa:o.fa,ta:o.ta};}

function renderDoc(DATA){
'use strict';
/* ================================================================
   ENGINE. Draws everything above. No box or arrow is hand-written.
   ================================================================ */
var NS='http://www.w3.org/2000/svg';
var COLX=[20,212,404,596,788], BW=160, BH=72;
var BOX_STYLES={
  exists:{label:'Exists today',cls:'s-exists'},
  'new':{label:'New or proposed',cls:'s-new',pill:'NEW'},
  favored:{label:'Favored',cls:'s-favored'},
  open:{label:'Open question (names who confirms)',cls:'s-open',badge:'?'},
  gap:{label:'Gap, opposed or rejected',cls:'s-gap'},
  unknown:{label:'Unknown or out of scope',cls:'s-unknown'},
  rule:{label:'Rule or decision',cls:'s-rule'},
  side:{label:'Supporting, off the main path',cls:'s-side'}
};
var ARROW_STYLES={
  exists:{label:'Exists',cls:'a-exists',head:11},
  newLink:{label:'New connection',cls:'a-new',head:11,ah:'ah-new'},
  main:{label:'New main path',cls:'a-main',head:17,ah:'ah-main'},
  gap:{label:'Gap',cls:'a-gap',head:11,ah:'ah-gap'},
  risky:{label:'Outbound or risky call',cls:'a-risky',head:11,ah:'ah-risky'},
  indirect:{label:'Indirect',cls:'a-indirect',head:11,ah:'ah-indirect'}
};
var warnings=[];
var LABELS=DATA.styleLabels||{};
Object.keys(LABELS.box||{}).forEach(function(k){BOX_STYLES[k].label=LABELS.box[k];});
Object.keys(LABELS.arrow||{}).forEach(function(k){ARROW_STYLES[k].label=LABELS.arrow[k];});
function warn(m){warnings.push(m);}

function el(name,attrs,parent){
  var e=document.createElementNS(NS,name);
  if(attrs){for(var k in attrs){if(attrs[k]!==null&&attrs[k]!==undefined){e.setAttribute(k,attrs[k]);}}}
  if(parent){parent.appendChild(e);}
  return e;
}
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function fmt(s){
  return esc(s)
    .replace(/\{\{(.+?)\}\}/g,'<code>$1</code>')
    .replace(/\*\*(.+?)\*\*/g,'<strong>$1</strong>')
    .replace(/\[(\d+)\]/g,'<a href="#src-$1" class="cite" aria-label="Source $1">[$1]</a>');
}
function plain(s){return String(s).replace(/\{\{(.+?)\}\}/g,'$1').replace(/\*\*(.+?)\*\*/g,'$1');}

/* Measure text in an off-screen SVG so wrapping works even inside hidden tabs */
var meas=el('svg',{'class':'measurer','aria-hidden':'true'});
var measText=el('text',{},meas);
document.body.appendChild(meas);
function tw(s,cls){measText.setAttribute('class',cls);measText.textContent=s;return measText.getComputedTextLength();}
function wrap(text,cls,maxW,where){
  var words=String(text).split(/\s+/), lines=[], cur='';
  words.forEach(function(w){
    var t=cur?cur+' '+w:w;
    if(tw(t,cls)<=maxW||!cur){cur=t;}else{lines.push(cur);cur=w;}
  });
  if(cur){lines.push(cur);}
  lines.forEach(function(l){if(tw(l,cls)>maxW+0.5){warn(where+': a word does not fit the box width: '+l);}});
  return lines;
}

function boxPos(b){return {x:COLX[b.col],y:40+110*b.row};}
function anchor(b,side,f){
  var p=boxPos(b); f=(f===undefined||f===null)?0.5:f;
  if(side==='top'){return {x:p.x+BW*f,y:p.y,dx:0,dy:-1};}
  if(side==='bottom'){return {x:p.x+BW*f,y:p.y+BH,dx:0,dy:1};}
  if(side==='left'){return {x:p.x,y:p.y+BH*f,dx:-1,dy:0};}
  return {x:p.x+BW,y:p.y+BH*f,dx:1,dy:0};
}
function clamp(v,a,b){return Math.max(a,Math.min(b,v));}
function bez(p0,c0,c1,p1,t){
  var u=1-t;
  return {x:u*u*u*p0.x+3*u*u*t*c0.x+3*u*t*t*c1.x+t*t*t*p1.x,
          y:u*u*u*p0.y+3*u*u*t*c0.y+3*u*t*t*c1.y+t*t*t*p1.y};
}

function flatTip(tip){
  if(typeof tip==='string'){return plain(tip);}
  var s=plain(tip.i);
  if(tip.t){s+=' '+tip.t.map(function(r){return plain(r[0])+': '+plain(r[1])+'.';}).join(' ');}
  if(tip.b){s+=' '+tip.b.map(plain).join(' ');}
  return s;
}
function renderTip(tip){
  if(typeof tip==='string'){return '<p>'+fmt(tip)+'</p>';}
  var h='<p>'+fmt(tip.i)+'</p>';
  if(tip.t){h+='<table class="tip-table"><tbody>'+tip.t.map(function(r){return '<tr><th scope="row">'+fmt(r[0])+'</th><td>'+fmt(r[1])+'</td></tr>';}).join('')+'</tbody></table>';}
  if(tip.b){h+='<ul>'+tip.b.map(function(x){return '<li>'+fmt(x)+'</li>';}).join('')+'</ul>';}
  return h;
}

function legendSwatchBox(style){
  var s=el('svg',{width:34,height:20,viewBox:'0 0 34 20','aria-hidden':'true'});
  var g=el('g',{'class':'box '+BOX_STYLES[style].cls},s);
  el('rect',{'class':'body',x:2,y:3,width:30,height:14,rx:4},g);
  return s;
}
function legendSwatchArrow(style){
  var s=el('svg',{width:44,height:20,viewBox:'0 0 44 20','aria-hidden':'true'});
  var d=(style==='main')?'M3,10 L41,10':'M3,10 L41,10';
  el('path',{'class':'arrow '+ARROW_STYLES[style].cls,d:d},s);
  return s;
}

/* Build one diagram: SVG, legend, detail panel, print table. Everything is found by its own id. */
function buildDiagram(tab){
  var id=tab.id, boxes=tab.boxes, arrows=tab.arrows||[];
  var byId={}, cells={};
  if(boxes.length>(tab.maxBoxes||10)){warn(id+': more than 10 boxes ('+boxes.length+')');}
  boxes.forEach(function(b){
    if(byId[b.id]){warn(id+': duplicate box id '+b.id);}
    byId[b.id]=b;
    var key=b.col+','+b.row;
    if(cells[key]){warn(id+': two boxes share the cell '+key+' ('+cells[key]+', '+b.id+')');}
    cells[key]=b.id;
    if(!BOX_STYLES[b.style]){warn(id+'/'+b.id+': unknown box style '+b.style);}
    if(!b.tip||(typeof b.tip==='string'&&!b.tip.trim())||(typeof b.tip==='object'&&!(b.tip.i||'').trim())){warn(id+'/'+b.id+': empty tip');}
    var tw1=b.title.split(/\s+/).length, sw1=b.sub.split(/\s+/).length;
    if(tw1<2||tw1>4){warn(id+'/'+b.id+': title should be 2 to 4 words');}
    if(sw1<3||sw1>6){warn(id+'/'+b.id+': subtitle should be 3 to 6 words');}
    if(/^[A-Z]/.test(b.sub)){warn(id+'/'+b.id+': subtitle should be lowercase');}
    if(b.style==='open'&&!b.confirm){warn(id+'/'+b.id+': open question does not name who confirms');}
  });
  var maxRow=0; boxes.forEach(function(b){if(b.row>maxRow){maxRow=b.row;}});
  var H=40+110*maxRow+BH+40+(tab.padBottom||0);
  var svgId='svg-'+id;

  var wrapEl=document.createElement('div');
  var scroll=document.createElement('div'); scroll.className='diagram-scroll'; scroll.tabIndex=-1;
  scroll.setAttribute('role','region'); scroll.setAttribute('aria-label','Diagram: '+tab.title+'. Scrolls sideways on narrow screens.');
  scroll.tabIndex=0;
  wrapEl.appendChild(scroll);
  var svg=el('svg',{id:svgId,viewBox:'0 0 960 '+H,width:960,height:H,role:'group','aria-label':'Diagram: '+tab.title+'. Each box opens its detail below when you press Enter or Space.'});
  scroll.appendChild(svg);

  /* arrowhead markers: unique ids per diagram */
  var defs=el('defs',{},svg);
  var usedArrow={}, usedBox={};
  arrows.forEach(function(a){usedArrow[a.style]=true;});
  boxes.forEach(function(b){usedBox[b.style]=true;});
  Object.keys(usedArrow).forEach(function(st){
    var S=ARROW_STYLES[st]; if(!S){warn(id+': unknown arrow style '+st);return;}
    var hs=S.head;
    var m=el('marker',{id:svgId+'-ah-'+st,markerUnits:'userSpaceOnUse',markerWidth:hs,markerHeight:hs*1.2,refX:hs*0.7,refY:hs*0.6,orient:'auto-start-reverse'},defs);
    el('path',{'class':'ah '+(S.ah||'ah-exists'),d:'M0,0 L'+hs+','+(hs*0.6)+' L0,'+(hs*1.2)+' z'},m);
  });

  /* arrows first, so boxes sit on top */
  var gA=el('g',{'class':'arrows'},svg);
  arrows.forEach(function(a,i){
    var f=byId[a.from], t=byId[a.to];
    if(!f||!t){warn(id+': arrow '+i+' points at a box that does not exist ('+a.from+' to '+a.to+')');return;}
    var S=ARROW_STYLES[a.style]; if(!S){return;}
    var p0=anchor(f,a.fs,a.fa), p1=anchor(t,a.ts,a.ta);
    var inset=S.head*0.3;
    var e1={x:p1.x+p1.dx*inset,y:p1.y+p1.dy*inset,dx:p1.dx,dy:p1.dy};
    var sep0=(p1.x-p0.x)*p0.dx+(p1.y-p0.y)*p0.dy;
    var sep1=(p0.x-p1.x)*p1.dx+(p0.y-p1.y)*p1.dy;
    var k0=sep0>0?clamp(sep0*0.5,12,90):50, k1=sep1>0?clamp(sep1*0.5,12,90):50;
    var c0={x:p0.x+p0.dx*k0,y:p0.y+p0.dy*k0}, c1={x:p1.x+p1.dx*k1,y:p1.y+p1.dy*k1};
    var d='M'+p0.x+','+p0.y+' C'+c0.x+','+c0.y+' '+c1.x+','+c1.y+' '+e1.x+','+e1.y;
    el('path',{'class':'arrow '+S.cls,d:d,'marker-end':'url(#'+svgId+'-ah-'+a.style+')','data-from':a.from,'data-to':a.to},gA);
    var dist=Math.hypot(p1.x-p0.x,p1.y-p0.y);
    if(a.label){
      if(dist<90){warn(id+': arrow label "'+a.label+'" skipped; the arrow is only '+Math.round(dist)+' px long');}
      else{
        var mid=bez(p0,c0,c1,e1,0.5);
        var lt=el('text',{'class':'alabel',x:mid.x,y:mid.y-7,'text-anchor':'middle'},gA);
        lt.textContent=a.label;
      }
    }
  });

  /* boxes */
  var gB=el('g',{'class':'boxes'},svg);
  boxes.forEach(function(b){
    var S=BOX_STYLES[b.style]||BOX_STYLES.exists, p=boxPos(b);
    var g=el('g',{'class':'box '+S.cls,tabindex:0,role:'button','aria-pressed':'false','data-box':b.id,
      'aria-label':b.title+'. '+b.sub+'. '+S.label+'. Press Enter for detail.'},gB);
    el('rect',{'class':'halo',x:p.x-4,y:p.y-4,width:BW+8,height:BH+8,rx:13},g);
    el('rect',{'class':'body',x:p.x,y:p.y,width:BW,height:BH,rx:10},g);
    var tl=wrap(b.title,'t-title',BW-16,id+'/'+b.id+' title');
    var sl=wrap(b.sub,'t-sub',BW-16,id+'/'+b.id+' subtitle');
    if(tl.length>2){warn(id+'/'+b.id+': title needs '+tl.length+' lines');}
    if(sl.length>2){warn(id+'/'+b.id+': subtitle needs '+sl.length+' lines');}
    var total=tl.length*16+sl.length*14+5;
    if(total>BH-6){warn(id+'/'+b.id+': text is '+total+' px tall and does not fit a '+BH+' px box');}
    var y0=p.y+(BH-total)/2;
    tl.forEach(function(line,i){var t=el('text',{'class':'t-title',x:p.x+BW/2,y:y0+12+16*i,'text-anchor':'middle'},g);t.textContent=line;});
    sl.forEach(function(line,j){var t=el('text',{'class':'t-sub',x:p.x+BW/2,y:y0+tl.length*16+5+11+14*j,'text-anchor':'middle'},g);t.textContent=line;});
    if(S.pill){
      var pg=el('g',{'class':'pill'},g);
      el('rect',{x:p.x+6,y:p.y-10,width:34,height:15,rx:7.5},pg);
      var pt=el('text',{x:p.x+23,y:p.y+1,'text-anchor':'middle'},pg); pt.textContent=S.pill;
    }
    if(S.badge){
      var qg=el('g',{'class':'qbadge'},g);
      el('circle',{cx:p.x+BW-10,cy:p.y,r:10},qg);
      var qt=el('text',{x:p.x+BW-10,y:p.y+4.5,'text-anchor':'middle'},qg); qt.textContent=S.badge;
    }
  });

  /* plus signs: two boxes side by side that are independent of each other */
  (tab.plus||[]).forEach(function(pr){
    var a=byId[pr[0]], b=byId[pr[1]];
    if(!a||!b){warn(id+': plus sign names a box that does not exist');return;}
    var pa=boxPos(a), pb=boxPos(b);
    if(pa.y!==pb.y||Math.abs(a.col-b.col)!==1){warn(id+': plus sign needs two boxes side by side');return;}
    var lft=pa.x<pb.x?pa:pb, cx=lft.x+BW+(COLX[1]-COLX[0]-BW)/2, cy=lft.y+BH/2;
    var pg2=el('g',{'class':'plus','aria-hidden':'true'},svg);
    el('circle',{cx:cx,cy:cy,r:13},pg2);
    var ptx=el('text',{x:cx,y:cy+7,'text-anchor':'middle'},pg2); ptx.textContent='+';
  });

  /* legend, built only from the styles this diagram uses */
  var legend=document.createElement('ul'); legend.className='legend'; legend.setAttribute('aria-label','Legend for this diagram');
  Object.keys(BOX_STYLES).forEach(function(st){
    if(!usedBox[st]){return;}
    var li=document.createElement('li'); li.appendChild(legendSwatchBox(st));
    li.appendChild(document.createTextNode(BOX_STYLES[st].label)); legend.appendChild(li);
  });
  Object.keys(ARROW_STYLES).forEach(function(st){
    if(!usedArrow[st]){return;}
    var li=document.createElement('li'); li.appendChild(legendSwatchArrow(st));
    li.appendChild(document.createTextNode('Arrow: '+ARROW_STYLES[st].label)); legend.appendChild(li);
  });
  if((tab.plus||[]).length){
    var lp=document.createElement('li'), sp=el('svg',{width:26,height:26,viewBox:'0 0 26 26','aria-hidden':'true'});
    var gp2=el('g',{'class':'plus'},sp); el('circle',{cx:13,cy:13,r:11},gp2);
    var tp2=el('text',{x:13,y:20,'text-anchor':'middle'},gp2); tp2.textContent='+';
    lp.appendChild(sp); lp.appendChild(document.createTextNode('Plus: independent, run in any order')); legend.appendChild(lp);
  }
  wrapEl.appendChild(legend);

  var hint=document.createElement('p'); hint.className='hint';
  hint.textContent='Click a box, or focus it and press Enter or Space, to read its detail.';
  wrapEl.appendChild(hint);

  var detail=document.createElement('div'); detail.className='detail'; detail.id='detail-'+id;
  detail.setAttribute('aria-live','polite'); detail.setAttribute('role','region'); detail.setAttribute('aria-label','Box detail');
  detail.innerHTML='<p class="placeholder">No box selected. Click a box above to read what it is, what it wraps and where the numbers come from.</p>';
  wrapEl.appendChild(detail);

  /* print-only Box | Detail table */
  var tbl=document.createElement('table'); tbl.className='boxtable';
  var rows='<thead><tr><th>Box</th><th>Detail</th></tr></thead><tbody>';
  boxes.forEach(function(b){
    rows+='<tr><td><strong>'+esc(b.title)+'</strong><br>'+esc(b.sub)+'</td><td>'+esc(flatTip(b.tip))+(b.confirm?' Who confirms: '+esc(b.confirm)+'.':'')+'</td></tr>';
  });
  tbl.innerHTML=rows+'</tbody>';
  wrapEl.appendChild(tbl);

  /* interaction, wired by the diagram's own ids */
  var current=null;
  function select(bid){
    var b=byId[bid]; if(!b){return;}
    var svgEl=document.getElementById(svgId), det=document.getElementById('detail-'+id);
    Array.prototype.forEach.call(svgEl.querySelectorAll('.box'),function(g){
      var on=g.getAttribute('data-box')===bid; g.classList.toggle('sel',on); g.setAttribute('aria-pressed',on?'true':'false');
    });
    current=bid;
    var S=BOX_STYLES[b.style];
    var colorVar={exists:'--exists-bd','new':'--new-bd',favored:'--fav-bd',open:'--fav-bd',gap:'--gap-bd',unknown:'--unk-bd',rule:'--rule-bd'}[b.style];
    det.style.borderLeftColor='var('+colorVar+')';
    det.innerHTML='<h3>'+esc(b.title)+'</h3><p class="status">'+esc(b.sub)+' - '+esc(S.label)+'</p>'+renderTip(b.tip)+
      (b.confirm?'<p class="confirm"><strong>Who confirms:</strong> '+esc(b.confirm)+'</p>':'');
  }
  svg.addEventListener('click',function(ev){
    var g=ev.target.closest?ev.target.closest('.box'):null; if(g){select(g.getAttribute('data-box'));}
  });
  svg.addEventListener('keydown',function(ev){
    if(ev.key==='Enter'||ev.key===' '||ev.key==='Spacebar'){
      var g=ev.target.closest?ev.target.closest('.box'):null;
      if(g){ev.preventDefault();select(g.getAttribute('data-box'));}
    }
  });
  return wrapEl;
}

function buildTable(def){
  var h='<h3>'+esc(def.title)+'</h3><div class="tablewrap"><table class="dtable"><thead><tr>'+def.head.map(function(x){return '<th scope="col">'+esc(x)+'</th>';}).join('')+'</tr></thead><tbody>';
  def.rows.forEach(function(r){h+='<tr>'+r.map(function(c,i){return (i===0?'<th scope="row">':'<td>')+fmt(c)+(i===0?'</th>':'</td>');}).join('')+'</tr>';});
  return h+'</tbody></table></div>'+(def.note?'<p class="fine">'+fmt(def.note)+'</p>':'');
}

function buildOptions(tab){
  var box=document.createElement('div');
  var head=document.createElement('h3'); head.textContent='Options considered'; box.appendChild(head);
  var bar=document.createElement('div'); bar.className='optbar';
  var be=document.createElement('button'); be.type='button'; be.className='btn'; be.textContent='Expand all';
  var bc=document.createElement('button'); bc.type='button'; bc.className='btn'; bc.textContent='Collapse all';
  bar.appendChild(be); bar.appendChild(bc); box.appendChild(bar);
  var list=document.createElement('div'); box.appendChild(list);
  function credit(item){
    var h=fmt(item[0])+' <span class="credit">('+esc(item[1])+(item[2]?', ['+item[2]+']':'')+')</span>';
    return '<li>'+h.replace(/<span class="credit">\((.+?), \[(\d+)\]\)<\/span>/,'<span class="credit">($1) <a href="#src-$2" class="cite">[$2]</a></span>')+'</li>';
  }
  tab.options.forEach(function(o){
    var d=document.createElement('details'); d.className='opt '+o.status;
    var badge=o.status==='favored'?'Favored':'Rejected';
    var body='<div class="obody"><h4>Pros</h4><ul>'+o.pros.map(credit).join('')+'</ul><h4>Cons</h4><ul>'+o.cons.map(credit).join('')+'</ul>';
    if(o.status==='rejected'){
      body+='<p class="why"><strong>Why rejected:</strong> '+fmt(o.why)+'</p><p class="recon"><strong>Would reconsider if:</strong> '+fmt(o.reconsider)+'</p>';
    }
    body+='</div>';
    d.innerHTML='<summary><span class="oname">'+esc(o.name)+'</span><span class="badge">'+badge+'</span></summary>'+body;
    if(o.status==='favored'){d.open=true;}
    list.appendChild(d);
  });
  be.addEventListener('click',function(){Array.prototype.forEach.call(list.querySelectorAll('details'),function(d){d.open=true;});});
  bc.addEventListener('click',function(){Array.prototype.forEach.call(list.querySelectorAll('details'),function(d){d.open=false;});});
  return box;
}

function buildNext(tab){
  var N=DATA.next, h='<h2 class="ptitle">'+esc(tab.title)+'</h2>';
  h+='<p class="bigq"><strong>Question for the group: '+esc(N.question)+'</strong></p>';
  h+='<div class="tablewrap"><table class="dtable"><thead><tr>'+N.head.map(function(x){return '<th scope="col">'+esc(x)+'</th>';}).join('')+'</tr></thead><tbody>'+
     N.rows.map(function(r){return '<tr>'+r.map(function(c){return '<td>'+fmt(c)+'</td>';}).join('')+'</tr>';}).join('')+'</tbody></table></div>';
  return h;
}

function buildRef(tab){
  var h='<h2 class="ptitle">'+esc(tab.title)+'</h2>';
  h+='<h3 id="sources-h">Sources</h3><ol class="refs sources" aria-labelledby="sources-h">'+
     DATA.sources.map(function(x){return '<li id="src-'+x.n+'" value="'+x.n+'">'+(x.path?'<a href="'+esc(x.path)+'">'+esc(x.label)+'</a>':esc(x.label))+' - '+esc(x.note)+'</li>';}).join('')+'</ol>';
  h+='<h3 id="terms-h">Definitions</h3><ol class="refs" aria-labelledby="terms-h">'+
     DATA.glossary.rows.map(function(r){return '<li><strong>'+esc(r[0])+'</strong> - '+fmt(r[1])+'</li>';}).join('')+'</ol>';
  return h;
}

/* Tabs: a top row of groups, and a second row of sub-tabs inside a group that has more than one page */
var tablist=document.getElementById('tablist'), panelsEl=document.getElementById('panels');
var gTabEls={}, gPanelEls={}, subLists={}, tabEls={}, panelEls={}, groupOf={}, lastLeaf={};
var tabById={}; DATA.tabs.forEach(function(t){tabById[t.id]=t;});

function buildLeaf(tab,multi){
  var p=document.createElement('section'); p.id='panel-'+tab.id; p.className='leaf';
  if(multi){p.setAttribute('role','tabpanel'); p.setAttribute('aria-labelledby','tab-'+tab.id); p.hidden=true;}
  if(tab.next){p.innerHTML=buildNext(tab);}
  else if(tab.ref){p.innerHTML=buildRef(tab);}
  else{
    var hd=document.createElement('h2'); hd.className='ptitle'; hd.textContent=tab.title; p.appendChild(hd);
    var intro=document.createElement('p'); intro.className='intro'; intro.innerHTML=fmt(tab.intro); p.appendChild(intro);
    if(tab.callout){var c=document.createElement('div'); c.className='callout'; c.innerHTML=fmt(tab.callout); p.appendChild(c);}
    if(tab.html){var pic=document.createElement('div'); pic.className='diagram-scroll'; pic.innerHTML=tab.html; p.appendChild(pic);}   // a picture the grid cannot draw
    else{p.appendChild(buildDiagram(tab));}
    (tab.tables||[]).forEach(function(k){
      var def=(k==='glossary')?DATA.glossary:DATA.tableDefs[k];
      var d=document.createElement('div'); d.innerHTML=buildTable(def); p.appendChild(d);
    });
    if(tab.options){p.appendChild(buildOptions(tab));}
  }
  return p;
}
function buildPage(){
  var M=DATA.meta;
  document.getElementById('kicker').textContent=M.kicker;
  document.getElementById('title').textContent=M.title;
  document.getElementById('subtitle').textContent=M.subtitle;
  document.getElementById('byline').textContent=M.byline;
  document.getElementById('foot').textContent=M.foot;
  document.getElementById('badges').innerHTML=M.badges.map(function(b){return '<li>'+esc(b)+'</li>';}).join('');
  document.getElementById('cards').innerHTML=DATA.cards.map(function(c){
    return '<article class="card"><h2>'+esc(c.title)+'</h2><ul>'+c.items.map(function(i){return '<li>'+fmt(i)+'</li>';}).join('')+'</ul></article>';
  }).join('');

  DATA.groups.forEach(function(g){
    var multi=g.tabs.length>1;
    var tb=document.createElement('button'); tb.type='button'; tb.id='gtab-'+g.id; tb.setAttribute('role','tab');
    tb.setAttribute('aria-controls','gpanel-'+g.id); tb.setAttribute('aria-selected','false'); tb.tabIndex=-1; tb.textContent=g.label;
    tb.setAttribute('data-group',g.id); tablist.appendChild(tb); gTabEls[g.id]=tb;

    var gp=document.createElement('section'); gp.id='gpanel-'+g.id; gp.className='gpanel'; gp.setAttribute('role','tabpanel');
    gp.setAttribute('aria-labelledby','gtab-'+g.id); gp.hidden=true;
    if(multi){
      var sl=document.createElement('div'); sl.className='sublist'; sl.setAttribute('role','tablist'); sl.setAttribute('aria-label',g.label+' pages');
      gp.appendChild(sl); subLists[g.id]=sl;
    }
    g.tabs.forEach(function(tid){
      var tab=tabById[tid]; groupOf[tid]=g.id;
      if(multi){
        var st=document.createElement('button'); st.type='button'; st.id='tab-'+tid; st.setAttribute('role','tab');
        st.setAttribute('aria-controls','panel-'+tid); st.setAttribute('aria-selected','false'); st.tabIndex=-1; st.textContent=tab.label;
        st.setAttribute('data-tab',tid); subLists[g.id].appendChild(st); tabEls[tid]=st;
      }
      var leaf=buildLeaf(tab,multi); gp.appendChild(leaf); panelEls[tid]=leaf;
    });
    lastLeaf[g.id]=g.tabs[0];
    panelsEl.appendChild(gp); gPanelEls[g.id]=gp;
  });
}

function leafIds(){return DATA.tabs.map(function(t){return t.id;});}
/* Show one page (a leaf). Its group and sub-tab open with it. */
function activate(id,focusTab,setHash){
  if(!tabById[id]){id=DATA.tabs[0].id;}
  var gid=groupOf[id]; lastLeaf[gid]=id;
  DATA.groups.forEach(function(g){
    var on=g.id===gid, tb=gTabEls[g.id];
    tb.setAttribute('aria-selected',on?'true':'false'); tb.tabIndex=on?0:-1; gPanelEls[g.id].hidden=!on;
    if(g.tabs.length>1){
      g.tabs.forEach(function(tid){
        var son=tid===id, st=tabEls[tid];
        st.setAttribute('aria-selected',son?'true':'false'); st.tabIndex=son?0:-1; panelEls[tid].hidden=!son;
      });
    }
  });
  if(focusTab){(tabEls[id]&&gPanelEls[gid].contains(document.activeElement)?tabEls[id]:gTabEls[gid]).focus();}
  if(setHash!==false&&location.hash!=='#'+id){try{history.replaceState(null,'','#'+id);}catch(e){location.hash=id;}}
}
tablist.addEventListener('click',function(ev){var b=ev.target.closest('[role=tab]'); if(b){var g=b.getAttribute('data-group'); activate(lastLeaf[g],false);}});
tablist.addEventListener('keydown',function(ev){
  var ids=DATA.groups.map(function(g){return g.id;}), cur=document.activeElement&&document.activeElement.getAttribute('data-group');
  var i=ids.indexOf(cur); if(i<0){return;}
  var n=null;
  if(ev.key==='ArrowRight'){n=(i+1)%ids.length;}
  else if(ev.key==='ArrowLeft'){n=(i-1+ids.length)%ids.length;}
  else if(ev.key==='Home'){n=0;}
  else if(ev.key==='End'){n=ids.length-1;}
  if(n!==null){ev.preventDefault();activate(lastLeaf[ids[n]],false);gTabEls[ids[n]].focus();}
});
panelsEl.addEventListener('click',function(ev){var b=ev.target.closest&&ev.target.closest('.sublist [role=tab]'); if(b){activate(b.getAttribute('data-tab'),false);}});
panelsEl.addEventListener('keydown',function(ev){
  var b=ev.target.closest&&ev.target.closest('.sublist [role=tab]'); if(!b){return;}
  var g=DATA.groups.filter(function(x){return x.id===groupOf[b.getAttribute('data-tab')];})[0], ids=g.tabs, i=ids.indexOf(b.getAttribute('data-tab'));
  var n=null;
  if(ev.key==='ArrowRight'){n=(i+1)%ids.length;}
  else if(ev.key==='ArrowLeft'){n=(i-1+ids.length)%ids.length;}
  else if(ev.key==='Home'){n=0;}
  else if(ev.key==='End'){n=ids.length-1;}
  if(n!==null){ev.preventDefault();activate(ids[n],false);tabEls[ids[n]].focus();}
});

/* A citation link such as #src-3 opens the Reference page and scrolls to that source */
function goSource(hash){
  var m=/^#?(src-\d+)$/.exec(hash); if(!m){return false;}
  activate('ref',false);
  var li=document.getElementById(m[1]);
  if(li){li.scrollIntoView({block:'center'});li.classList.remove('flash');void li.offsetWidth;li.classList.add('flash');}
  return true;
}
document.addEventListener('click',function(ev){
  var a=ev.target.closest&&ev.target.closest('a[href^="#src-"]');
  if(a){ev.preventDefault();goSource(a.getAttribute('href'));}
});
/* The hash can name a page (#organizer) or a group (#agents opens its first page) */
function fromHash(){
  var h=location.hash.replace(/^#/,'');
  var g=DATA.groups.filter(function(x){return x.id===h;})[0];
  if(tabById[h]){activate(h,false,false);}
  else if(g){activate(lastLeaf[g.id],false,false);}
  else if(!goSource(location.hash)){activate(DATA.tabs[0].id,false,false);}
}
window.addEventListener('hashchange',fromHash);

/* Print: open every option card, then restore */
var openBefore=[];
window.addEventListener('beforeprint',function(){
  openBefore=[]; Array.prototype.forEach.call(document.querySelectorAll('details.opt'),function(d){openBefore.push(d.open);d.open=true;});
});
window.addEventListener('afterprint',function(){
  Array.prototype.forEach.call(document.querySelectorAll('details.opt'),function(d,i){d.open=!!openBefore[i];});
});

/* Check the data, write problems to the hidden #warn element */
function validateData(){
  DATA.tabs.forEach(function(t){
    if(t.next||t.ref){return;}
    if(!t.html&&(!t.boxes||!t.boxes.length)){warn(t.id+': no boxes');}
    (t.tables||[]).forEach(function(k){if(k!=='glossary'&&!DATA.tableDefs[k]){warn(t.id+': unknown table '+k);}});
  });
  var seen={};
  DATA.groups.forEach(function(g){g.tabs.forEach(function(t){if(!tabById[t]){warn('group '+g.id+' names an unknown tab '+t);}if(seen[t]){warn('tab '+t+' is in two groups');}seen[t]=true;});});
  DATA.tabs.forEach(function(t){if(!seen[t.id]){warn('tab '+t.id+' is in no group');}});
  var cited={};
  var all=JSON.stringify(DATA);
  (all.match(/\[(\d+)\]/g)||[]).forEach(function(m){cited[m.slice(1,-1)]=true;});
  Object.keys(cited).forEach(function(n){
    if(!DATA.sources.some(function(s){return String(s.n)===n;})){warn('citation ['+n+'] has no matching source');}
  });
}

buildPage();
(function(){var tb=document.querySelector('.tabbar');function set(){document.documentElement.style.setProperty('--tbh',(tb.offsetHeight-1)+'px');}set();window.addEventListener('resize',set);})();
validateData();
fromHash();
if(!tabById[location.hash.replace(/^#/,'')]&&!/^#src-\d+$/.test(location.hash)&&!DATA.groups.some(function(g){return '#'+g.id===location.hash;})){activate(DATA.tabs[0].id,false,true);}
var w=document.getElementById('warn');
w.setAttribute('data-warnings',String(warnings.length));
w.textContent=warnings.join('\n');
if(warnings.length&&window.console){console.warn('Diagram warnings ('+warnings.length+'):\n'+warnings.join('\n'));}
}
