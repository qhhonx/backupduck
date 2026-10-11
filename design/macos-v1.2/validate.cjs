'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=__dirname,cat=JSON.parse(fs.readFileSync(path.join(root,'catalog.json')));
const elements=new Map(),events={};
function node(id){if(!elements.has(id))elements.set(id,{value:'',innerHTML:'',scrollTop:0,inert:false,dataset:{},style:{setProperty(){}},classList:{toggle(){}},scrollTo(){},focus(){},querySelectorAll(){return[]}});return elements.get(id)}
const timers=[];const context=vm.createContext({console,URLSearchParams,location:{search:''},document:{querySelector:node,querySelectorAll:()=>[],documentElement:{dataset:{}},addEventListener:(type,cb)=>events[type]=cb,activeElement:null},window:{},setTimeout:fn=>timers.push(fn),clearTimeout(){},queueMicrotask:fn=>fn()});
for(const f of ['../android-v1.2/icons.js','catalog.js','prototype.js'])vm.runInContext(fs.readFileSync(path.join(root,f),'utf8'),context,{filename:f});
let count=0;
for(const item of cat){assert(fs.existsSync(path.join(root,'../../',item.source)),item.source);context.window.reviewAPI.open(item.id);for(const state of item.states){context.window.reviewAPI.setScenario(state);const html=context.window.reviewAPI.content(item.id);assert(html.length>25,`${item.id}/${state}`);for(const m of html.matchAll(/data-open="([^"]+)"/g))assert(cat.some(x=>x.id===m[1]),`Unknown destination ${m[1]} in ${item.id}`);if(item.id.startsWith('help-')||item.id==='folder-help')assert(!/data-open=|data-do=|data-toggle=/.test(html),`Help launches workflow: ${item.id}`);count++}}
// Model transitions are prototype behavior only, never native-interface evidence.
context.window.reviewAPI.open('device-name');vm.runInContext("draft.name='';save()",context);assert.equal(context.window.reviewAPI.inspect().scenario,'名称无效');assert(vm.runInContext('formError.length>0',context));
context.window.reviewAPI.open('folder-rules');vm.runInContext("draft.include='[';save()",context);assert(vm.runInContext('formError.length>0 && draft.include===\'[\'',context));
context.window.reviewAPI.open('concurrency');const before=context.window.reviewAPI.model.concurrency;vm.runInContext("draft.concurrency='4';perform('back')",context);assert.equal(context.window.reviewAPI.model.concurrency,before);
context.window.reviewAPI.open('concurrency');events.input({target:{dataset:{edit:'concurrency'},value:'4',id:''}});assert.equal(context.window.reviewAPI.model.concurrency,'4');context.window.reviewAPI.setScenario('保存失败');events.input({target:{dataset:{edit:'concurrency'},value:'2',id:''}});assert.equal(context.window.reviewAPI.model.concurrency,'4');
context.window.reviewAPI.open('folder-issue-detail');context.window.reviewAPI.setScenario('正常');vm.runInContext("perform('retry-file')",context);assert.equal(context.window.reviewAPI.inspect().scenario,'已请求重试');
context.window.reviewAPI.open('folder-rules');context.window.reviewAPI.setScenario('保存失败');assert(context.window.reviewAPI.content('folder-rules').includes('recover-source'));vm.runInContext("perform('recover-source')",context);assert.equal(context.window.reviewAPI.inspect().scenario,'正常');
assert.equal(cat.filter(x=>x.kind==='system').length,7);
console.log(`Mac prototype: ${cat.length} entries / ${count} states rendered; route targets, source references, pure help, invalid drafts, cancellation, saved model and retry request semantics passed. Native/UI acceptance remains pending.`);
