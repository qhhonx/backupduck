#!/usr/bin/env python3
"""Measure local timestamped frames; flag candidates, never assert hidden gesture input.
Requires numpy and Pillow. Input is sample-motion.swift's frames.csv.
"""
from pathlib import Path
import argparse,csv,json,math,html
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--frames',required=True);p.add_argument('--output',required=True)
p.add_argument('--config',help='JSON: normalized content rectangle, optional template tracks and release windows')
a=p.parse_args();folder=Path(a.frames);out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
config=json.loads(Path(a.config).read_text()) if a.config else {}
inputs=list(csv.DictReader((folder/'frames.csv').open()))
content=config.get('content',[0,0.14,1,0.9]); rows=[];previous=None
for r in inputs:
 im=Image.open(folder/r['file']).convert('RGB');w,h=im.size
 roi=im.crop(tuple(int(v*s) for v,s in zip(content,[w,h,w,h]))).resize((240,480))
 pixels=np.asarray(roi,dtype=np.float32);gray=pixels.mean(2)
 blocks=gray[:480,:240].reshape(24,20,12,20).transpose(0,2,1,3)
 # Uniform blocks are candidates: white photos, sky and natural row endings can be valid.
 flat=float(np.mean(blocks.std((2,3))<3.0));sharp=float(np.mean(np.abs(np.diff(gray,axis=0))))
 change=0 if previous is None else float(np.mean(np.abs(pixels-previous)))
 rows.append({'time':float(r['actual_seconds']),'file':r['file'],'flat_fraction':flat,'edge_energy':sharp,'frame_change':change})
 previous=pixels
tracks=[]
for spec in config.get('tracks',[]):
 reference=Image.open(folder/spec['reference']).convert('L');scale=spec.get('analysis_scale',0.25)
 reference=reference.resize((int(reference.width*scale),int(reference.height*scale)))
 rect=tuple(int(x*scale) for x in spec['template']);template=np.asarray(reference.crop(rect),dtype=np.float32)
 # High-pass matching rejects changing glass/background brightness.
 def highpass(im):return np.asarray(im,dtype=np.float32)-np.asarray(im.filter(ImageFilter.GaussianBlur(2)),dtype=np.float32)
 template=highpass(reference.crop(rect));values=[]
 for row in rows:
  if not spec.get('start',-1)<=row['time']<=spec.get('end',1e9):continue
  im=Image.open(folder/row['file']).convert('L');im=im.resize(reference.size)
  x0,y0,x1,y1=(int(x*scale) for x in spec['search']);region=highpass(im.crop((x0,y0,x1,y1)))
  best=(-2,None)
  for factor in spec.get('scales',[1]):
   t=np.asarray(Image.fromarray(template,mode='F').resize((max(2,int(template.shape[1]*factor)),max(2,int(template.shape[0]*factor)))),dtype=np.float32)
   th,tw=t.shape
   if th>region.shape[0] or tw>region.shape[1]:continue
   windows=np.lib.stride_tricks.sliding_window_view(region,(th,tw))[::2,::2]
   t=t-t.mean();norm=float(np.sqrt((t*t).sum()))
   numerator=np.einsum('ijkl,kl->ij',windows,t,optimize=True)
   integral=lambda x: np.pad(x,((1,0),(1,0))).cumsum(0).cumsum(1)
   def box_sum(x):
    v=integral(x); return (v[th:,tw:]-v[:-th,tw:]-v[th:,:-tw]+v[:-th,:-tw])[::2,::2]
   sums=box_sum(region);squares=box_sum(region*region)
   denominator=np.sqrt(np.maximum(1e-8,squares-sums*sums/(th*tw)))*max(1e-8,norm)
   scores=numerator/denominator; iy,ix=np.unravel_index(np.argmax(scores),scores.shape);score=float(scores[iy,ix])
   if score>best[0]:
    patch=region[iy*2:iy*2+th,ix*2:ix*2+tw]
    contrast=float((patch*t).sum()/max(1e-8,(t*t).sum()))
    best=(score,{'time':row['time'],'x':(x0+ix*2)/scale,'y':(y0+iy*2)/scale,'scale':factor,'contrast_proxy':contrast,'match_score':score})
  if best[1] is not None:values.append(best[1])
 tracks.append({'name':spec['name'],'values':values})
for track in tracks:
 with (out/(track['name']+'.csv')).open('w') as f:
  if track['values']:
   writer=csv.DictWriter(f,fieldnames=track['values'][0].keys());writer.writeheader();writer.writerows(track['values'])
