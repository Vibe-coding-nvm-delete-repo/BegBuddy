# BegBuddy

An assisted `/who` scanner and outreach CRM for **WoW Classic Hardcore** (Classic Era client, interface `11509`)
and **World of Warcraft: Forever** (beta, interface `16001`). One copy of the folder works on both.

It scans any zones you tick, keeps a de-duplicated contact list, moves people through a pipeline
as the conversation progresses, and stores the full message history per person. At a mailbox it
sends a mail instead of a whisper, from its own mail template, so it can reach people anywhere.

**It never sends anything on its own.** By default a click loads the whisper into your chat box and you
press Enter. With One-click send turned on in Settings, one click sends one whisper or one mail to one
person. Nothing is recorded as "contacted" until the client confirms the whisper went out.

---

## Install

Source lives in `C:\Users\chris\dev\repos\BegBuddy\BegBuddy`. Copy that folder into each client's AddOns folder:

| Game | AddOns folder |
|---|---|
| Hardcore (Classic Era) | `World of Warcraft\_classic_era_\Interface\AddOns\BegBuddy\` |
| Forever beta | `World of Warcraft\_classic_beta_\Interface\AddOns\BegBuddy\` |

```powershell
$src = "C:\Users\chris\dev\repos\BegBuddy\BegBuddy"
foreach ($flavor in "_classic_era_", "_classic_beta_") {
  Copy-Item -Recurse -Force $src "C:\Program Files (x86)\World of Warcraft\$flavor\Interface\AddOns\"
}
```

Restart the client, or `/reload` if it was already running. Each client keeps its own saved data,
so Hardcore starts with an empty contact list.

---

## Use

| Command | Effect |
|---|---|
| `/beg` | open or close the window |
| `/beg scan` | run the next `/who` slice |
| `/beg addzone` | add (and tick) the zone you are standing in, if it is not already listed |
| `/beg nextzone` | move the scan on to the next ticked zone |
| `/beg mail` | at an open mailbox, mail the top person in Queued |
| `/beg reset` | restart the slice plan for the zone being scanned |
| `/beg settings` | open settings |
| `/beg probe` | print which APIs exist on your client |
| `/beg pause` / `/beg resume` | stop / allow sending |
| `/beg save` | ask the client to write SavedVariables |
| `/beg template` | reset the message to the default |
| `/beg template <text>` | set the message directly |
| `/beg dumpwho` | dump the raw Who fields for entry 1 |
| `/beg export` | dump every contact to a copyable window (backup) |
| `/beg clear` | move everyone in Queued to Archived (no prompt) |
| `/beg wipe confirm` | delete all data (the same as **Clear all**; your quick messages and saved profiles are kept) |

### Picking zones

The **Zones** button on the scan panel opens a list of every open-world zone, grouped and
coloured: Capital cities (gold), Starting zones (purple), Kalimdor (orange), Eastern Kingdoms (green),
Battlegrounds (red), and any you added by hand (blue). Starting zones lists the zones new characters
begin in; they also appear under their continent, and a zone ticked in both is scanned once. Tick as many as you like. Each group can be folded with **+/-**,
and has **all** / **none** buttons. Your ticks and folds are saved.

The scan works through the ticked zones in list order. When a zone's last slice is done, the next
click moves on to the next ticked zone by itself and says so in chat; **Next zone** skips ahead
early. The zone being scanned is marked `< scanning now`.

### The Stats tab

The **Stats** tab (right of Blocked, or `/beg stats`) shows what is working. At the top, pick what counts as
success: **Replied**, **Funded**, or **Gold** of at least an amount (click Gold again to step the amount). Under it
is the funnel, with how much gold and how many items came back, the average gift, gold per ask, and the median time to
a reply. Then pick a breakdown (template, class, level, zone, time of day, day, whisper or mail, ask number) and click a
heading to sort. A row marked * has fewer asks than "Trust after N asks" and sorts last when you sort by a rate.
Gold and items count when they arrive by mail (not a mail returned to you) or by trade; trade capture is untested on Forever.

### Picking a class

The class picker at the right end of the scan panel lists each class in its class colour. Tick as many
as you like; the list stays open while you tick. With classes ticked, each level band is scanned once
per ticked class (the scan adds `c-"Class"` to the `/who` query), so a band with two classes takes two
clicks. **All classes** (nothing ticked) scans everyone. Each set of ticked classes is its own scan plan,
so changing the ticks starts from the first level band, like changing the level range does. Only the
classes your faction can find are listed.

A zone missing from the list (a dungeon, say) can still be added: **Add this zone** while standing
in it, or type it under Settings > Zones & data. The `/who` zone filter needs the client's own
exact zone string, so on a non-English client use **Add this zone** rather than the built-in names.

### Settings

Six tabs:

- **Whisper** - the whisper template. **Saves as you type**, no button to press.
  `{name}` and `{level}` insert at your cursor. Live preview uses a real name from your queue.
  Undo, Trim to fit, and Reset if you change your mind. The counter tells you what the limit
  means, and warns when a message is long enough to scroll out of view.
- **Mail** - the mail templates, separate from the whisper ones: a **Subject** (64 characters) and
  a **Body** (500 characters, Enter makes a new line). Several named templates, each with its own
  sent / replied / funded results. `{name}` and `{level}` go into whichever box you clicked last.
  A preview shows the subject in gold and the body as it will arrive. **Open with mailbox** (on by
  default) opens the BegBuddy window when you open a mailbox.
- **Scan** - your level ranges and the numbers behind them.
- **Quick messages** - the one-click whispers (see below). Edit the text (saves as you type), **Hide** or
  **Show**, move with **Up** / **Down**, **Delete**, or type a new one and press Enter or **Add**. Up to 24.
  **Restore the starting list** puts the list back (asks first). This list is kept when you reset the
  settings and when you use **Clear all**.
- **Zones & data** - remove zones you added by hand, export everything, force a save.

### Setting your level range

Settings → **Scan**, two fields that matter:

- **Min level** - bottom of the range
- **Max level** - top of the range

Plus one more, **Slice size** - how many levels go into each `/who` query. The client caps results
per query, so a wide range has to be split or you silently miss people. 5 is a sensible default.

The line under the fields shows exactly what you will get:

```
6 slices to scan:  1-5, 6-10, 11-15, 16-20, 21-25, 26-30
```

...and the chip row in the main window shows the same slices as coloured chips: green done, blue
next, grey pending.

Defaults: min 1, max = the client's level cap (60 on Hardcore), slice size 5.

Changing Min, Max or Slice size starts that city's scan over on the new range. Progress is stored
against the range it was made on, so a new range never shows up as already done.

There is no separate "scan plan" to keep in sync. Min and Max are the only input, always - an
earlier version had a second ranges box, and once it had been pinned the Min/Max fields looked
dead. It is gone.

### The loop

1. Stand in a city, click **Add this zone** (or pick one from the dropdown).
2. Click **Scan next slice** (or `/beg scan`) as many times as you like. Each click runs one
   `/who` and adds only people you do not already have, so the list keeps growing past 50,
   100 and on with no ceiling. After the last band it starts a new pass by itself to catch
   people who logged in since.
3. Click **send** next to a name in **Queued**, or select it and click **Send whisper**.
   (With One-click send off, the button is **Load whisper** and you press **Enter** in chat.)
4. The card moves to **Contacted** the moment the client confirms the send.
5. If they reply, the card moves to **Replied** and gets a red `new` marker.
6. Type in the box at the bottom of the detail pane and press Enter to reply.
7. **History** opens the full conversation with timestamps in its own window.
   People in Replied or Funded also get **Invite** (party invite) and **Add friend**.
   **Leave group**, top right of the window, gets you out of the party or raid in one
   click (`/beg leave` does the same).
   Closing someone out, or sending their whisper, selects the next name in that tab.
8. **Funded** / **Archive** / **Not interested** / **Block** close it out. Declined, blocked and
   funded names are never re-queued by a later scan.

`{name}` and `{level}` in the template are swapped in at load time.

### Quick messages

A strip of buttons sits above the reply box in the detail pane. Click one and it is whispered to the
person you have open, like a reply you typed: one click, one whisper. Nothing is sent when nobody is
open, in combat, or inside the wait between sends. **Pause** does not stop it, the same as a typed reply.
`{name}` and `{level}` work in a message. The **Quick -** button beside **Send** folds the strip away
(**Quick +** opens it again).

It starts with these seven, in this order:

- Tysm!
- Tysm!!! You're the best!
- Yes please!
- I'm in front of the AH!
- I'm in front of the bank!
- I'm rich!!!
- Fuck yes tysm!

then a friendly set: Thank you so much! / Please! / Where are you? / One moment please! / On my way! /
Sorry, I can't right now. / No thanks, I'm good! / What do you need? Change any of it under Settings >
**Quick messages**.

### Clear and Clear all

Two buttons at the bottom right:

- **Clear** moves everyone in Queued to Archived (after a prompt). Nothing else changes.
- **Clear all** deletes everything BegBuddy saved: every list, history, counter and player record, the
  templates and their results, scan progress, zones and settings. **It cannot be undone**, so the first
  click only turns the button to **Click again to confirm** and the second click does it. The window
  refreshes at once. Your **quick messages**, the window's place and the saved profiles (shared by the Zip addons) are kept. Hover the button for the
  reminder. If you might want the data back, use **Export everything** first.

### Mail mode

Open any mailbox and the window switches to mail by itself (the header button says
**Sending: mail** in gold). Then:

- **Mail next (N)** (bottom right) mails the top person in Queued, one mail per click. Every
  **send** button and **Send mail** in the detail pane sends a mail too. While the server is
  confirming, the button says **Sending...**; nothing can be double-sent.
- Unlike whispers, people a check found offline are still mailed. Mail reaches them anywhere,
  online or not.
- Each mail costs postage (30 copper). The hint line shows the postage and how many more mails
  your gold covers, and how the last mail went.
- If the Send Mail tab has an item, gold or a cash-on-delivery charge in it, BegBuddy refuses to
  send, because the game would attach it to the begging mail.
- A sent mail moves the person from **Queued** to **Contacted**, so they drop off the Queued list
  and Mail next goes to the next name.
- If the recipient can never get mail (no such name, other faction, self-found, other realm),
  they are archived with "cannot be mailed" and the reason.
- If the limit is on your side (the game's cap on how many different people you can mail,
  friends-or-guild-only mail, or a self-found sender), sending pauses with the reason and the
  person stays in Queued. `/beg resume` when you are ready.
- Any other failure is logged in the history, counts towards the three-warnings pause, and the
  next click moves on to the next person.
- When you open the inbox, mail from anyone you mailed is read from the headers only (nothing is
  marked read): gold moves them to **Funded**, a plain reply to **Replied**, both with the `new`
  marker.
- Click the header button to send whispers instead while the mailbox is open. Closing and
  reopening the mailbox goes back to mail.

The idea: stand at a mailbox semi-AFK, tick a few zones, scan, and come back every 10-15 minutes to
fire off another batch with **Mail next**.

---

## First-run smoke test

Because the Forever client is in beta, verify in this order. Each step isolates one layer, so if
something fails you know exactly which API moved.

1. **`/beg`** - window opens. If not, the LUA error names the line.
2. **`/beg probe`** - should print `function` for `SendWho`, `GetWhoInfo`, `GetNumWhoResults`,
   `SendChatMessage`, `Ambiguate`, `C_Map.GetMapInfo`, `GetRealZoneText`.
   Anything printing `nil` is an API this beta moved; tell me which one.
3. **`/beg addzone`** in a city - the zone appears in the dropdown. If the dropdown looks empty,
   hit **Find cities**, or type a zone in settings.
4. **Click Scan next slice once.** Watch chat for the `Scanning ... [z-"..."]` line, then
   `Slice 1: N result(s), M new name(s)`.
   - If you get *"No response from the server"*, Who queries are throttled: wait ~10s and retry.
   - If you get *"Who query refused"*, the call was not in a hardware-event context. Use the
     button, not a macro.
5. **Send whisper** - card should jump to Contacted.
6. **Whisper yourself from another account** - card should jump to Replied with a `new` marker.

---

## Why it works the way it does

**One click = one query.** `C_FriendList.SendWho` is flagged `#hwevent` and needs a real hardware
event. That was added in patch 8.2.5 explicitly as "a measure against gold spam channel invites
and other unintended uses for automatically querying player names." There is no timer-driven
scanning here on purpose, because there cannot be.

