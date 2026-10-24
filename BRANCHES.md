# Working with the branches

Run these commands inside this repository. Git branches share one working folder, so switching a branch changes the files in your editor.

    git branch --list
    git switch main
    git switch auth
    git log --oneline --decorate --graph --all

The feature branches were created as siblings from `main`, not a chain. Each branch owns its module entry and feature files. After authentication is merged into `main`, merge the updated `main` into the remaining feature branches to bring in the shared login, session handling, and Profile. Until then, those branches may still show the original Home and placeholders.

| Branch | Entry file owned by that branch | Initial screen |
| --- | --- | --- |
| `auth` | `lib/features/auth/module_entry.dart` and auth presentation/data files | Login at app startup; Profile in the module tabs |
| `feed` | `lib/features/feed/module_entry.dart` | Feed |
| `discovery` | `lib/features/discovery/module_entry.dart` | Nearby |
| `messaging` | `lib/features/messaging/module_entry.dart` | Chats |
| `navigation` | Shared `lib/app` navigation and navigation tests | Home and tabs |

To see a branch's changes since its common ancestor with `main`, switch to it and run `git diff main...HEAD`. After a feature is merged into `main`, that comparison no longer lists the merged feature changes. Run `git switch main` to return to the shared baseline. Do not add unfinished module work directly to `main`.

Use Hive for local preferences/caches and Turso through a backend for shared data. Coordinate cloud schema migrations, repository contracts, and Hive keys across branches. The `auth` branch changes the shared entry to restore a session or display Login, then enter the module tabs directly; it removes Home. Review that integration with navigation work and use [UI_GUIDE.md](UI_GUIDE.md) for the account and cache contracts. When a module is ready, review its UI, repository behavior, persistence, and tests, then merge it into `main`. For example:

    git switch main
    git merge --no-ff auth

After a merge, each remaining feature branch can merge the updated `main` before it is reviewed. The separate `module_entry.dart` files keep the first four merges independent. The `archive/sprint-0` branch is a reference to the previous combined preview; it is not part of this merge plan.