fits=[]
for window in config.get('release_windows',[]):
 track=next(x for x in tracks if x['name']==window['track']);key=window.get('property','y')
 samples=[x for x in track['values'] if window['start']<=x['time']<=window['end'] and x['match_score']>=window.get('min_score',0.55)]
 if len(samples)<5:continue
 times=np.array([x['time'] for x in samples]);observed=np.array([x[key] for x in samples])
 span=observed[-1]-observed[0]
 if abs(span)<1e-6:continue
 normalized=(observed-observed[0])/span;t=times-times[0];best=(1e9,None)
 # Fit visible behavior only. A held gesture must never be labeled a free spring.
 for duration in np.linspace(max(t[-1]*0.2,0.025),t[-1]*1.6,70):
  u=np.clip(t/duration,0,1)
  for power in np.linspace(1,5,41):
   for family,prediction in [('ease_out_power',1-(1-u)**power),('ease_in_power',u**power)]:
    rmse=float(np.sqrt(np.mean((prediction-normalized)**2)))
    if rmse<best[0]:best=(rmse,{'family':family,'duration':float(duration),'power':float(power)})
  for family,prediction in [('smoothstep',u*u*(3-2*u)),('cosine',0.5-0.5*np.cos(np.pi*u))]:
   rmse=float(np.sqrt(np.mean((prediction-normalized)**2)))
   if rmse<best[0]:best=(rmse,{'family':family,'duration':float(duration)})
  for damping in [0.8,0.9,1.0]:
   omega=6/duration
   if damping==1:prediction=1-(1+omega*t)*np.exp(-omega*t)
   else:
    wd=omega*math.sqrt(1-damping*damping)
    prediction=1-np.exp(-damping*omega*t)*(np.cos(wd*t)+damping/math.sqrt(1-damping*damping)*np.sin(wd*t))
   rmse=float(np.sqrt(np.mean((prediction-normalized)**2)))
   if rmse<best[0]:best=(rmse,{'family':'damped_spring','duration':float(duration),'damping':damping})
 fits.append({'window':window,'samples':len(samples),'normalized_rmse':best[0],'fit':best[1],
  'limitation':'Visible fit only; release boundary must be manually confirmed. Contrast proxy is not true alpha.'})
flags=[dict(r,reason='uniform-area candidate' if r['flat_fraction']>0.45 else 'abrupt-change candidate') for r in rows if r['flat_fraction']>0.45 or r['frame_change']>35]
with (out/'frames.csv').open('w') as f:
 writer=csv.DictWriter(f,fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)
(out/'analysis.json').write_text(json.dumps({'frames':len(rows),'flags':flags,'tracks':tracks,'fits':fits},indent=2))
# Every interaction remains available at source timestamps, including frames not flagged.
for page in range((len(inputs)+29)//30):
 sheet=Image.new('RGB',(1500,((min(30,len(inputs)-page*30)+4)//5)*570),'#eee');draw=ImageDraw.Draw(sheet)
 for n,r in enumerate(inputs[page*30:(page+1)*30]):
  im=Image.open(folder/r['file']);im.thumbnail((296,536));x=n%5*300;y=n//5*570;sheet.paste(im,(x,y+25));draw.text((x+4,y+4),r['actual_seconds'],fill='black')
 sheet.save(out/f'sequence-{page:03}.jpg',quality=88)
body='<h1>Motion measurements</h1><p>Flags need human review. Gesture input, true alpha and proprietary timing are not directly observable.</p>'
body+='<pre>'+html.escape(json.dumps(fits,indent=2))+'</pre>'
body+='<table><tr><th>Time</th><th>Candidate</th><th>Uniform fraction</th></tr>'
body+=''.join(f'<tr><td>{r["time"]:.4f}</td><td>{r["reason"]}</td><td>{r["flat_fraction"]:.3f}</td></tr>' for r in flags)+'</table>'
body+=''.join(f'<img style="max-width:100%" src="sequence-{i:03}.jpg">' for i in range((len(inputs)+29)//30))
(out/'report.html').write_text('<!doctype html><meta charset="utf-8"><style>body{font:16px system-ui;max-width:1400px;margin:auto}td{padding:6px}pre{white-space:pre-wrap}</style>'+body)
print(f'{len(rows)} frames; {len(flags)} review candidates; {len(fits)} fitted windows: {out}')