**Who results are capped, the list is not.** The server answers one `/who` with at most 50 names,
so the scan is sliced into level bands. When a band comes back full, the next clicks run extra
scans for it: first one per level, then, for a level that is still full, one per class (skipping
the class your faction cannot see: Paladins for Horde, Shamans for Alliance). Only a single
level and class with more than 50 people online can still hide names, and the addon says when
that happens. Pending extra scans last for this session and are dropped by Reset or a range change.

**Nothing is auto-sent.** Every whisper takes one click from you, and a click inside the send gap
(`Send gap (seconds)`, default 2) is held back. Mass unsolicited whispers with nobody at the keys
are spam by Blizzard's rules and the fastest way to get silenced, so there is no send-everyone
button and there will not be one.

**Sends are guarded, not just paced.** The row whisper button only appears where sending is
actually safe: never for somebody who already replied or has been closed out, and not again for
somebody contacted inside the re-whisper cooldown (`Do not re-whisper the same person for`,
default 30 minutes). Rapid fire makes double-sends easy, and a stranger receiving the same beg
twice is the thing that gets reported.

**Your own `/who` still works.** Scans keep the Who results going to the Who list (switched off, a
query with 1-3 results is printed to chat instead and the addon never sees it). To keep Blizzard's
Friends window from popping open, the addon stops it listening for Who results during its own query
only and hands the listener back straight after, so a manual `/who` behaves normally.

