"""Build a simplified ODbL Ariana city map; no runtime network access.

Run python tool/download_ariana_map.py to refresh from OpenStreetMap, or pass
--source path/to/extract.osm to regenerate from an existing OSM XML extract.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path)
args = parser.parse_args()
bounds = [36.84, 10.15, 36.90, 10.21]  # south, west, north, east
south, west, north, east = bounds
url = f'https://api.openstreetmap.org/api/0.6/map?bbox={west},{south},{east},{north}'
if args.source:
    source = args.source.read_bytes()
elif sys.platform == 'win32':
    # Schannel uses Windows' trusted certificate store, including managed proxies.
    source = subprocess.check_output(['curl.exe', '--fail', '--silent', '--show-error',
        '--max-time', '45', '--user-agent', 'Connectly-university-offline-map/1.0', url])
else:
    with urllib.request.urlopen(urllib.request.Request(url, headers={
            'User-Agent': 'Connectly-university-offline-map/1.0'}), timeout=45) as response:
        source = response.read()
root = ET.fromstring(source)
source_bounds = root.find('bounds')
if source_bounds is None or [float(source_bounds.attrib[key]) for key in
        ('minlat', 'minlon', 'maxlat', 'maxlon')] != bounds:
    raise ValueError('The source extract must match the configured Ariana bounds.')
nodes = {n.attrib['id']: [round(float(n.attrib['lat']), 5), round(float(n.attrib['lon']), 5)]
         for n in root.findall('node')}
roads = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'residential',
         'unclassified', 'living_street', 'pedestrian'}
features = []
for way in root.findall('way'):
    tags = {t.attrib['k']: t.attrib['v'] for t in way.findall('tag')}
    kind = tags.get('highway')
    if kind not in roads:
        kind = ('water' if tags.get('natural') == 'water' else
                'park' if tags.get('leisure') == 'park' else None)
    if kind is None:
        continue
    points = [nodes[n.attrib['ref']] for n in way.findall('nd') if n.attrib['ref'] in nodes]
    if len(points) >= 2:
        features.append({'kind': kind, 'points': points})
result = {
    'bounds': bounds,
    'source': 'OpenStreetMap contributors, https://www.openstreetmap.org/copyright',
    'sourceUrl': url,
    'license': 'ODbL 1.0, https://opendatacommons.org/licenses/odbl/1-0/',
    'features': features,
}
target = Path(__file__).resolve().parents[1] / 'assets/maps/ariana.json'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(result, separators=(',', ':')), encoding='utf-8')
print(f'Saved {len(features)} map features ({target.stat().st_size} bytes)')
