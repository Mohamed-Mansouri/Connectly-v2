# People: search, connections and proximity

The People bottom tab replaces Nearby and the Feed toolbar's People button. It
opens in Map mode with a 1 km radius once the signed-in account has a saved pin.
`presentation/people_screen.dart` combines name search, Discover/Friends/Friend
requests/Following filters, list/map modes and connection controls. Follow is
one-way; requests need acceptance by the recipient. Connections delegate to
the existing FeedRepository mutations so feed and chat contacts stay consistent.

`data/people_repository.dart` reads local accounts and optional visible pins in
one SQLite snapshot. Search uses bound arguments and literal substring matching.
Radius filters exclude missing/hidden pins, sort nearest first and use Haversine
distance from the signed-in account's saved location. Any distance lists accounts
even without pins. There is no 50-person truncation before distance filtering.

`presentation/location_sheet.dart` places pins manually or requests a single
foreground location fix. Save commits the position and visibility; cancel does
not write. Hide retains the owner's distance origin; Remove deletes their row.
Permission/location failures allow manual placement in this separate setup
sheet; tapping empty space on the discovery map does not create a pin. No
background tracking or cross-phone discovery is implemented. Startup adds six
fictional, loginable Demo accounts near Ariana center and ESPRIT Charguia. The
seed is repeatable and leaves existing pins and friendships alone.

`presentation/ariana_map.dart` renders simplified real Ariana city geometry
bundled in `assets/maps/ariana.json`, with no runtime HTTP/tile requests. Coverage
is 36.84–36.90°N, 10.15–10.21°E. Map markers represent accounts on this phone;
select one to reveal follow/friend controls. Data © OpenStreetMap contributors,
ODbL 1.0; see the on-map credits and `assets/maps/README.md`.
Previously saved pins outside Ariana remain in SQLite and can be repositioned.

Database version 2 adds `user_locations` (account FK with cascade, valid lat/lon,
visibility and update timestamp) without replacing version 1 records. Location
data is stored in SQLite, not Hive. Tests cover the upgrade, literal search,
relationship filters, distance boundaries, hidden pins, offline map selection,
GPS failure/manual fallback, guest view and narrow layouts.
