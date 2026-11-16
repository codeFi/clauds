<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Clauds icon">
</p>

<h1 align="center">Clauds</h1>

<p align="center">
  A macOS menu bar app that switches the Claude desktop app between accounts.<br>
  Every account stays signed in.
</p>

<p align="center">
  <a href="https://github.com/codeFi/clauds/actions/workflows/build.yml"><img src="https://github.com/codeFi/clauds/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black.svg" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-5.10-orange.svg" alt="Swift 5.10">
</p>

<p align="center">
  <img src="docs/images/demo.gif" width="450" alt="A short tour of the Clauds panel">
</p>

> [!IMPORTANT]
> Clauds is an independent project. It is not made, endorsed, or supported by Anthropic.
> "Claude" is a trademark of Anthropic, PBC.

## Contents

- [Why](#why)
- [Features](#features)
- [Screenshots](#screenshots)
- [Requirements](#requirements)
- [Install](#install)
- [First use](#first-use)
- [How to use it](#how-to-use-it)
- [Privacy and security](#privacy-and-security)
- [Limits](#limits)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [How it works](#how-it-works)
- [Development](#development)
- [Contributing](#contributing)
- [Other systems](#other-systems)
- [License](#license)

## Why

The Claude desktop app holds one login at a time. If you have a work account and a personal
account, you must sign out and sign in again each time, and you wait for an email code each time.

Clauds keeps one Claude data folder for each account. A switch takes one click. No account
is signed out.

## Features

- **One-click switch.** Click an account in the menu bar. Claude opens again with that account.
- **Side by Side.** Run one Claude copy for each account, all at the same time. No restart.
- **Shared Code sessions.** Continue the same Code session from a different account. There are no
  copies: all accounts use the same session files.
- **Session owners.** The app records which account made each session. In Side by Side, each
  account sees only its own sessions (unless you turn on sharing there, which is risky).
- **Auto-switch near a limit.** When the current account is at 90% of a limit, the app goes to the
  account with the most room. It asks first, or switches by itself. Off by default.
- **Live usage.** See the 5-hour limit, the weekly limit, and the weekly per-model limit for each
  account, each with its reset time.
- **Chat windows.** Open claude.ai for any account in its own window, with its own login.
- **Start at Login.**
- **Self-update.** The app tells you when a new version is ready, shows what is new, and installs
  it when you say so. Each update has a signature that the app checks.
- **Local only.** No server, no analytics, no telemetry. The app does not read your tokens,
  cookies, or passwords.
- **Small.** One Swift package. One dependency (Sparkle, for the updates).

## Screenshots

| Restart mode | Side by Side |
| --- | --- |
| <img src="docs/images/panel-dark.png" width="380" alt="The panel in dark mode: one current account and two saved accounts"> | <img src="docs/images/side-by-side-dark.png" width="380" alt="The panel in dark mode with Side by Side on: two open accounts"> |
| <img src="docs/images/panel-light.png" width="380" alt="The panel in light mode"> | <img src="docs/images/side-by-side-light.png" width="380" alt="The panel in light mode with Side by Side on"> |

The pictures use fake accounts. The app makes them itself with `--render-demo`.

## Requirements

- macOS 14 (Sonoma) or later
- The [Claude desktop app](https://claude.ai/download)
- Only if you build the app yourself: Xcode 15.3 or later, or the Swift 5.10 toolchain

## Install

There are two ways. Use only one.

### Way 1: download the app

1. Download `Clauds-1.0.0.dmg` from the
   [latest release](https://github.com/codeFi/clauds/releases/latest).
2. Open the file. Drag **Clauds** to the **Applications** folder.
3. Open **Clauds** from Applications.
4. macOS blocks the first start. Permit the app one time, as the next part shows.

The download works on Apple silicon Macs and on Intel Macs.

#### The app is not notarized

> [!WARNING]
> The download is **not notarized by Apple**. macOS says that it cannot check the app for
> malicious software, and does not open it at the first start. This is expected.

"Notarized" means that the developer has a paid Apple Developer account, and that Apple scanned the
app. This is a free project without such an account. The app has only an ad-hoc signature (a
signature with no identity).

What this means for you:

- macOS cannot tell you who made the app. You must decide if you trust it.
- The full source code is in this repository. You can read it, and you can build the app yourself
  (Way 2). The result is the same app.
- Each release lists the SHA-256 checksum of the file. Compare it to make sure that the download is
  the file that was published:
  `shasum -a 256 ~/Downloads/Clauds-1.0.0.dmg`

To permit the app, one time:

1. Open the app. A warning shows. Click **Done**. Do not click **Move to Trash**.
2. Open **System Settings > Privacy & Security**.
3. Go down to **Security**. Next to "Clauds was blocked", click **Open Anyway**.
4. Click **Open Anyway** again, and type your Mac password.

Or do it in Terminal, one time:

```bash
xattr -dr com.apple.quarantine "/Applications/Clauds.app"
```

This command removes the "downloaded from the internet" mark from the app. Use it only for an app
that you trust.

### Way 2: build the app yourself

This takes about one minute. macOS shows no warning, because the app is made on your Mac.

```bash
git clone https://github.com/codeFi/clauds.git
cd clauds
./build.sh --install
open "/Applications/Clauds.app"
```

`./build.sh --install` builds the app, gives it an ad-hoc signature, and copies it to
`/Applications`. Without `--install`, the app is only in `build/Clauds.app`.

### Updates

The app updates itself.

- At its second start, the app asks if it can look for updates automatically. If you say yes, it
  looks one time each day.
- When a new version is ready, a window shows the release notes and three buttons:
  **Skip This Version**, **Remind Me Later**, and **Install Update**. Nothing installs without your click.
- To look now: **… > Check for Updates…**. To turn the automatic check off:
  **… > Check for Updates Automatically**.
- An update keeps your accounts and logins.
- After an update, macOS does not show the "not notarized" warning again.

How it stays safe: each update file has a signature made with a secret key that only the
maintainer has. The app checks the signature and refuses a file that does not match. See
[docs/RELEASING.md](docs/RELEASING.md).

#### If you used "Claude Switcher"

Clauds had the name "Claude Switcher" before. That app cannot update itself to Clauds.

1. Quit Claude Switcher and move `/Applications/Claude Switcher.app` to the Trash.
2. Install Clauds.
3. Quit Claude, then start Clauds one time. It moves your saved accounts from
   `~/Library/Application Support/ClaudeSwitcher` to `~/Library/Application Support/Clauds`.
   While Claude is open, Clauds uses the old folder and moves nothing.
4. Sign in for live usage again: open the … menu of each account, then **Sign In for Live Usage…**.

If you built the app yourself and want to stay on your own build, turn the automatic check off.
An update replaces your build with the release build.

## First use

1. Open the Claude desktop app and sign in to your first account, as usual.
2. Open Clauds. At the first start, it asks if it can start at login. Choose what you want.
   Then click the Clauds icon in the menu bar.
3. Click **Save Current Claude Login as Account…** and give it a name. No files move.
4. Click **Add Account** and give the second account a name.
5. A sign-in window opens. Sign in to the second account there. This login is for the live usage
   numbers and the chat window. The window closes by itself when the login is good.
6. Claude opens for the new account. Sign in there too. This login is for the Claude app.

You do steps 5 and 6 one time for each account. After that, both logins stay.

> [!NOTE]
> Why two sign-ins? The Claude app keeps its login in its own encrypted store. Clauds does
> not read that store. So the Claude app and the Clauds web views each need a login.

## How to use it

### Switch accounts (restart mode)

Click an account. Claude quits, and opens again with that account. This takes some seconds.

Running Code sessions stop when Claude quits. Finish or pause your work first.

### Side by Side

Turn on **Side by Side (no restart)**.

- Each account gets its own Claude copy. All copies can be open at the same time.
- A click on an account brings its copy to the front, or starts it.
- A green dot shows which accounts have a copy open.
- Each account sees only the Code sessions that it owns.

When you turn this switch on or off, all Claude copies quit one time.

### Share Code sessions

Turn on **Share Code Sessions**.

- All accounts in the same organization see the same Code sessions.
- You can start a session with one account and continue it with a different account.
- For a new account: sign in, then use **… > Share Code Sessions Now (Restarts Claude)** one time.

#### Share Code sessions in Side by Side (risky)

In Side by Side, this switch is off by default. You can turn it on. The app shows a warning first.

With this on, all open Claude copies write the same session files. This can go wrong:

- If the same session is open in two accounts, it can lose messages, split in two, or go back to
  an old state.
- A session that you archive or rename in one copy can come back or change in a different copy.
- A new session can stay hidden in the other copies until they restart.
- The app cannot know which account made a new session. It gives new sessions to the main account.

Rule to stay safe: work on one session in one account at a time.

The conversation text of each session is in `~/.claude/projects`. The app does not change those files.

### Auto-switch near a limit

Open **… > Auto-Switch Near a Limit**. This works in restart mode only (Side by Side off).

| Choice | What the app does |
| --- | --- |
| **Off** | Nothing. This is the default. |
| **Ask Me First** | Shows a question. You click **Switch** or **Cancel**. |
| **Switch Automatically** | Switches without a question. |

The rules:

- The current account must be at 90% or more of one limit (5-hour, weekly, or weekly per-model).
- A different account must be at 80% or less on all its limits. The app picks the one with the most room.
- The app uses only live numbers that are less than 15 minutes old. So the other accounts must be
  signed in for live usage.
- The app waits 20 minutes between two questions or two switches.
- Claude must be open. The app does not start Claude for an auto-switch.

A switch quits Claude. Running Code sessions in the app stop. With **Switch Automatically**, this
can happen in the middle of your work. Use **Ask Me First** if that is a problem.

### Usage numbers

Each account card shows three limits:

| Label | Limit | Reset text |
| --- | --- | --- |
| `5h` | The 5-hour limit | Time left, for example `1h 03m left` |
| `Week` | The weekly limit for all models | Day and time, for example `Thu 14:00` |
| `<Model> wk` | The weekly limit for one model | Day and time |

- Green is below 60%. Orange is 60% to 84%. Red is 85% or more.
- Put the pointer on a limit to see its full name and its exact reset time.
- The numbers refresh every 2 minutes.
- If an account is not signed in for live usage, the card says so. Use **… > Sign In for Live Usage…**
  on that account.

### The account menu (… on a card)

| Item | What it does |
| --- | --- |
| Sign In for Live Usage… | Opens the sign-in window. Shown only when the login is missing. |
| Open Chats in Window | Opens claude.ai for this account in its own window. |
| New Chat in Window | Opens a new chat for this account. |
| Rename… / Set Email… | Changes the text on the card. The email is only a label. |
| Move Up / Move Down | Changes the order. |
| Remove… | Moves the account's Claude data to the Trash. Its sessions go to the shared pool first. |

### The app menu (… at the bottom)

| Item | What it does |
| --- | --- |
| Share Code Sessions Now (Restarts Claude) | Links the session folders now. |
| Check for Updates… | Looks for a new version now, and shows the result. |
| Check for Updates Automatically | On: the app looks one time each day. |
| Start at Login | Starts Clauds when you log in to the Mac. The app asks one time, at the first start. It does not turn this on without your yes. |
| Show Saved Accounts in Finder | Opens the folder with the saved account data. |
| Open Claude | Opens the Claude app. |
| About Clauds | Shows the version, the license, and the project link. |
| Quit Clauds | Quits the menu bar app. Claude stays open. |

## Privacy and security

- **Everything stays on your Mac.** There is no server, no account, no analytics, and no telemetry.
- **Two network uses.** The app contacts `claude.ai`, through the macOS web view, for the chat
  windows and the live usage numbers. And it contacts GitHub (`raw.githubusercontent.com` and
  `github.com`) to look for updates and to download them. The update check sends no data about
  you or your accounts. You can turn it off.
- **Signed updates.** The app installs an update only if its signature is valid.
- **No secrets are read.** The app moves whole Claude data folders. It does not open, copy, or store
  passwords, tokens, or cookies, and it does not read the encrypted login store of the Claude app.
- **Private files.** All files and folders that the app makes can be opened only by your macOS user.
- **Nothing is deleted.** When two versions of a session file exist, the newer one wins and the
  older one is kept in a `_conflicts` folder.
- **No sandbox.** The app must rename folders in `~/Library/Application Support`, so it cannot run
  in the App Sandbox. Read the code before you run it. It is about 2,500 lines.

To report a security problem, read [SECURITY.md](SECURITY.md).

## Limits

- **Desktop app only.** The Claude Code CLI (`~/.claude` and the Keychain) is not switched.
- **Unofficial usage numbers.** The live usage numbers come from the same address that the claude.ai
  website uses. It is not a public interface. Anthropic can change it, and then the live numbers
  stop until the app is updated. The app then shows the older numbers that Claude saves on the Mac.
- **Claude reads sessions at start.** After a layout change, a Claude copy that is open shows the
  new session list only after its next start.
- **Conversation text is shared by design.** Claude keeps the text of Code sessions in
  `~/.claude/projects` for all accounts. Do not send messages to the same session from two open
  copies at the same time.
- **Artifacts are not shared.** A published artifact belongs to one account on Anthropic's servers.
- **Delete is for all.** With shared sessions, a session that you delete is gone for all accounts.
- **Claude updates can break things.** The app depends on how the Claude desktop app stores its
  data. A Claude update can change that.
- **Your Claude plan terms apply.** Use only accounts that are yours.

## Troubleshooting

**Claude did not quit.**
Close Claude yourself (Cmd+Q in each copy), then click the account again.

**A new account shows a blank window in Side by Side.**
Quit that copy and click the account again. If it stays blank, turn Side by Side off and on.

**The card shows old numbers, or "Sign in for live usage".**
Use **… > Sign In for Live Usage…** on that account. The window closes by itself after the login.

**The session list looks wrong after a mode change.**
Quit and open that Claude copy. Claude reads the session list only at start.

**"Start at Login" does not stay on.**
Open System Settings > General > Login Items, and permit Clauds. The switch works only
for the copy in `/Applications`.

**I want to see what the app saved.**
Use **… > Show Saved Accounts in Finder**, or open `~/Library/Application Support/Clauds`.

**Something went wrong with session files.**
Stop. Do not delete anything. Older versions are in
`~/Library/Application Support/Clauds/SharedSessions/_conflicts`. Then open an issue, without
private data.

## Uninstall

Do these steps in this order. They put the session files back in the Claude folders before the app
goes away.

1. Turn off **Side by Side**.
2. Turn off **Share Code Sessions**. Each account gets its own session files back.
3. Click the account that you want to keep in the Claude app. It becomes the current account.
4. Turn off **… > Start at Login**.
5. Quit Clauds and move `/Applications/Clauds.app` to the Trash.

The folder `~/Library/Application Support/Clauds` still holds the saved data of your
other accounts, and sessions that no account owns. Make a backup of it before you delete it:

```bash
tar -czf ~/Clauds-backup.tgz -C ~/Library/"Application Support" Clauds
```

## How it works

In short: Claude keeps its login in `~/Library/Application Support/Claude`. Clauds keeps
one such folder for each account, and renames them (restart mode) or starts Claude with a different
data folder (Side by Side).

The full description, with the session layouts, the owner record, and the data safety rules, is in
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Development

```bash
./build.sh                 # build/Clauds.app
./build.sh --install       # also copy it to /Applications
./build.sh --universal     # build for Apple silicon and Intel
./build.sh --dmg           # universal build, and build/Clauds-<version>.dmg
swift build -c release     # compile only
```

- The version number is in [`VERSION`](VERSION).
- The app draws its own icon. The build also makes a layered icon from
  [`Resources/AppIcon.icon`](Resources/AppIcon.icon), so that macOS 26 and later keep the amber
  background. This step needs Xcode 26 or later. Without it, the app uses the plain icon.
- To make the README pictures again:
  `.build/release/Clauds --render-demo docs/images`
- The command line hooks for tests are in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md#command-line-hooks).

Make a backup before you test changes to the switch or the session code:

```bash
tar -czf ~/claude-backup.tgz -C ~/Library/"Application Support" Claude Clauds
```

## Contributing

Bug reports, ideas, and pull requests are welcome.

- [CONTRIBUTING.md](CONTRIBUTING.md): how to build, test safely, and send a pull request
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md): how we behave
- [SECURITY.md](SECURITY.md): how to report a security problem in private
- [SUPPORT.md](SUPPORT.md): where to ask for help
- [CHANGELOG.md](CHANGELOG.md): what changed in each version
- [docs/RELEASING.md](docs/RELEASING.md): how a release and its signed update are made

## Other systems

Clauds is for macOS only. Other people port it to other systems:

- **Linux (KDE Plasma):** [Clauds for KDE Plasma](https://github.com/MultiClauds/clauds-kde), a
  system tray app.

A port is a different project with a different maintainer. It is not tested here. Send questions and
bug reports for a port to its own repository.

## Third-party software

- [Sparkle](https://sparkle-project.org) does the self-update. It has the MIT License. Its license
  text is in the app, in `Contents/Resources/Sparkle-LICENSE.txt`.

## License

[MIT](LICENSE) © 2026 [Razvan Tanase](https://github.com/codeFi)

Clauds is not affiliated with Anthropic. "Claude" and "Anthropic" are trademarks of
Anthropic, PBC. You use this software at your own risk.
