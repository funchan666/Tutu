"""Normalize supplied media to CDN references without copying or downloading binaries.

ContentMapping retains original filenames and SHA256 provenance after local removal.
EditorialCatalog is the maintained source of identities and authored content; this
script preserves all records and only replaces known legacy media references.
"""
from pathlib import Path
from urllib.parse import quote
import json

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://pub-1e78b29dc9034ab296832bae0193b76c.r2.dev/'
mapping_path = ROOT / 'Docs/ContentMapping.json'
mapping = json.loads(mapping_path.read_text())
aliases = {}
for row in mapping:
    source = Path(row['source'])
    folder = {'picss': 'pics', 'videoss': 'videoss'}[source.parts[0]]
    url = BASE + folder + '/' + quote(source.name)
    row['remoteURL'] = url
    row['storage'] = 'remote'
    aliases['bundle/' + row['resource']] = url
assert len(aliases) == len(mapping), 'Duplicate legacy media references'

def normalize(value):
    if isinstance(value, str):
        return aliases.get(value, value)
    if isinstance(value, list):
        return [normalize(item) for item in value]
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in value.items()}
    return value

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

for relative in [
    'Docs/BackendAPI/sources/EditorialCatalog.json',
    'Docs/HomeRoomMapping.json',
    'Docs/VoiceRoomMapping.json',
    'Docs/RoomHostCards.json',
    'Scripts/discover_content.json',
]:
    path = ROOT / relative
    save(path, normalize(json.loads(path.read_text())))
save(mapping_path, mapping)
save(ROOT / 'Tutu/Resources/Content/EditorialMediaAliases.json', aliases)
print(f'Normalized {len(aliases)} remote media references; no binaries copied or downloaded.')
