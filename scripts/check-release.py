#!/usr/bin/env python3
"""Check release metadata and embedded trust before publishing."""
from pathlib import Path
import json,plistlib,re,sys,tomllib,urllib.request
r=Path(__file__).resolve().parent.parent
i=json.loads((r/'release.json').read_text())
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?',i['version'])
assert type(i['build']) is int and 0<i['build']<2100000000
assert i['distribution_repository']=='qhhonx/backupduck'
assert tomllib.loads((r/'Cargo.toml').read_text())['workspace']['package']['version']==i['version']
for package in tomllib.loads((r/'Cargo.lock').read_text())['package']:
 if package['name']=='backupduck' or package['name'].startswith('backupduck-'):
  assert package['version']==i['version']
p=plistlib.loads((r/'apps/macos/BackupDuck/Info.plist').read_bytes())
assert p['SUPublicEDKey']==(r/'assets/update-public-key.txt').read_text().strip()
# Pin the installed-client trust anchors; changing both asset and plist together
# must not silently sever updates. An intentional rotation needs a migration.
assert p['SUPublicEDKey']=='s+qs6cjo68nDzWOAs2OB4CyO5WtcjD19KDJ2Pu1fVN4=', 'Sparkle trust identity changed'
assert (r/'assets/android-signing-cert.sha256').read_text().strip()=='4dd6c7ba1caa93069542dd65607100468bf49a1026dd51d3fd7638ad11361bb3', 'Android RC.2 release trust identity changed'
assert p['SUFeedURL']==i['website']+'/appcast.xml'
assert p['SURequireSignedFeed'] and p['SUVerifyUpdateBeforeExtraction']
# The release identity, native package and background registration must agree.
assert p['CFBundleIdentifier']=='app.backupduck'
ios=plistlib.loads((r/'apps/ios/BackupDuck/Info.plist').read_bytes())
assert ios['CFBundleIdentifier']=='app.backupduck'
store=plistlib.loads((r/'apps/macos/BackupDuck/StoreInfo.plist').read_bytes())
assert store['CFBundleIdentifier']=='app.backupduck'
assert not any(key.startswith('SU') for key in store), 'Store build must not advertise Sparkle'
for metadata in [p,ios,store]:
 assert metadata['CFBundleShortVersionString']==i['version'].split('-')[0]
 assert int(metadata['CFBundleVersion'])==i['build']
assert ios['BackupDuckReleaseVersion']==i['version']
identifier='app.backupduck.backup.processing'
assert identifier in ios['BGTaskSchedulerPermittedIdentifiers']
assert identifier in (r/'apps/ios/BackupDuck/BackgroundLifecycle.swift').read_text()
gradle=(r/'apps/android/app/build.gradle').read_text()
assert "namespace 'app.backupduck'" in gradle and "applicationId 'app.backupduck'" in gradle
assert 'Java_app_backupduck_NativeBridge_call' in (r/'crates/native/src/lib.rs').read_text()
assert (r/'apps/android/app/src/main/java/app/backupduck/NativeBridge.kt').exists()
if len(sys.argv)>1:
 releases=json.loads(Path(sys.argv[1]).read_text())
 for release in releases:
  if release['tag_name']=='v'+i['version'] and not release['draft']:
   print('publish=false');break
 else:
  def parts(version):
   match=re.fullmatch(r'(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?',version)
   if not match: return None
   major,minor,patch,stage,number=match.groups()
   return (int(major),int(minor),int(patch),{'alpha':0,'beta':1,'rc':2,None:3}[stage],int(number or 0))
  published=[release for release in releases if not release['draft'] and release.get('published_at') and parts(release['tag_name'].removeprefix('v'))]
  if published:
   previous=max(published,key=lambda release:parts(release['tag_name'].removeprefix('v')))
   assert parts(i['version']) > parts(previous['tag_name'].removeprefix('v')), 'Release version must increase'
   expected=f"https://github.com/{i['distribution_repository']}/releases/download/{previous['tag_name']}/android-update.json"
   assert any(a['name']=='android-update.json' and a['browser_download_url']==expected for a in previous['assets']), 'Previous release metadata missing'
   with urllib.request.urlopen(expected,timeout=30) as response:
    old=json.load(response)
   assert i['build'] > old['build'], 'Build number must increase'
  print('publish=true')
else: print('Release configuration verified')
