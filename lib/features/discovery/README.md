# Discovery module

This branch owns the Nearby tab. `module_entry.dart` connects the navigation shell to `presentation/nearby_screen.dart`. The screen is an empty starting view; the map, user cards, location permission, and API calls are still to be built.

Planned endpoints: `PUT /me/location` and `GET /users/nearby`. The advanced demonstration shows matches appearing and disappearing as two test locations cross a radius boundary. The supplied Nearby mockup remains on `archive/sprint-0` at `design/reference/nearby.png`.
