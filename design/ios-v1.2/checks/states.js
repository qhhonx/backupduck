async page => {
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await page.setViewportSize({width:1500,height:1200});
  const base=await page.evaluate(()=>new URL('./index.html',location.href).href);await page.goto(base);
  const entries=await page.locator('#catalog [data-catalog]').evaluateAll(es=>es.map(e=>e.dataset.catalog));
  const result=[];
  for(const locale of ['zh','en']) {
    for(const id of entries) {
      await page.goto(base+'?screen='+id);
      await page.locator('#locale').selectOption(locale);
      const scenarios=await page.locator('#scenario option').allTextContents();
      for(const scene of scenarios) {
        await page.locator('#scenario').selectOption(scene);
        const screen=await page.evaluate(()=>{
          const box=document.querySelector('.sheet')||document.querySelector('#app');
          const visible=box.innerText.trim();
          const wrong=[...box.querySelectorAll('button, input, select')].filter(e=>{
            const r=e.getBoundingClientRect(),b=box.getBoundingClientRect();
            return r.width>0&&r.left<b.left-1||r.right>b.right+1;
          }).map(e=>e.textContent||e.getAttribute('aria-label'));
          const rawKeys=visible.match(/\b(?:event_|library_filter_|state_|task_order_|design_|apple_|history_)[a-z_]+\b/g)||[];
          return {textLength:visible.length,horizontalOverflow:wrong,rawKeys};
        });
        result.push({locale,id,scene,...screen});
        if(screen.textLength<10) throw Error('Blank screen '+id+' '+scene);
      }
    }
  }
  const overflow=result.filter(x=>x.horizontalOverflow.length),missing=result.filter(x=>x.rawKeys.length);
  return {states:result.length,errors,overflow,missing};
}
