# Working with the branches

Run these commands inside this repository. Git branches share one working folder, so switching a branch changes the files in your editor.

    git branch --list
    git switch main
    git switch auth
    git log --oneline --decorate --graph --all

The feature branches are siblings from `main`, not a chain. For example, `auth` does not contain the feed screen, and `feed` does not contain the auth screen. Every branch can launch the app: its own screen replaces one placeholder; the other three placeholders remain.

| Branch | Entry file owned by that branch | Initial screen |
| --- | --- | --- |
| `auth` | `lib/features/auth/module_entry.dart` | Profile |
| `feed` | `lib/features/feed/module_entry.dart` | Feed |
| `discovery` | `lib/features/discovery/module_entry.dart` | Nearby |
| `messaging` | `lib/features/messaging/module_entry.dart` | Chats |
| `navigation` | Shared `lib/app` navigation and navigation tests | Home and tabs |

To see only one branch's work, switch to it and run `git diff main...HEAD`. To return to the clean baseline, run `git switch main`. Do not add unfinished module work directly to `main`.

When a module is ready, review its UI, API endpoints, and tests, then merge it into `main`. For example:

    git switch main
    git merge --no-ff auth

After a merge, each remaining feature branch can merge the updated `main` before it is reviewed. The separate `module_entry.dart` files keep the first four merges independent. The `archive/sprint-0` branch is a reference to the previous combined preview; it is not part of this merge plan.
