# Working with the branches

Run these commands inside this repository. Git branches share one working folder, so switching a branch changes the files in your editor.

    git branch --list
    git switch main
    git switch auth
    git log --oneline --decorate --graph --all

The feature branches were created as siblings from `main`, not a chain. Each branch owns its module entry and feature files. Authentication, feed, and messaging are integrated into `main`; merge the updated `main` into remaining feature branches to bring in login, secure sessions, posts, connections, and chats. Until then, those branches may still show earlier screens.

| Branch | Entry file owned by that branch | Initial screen |
| --- | --- | --- |
| `auth` | `lib/features/auth/module_entry.dart` and auth presentation/data files | Login at app startup; Profile in the module tabs |
| `feed` | `lib/features/feed/module_entry.dart` | Feed |
| `discovery` | `lib/features/discovery/module_entry.dart` | Nearby |
| `messaging` | `lib/features/messaging/module_entry.dart` | Chats |
| `navigation` | Shared `lib/app` navigation and navigation tests | Home and tabs |

To see a branch's changes since its common ancestor with `main`, switch to it and run `git diff main...HEAD`. After a feature is merged into `main`, that comparison no longer lists the merged feature changes. Run `git switch main` to return to the shared baseline. Do not add unfinished module work directly to `main`.

The current presentation uses SQLite on the phone through `sqflite`, with Hive for preferences/drafts. Coordinate the local schema version, repository interfaces, and Hive keys across branches. Older feature branches may retain the previous cloud implementation until they merge the updated baseline. See [UI_GUIDE.md](UI_GUIDE.md) for current storage and navigation. Review UI, local persistence, and tests before merging a feature into `main`. For example:

    git switch main
    git merge --no-ff auth

After a merge, each remaining feature branch can merge the updated `main` before it is reviewed. The separate `module_entry.dart` files keep the first four merges independent. The `archive/sprint-0` branch is a reference to the previous combined preview; it is not part of this merge plan.
