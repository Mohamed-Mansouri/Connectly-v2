# Nearby People for the Ariana presentation

## Summary

Make **Find your people** open on the map and show location-sharing accounts within 1 km of your saved location. Keep the demo offline and on one phone. The discovery map will select existing people’s markers; your own location can still be set in the separate location setup sheet.

## Implementation changes

- Use the existing `visible` location setting as the opt-in rule. Default to a 1 km radius when your saved location exists, sort nearby results by distance, and keep the current radius choices and List view. Without a saved location, show the available shared markers with a prompt to set yours; do not label them “nearby.”
- Open the People screen in Map view. Tapping a marker selects that person and shows the existing Follow and Add friend actions. Tapping empty space on the discovery map does nothing.
- At startup, add six clearly labeled, loginable **Demo** accounts: three with distinct pins around the existing Ariana center and three around ESPRIT’s evening campus at approximately **36.8533, 10.2072**. Use stable IDs, save their locations as visible, and make seeding repeatable without resetting existing accounts, locations, or friendships. The campus is at [18 Rue de l’Usine, Charguia 2](https://fr.linkedin.com/posts/esprit_2_ouverture-des-inscriptions-pour-les-cours-activity-7221099175097098243-u9QX); the [mapped coordinates](https://tn.near-place.com/esprit-night-schools-18-rue-de-lusine-tunis/en) fall within the bundled map.
- Start demo profiles as discoverable people, with no friendship to the signed-in account. Document their local login credentials so you can switch accounts and accept a request sent from the map. Update the README’s current “starts empty” instructions to describe the automatic demo data.

## Test plan

- Verify both pin clusters appear within 1 km when your saved location is near the corresponding area, and hidden or unlocated accounts never appear as map markers.
- Verify marker selection exposes friend actions, empty-map taps create no pin, and a request can be accepted after signing in as a demo account.
- Verify seeding runs again without duplicates or changes to existing user data. Run Flutter tests and analysis, then install and check the map on the paired phone.

## Assumptions

Demo profiles are fictional and visibly labeled. They represent accounts on this phone; discovering people on separate phones would require a later shared service.
