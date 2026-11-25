# How Clauds works

This page is for people who want to know what the app does to the files on the Mac, and for
contributors.

## Folders

| Path | What is in it |
| --- | --- |
| `~/Library/Application Support/Claude` | The data folder of the Claude desktop app. It holds the login of the main account. |
| `~/Library/Application Support/Clauds/accounts.json` | The account list, the active account, and the two switches. |
| `~/Library/Application Support/Clauds/Profiles/<id>` | The Claude data folder of each account that is not the main one. |
| `~/Library/Application Support/Clauds/SharedSessions/orgs` | The pool of shared Code session files. |
| `~/Library/Application Support/Clauds/SharedSessions/owners.json` | Which account made each Code session. |
| `~/Library/Application Support/Clauds/SharedSessions/_conflicts` | Older versions of files that lost a "newer wins" decision. Nothing is deleted. |
| `~/Library/Application Support/Clauds/usage-debug.json` | The last raw usage answers, for problem finding. |
| `~/Library/Application Support/Clauds/quit-debug.json` | How long the last quit of Claude took, for problem finding. Numbers only. |
| `~/.claude/projects` | The conversation text of Code sessions. Claude owns this folder. All accounts use it. |

## The two ways to switch

### Restart mode (Side by Side off)

1. The app asks Claude to quit and waits for its helper processes.
2. It renames `Claude` to `Profiles/<old account>`.
3. It renames `Profiles/<new account>` to `Claude`.
4. It opens Claude again.

A rename on the same disk is immediate and moves no data. If a step fails, the app renames the
folders back.

### Side by Side mode

- The main account uses the normal folder.
- Each other account runs a second copy of Claude with `--user-data-dir=<Profiles/id>`.
- A click on an account brings its copy to the front, or starts it.
- The app finds which copy belongs to which account from the command line of the process.

## Code sessions

Claude keeps the metadata of each Code session in
`<data folder>/claude-code-sessions/<Claude account id>/<organization id>/local_<id>.json`.

### Shared layout (Share Code Sessions on)

- `claude-code-sessions/<Claude account id>` is a symlink to `SharedSessions/orgs`.
- All accounts in the same organization see the same session files. There are no copies.
- The symlink must be at the account level. Claude opens the organization folder in a way that
  refuses a symlink there, and saves fail with `ENOTDIR`.

### Separate layout (Share Code Sessions off, and the default in Side by Side)

- Each account has a real `claude-code-sessions/<Claude account id>` folder.
- That folder holds only the sessions that the account owns. Forks that the account made are its own.
- Sessions of other accounts stay in the pool.

Why: two open Claude copies that write the same session file make a session split, or make it go
back to an old state. So Side by Side does not share session files by default.

The user can turn on sharing in Side by Side (`shareInSideBySide` in `AccountStore.swift`). The
panel shows a warning first. In that state the app cannot know which open copy made a new session,
so the next layout change gives new sessions to the main account.

### Owner record

`owners.json` maps each session id to its owner.

- The owner is a Claude account id, or a tag `switcher:<id>` for a session that was made while the
  files were shared.
- `@account-of:<tag>` maps a tag to the Claude account that was signed in.
- A session with no record gets the account whose folder it was made in.

### Archive list

Each session folder has `archived-sessions.idx`. On each layout change, the app builds this file
again from the `isArchived` mark in each session file of that folder.

## Data safety rules

1. **One live file for each session.** Session files move between the pool and the owner's folder.
   They are not copied.
2. **Nothing is deleted.** Same name, different content: the newer file wins, and the older one goes
   to `SharedSessions/_conflicts/<label>/<time>_<name>`.
3. **A folder is removed only when it is empty.**
4. **If `owners.json` cannot be read, every session operation stops.** The last good version is
   `owners.json.bak`.
5. **One session operation at a time.** A lock guards them. Only one Clauds can run.
6. **A symlink that this app did not make is not touched.**
7. **Remove account:** its sessions go to the pool first. Then its Claude data goes to the Trash.
8. **Private files.** `umask 077`; folders are `700`, files are `600`.

## Usage numbers

Two sources:

- **Local.** Claude writes `<data folder>/plan-usage-history.json`. It has percent numbers only
  (5-hour and weekly), no reset times, and Claude does not update it often.
- **Live.** A hidden web view for each account loads a small page on `claude.ai`, then asks
  `/api/organizations/<organization>/usage`, as the website does. The answer has each limit with its
  percent and reset time. The app asks every 2 minutes.

The web view of an account uses a separate website data store (`WKWebsiteDataStore(forIdentifier:)`).
The chat window of that account uses the same store. That is why one sign-in in the window is
enough for the live numbers.

The live source is **not an official interface**. Anthropic can change it at any time. When it
fails, the panel shows the local numbers.

The Claude app and the web views keep separate logins. The app does not take the login out of the
Claude app. That is why a new account needs two sign-ins.

## The panel

`PanelController` makes a menu bar item and a borderless, clear window. `PanelChrome` draws the
round panel. macOS makes the shadow from that shape.

## Source files

| File | Job |
| --- | --- |
| `App.swift` | Start, command line hooks, the panel content, the actions, the About window. |
| `PanelController.swift` | The menu bar icon and the panel window. |
| `PanelParts.swift` | The views in the panel, and the `Usage` model. |
| `AccountStore.swift` | The account list, the switch, Side by Side, usage refresh. |
| `AutoSwitch.swift` | The auto-switch rules: when to go to a different account, and to which one. |
| `SessionLinker.swift` | The session layouts, the owner record, the archive list. |
| `LiveUsage.swift` | Live usage from claude.ai. |
| `ChatWindows.swift` | One claude.ai window for each account, and the sign-in flow. |
| `IconArt.swift` | The menu bar icon and the app icon, drawn in code. |
| `Updates.swift` | Self-update with Sparkle. See [RELEASING.md](RELEASING.md). |
| `Demo.swift` | The README pictures, with fake accounts. |

## Command line hooks

Run the binary inside the app: `"Clauds.app/Contents/MacOS/Clauds" <hook>`.

| Hook | What it does |
| --- | --- |
| `--render-demo <dir>` | Writes the README pictures and the GIF, with fake accounts. |
| `--render-panel <png>` | Draws the panel with your real accounts. Do not share this picture. |
| `--render-icons <dir>` | Writes the icons (the build uses this). |
| `--login-item [on\|off]` | Prints, or sets, the Start at Login state. |
| `--show-panel` | Asks the running app to open its panel. |
| `--link-sessions <data dir> <shared dir> [tag]` | Applies the shared layout to a data folder. |
| `--unlink-sessions <data dir> <shared dir> [tag]` | Applies the separate layout to a data folder. |
