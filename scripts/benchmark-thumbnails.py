#!/usr/bin/env python3
"""Build/run an isolated baseline-vs-candidate UIKit cache benchmark.
Uses only a user-selected disposable simulator with synthetic Photos fixtures.
"""
from pathlib import Path
import argparse,json,subprocess,statistics,hashlib
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--device',required=True,help='Disposable simulator UDID with synthetic images')
p.add_argument('--baseline',default='3d21049',help='Committed pipeline revision to replay')
p.add_argument('--nuke',action='store_true',help='Compare Nuke 13.2.0 default and tuned image pipelines')
p.add_argument('--nuke-path',type=Path,help='Optional local checkout of the pinned Nuke version')
p.add_argument('--output',default='build/thumbnail-benchmark')
a=p.parse_args(); root=Path(__file__).resolve().parents[1]; out=(root/a.output).resolve();out.mkdir(parents=True,exist_ok=True)
src=subprocess.check_output(['git','show',f'{a.baseline}:apps/apple/Shared/PhotoLibraryModel.swift'],cwd=root,text=True)
start=src.index('#if os(iOS)\n/// Rebuildable renditions')
end=src.index('\nfunc taskSymbol(',start)
baseline='import Combine\nimport Foundation\nimport Photos\nimport CryptoKit\nimport UIKit\n'+src[start:end]
baseline=baseline.replace('ThumbnailPipeline','BenchmarkBaselinePipeline').replace('ThumbnailDiskCache','BenchmarkBaselineDiskCache')
(out/'Baseline.swift').write_text(baseline)
candidate=(root/'apps/apple/Shared/PhotoLibraryModel.swift').read_text()
(out/'CandidatePhotoLibraryModel.swift').write_text(candidate)
# Generated project lives only in ignored output. Production source is never rewritten.
settings={'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','CODE_SIGNING_ALLOWED':'NO','ENABLE_USER_SCRIPT_SANDBOXING':'NO','ENABLE_TESTABILITY':'YES','ONLY_ACTIVE_ARCH':'YES','ARCHS':'arm64'}
app={'type':'application','platform':'iOS','sources':[{'path':str(root/'apps/apple/Shared'),'excludes':['PhotoLibraryModel.swift']},{'path':str(out/'CandidatePhotoLibraryModel.swift')},{'path':str(root/'apps/apple/Resources')},{'path':str(root/'apps/ios/BackupDuck'),'excludes':['Info.plist']},{'path':str(out/'Baseline.swift')}],
'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'app.backupduck.cachebenchmark','INFOPLIST_FILE':str(root/'apps/ios/BackupDuck/Info.plist'),'SWIFT_OBJC_BRIDGING_HEADER':str(root/'crates/native/include/backupduck.h'),'OTHER_LDFLAGS':['$(BUILT_PRODUCTS_DIR)/libbackupduck_native.a','-framework','Security','-framework','SystemConfiguration','-lsqlite3','-lz','-liconv'],'TARGETED_DEVICE_FAMILY':'1,2'}},
'preBuildScripts':[{'name':'Build benchmark engine','script':'set -eu\nexport PATH="$HOME/.cargo/bin:$PATH"\nexport IPHONEOS_DEPLOYMENT_TARGET=17.0\nexport SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"\ncd '+"'"+str(root).replace("'","'\\''")+"'"+'\ncargo build --locked --release -p backupduck-native --no-default-features --target aarch64-apple-ios-sim\ncp target/aarch64-apple-ios-sim/release/libbackupduck_native.a "$BUILT_PRODUCTS_DIR/"'}]}
spec={'name':'ThumbnailBenchmark','options':{'deploymentTarget':{'iOS':'17.0'}},'settings':{'base':settings},'targets':{'BackupDuck':app,'ThumbnailBenchmarkTests':{'type':'bundle.unit-test','platform':'iOS','sources':[{'path':str(root/'scripts/benchmarks/ThumbnailBenchmarkTests.swift')}],'dependencies':[{'target':'BackupDuck'}],'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'app.backupduck.cachebenchmark.tests','GENERATE_INFOPLIST_FILE':'YES'}}}},'schemes':{'ThumbnailBenchmark':{'build':{'targets':{'BackupDuck':'all'}},'test':{'targets':['ThumbnailBenchmarkTests']}}}}
if a.nuke:
 if a.nuke_path:
  checkout=a.nuke_path.resolve()
  version=subprocess.check_output(['git','describe','--tags','--exact-match'],cwd=checkout,text=True).strip()
  if version!='13.2.0': raise SystemExit('The local Nuke checkout must be exactly 13.2.0')
  if subprocess.run(['git','diff','--quiet','HEAD','--'],cwd=checkout).returncode:
   raise SystemExit('The local Nuke checkout must have no tracked modifications')
  spec['packages']={'Nuke':{'path':str(checkout)}}
 else:
  spec['packages']={'Nuke':{'url':'https://github.com/kean/Nuke.git','exactVersion':'13.2.0'}}
 spec['targets']['ThumbnailBenchmarkTests']['dependencies'].append({'package':'Nuke','product':'Nuke'})
 spec['targets']['ThumbnailBenchmarkTests']['settings']['base']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='$(inherited) NUKE_BENCHMARK'
 spec['targets']['ThumbnailBenchmarkTests']['sources'].append({'path':str(root/'scripts/benchmarks/NukeBenchmarkAdapter.swift')})
(out/'project.json').write_text(json.dumps(spec,indent=2))
subprocess.run(['xcodegen','generate','--spec',str(out/'project.json')],check=True,cwd=root)
with (out/'run.log').open('w') as log:
 result=subprocess.run(['xcodebuild','-project',str(out/'ThumbnailBenchmark.xcodeproj'),'-scheme','ThumbnailBenchmark','-configuration','Release','-parallel-testing-enabled','NO','-destination',f'platform=iOS Simulator,id={a.device}','-derivedDataPath',str(out/'DerivedData'),'-resultBundlePath',str(out/'results.xcresult'),'test'],cwd=root,stdout=log,stderr=subprocess.STDOUT)
if result.returncode: raise SystemExit(f'Benchmark failed; inspect {out / "run.log"}')
subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(out/'results.xcresult'),'--output-path',str(out/'attachments')],check=True)
manifest=json.loads((out/'attachments/manifest.json').read_text())
attachment=next(item for test in manifest for item in test['attachments'] if item['suggestedHumanReadableName'].startswith('thumbnail-benchmark'))
metrics=json.loads((out/'attachments'/attachment['exportedFileName']).read_text())
(out/'metrics.json').write_text(json.dumps(metrics,indent=2))
summary=[]
for scenario in dict.fromkeys(row['scenario'] for row in metrics):
 values={}
 for strategy in dict.fromkeys(row['strategy'] for row in metrics):
  rows=[row for row in metrics if row['scenario']==scenario and row['strategy']==strategy]
  values[strategy]={'elapsed_median_ms':statistics.median(row['elapsed_ms'] for row in rows),
   'loader_starts':[row['loader_starts'] for row in rows], 'completed':[row['completed'] for row in rows],
   'first_p95_median_ms':statistics.median(row['first_p95_ms'] for row in rows),
   'final_p95_median_ms':statistics.median(row['final_p95_ms'] for row in rows),
   'main_gap_p95_median_ms':statistics.median(row.get('main_gap_p95_ms',0) for row in rows),
   'main_gap_max_median_ms':statistics.median(row.get('main_gap_max_ms',0) for row in rows)}
 summary.append({'scenario':scenario,'strategies':values})
(out/'summary.json').write_text(json.dumps(summary,indent=2))
(out/'context.json').write_text(json.dumps({'baseline':a.baseline,'baseline_commit':subprocess.check_output(['git','rev-parse',a.baseline],cwd=root,text=True).strip(),'candidate_sha256':hashlib.sha256(candidate.encode()).hexdigest(),'nuke':'13.2.0' if a.nuke else None,'configuration':'Release','fixture':'synthetic simulator Photos metadata and controlled image loader'},indent=2))
print(f'Benchmark results and comparison: {out}')
