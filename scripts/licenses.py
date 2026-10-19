"""Collect Cargo package notices without shipping duplicate plaintext files."""
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

out = Path('dist/licenses')
out.mkdir(parents=True, exist_ok=True)
metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--format-version', '1']))
index = {}
for package in metadata['packages']:
    root = Path(package['manifest_path']).parent
    sources = []
    for directory, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if name not in ('.git', 'target', 'node_modules', '.vendor', 'dist', 'artifacts')]
        sources.extend(Path(directory) / name for name in files if name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')))
    for source in sources:
        if not source.is_file() or any(part in ('.git', 'target', 'node_modules', '.vendor') for part in source.relative_to(root).parts):
            continue
        if not source.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')):
            continue
        data = source.read_bytes()
        name = hashlib.sha256(data).hexdigest() + '.txt'
        (out / name).write_bytes(data)
        index[f"{package['name']}@{package['version']}/{source.relative_to(root).as_posix()}"] = name
for source in [Path('LICENSE'), Path('THIRD_PARTY_NOTICES.md'), Path('config/licenses/Pretendard-OFL.txt')]:
    shutil.copyfile(source, out / source.name)
(out / 'LICENSE-INDEX.json').write_text(json.dumps(index, indent=2, ensure_ascii=False), encoding='utf-8')
assert index, 'No dependency notices collected'
print(f'{len(index)} component notices, {len(set(index.values()))} unique files')
