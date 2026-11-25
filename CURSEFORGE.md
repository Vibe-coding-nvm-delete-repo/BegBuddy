# BegBuddy

**Scan zones and manage player conversations, with you in control of every message.**

BegBuddy runs `/who` scans in zones you choose and keeps a contact list with a conversation history for each person. You can send a whisper or, at a mailbox, a mail. BegBuddy never sends anything on its own.

## Features

- **Zone scans**, run one `/who` slice at a time across the zones you tick. Add a zone while standing in it.
- **Contact pipeline**, move people through Queued, Contacted, Replied, Funded and Archived as conversations progress.
- **Message history**, keep a full history for each person, with timestamps.
- **Whispers you approve**, send one at a time with a click. With One-click send off, load the message into chat and press Enter.
- **Mail at a mailbox**, use separate subject and body templates to mail the next queued person or a selected contact.
- **Message templates**, use `{name}` and `{level}` in whisper and mail text.
- **Scan controls**, set a level range and slice size, and see scan progress.
- **Settings**, manage whispers, mail, scans, zones and data in Zip settings.

## Commands

| Command | Effect |
|---|---|
| `/beg` | Open or close BegBuddy |
| `/beg scan` | Run the next `/who` slice |
| `/beg addzone` | Add and tick the zone you are standing in |
| `/beg nextzone` | Move to the next ticked zone |
| `/beg mail` | At an open mailbox, mail the top person in Queued |
| `/beg reset` | Restart the slice plan for the zone being scanned |
| `/beg settings` | Open settings |
| `/beg probe` | Print which APIs exist on your client |
| `/beg pause` | Stop sending |
| `/beg resume` | Allow sending |
| `/beg save` | Ask the client to write SavedVariables |
| `/beg template` | Reset the message to the default |
| `/beg template <text>` | Set the message directly |
| `/beg dumpwho` | Dump raw Who fields for entry 1 |
| `/beg export` | Show every contact in a copyable window |
| `/beg clear` | Move everyone in Queued to Archived |
| `/beg wipe confirm` | Delete all data |

## Part of the Zip addons

BegBuddy is one of the Zip addons. Open its settings at Esc > Options > AddOns > Zip. Each Zip addon has its own tab, with pages, Profiles and shared Window controls for locking, sizing and resetting position. BegBuddy works on its own; it does not need another Zip addon.

Use `/beg open`, `/beg settings`, `/beg lock`, `/beg unlock`, `/beg reset`, `/beg scale`, `/beg minimap`, `/beg profile`, `/beg list` or `/beg help` for shared Zip commands. The Zip minimap button opens an addon with a left click, opens settings with a right click, and can be dragged to move. Use `minimap` to hide or show it.

Profiles save BegBuddy settings under a name, load them on any character, or reset them to defaults. Profiles do not change records, history or contacts. Shared settings words are machine translated into German, French, Spanish, Russian, Portuguese, Italian, Korean and Chinese. Addon text is English.

BegBuddy is for WoW Classic Era, Hardcore and WoW Forever. It uses no libraries.
