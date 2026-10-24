#!/usr/bin/env python3
"""Validate Catalog inheritance and the readings consumed by the device host."""
from pathlib import Path
import copy
import json

root = Path(__file__).resolve().parents[1] / 'app/src/catalog/assets/scenarios'
raw = {}
for file in root.glob('*.json'):
    value = json.loads(file.read_text())
    assert value['id'] not in raw, f'Duplicate scenario: {value["id"]}'
    raw[value['id']] = value

def resolve(identifier, seen=()):
    assert identifier not in seen, f'Inheritance cycle: {identifier}'
    value = raw[identifier]
    result = copy.deepcopy(resolve(value['extends'], seen + (identifier,))) if 'extends' in value else {}
    for key, child in value.items():
        if key in ('core', 'prefs', 'snapshot') and isinstance(child, dict):
            result.setdefault(key, {}).update(child)
        elif key != 'extends':
            result[key] = child
    return result

for identifier in raw:
    scenario = resolve(identifier)
    if 'page' in scenario and scenario.get('storage') is not None:
        for key in ('total_bytes', 'free_bytes'):
            assert isinstance(scenario['storage'].get(key), int), f'{identifier}: missing {key}'
print(f'Catalog fixture inheritance and storage readings: {len(raw)} passed')
