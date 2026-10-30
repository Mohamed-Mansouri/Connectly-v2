# Bundled Ariana map

The simplified map contains real OpenStreetMap street and area geometry.
Data © OpenStreetMap contributors, licensed under the Open Database License
(ODbL) 1.0: https://opendatacommons.org/licenses/odbl/1-0/.
Attribution: https://www.openstreetmap.org/copyright.

The derived geometry database is `ariana.json`, distributed under ODbL 1.0.
Coverage: **Ariana city**, 36.84–36.90°N and 10.15–10.21°E. It is a simplified
street map, not a full map of the governorate. Generate it with
`python tool/download_ariana_map.py` (network needed only when regenerating).
The app displays attribution on the map and a credits dialog. No tiles or map
data are downloaded at runtime. App user pins are separate SQLite records.
