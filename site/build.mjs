import {cp, mkdir, readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {completeRelease} from './lib/releases.js';

const source = fileURLToPath(new URL('.', import.meta.url));
export async function buildSite(output, releases, fetchFeed = fetch) {
  const release = completeRelease(releases);
  if (!release) throw Error('No complete published release; keep the previous website deployment.');
  const response = await fetchFeed(release.feed, {signal: AbortSignal.timeout(10000)});
  if (!response.ok) throw Error('Cannot retrieve the published appcast.');
  const feed = Buffer.from(await response.arrayBuffer());
  if (feed.length > 1048576 || !feed.includes(Buffer.from('<rss'))) throw Error('Invalid published appcast.');
  await mkdir(output, {recursive: true});
  for (const name of ['index.html', 'privacy.html', 'style.css', 'app.js', 'zh.json', 'icon.png', 'memories.png', 'media']) {
    await cp(resolve(source, name), resolve(output, name), {recursive: true});
  }
  await mkdir(resolve(output, 'lib'), {recursive: true});
  await cp(resolve(source, 'lib/demo.js'), resolve(output, 'lib/demo.js'));
  const {feed: _, ...metadata} = release;
  await writeFile(resolve(output, 'releases.json'), JSON.stringify(metadata) + '\n');
  // Sparkle verifies the signed feed, including its whitespace. Never serialize it.
  await writeFile(resolve(output, 'appcast.xml'), feed);
  await writeFile(resolve(output, '.nojekyll'), '');
  await writeFile(resolve(output, 'CNAME'), 'backupduck.app\n');
  return metadata;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const output = resolve(process.argv[2] || 'build/site');
  const fixture = process.argv[3];
  let releases;
  if (fixture) releases = JSON.parse(await readFile(fixture, 'utf8'));
  else {
    const headers = {Accept: 'application/vnd.github+json', 'User-Agent': 'BackupDuck'};
    // Authenticate only the GitHub API request; never forward credentials to assets.
    if (process.env.GH_TOKEN) headers.Authorization = `Bearer ${process.env.GH_TOKEN}`;
    const response = await fetch('https://api.github.com/repos/qhhonx/backupduck/releases?per_page=30', {
      headers, signal: AbortSignal.timeout(10000)
    });
    if (!response.ok) throw Error(`Cannot read published releases (HTTP ${response.status}).`);
    releases = await response.json();
  }
  console.log(JSON.stringify(await buildSite(output, releases)));
}