**Server errors are logged, not pattern-matched.** If a system line arrives within 3 seconds of a
send it is recorded against that contact as `server:` in the history, verbatim. That way the
reason is visible in your own client language instead of relying on English string matching.
Three such warnings inside a minute trips an automatic pause.

**No Blizzard frames are hooked.** Every widget is created by this addon, so there is no taint.

---

## Known limits

- **Replies sent while you are offline are lost forever.** WoW does not store them. The Replied
  tab will under-count, and there is no fix - only the fact that a name you already contacted
  stays in Contacted rather than returning to Queued, so you will not re-whisper them.
- **SavedVariables only write on exit, `/reload`, or logout.** A client crash loses the session.
  `/beg save` calls `C_AddOns.SaveAddOnsData` if this client has it, and otherwise says so.
- **Same-name players on connected realms.** The key keeps the realm suffix when the Who list
  provides one, so two different Bobs stay separate. If this client returns bare names, they
  cannot be told apart.
- **Addon messages are not tracked.** Mail is tracked only through the inbox headers of people
  you mailed, and only while the mailbox is open.
- **Mail can be reported as spam** by the person who gets it, just like a whisper. Keep it to
  people you would whisper anyway.
- **BNet whispers are not tracked.** `CHAT_MSG_BN_WHISPER` is a different namespace.
- **Hardcore Self-Found players cannot trade gold.** `/who` does not say who is Self-Found, so
  expect some polite "I can't" replies from them.
