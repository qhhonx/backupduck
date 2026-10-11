// Verify design contracts, flows and geometry using synthetic data, never production APIs.
const {chromium}=require(process.env.BACKUPDUCK_PLAYWRIGHT||'playwright');
const fs=require('fs'),path=require('path'),http=require('http'),assert=require('assert');
const root=path.resolve(__dirname,'../../..'),base=path.join(root,'design/android-v1.2'),catalog=JSON.parse(fs.readFileSync(path.join(base,'catalog.json')));
const out=path.join(root,'output/playwright/android-receiver-v1.2.1');fs.mkdirSync(out,{recursive:true});
const server=http.createServer((req,res)=>{const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);const file=path.resolve(root,'.'+pathname);if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}if(!fs.existsSync(file)){res.writeHead(404);return res.end();}res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':file.endsWith('.png')?'image/png':'text/html');res.end(fs.readFileSync(file));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});const page=await browser.newPage({viewport:{width:1280,height:1000}});const errors=[];page.on('pageerror',e=>errors.push(e.message));let requests=0;page.on('request',r=>{if(!r.url().startsWith(`http://127.0.0.1:${server.address().port}/`))requests++});
try{await page.goto(`http://127.0.0.1:${server.address().port}/design/android-v1.2/index.html`);assert.deepStrictEqual(await page.evaluate(()=>reviewAPI.catalog),catalog);let variants=0;for(const item of catalog){assert(fs.existsSync(path.join(root,item.source)),item.source);await page.evaluate(id=>reviewAPI.open(id),item.id);for(const state of item.states){await page.evaluate(state=>reviewAPI.setScenario(state),state);assert.equal(await page.locator(`#app [data-screen="${item.id}"]`).count(),1,`${item.id}/${state}`);variants++;}const destinations=await page.locator('#app [data-open]').evaluateAll(nodes=>nodes.map(n=>n.dataset.open));destinations.forEach(id=>assert(catalog.some(x=>x.id===id),`${item.id} → ${id}`));}
for(const width of [320,360,411])for(const font of ['1','1.3','2']){await page.selectOption('#width',String(width));await page.selectOption('#font',font);await page.evaluate(()=>reviewAPI.open('receive'));const rects=await page.locator('.nav button').evaluateAll(nodes=>nodes.map(n=>{const i=n.querySelector('svg').getBoundingClientRect(),t=n.querySelector('label').getBoundingClientRect();return {iconBottom:i.bottom,labelTop:t.top,height:n.getBoundingClientRect().height}}));rects.forEach(r=>{assert(r.labelTop-r.iconBottom>=3,'navigation overlap');assert(r.height>=48,'touch target')});assert(await page.locator('#phone').evaluate(n=>n.scrollWidth<=n.clientWidth+1),'phone overflow');}
await page.selectOption('#width','320');await page.selectOption('#font','2');
for(const item of catalog){await page.evaluate(id=>{reviewAPI.open(id);model.busy=false;render()},item.id);const overflow=await page.locator('#app [data-screen="'+item.id+'"]').evaluate(n=>n.scrollWidth>n.clientWidth+1);assert(!overflow,'large-font horizontal overflow: '+item.id);}
await page.selectOption('#width','360');await page.selectOption('#font','1');await page.evaluate(()=>reviewAPI.open('browser'));await page.locator('#app [data-open="browser-code"]').click();await page.locator('#field-code').fill('123');await page.locator('[data-do="save-code"]').click();assert(await page.locator('#error-code').isVisible());await page.locator('#field-code').fill('0123456789');await page.locator('[data-do="save-code"]').click();await page.waitForTimeout(800);assert.equal(await page.evaluate(()=>document.documentElement.dataset.screen),'browser');
await page.locator('#app [data-open="browser-code"]').click();await page.selectOption('#scenario','保存失败');await page.locator('#field-code').fill('0123456789');await page.locator('[data-do="save-code"]').click();await page.waitForTimeout(800);assert.equal(await page.evaluate(()=>document.documentElement.dataset.screen),'browser-code');assert(await page.locator('.notice.error').isVisible());
await page.evaluate(()=>{model.busy=false;reviewAPI.open('browser');render()});await page.locator('#app [data-toggle="browser"]').click();assert.equal(await page.locator('#app [data-toggle="browser"]').getAttribute('aria-checked'),'false');
await page.evaluate(()=>reviewAPI.open('device-name'));await page.locator('#field-nameDraft').fill('Cancelled edit');await page.locator('[data-do="back"]').last().click();assert.equal(await page.evaluate(()=>model.name),'Pixel XL');
await page.evaluate(()=>reviewAPI.open('export-report'));await page.locator('#app [data-open="system-document"]').click();await page.locator('[data-do="system-return"]').click();assert.equal(await page.evaluate(()=>document.documentElement.dataset.screen),'export-report');
await page.evaluate(()=>reviewAPI.open('archive'));await page.locator('.sheet-foot [data-open="system-document"]').click();await page.locator('[data-do="system-return"]').click();assert.equal(await page.evaluate(()=>document.documentElement.dataset.screen),'archive-progress');
// v1.2.1: help is read-only; receiving controls belong to the status card.
for(const id of ['help-connection','help-background','help-results','help-storage','help-recovery']){
 await page.evaluate(id=>reviewAPI.open(id),id);
 const body=page.locator(`#app .content[data-screen="${id}"]`);
 assert.equal(await body.locator('[data-open],[data-do],[data-toggle],button,a').count(),0,`${id} must not enter a workflow`);
 assert.equal(await body.locator('.setting svg').count(),0,`${id} must have no disclosure arrows`);
 assert.equal(await page.locator('.toolbar [data-do="back"]').count(),1,`${id} retains back navigation`);
}
await page.evaluate(()=>reviewAPI.open('help'));
await page.locator('#app .content[data-screen="help"] [data-open="help-storage"]').click();
assert.equal(await page.evaluate(()=>document.documentElement.dataset.screen),'help-storage');
await page.locator('.toolbar [data-do="back"]').click();
assert.equal(await page.evaluate(()=>document.documentElement.dataset.screen),'help');
for(const protectedState of ['等待接收','高温暂停','空间不足']){
 await page.evaluate(state=>{message='';clearTimeout(messageTimer);reviewAPI.open('receive');reviewAPI.setScenario(state)},protectedState);
 assert.equal(await page.locator('#app .content[data-screen="receive"]>.hero [data-do="pause"]').count(),1);
 assert.equal(await page.locator('#app .content[data-screen="receive"] .meter').count(),0,'No idle progress slot');
 await page.locator('.hero [data-do="pause"]').click();
 assert.equal(await page.locator('.hero [data-do="resume"].primary').count(),1,'Resume is the primary action');
 assert((await page.locator('.hero').innerText()).includes('已接收文件的相册处理继续'));
 await page.locator('.hero [data-do="resume"]').click();
 assert.equal(await page.evaluate(()=>scenario),protectedState,'Resume must preserve temperature/space hold');
}
await page.selectOption('#width','320');await page.selectOption('#font','2');
for(const theme of ['light','dark']){
 await page.evaluate(t=>document.documentElement.dataset.theme=t,theme);
 for(const state of ['等待接收','手动暂停','高温暂停','空间不足']){
  await page.evaluate(state=>{message='';clearTimeout(messageTimer);reviewAPI.open('receive');reviewAPI.setScenario(state)},state);
  assert(await page.locator('#phone').evaluate(n=>n.scrollWidth<=n.clientWidth+1));
  const actions=await page.locator('.hero .receive-actions .button').evaluateAll(nodes=>nodes.map(n=>({top:n.getBoundingClientRect().top,bottom:n.getBoundingClientRect().bottom,height:n.getBoundingClientRect().height})));
  assert(actions.every(r=>r.height>=48),'Touch target smaller than 48dp');const heading=await page.locator('.hero h2').evaluate(n=>({height:n.getBoundingClientRect().height,font:parseFloat(getComputedStyle(n).fontSize)}));assert(heading.height<=heading.font*2.8,'Large-font heading squeezed into character columns');
  if(actions.length===2)assert(actions[1].top>=actions[0].bottom,'Large-font buttons overlap');
  await page.waitForTimeout(250);await page.locator('#phone').screenshot({path:path.join(out,`receive-${state}-320-large-${theme}.png`)});
 }
 await page.evaluate(()=>{message='';clearTimeout(messageTimer);reviewAPI.open('help-storage')});await page.waitForTimeout(250);await page.locator('#phone').screenshot({path:path.join(out,`help-storage-320-large-${theme}.png`)});
}
await page.selectOption('#width','360');await page.selectOption('#font','1');
for(const theme of ['light','dark']){await page.evaluate(t=>document.documentElement.dataset.theme=t,theme);for(const screen of ['receive','transfers','browser','browser-code','browser-revoke','storage','settings','relay-preview']){await page.evaluate(id=>{reviewAPI.open(id);message='';model.code='';render()},screen);await page.waitForTimeout(250);await page.locator('#phone').screenshot({path:path.join(out,`${screen}-${theme}.png`)});}}
assert.deepStrictEqual(errors,[]);assert.equal(requests,0,'prototype contacted external service');console.log(`PASS: ${catalog.length} contracts / ${variants} state variants; 320/360/411dp, 1/1.3/2 font; browser invalid-input, save, failure; pure-reading help, pause/resume with preserved temperature/space holds; light/dark evidence; no external requests`);
}finally{await browser.close();server.close();}})().catch(e=>{console.error(e);server.close();process.exit(1)});
