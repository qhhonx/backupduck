async page=>{
 const base=await page.evaluate(()=>new URL('./index.html',location.href).href);
 const require=(ok,msg)=>{if(!ok)throw Error(msg)};
 const done=[];
 await page.goto(base+'?screen=activity-log');await page.locator('#locale').selectOption('en');
 await page.locator('.sheet-foot [data-open="diagnostic-share"]').click();
 require(await page.locator('.sheet-head [data-action="close"]').isDisabled(),'Preparing must prevent dismissal');
 await page.waitForFunction(()=>document.querySelector('[data-action="share-report"]')!==null);
 require((await page.locator('.sheet-body').innerText()).includes('Activity log ready'),'Prepared file does not mean saved destination');
 await page.locator('[data-action="share-report"]').click();require((await page.locator('.boundary').innerText()).includes('does not mean saving succeeded'),'System sharing boundary must not claim success');
 await page.locator('.sheet-foot [data-action="share-return"]').click();require(await page.locator('[data-action="share-report"]').count()===1,'Cancelled sharing retains prepared file window');
 await page.locator('#scenario').selectOption('导出失败');require(await page.locator('[data-action="share-report"]').count()===0,'Failed preparation cannot expose share');
 await page.locator('[data-action="prepare-report"]').click();await page.waitForFunction(()=>document.querySelector('#scenario')?.value==='导出失败');
 require((await page.locator('.sheet-body').innerText()).includes('Could not prepare'),'Failure remains in current export window');
 await page.locator('[data-action="prepare-report"]').click();await page.waitForFunction(()=>document.querySelector('[data-action="share-report"]')!==null);
 await page.locator('.sheet-foot [data-action="close"]').click();require(await page.locator('#sheet-title').innerText()==='Activity log','Export close returns to existing log');done.push('export preparation, explicit sharing, cancellation, failure and fresh retry');
 await page.goto(base+'?screen=transfer-sort');await page.locator('#locale').selectOption('en');
 for(const state of ['准备原件','历史扫描']){await page.locator('#scenario').selectOption(state);require(await page.locator('[data-choice="sort"][data-value="activity"]').count()===0,'Source browsers must not offer unsupported activity ordering')}
 await page.locator('#scenario').selectOption('已接收');require(await page.locator('[data-choice="sort"][data-value="activity"]').count()===1,'Receipt time ordering is real');done.push('state-specific sort options match native API');
 await page.goto(base+'?screen=transfer-detail');await page.locator('#locale').selectOption('en');await page.locator('#scenario').selectOption('发送失败');
 require((await page.locator('.timeline li').first().innerText()).includes('Receipt is not confirmed'),'Failed send must not claim persisted originals');
 await page.locator('#scenario').selectOption('相册处理失败');require((await page.locator('.timeline li').first().innerText()).includes('persisted and verified'),'Publication failure retains received originals');
 require(await page.locator('[data-action="retry-detail"]').count()===0,'iOS must not invent receiver-processing retry API');done.push('send failure and gallery failure have separate receipt truth');
 return {flows:done};
}
