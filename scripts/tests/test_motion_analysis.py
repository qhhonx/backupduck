"""Verify the recording analyser on known synthetic motion, without private media."""
import csv,json,subprocess,sys,tempfile,unittest
from pathlib import Path
import numpy as np
from PIL import Image
class MotionAnalysisTests(unittest.TestCase):
 def test_known_ease_out_translation(self):
  root=Path(__file__).resolve().parents[1]
  with tempfile.TemporaryDirectory() as temporary:
   folder=Path(temporary); frames=folder/'frames';frames.mkdir()
   pattern=np.random.default_rng(42).integers(20,230,(24,24),dtype=np.uint8)
   rows=[]
   for i in range(37):
    t=i/60; progress=1-(1-min(1,t/.4))**2
    x=10+round(60*progress)
    pixels=np.full((80,120),240,dtype=np.uint8);pixels[28:52,x:x+24]=pattern
    file=f'{i}.png';Image.fromarray(pixels).save(frames/file);rows.append([t,t,file])
   with (frames/'frames.csv').open('w') as f:
    w=csv.writer(f);w.writerow(['requested_seconds','actual_seconds','file']);w.writerows(rows)
   config={'tracks':[{'name':'patch','reference':'36.png','template':[70,28,94,52],'search':[0,20,120,65],'analysis_scale':1,'start':0,'end':.6}],
    'release_windows':[{'track':'patch','property':'x','start':0,'end':.6,'min_score':.7}]}
   (folder/'config.json').write_text(json.dumps(config))
   subprocess.run([sys.executable,str(root/'analyze-motion.py'),'--frames',str(frames),'--output',str(folder/'out'),'--config',str(folder/'config.json')],check=True,capture_output=True)
   result=json.loads((folder/'out/analysis.json').read_text());fit=result['fits'][0]
   self.assertLess(fit['normalized_rmse'],.025)
   self.assertEqual(fit['fit']['family'],'ease_out_power')
   self.assertAlmostEqual(fit['fit']['duration'],.4,delta=.025)
   self.assertAlmostEqual(fit['fit']['power'],2,delta=.25)
if __name__=='__main__':unittest.main()
