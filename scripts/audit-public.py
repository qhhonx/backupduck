#!/usr/bin/env python3
"""Check candidate source for private material and public documentation rules."""
from pathlib import Path
import argparse, re, subprocess, sys
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--staged',action='store_true',help='Read the entire Git index, not working files.')
parser.add_argument('--documentation',action='store_true',help='Also check primary Markdown and internal design records.')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
git_root=Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],cwd=root).decode().strip()).resolve()
if git_root != root:
 sys.exit('Audit root must be an independent Git repository; refusing to scan the parent repository.')
listing=['git','ls-files','--cached','-z']
if not args.staged: listing[3:3]=['--others','--exclude-standard']
names=[name for name in subprocess.check_output(listing,cwd=root).decode().split('\0') if name]
if not names: sys.exit('No candidate files found; an empty scan is not a successful audit.')
rules={
 'private key':rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
 'GitHub token':rb'gh[pousr]_[A-Za-z0-9]{30,}',
 'absolute home':rb'/(?:Users|home)/[A-Za-z][^/\s"\']+/',
 'Apple device ID':rb'\b[0-9A-F]{8}-[0-9A-F]{16}\b',
 'personal team setting':rb'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}',
}
errors=[]
for name in sorted(set(names)):
 if not name: continue
 path=root/name
 if path.suffix in ['.jks','.keystore','.key','.mobileprovision','.p12']:
  errors.append((name,'signing material'));continue
 if not args.staged and not path.is_file(): continue
 if args.staged:
  content=subprocess.check_output(['git','show',f':{name}'],cwd=root)
 else:
  content=path.read_bytes()
 if args.documentation:
  if name.startswith(('.playwright-cli/','output/','artifacts/')):
   errors.append((name,'local development output'))
  if name.startswith('design/') and path.suffix=='.md' and re.search(
    r'(?:handoff|acceptance-feedback|continuation|(?:^|/)feedback|fidelity-(?:redo-status|delivery-audit|completion-audit)|requirement-evidence-audit|native-status|(?:^|/)bd\d|(?:^|/)validation\.md$)',name):
   errors.append((name,'internal design or acceptance record'))
  if path.suffix=='.md' and not re.search(r'\.zh(?:-[A-Za-z]+)?\.md$',name):
   prose=content.decode('utf-8',errors='replace')
   if any(len(re.findall(r'[\u3400-\u9fff]',line))>=12 for line in prose.splitlines()):
    errors.append((name,'primary documentation must use English; keep translations explicitly labeled'))
 if path.suffix in ['.png','.icns','.jar']: continue
 for label,pattern in rules.items():
  if re.search(pattern,content): errors.append((name,label))
for name,label in errors: print(f'{name}: {label}')
if errors: sys.exit(1)
scope='Git index' if args.staged else 'working tree'
print(f'Public-source checks passed for {len(set(names))} files ({scope}). Review still required for context-specific personal data.')