- The per-class extra scans use the `c-"Class"` who filter. It is standard `/who` syntax but has
  not been checked on this client yet; if extra scans for a class come back empty in a busy city,
  that filter is the first suspect.
- If a `/who` times out, the next scan waits up to 10 seconds, so a late answer from the old query
  cannot be credited to the new level band.
- The seeded capital city list is best-effort. If your client doesn't recognise a map ID it is
  skipped silently, and **Add this zone** is the reliable path.

---

## Files

| File | Role |
|---|---|
| `BegBuddy.toc` | interfaces `11509` (Hardcore) and `16001` (Forever), SavedVariables `BegDB` |
| `Core.lua` | namespace, defaults, database, zone picks, boot events |
| `Classes.lua` | class names, tokens and colours |
| `Contacts.lua` | contact lookup, status changes, counts, sorting |
| `Templates.lua` | whisper and mail templates and their results |
| `Export.lua` | the plain-text backup |
| `Scan.lua` | city list, slice plan, `SendWho` |
| `WhoResults.lua` | harvest, online check, next-step text, diagnostics |
| `Comms.lua` | template rendering, assisted send, reply capture, history |
| `Guard.lua` | the checks before an opener may go out |
| `Mail.lua` | mail mode: rendering, send checks, `SendMail`, server answers, inbox headers |
| `UIWidgets.lua` | hand-rolled widgets (no MenuUtil / ScrollBox / UIDropDownMenu) |
| `UIZones.lua` | the zone picker |
| `UIList.lua` | the contact list and slice chips |
| `UIMain.lua` | the main window |
| `UIRefresh.lua` | redraws the main window |
| `UI.lua` | public surface, history popout, copy box |

