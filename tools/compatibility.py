#!/usr/bin/env python3
"""Compile the actual Android JVM data/archive code without writing its checkout.

LIMEN_ANDROID names a reviewed checkout. Dependencies are pinned to its toolchain,
kept in /tmp, and never bundled in Limen. Outputs are synthetic compatibility evidence.
"""
import argparse
import os
import subprocess
import shutil
import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID = Path(os.environ['LIMEN_ANDROID'])
CACHE = Path('/tmp/limen-jvm-compatibility')
CACHE.mkdir(exist_ok=True)
GRADLE = Path.home() / '.gradle/caches/modules-2/files-2.1'
ARTIFACTS = [
    ('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.3.20'),
    ('org.jetbrains.kotlin', 'kotlin-stdlib', '2.3.20'),
    ('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.3.20'),
    ('org.jetbrains.kotlin', 'kotlin-reflect', '1.6.10'),
    ('org.jetbrains.kotlin', 'kotlin-daemon-embeddable', '2.3.20'),
    ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0'),
    ('org.jetbrains', 'annotations', '13.0'),
    ('org.jetbrains.kotlin', 'kotlin-serialization-compiler-plugin-embeddable', '2.3.20'),
    ('org.jetbrains.kotlinx', 'kotlinx-serialization-core-jvm', '1.8.1'),
    ('org.jetbrains.kotlinx', 'kotlinx-serialization-json-jvm', '1.8.1'),
    ('com.googlecode.libphonenumber', 'libphonenumber', '9.0.34'),
]

def artifact(group, name, version):
    filename = f'{name}-{version}.jar'
    cached = list((GRADLE / group / name / version).glob(f'*/{filename}'))
    if cached:
        return cached[0]
    local = CACHE / filename
    if not local.exists():
        url = f'https://repo.maven.apache.org/maven2/{group.replace(".", "/")}/{name}/{version}/{filename}'
        urllib.request.urlretrieve(url, local)
    return local


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'LimenKitTests/Fixtures/Compatibility')
    parser.add_argument('--verify-swift', type=Path)
    args = parser.parse_args()
    jars = [artifact(*a) for a in ARTIFACTS]
    classpath = os.pathsep.join(map(str, jars))
    plugin = jars[7]
    data = ANDROID / 'app/src/main/java/dev/peringer/limen/data'
    sources = [data / (name + '.kt') for name in ['Templates', 'SwissIdentity', 'Protocol', 'RecordDetails', 'LegalOverlay', 'LegalProfile', 'ProtocolIntegrity', 'Store', 'Archive', 'ArchiveCrypto']]
    classes = CACHE / 'classes'
    classes.mkdir(exist_ok=True)
    subprocess.run(['java', '-cp', classpath, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                    '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', classpath,
                    f'-Xplugin={plugin}', '-d', str(classes), *map(str, sources),
                    str(ROOT / 'tools/fixtures/Compatibility.kt')], check=True)
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ['android-store', 'verified-swift.zip', 'verified-swift.limen']:
        generated = args.output / name
        if generated.exists():
            shutil.rmtree(generated)
    command = ['java', '-cp', str(classes) + os.pathsep + classpath, 'CompatibilityKt', str(args.output)]
    if args.verify_swift:
        command += [str(args.verify_swift)]
    subprocess.run(command, check=True)
    for name in ['android-store', 'verified-swift.zip', 'verified-swift.limen']:
        generated = args.output / name
        if generated.exists():
            shutil.rmtree(generated)
    source_hash = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ANDROID, text=True).strip()
    manifest = {'android_reference': source_hash, 'kotlin': '2.3.20', 'serialization': '1.8.1',
                'sha256': {str(p.relative_to(args.output)): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in sorted(args.output.glob('*')) if p.is_file() and p.name != 'reference.json'}}
    (args.output / 'reference.json').write_text(json.dumps(manifest, indent=2) + '\n')

if __name__ == '__main__':
    main()
