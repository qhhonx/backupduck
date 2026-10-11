async page => {
  const errors=[], issues=[], shots=[];page.on('pageerror',e=>errors.push(e.message));
  await page.setViewportSize({width:1700,height:1300});
  const base=await page.evaluate(()=>new URL('./index.html',location.href).href);
  await page.goto(base);const entries=await page.locator('#catalog [data-catalog]').evaluateAll(es=>es.map(e=>e.dataset.catalog));
  let states=0;
  for(const [locale,width,font,dark] of [['en','320','2',true],['zh','375','2',false],['en','768','1',true]]) {
    for(const id of entries) {
      await page.goto(base+'?screen='+id);await page.locator('#locale').selectOption(locale);await page.locator('#width').selectOption(width);await page.locator('#font').selectOption(font);await page.locator('#dark').setChecked(dark);
      for(const scene of await page.locator('#scenario option').allTextContents()) {
        await page.locator('#scenario').selectOption(scene);states++;
        const check=await page.evaluate(()=>{
          const box=document.querySelector('.sheet')||document.querySelector('#app'),b=box.getBoundingClientRect();
          const bad=[...box.querySelectorAll('button,input,select')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&(r.left<b.left-1||r.right>b.right+1)}).map(e=>e.textContent||e.getAttribute('aria-label'));
          const footer=document.querySelector('.sheet-foot');const footerOutside=footer?footer.getBoundingClientRect().bottom>b.bottom+1:false;
          const head=document.querySelector('.sheet-head'),body=document.querySelector('.sheet-body');const bodyHeight=body?body.getBoundingClientRect().height:null;
          return {bad,footerOutside,bodyHeight};
        });
        if(check.bad.length||check.footerOutside||check.bodyHeight!==null&&check.bodyHeight<40)issues.push({locale,width,font,id,scene,...check});
      }
      if(['library','backup','receiver','settings','pair-scan','device-name','transfer-detail','help'].includes(id)){
        await page.evaluate(()=>Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))));const name=locale+'-'+width+'-'+font+'-'+id;await page.locator('#device').screenshot({path:'output/playwright/ios-v12/'+name+'.png'});shots.push(name);
      }
    }
  }
  return {states,errors,issues,screenshots:shots};
}
