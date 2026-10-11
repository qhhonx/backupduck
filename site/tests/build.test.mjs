import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm, access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {buildSite} from '../build.mjs';
const version = '0.3.0';
function release() {
  const prefix = `https://github.com/qhhonx/backupduck/releases/download/v${version}/`;
  return {tag_name: `v${version}`, published_at: '2026-10-10', draft: false,
    assets: [`BackupDuck-${version}-arm64.zip`, `BackupDuck-${version}-arm64.apk`, 'appcast.xml', 'android-update.json', 'SHA256SUMS'].map(name => ({name, size: 1, browser_download_url: prefix + name}))};
}
test('static site preserves signed bytes and publishes only complete release metadata', async () => {
  const output = await mkdtemp(join(tmpdir(), 'duck-site-'));
  try {
    const bytes = Buffer.from('<?xml version="1.0"?>\r\n<rss>  signed whitespace\n</rss>\n');
    await buildSite(output, [release()], async () => new Response(bytes));
    assert.deepEqual(await readFile(join(output, 'appcast.xml')), bytes);
    const metadata = JSON.parse(await readFile(join(output, 'releases.json'), 'utf8'));
    assert.equal(metadata.version, version);
    assert.equal(metadata.feed, undefined);
    assert.equal(await readFile(join(output, 'CNAME'), 'utf8'), 'backupduck.app\n');
    await access(join(output, 'lib/demo.js'));
    await assert.rejects(access(join(output, 'api')));
    await assert.rejects(buildSite(output, [{...release(), draft: true}]), /No complete/);
    assert.deepEqual(await readFile(join(output, 'appcast.xml')), bytes);
    await assert.rejects(buildSite(output, [release()], async () => new Response('error', {status: 503})));
    assert.deepEqual(await readFile(join(output, 'appcast.xml')), bytes);
  } finally { await rm(output, {recursive: true, force: true}); }
});
