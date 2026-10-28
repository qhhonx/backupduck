// Actual local dashboard. Synthetic API only; never contacts a Pixel.
const {chromium}=require(process.env.BACKUPDUCK_PLAYWRIGHT || 'playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),out=path.join(root,'build/design-review/browser');
fs.mkdirSync(out,{recursive:true});
const fixtures=Array.from({length:67},(_,i)=>({id:`synthetic-${i}`,filename:`${['旅行','海边','生日','日常'][i%4]}_${String(i+1).padStart(3,'0')}.${i%3===1?'mp4':'heic'}`,kind:['motion','video','photo'][i%3],burst_primary:i%9===8?true:null,total_bytes:8540000+i*10000,confirmed_bytes:i%4===3?2150000:8540000+i*10000,receipt:i%4===3?'receiving':'received',processing:['complete','complete','failed','pending'][i%4],processing_error:i%4===2?'conversion_required':null,captured_at_ms:1790906400000-i*14400000,received_at_ms:1790934400000,published_at_ms:i%4<2?1790938400000:null,originals_released:false,senders:['演示 iPhone']}));
let mode='normal',lastRetry=null,requests=[],historyDelay=0,retryDelay=0;
const contractOnly=process.env.BACKUPDUCK_DASHBOARD_CONTRACT_ONLY==='1';
function overview(){return {total:67,received:51,published:34,failed:17,waiting:0,reserved_bytes:632000000,free_bytes:28500000000,min_free_bytes:3000000000,total_space_bytes:64000000000,device:mode==='missing'?null:{temperature_deci_celsius:385,battery_percent:78,charging:true,thermal_threshold_celsius:42,thermal_enabled:true,thermal_held:mode==='thermal'}};}
const server=http.createServer((req,res)=>{
 const u=new URL(req.url,'http://local');
 if(u.pathname.startsWith('/api/')){
   requests.push({path:u.pathname,query:u.search,method:req.method,authorization:req.headers.authorization});
   const json=(v,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(v));};
   if(u.pathname==='/api/login')return json({token:'synthetic-review-token'},mode==='login-invalid'?401:mode==='login-locked'?429:mode==='login-offline'?503:200);
   if(mode==='expired')return json({},401);
   if(mode==='offline')return json({},503);
   if(u.pathname==='/api/logout'){if(mode==='logout-error')return json({},503);res.writeHead(204);return res.end();}
   if(u.pathname==='/api/retry'){lastRetry=u.searchParams.get('id');const body={count:mode==='retry-zero'?0:lastRetry?1:17},status=mode==='retry-error'?500:200;if(retryDelay)return setTimeout(()=>json(body,status),retryDelay);return json(body,status);}
   if(u.pathname==='/api/overview')return json(overview());
   if(u.pathname==='/api/history'){
     if(mode==='history-error')return json({},503);
     let rows=mode==='empty'?[]:fixtures.map(x=>({...x}));
     if(mode==='missing-id')rows.forEach(x=>delete x.id);
     if(mode==='missing')rows.forEach(x=>{x.captured_at_ms=null;x.received_at_ms=null;x.published_at_ms=null;x.senders=[];});
     if(mode==='long')rows[0].filename='演示长文件名_不包含任何私人原件_家庭旅行与视频_000001.HEIC';
     const search=u.searchParams.get('search'),st=u.searchParams.get('state'),kind=u.searchParams.get('kind');
     rows=rows.filter(x=>!search||x.filename.toLowerCase().includes(search.toLowerCase())).filter(x=>!st||st==='all'||st==='receiving'&&x.receipt!=='received'||st==='published'&&x.processing==='complete'||st==='failed'&&x.processing==='failed'||st==='processing'&&x.receipt==='received'&&x.processing==='pending').filter(x=>!kind||kind==='all'||x.kind===kind||kind==='burst'&&x.burst_primary!=null);
     const p=Number(u.searchParams.get('page'))||1,n=Number(u.searchParams.get('per_page'))||20;
     const body={items:rows.slice((p-1)*n,p*n),total:rows.length,pages:Math.max(1,Math.ceil(rows.length/n)),page:p,per_page:n};
     if(historyDelay)return setTimeout(()=>json(body),historyDelay);
     return json(body);
   }
   return json({},404);
 }
 const files={'/':'crates/native/src/dashboard/index.html','/style.css':'crates/native/src/dashboard/style.css','/tokens.css':'crates/native/src/dashboard/tokens.css','/app.js':'crates/native/src/dashboard/app.js','/duck.png':'assets/AppIcon.png'};
 const filename=files[u.pathname]|| (u.pathname==='/assets/AppIcon.png'?'assets/AppIcon.png':null);
 if(!filename){res.writeHead(404);return res.end();}
 try{res.setHeader('Content-Type',filename.endsWith('.css')?'text/css':filename.endsWith('.js')?'text/javascript':filename.endsWith('.png')?'image/png':filename.endsWith('.json')?'application/json':'text/html');res.end(fs.readFileSync(path.join(root,filename)));}catch(e){res.writeHead(404);res.end();}
});
const counts={desktopThemes:0,mobileWidths:0};
let base;
async function login(page){await page.locator('#code').fill('0000000000');await page.locator('#login-button').click();await page.locator('#dashboard').waitFor({state:'visible'});await page.locator('#recent-items tr').first().waitFor({state:'attached'});}
async function readyPage(browser,options={}){const context=await browser.newContext({locale:'zh-CN',viewport:{width:1360,height:920},...options});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(base);return {context,page,errors};}
async function snapshot(page,name){await page.screenshot({path:path.join(out,name+'.png')});}
async function noPageOverflow(page){assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Body must not overflow; tables may scroll internally');}
async function toTransfers(page){await page.locator('.side-link[data-page="transfers"]').click();await page.locator('#transfers-section').waitFor({state:'visible'});}
(async()=>{
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});base=`http://127.0.0.1:${server.address().port}`;
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
     for(const variant of [{locale:'zh-CN',colorScheme:'light',viewport:{width:1360,height:920},name:'desktop'},{locale:'en-US',colorScheme:'dark',viewport:{width:320,height:844},name:'english-320-dark'}]){
       const context=await browser.newContext(variant),page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(base);await login(page);await page.locator('#recent-items .file-name').first().waitFor();
       for(const section of ['overview','transfers','settings']){await page.locator(`.side-link[data-page="${section}"]`).click();await page.locator(`[data-page-panel="${section}"]`).first().waitFor({state:'visible'});assert.equal(await page.locator('.side-link .side-icon>svg').count(),4);assert.equal(await page.locator('.side-link.active').getAttribute('data-page'),section);await noPageOverflow(page);}
       await toTransfers(page);await page.locator('#items .file-name').nth(2).click();assert.equal(await page.locator('#details-close>svg').count(),1);assert.equal(await page.locator('#details-close').getAttribute('aria-label'),variant.locale==='en-US'?'Close details':'关闭详情');await page.locator('#details-close').click();assert.equal(await page.locator('#refresh').getAttribute('aria-label'),variant.locale==='en-US'?'Refresh records':'立即刷新');
       assert(await page.locator('.guide-grid .status-badge').evaluateAll(rows=>rows.every(row=>row.scrollWidth<=row.clientWidth+1)),'Status-guide labels must wrap within their column');assert.equal(await page.locator('#guide-failed .status-symbol>svg').count(),1);assert.equal(await page.locator('#guide-failed svg').getAttribute('aria-hidden'),'true');assert.equal(await page.locator('.status-badge').evaluateAll(rows=>rows.every(row=>getComputedStyle(row,'::before').content==='none')),true);assert.equal(await page.locator('.pagination button>svg').count(),4);
       await page.locator('#help-open').click();assert.equal(await page.locator('#help-close>svg').count(),1);assert.equal(await page.locator('#help-close').getAttribute('aria-label'),variant.locale==='en-US'?'Close help':'关闭帮助');assert.equal(await page.locator('#help-dialog :is(a,input,select)').count(),0);assert.equal(await page.locator('#help-dialog button').count(),1);await page.locator('#help-close').click();assert.deepEqual(errors,[]);await context.close();
     }
   if(contractOnly){
     const contractOut=path.join(root,'build/design-review/browser-contract');fs.mkdirSync(contractOut,{recursive:true});
     const context=await browser.newContext({locale:'zh-CN',viewport:{width:1360,height:920}});
     await context.addInitScript(()=>{window.__dashboardIntervals=[];const start=window.setInterval;window.setInterval=(fn,ms,...args)=>{if(ms===8000)window.__dashboardIntervals.push(fn);return start(fn,ms,...args);};});
     const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(base);
     mode='login-locked';await page.locator('#code').fill('0000000000');await page.locator('#login-button').click();await page.waitForFunction(()=>document.getElementById('login-message').textContent.includes('五分钟'));assert.equal(await page.locator('#code').inputValue(),'0000000000');
     mode='normal';await page.locator('#remember').check();await login(page);await toTransfers(page);
     await page.locator('#pagination button').filter({hasText:/^2$/}).click();await page.waitForFunction(()=>document.getElementById('page-summary').textContent.includes('第 2'));
     await page.locator('#items .file-name').nth(2).click();mode='retry-error';await page.locator('#detail-retry').click();await page.locator('#detail-message.error').waitFor();
     const previous=await page.locator('#detail-message').textContent(),historyBefore=requests.filter(r=>r.path==='/api/history').length;
     const refreshResponse=page.waitForResponse(r=>r.url().includes('/api/overview'));await page.evaluate(()=>window.__dashboardIntervals[0]());await refreshResponse;assert.equal(requests.filter(r=>r.path==='/api/history').length,historyBefore);assert((await page.locator('#page-summary').textContent()).includes('第 2'));assert(await page.locator('#details-dialog').isVisible());assert.equal(await page.locator('#detail-message').textContent(),previous);
     mode='retry-zero';await page.locator('#detail-retry').click();await page.waitForFunction(()=>document.getElementById('detail-message').textContent==='没有可重试的失败记录。');assert((await page.locator('#detail-status').textContent()).includes('失败'));await page.screenshot({path:path.join(contractOut,'retry-zero.png')});
     mode='normal';await page.locator('#detail-retry').click();await page.waitForFunction(()=>document.getElementById('detail-message').textContent.includes('等待接收端'));assert((await page.locator('#detail-status').textContent()).includes('失败'));await page.locator('#details-close').click();
     const start=requests.length;historyDelay=350;await page.locator('#state-filter').selectOption('failed');await page.locator('#refresh').click();await page.waitForFunction(()=>document.getElementById('page-summary').textContent.includes('第 1')&&document.getElementById('history-table').getAttribute('aria-busy')==='false');historyDelay=0;
     const filtered=requests.slice(start).filter(r=>r.path==='/api/history'&&r.query.includes('state=failed'));assert(filtered.length>=2);assert(filtered.every(r=>new URLSearchParams(r.query).get('page')==='1'));
     mode='missing-id';await page.locator('#refresh').click();await page.waitForFunction(()=>document.querySelector('#items tr')?.dataset.id?.includes('/'));await page.locator('#items .file-name').first().click();assert(await page.locator('#detail-retry').isDisabled());assert(!requests.some(r=>r.query.includes('undefined')));await page.locator('#details-close').click();
     mode='retry-zero';await page.locator('#retry').click();await page.locator('#retry-confirm').click();await page.waitForFunction(()=>document.getElementById('retry-message').textContent==='没有可重试的失败记录。');assert(await page.locator('#retry-dialog').isVisible());await page.locator('#retry-cancel').click();
     // Escape/close must not abandon a retry while its result is still outstanding.
     mode='normal';await page.locator('#refresh').click();await page.waitForFunction(()=>document.querySelector('#items tr')?.dataset.id==='synthetic-2');await page.locator('#items .file-name').first().click();retryDelay=1500;
     await page.locator('#detail-retry').click();await page.waitForFunction(()=>document.getElementById('details-dialog').getAttribute('aria-busy')==='true');assert(await page.locator('#details-close').isDisabled());await page.keyboard.press('Escape');assert(await page.locator('#details-dialog').isVisible());
     await page.waitForFunction(()=>document.getElementById('details-dialog').getAttribute('aria-busy')==='false');assert((await page.locator('#detail-message').textContent()).includes('等待接收端'));await page.keyboard.press('Escape');await page.locator('#details-dialog').waitFor({state:'hidden'});
     await page.locator('#retry').click();await page.locator('#retry-confirm').click();await page.waitForFunction(()=>document.getElementById('retry-dialog').getAttribute('aria-busy')==='true');assert(await page.locator('#retry-cancel').isDisabled());await page.keyboard.press('Escape');assert(await page.locator('#retry-dialog').isVisible());await page.waitForFunction(()=>document.getElementById('retry-dialog').getAttribute('aria-busy')==='false');retryDelay=0;await page.keyboard.press('Escape');await page.locator('#retry-dialog').waitFor({state:'hidden'});
     const before=page.url();await page.locator('#help-open').click();assert.equal(await page.locator('#help-dialog button').count(),1);assert.equal(await page.locator('#help-dialog :is(a,input,select)').count(),0);await page.locator('#help-close').click();assert.equal(page.url(),before);
     await page.locator('.side-link[data-page="settings"]').click();mode='logout-error';await page.locator('#logout').click();await page.locator('#dashboard-feedback.error').waitFor();assert.equal(await page.evaluate(()=>localStorage.getItem('backupduck-dashboard-token')),'synthetic-review-token');assert(await page.locator('#dashboard').isVisible());
     mode='normal';const logout=page.waitForResponse(r=>r.url().includes('/api/logout'));await page.locator('#logout').click();assert.equal((await logout).status(),204);await page.locator('#login-panel').waitFor({state:'visible'});assert.equal(await page.evaluate(()=>localStorage.getItem('backupduck-dashboard-token')),null);
     await login(page);mode='expired';await page.evaluate(()=>window.__dashboardIntervals[0]());await page.locator('#login-panel').waitFor({state:'visible'});assert.equal(await page.locator('#items .file-name').count(),0);assert.equal(await page.evaluate(()=>localStorage.getItem('backupduck-dashboard-token')),null);assert((await page.locator('#login-message').textContent()).includes('会话'));assert.deepEqual(errors,[]);
     mode='normal';
     const native=await context.newPage();await native.route('**/app.js',route=>route.fulfill({contentType:'text/javascript',body:fs.readFileSync(path.join(root,'crates/native/src/dashboard/app.js'),'utf8')}));await native.goto(base);await login(native);await native.locator('.side-link[data-page="settings"]').click();await native.locator('#logout').click();await native.locator('#login-panel').waitFor({state:'visible'});assert.equal(await native.evaluate(()=>localStorage.getItem('backupduck-dashboard-token')),null);
     await context.close();const report={scope:'production dashboard API contract',checks:['logout 204','logout failure retains session','login 429 preserves input','401 clears records and token','retry count0/count1 are not gallery success','missing-id no request','auto-refresh retains failed dialog and page2','filter+refresh in-flight retains requested page1','read-only help','busy retry blocks Escape/close until response'],data:'synthetic only',checkedAt:new Date().toISOString()};fs.writeFileSync(path.join(contractOut,'report.json'),JSON.stringify(report,null,2)+'\n');console.log('PASS:',JSON.stringify(report));return;
   }
   // Production UI representative real-click flow in both themes.
   for(const theme of ['light','dark']){
     mode='normal';const {context,page,errors}=await readyPage(browser,{colorScheme:theme});
     assert.equal(await page.locator('#logout').count(),1);
     mode='login-invalid';await page.locator('#code').fill('0000000000');await page.locator('#login-button').click();await page.locator('#login-message.error').waitFor();assert.equal(await page.locator('#code').inputValue(),'0000000000');
     mode='login-locked';await page.locator('#login-button').click();await page.waitForFunction(()=>document.getElementById('login-message').textContent.includes('五分钟'));
     mode='normal';await page.locator('#remember').check();await login(page);assert.equal(await page.evaluate(()=>localStorage.getItem('backupduck-dashboard-token')),'synthetic-review-token');await snapshot(page,`overview-${theme}`);
     for(const section of ['transfers','storage','settings']){await page.locator(`.side-link[data-page="${section}"]`).click();await page.locator(`[data-page-panel="${section}"]`).waitFor({state:'visible'});await snapshot(page,`${section}-${theme}`);}
     await toTransfers(page);
     await page.locator('#pagination button').filter({hasText:/^2$/}).click();await page.waitForFunction(()=>document.getElementById('page-summary').textContent.includes('第 2'));
     const filename=await page.locator('#items .file-name').first().textContent();await page.locator('#refresh').click();assert((await page.locator('#page-summary').textContent()).includes('第 2'));assert.equal(await page.locator('#items .file-name').first().textContent(),filename);
     await page.evaluate(()=>scrollTo(0,500));const transferScroll=await page.evaluate(()=>scrollY);await page.locator('.side-link[data-page="settings"]').click();await toTransfers(page);await page.waitForFunction(target=>Math.abs(scrollY-target)<2,transferScroll);assert((await page.locator('#page-summary').textContent()).includes('第 2'));
     await page.locator('#search-files').fill('生日');await page.waitForFunction(()=>document.querySelectorAll('#items .file-name').length===17);assert((await page.locator('#page-summary').textContent()).includes('第 1'));
     await page.locator('#items .file-name').first().click();await page.locator('#details-dialog').waitFor({state:'visible'});await snapshot(page,`detail-${theme}`);
     mode='retry-error';await page.locator('#detail-retry').click();await page.locator('#detail-message.error').waitFor();assert(await page.locator('#details-dialog').isVisible());assert((await page.locator('#detail-status').textContent()).includes('失败'));await snapshot(page,`retry-error-${theme}`);
     mode='normal';await page.locator('#detail-retry').click();await page.waitForFunction(()=>document.getElementById('detail-message').textContent.includes('等待接收端'));assert(lastRetry&&lastRetry.startsWith('synthetic-'));assert(await page.locator('#details-dialog').isVisible());assert((await page.locator('#detail-status').textContent()).includes('失败'));
     await page.keyboard.press('Escape');await page.locator('#details-dialog').waitFor({state:'hidden'});assert.equal(await page.evaluate(()=>document.activeElement.className),'file-name');
     const before=page.url();await page.locator('#help-open').click();await page.locator('#help-dialog').waitFor({state:'visible'});assert.equal(await page.locator('#help-dialog button').count(),1);assert.equal(await page.locator('#help-dialog :is(a,input,select)').count(),0);await snapshot(page,`help-${theme}`);await page.locator('#help-close').click();assert.equal(page.url(),before);
     await page.locator('#retry').click();const calls=requests.filter(r=>r.path==='/api/retry').length;await page.locator('#retry-cancel').click();assert.equal(requests.filter(r=>r.path==='/api/retry').length,calls);
     await page.locator('#retry').click();await page.locator('#retry-confirm').click();await page.waitForFunction(()=>document.getElementById('retry-message').textContent.includes('17'));assert.equal(lastRetry,null);assert(await page.locator('#retry-dialog').isVisible());await page.locator('#retry-cancel').click();
     await page.locator('#search-files').fill('不存在的合成文件');await page.waitForFunction(()=>document.getElementById('result-count').textContent.includes('0'));assert((await page.locator('#items').textContent()).includes('没有符合'));await snapshot(page,`empty-${theme}`);
     await page.locator('#search-files').fill('');await page.waitForFunction(()=>document.querySelectorAll('#items .file-name').length===20);
     await page.locator('#state-filter').selectOption('receiving');await page.waitForFunction(()=>document.getElementById('result-count').textContent.includes('16'));assert((await page.locator('#items').textContent()).includes('接收中'));assert.equal(await page.locator('#items [role=progressbar]').count(),16);
     await page.locator('#state-filter').selectOption('all');await page.locator('#kind-filter').selectOption('burst');await page.waitForFunction(()=>document.getElementById('result-count').textContent.includes('7'));assert.equal(await page.locator('#items .file-icon.burst').count(),7);
     await page.locator('#kind-filter').selectOption('all');await page.waitForFunction(()=>document.querySelectorAll('#items .file-name').length===20);
     mode='missing-id';await page.locator('#search-files').fill('生日');await page.waitForFunction(()=>document.querySelectorAll('#items .file-name').length===17);await page.locator('#items .file-name').first().click();assert(await page.locator('#detail-retry').isDisabled());assert((await page.locator('#detail-message').textContent()).includes('标识'));assert(!requests.some(r=>r.query.includes('undefined')));await page.locator('#details-close').click();
     mode='history-error';await page.locator('#refresh').click();await page.locator('#message.error').waitFor();assert(await page.locator('#transfers-section').isVisible());await snapshot(page,`history-error-${theme}`);
     mode='offline';await page.locator('#refresh').click();await page.locator('#dashboard-feedback.error').waitFor();assert((await page.locator('#live-text').textContent()).includes('无法连接'));
     mode='normal';await page.locator('#refresh').click();await page.waitForFunction(()=>document.getElementById('live-text').textContent==='已连接管理页');
     await page.locator('.side-link[data-page="settings"]').click();await page.locator('#appearance').selectOption(theme==='light'?'dark':'light');assert.equal(await page.locator('html').getAttribute('data-theme'),theme==='light'?'dark':'light');await page.locator('#appearance').selectOption(theme);
     assert.equal(await page.locator('[data-page-panel="settings"] input[type="checkbox"]').count(),1);
     mode='logout-error';await page.locator('#logout').click();await page.locator('#dashboard-feedback.error').waitFor();assert(await page.locator('#dashboard').isVisible());
     mode='normal';await page.locator('#logout').click();await page.locator('#login-panel').waitFor({state:'visible'});assert.equal(await page.evaluate(()=>localStorage.getItem('backupduck-dashboard-token')),null);
     await login(page);mode='expired';await toTransfers(page);await page.locator('#refresh').click();await page.locator('#login-panel').waitFor({state:'visible'});assert((await page.locator('#login-message').textContent()).includes('会话'));assert.equal(await page.locator('#items .file-name').count(),0);
     assert.deepEqual(errors,[]);counts.desktopThemes++;await context.close();
   }
   // Responsive / keyboard / missing values / English / reduced motion.
   for(const width of [320,390])for(const theme of ['light','dark']){
     mode='normal';const {context,page,errors}=await readyPage(browser,{locale:'en-US',colorScheme:theme,viewport:{width,height:844},reducedMotion:'reduce'});await snapshot(page,`login-${width}-${theme}`);await noPageOverflow(page);await login(page);await snapshot(page,`overview-${width}-${theme}`);await noPageOverflow(page);await toTransfers(page);await snapshot(page,`transfers-${width}-${theme}`);await noPageOverflow(page);
     mode='missing';await page.locator('#refresh').click();await page.waitForFunction(()=>document.getElementById('temperature').textContent==='—');await page.locator('#items .file-name').first().click();assert((await page.locator('#detail-captured').textContent()).includes('Unknown'));assert((await page.locator('#detail-senders').textContent()).includes('Unknown'));await snapshot(page,`missing-detail-${width}-${theme}`);await page.keyboard.press('Escape');assert.deepEqual(errors,[]);counts.mobileWidths++;await context.close();
   }
   const report={...counts,checkedAt:new Date().toISOString(),data:'synthetic only',realPixel:'not tested',userAcceptance:'pending'};
   fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');console.log('PASS:',JSON.stringify(report));
 }finally{await browser.close();server.close();}
})().catch(error=>{console.error(error);server.close();process.exit(1);});
