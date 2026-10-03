#!/usr/bin/env python3
"""Prepare experimental sources outside application workspaces in disposable CI checkouts."""
import json
import os
from pathlib import Path
import re
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parents[2]
PLUGINS = ('clipboard-manager', 'dialog', 'fs', 'notification', 'opener', 'barcode-scanner')


def prepare_sources(destination, pins=None):
    destination = Path(destination).resolve()
    pins = pins or json.loads((ROOT / 'shared/ohos/runtime-pins.json').read_text())
    sources = {}
    for name, pin in pins.items():
        checkout = destination / name
        if checkout.exists():
            raise ValueError(f'Use a fresh external source directory: {checkout}')
        subprocess.run(['git', 'init', str(checkout)], check=True)
        subprocess.run(['git', '-C', str(checkout), 'fetch', '--depth', '1',
                        f"https://github.com/{pin['repository']}.git", pin['revision']], check=True)
        subprocess.run(['git', '-C', str(checkout), 'checkout', '--detach', 'FETCH_HEAD'], check=True)
        sources[name] = checkout
    core = sources['tauri']
    ability = sources['ability']
    # One source checkout supplies both the Rust Ability and its packaged ArkTS HAR.
    for name in ('tauri', 'wry', 'tao'):
        for manifest in sources[name].rglob('Cargo.toml'):
            lines = []
            for line in manifest.read_text().splitlines(True):
                for package, directory in (('openharmony-ability', 'ability'), ('openharmony-ability-derive', 'derive')):
                    if line.startswith(package + ' = ') and 'git = ' in line:
                        line = re.sub(r'git = "[^"]+"(?:, rev = "[^"]+")?',
                                      f'path = "{ability / "crates" / directory}"', line)
                lines.append(line)
            manifest.write_text(''.join(lines))
    manifest = core / 'Cargo.toml'
    text = manifest.read_text()
    for name in ('wry', 'tao'):
        text = re.sub(rf'^{name} = .*$', f'{name} = {{ path = "{sources[name]}" }}', text, flags=re.MULTILINE)
    manifest.write_text(text)
    packages = ('tauri', 'tauri-build', 'tauri-codegen', 'tauri-macros', 'tauri-plugin',
                'tauri-runtime', 'tauri-runtime-wry', 'tauri-utils')
    patches = {name: core / 'crates' / name for name in packages}
    patches.update({name: sources[name] for name in ('wry', 'tao')})
    patches['openharmony-ability'] = ability / 'crates/ability'
    patches['openharmony-ability-derive'] = ability / 'crates/derive'
    manifest = ROOT / 'Cargo.toml'
    text = manifest.read_text()
    for name in ('tauri', 'tauri-build', 'tauri-plugin', 'tauri-utils'):
        text = re.sub(rf'^{name} = .*$', f'{name} = {{ path = "{patches[name]}", default-features = false }}', text, flags=re.MULTILINE)
    manifest.write_text(text)
    for name in PLUGINS:
        patches[f'tauri-plugin-{name}'] = ROOT / 'plugins' / name
    return patches


def patch_application(workspace, host, patches):
    generated = Path(host) / 'gen'
    generated.mkdir(exist_ok=True)
    (generated / 'ohos-ability-source').write_text(str(patches['openharmony-ability'].parents[1]) + '\n')
    manifest = Path(host) / 'Cargo.toml'
    text = manifest.read_text()
    for name, path in patches.items():
        def replace_dependency(match):
            options = tomllib.loads('value = ' + match.group(1))['value']
            if isinstance(options, str):
                options = {}
            for key in ('version', 'path', 'git', 'rev', 'branch', 'tag', 'registry', 'workspace'):
                options.pop(key, None)
            options = {'path': str(path), **options}
            values = ', '.join(f'{key} = {json.dumps(value)}' for key, value in options.items())
            return name + ' = { ' + values + ' }'
        text = re.sub(rf'^{re.escape(name)} = (.*)$', replace_dependency, text, flags=re.MULTILINE)
    manifest.write_text(text)
    manifest = Path(workspace) / 'Cargo.toml'
    with manifest.open('a') as output:
        output.write('\n[patch.crates-io]\n')
        for name, path in patches.items():
            if name.startswith('openharmony-ability'):
                continue
            output.write(f'{name} = {{ path = "{path}" }}\n')


if __name__ == '__main__':
    import sys
    if len(sys.argv) != 4:
        raise SystemExit('prepare.py EXTERNAL_SOURCE_DIR WORKSPACE_DIR HOST_DIR')
    patch_application(sys.argv[2], sys.argv[3], prepare_sources(sys.argv[1]))
