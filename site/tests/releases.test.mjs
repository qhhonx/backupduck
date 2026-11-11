import {test} from 'node:test'; import assert from 'node:assert/strict'; import {completeRelease} from '../lib/releases.js';
function fixture(tag='v0.1.0-beta.1'){const prefix=`https://github.com/qhhonx/backupduck/releases/download/${tag}/`;return {tag_name:tag,published_at:'2026-09-13',draft:false,assets:[`BackupDuck-${tag.slice(1)}-arm64.zip`,`BackupDuck-${tag.slice(1)}-arm64.apk`,'appcast.xml','android-update.json','SHA256SUMS'].map(name=>({name,size:100,browser_download_url:prefix+name}))};}
test('only complete published releases are offered',()=>{const a=fixture();assert.ok(completeRelease([a]));a.assets.pop();assert.equal(completeRelease([a]),null);assert.equal(completeRelease([{...fixture(),draft:true}]),null);});
test('sort semantic versions and reject foreign downloads',()=>{assert.equal(completeRelease([fixture(),fixture('v0.1.0-beta.10'),fixture('v0.1.0-beta.2')]).version,'0.1.0-beta.10');const a=fixture();a.assets[0].browser_download_url='https://example.com/bad.zip';assert.equal(completeRelease([a]),null);});
test('RC releases advance past beta while stable releases win within the same version',()=>{
  const releases=['v0.2.0-alpha.1','v0.2.0-beta.99','v0.2.0-rc.1','v0.2.0-rc.10','v0.2.0-rc.2'].map(tag=>fixture(tag));
  assert.equal(completeRelease(releases).version,'0.2.0-rc.10');
  assert.equal(completeRelease([...releases,fixture('v0.2.0')]).version,'0.2.0');
  assert.equal(completeRelease([fixture('v0.1.0-beta.38'),fixture('v0.2.0-rc.1')]).version,'0.2.0-rc.1');
});

test('prefer the universal Mac ZIP and keep older Apple Silicon releases discoverable', () => {
  const older = fixture('v0.6.1');
  const newer = fixture('v0.6.2');
  const name = 'BackupDuck-0.6.2-universal.zip';
  newer.assets.push({name, size: 100, browser_download_url: `https://github.com/qhhonx/backupduck/releases/download/v0.6.2/${name}`});
  const release = completeRelease([older, newer]);
  assert.ok(release.mac.endsWith(name));
  assert.equal(release.universalMac, true);
  assert.equal(completeRelease([older]).universalMac, false);
  newer.assets.shift();
  assert.equal(completeRelease([older, newer]).version, '0.6.2');
});