The UI deliberately avoids `MenuUtil`, `ScrollBox` and `UIDropDownMenu` so that a beta client
shifting those APIs cannot break the window.

## Status

0.3.0 adds mail mode with its own templates (Settings > Mail), a multi-select zone picker for
every open-world zone that saves your ticks and rotates the scan through them, and more icons and
colour: status colours on the tabs, counters and detail pane, and icons on the scan buttons.

0.2.0 fixes: the contact list crashing as soon as a name was queued, level range changes not
restarting the scan, and a scan after a timeout being thrown away. Adds Hardcore support.

Window fixes in the same release:

- The city and template dropdowns scroll with the mouse wheel past 12 entries and say how many
  there are. Before, anything after the 12th city could not be picked.
- The contact list shows "1-17 of 30, scroll for more" when it has more names than fit.
- **Change levels** on the scan panel opens Settings straight on the Scan page.
- The number fields take whole numbers only, never go below 1 (0 allowed for the reply gap and
  re-whisper wait), refuse a Min above Max or a Max below Min with a message saying which to change
  first, and only print when a value actually changed.
- Enter or Escape in the message box leaves it. A pasted line break becomes a space, because a
  whisper is one line.
- The history pane and the export window keep long text inside their borders and scroll it.
- The History window updates while it is open, when a new whisper arrives.
- Two players with the same name on different realms stay separate contacts (a second Bob
  used to be merged into the first). Name lookups use an index, so scans and whispers stay
  fast with thousands of contacts.
- **Auto: send next** (bottom right) whispers the top person in Queued, in the list's sort
  order, one whisper per click. Click it as fast as you like: clicks inside the send gap do
  nothing, and nobody can be sent to twice, even before the game confirms the first send.
  People a check found offline are skipped. The number on it is how many are left.
- Each sendable name has **check** and **send** buttons. **check** runs one `/who` for that
  name: offline people are archived on the spot (with Auto-archive offline on), online people
  show `online`. Click check then send straight away; you do not have to wait for the answer.
  A send to someone offline is also archived instantly, and no longer holds up the next send.
- The list has **Name** and **Lvl** column headers. Click one to sort by it, again to reverse,
  a third time for the order people were found. The choice is saved.
- Every contact action has a small icon. Replied and Funded contacts get Invite and Add friend.
- One-click send (Settings, Scan page, off by default since 0.4.1): the row **send** button and **Send whisper**
  send the message in one click instead of loading it into chat for Enter.
- Clicks redraw the window in the same frame, buttons visibly press, and closing out or
  whispering the selected contact moves the selection to the next name in that tab.

Checked by clicking every button in every window against a stubbed game API, in the order a player
would, plus the scan, whisper, reply, offline archive, settings and slash command scenarios.
**Not yet run inside a live client.**
