# BegBuddy changelog

## 0.5.2 (2026-11-14)

- Problem log: every Lua error and every call the game refuses from a Zip addon is now saved, so a break can be traced. `/beg health` lists them and `/beg health clear` empties the list. You get one chat line the first time something is saved.

## 0.5.1 (2026-11-08)

- **Leave group**, top right of the window next to Settings: one click out of a party or raid, no menu. `/beg leave` does the same, so a macro can use it.

## 0.5.0 (2026-11-05)

- **Stats tab** next to Blocked: the funnel (found, asked, replied, funded), the gold and items that came back, and a sortable table for one breakdown at a time: by template, class (in class colours), level, zone, time of day, day of the week, whisper or mail, and ask number. `/beg stats` opens it.
- **You pick what success means:** Replied, Funded, or Gold of at least an amount (click Gold again to step 1s, 10s, 50s, 1g, 5g, 10g). Every rate and the Success column follow that choice.
- **Gold and items are now kept.** Gold and items that arrive by mail are added to the person's card once (a mail you sent that came back is not counted), and trades are counted too: when the other player has accepted and the game says the trade completed, their gold and items go on the card and they move to Funded. Trade capture has not been tried on Forever yet.
- Rows with fewer asks than the "Trust after N asks" setting are marked * and sorted last when you sort by a rate, so a lucky 1 of 2 can't top the list.
- Cheap: the numbers are worked out only while the Stats tab is open, kept until something changes, and a breakdown is built only when you look at it.

## 0.4.3 (2026-11-04)

- The class picker is now **multiselect** and every class shows in its **class colour**. Tick as many classes as you like; the list stays open while you tick, and ticked rows get a faint wash of the class colour.
- With classes ticked, each level band gets one scan per class. A band that comes back full is cut into single levels for that class.
- The button shows up to two ticked classes in colour, then +N. Nothing ticked means All classes.
- Faster: the ticked classes are worked out once, not on every lookup, and the picker's rows are built once.

## 0.4.2 (2026-11-04)

- New **class dropdown** in the scan panel, next to Next zone. Pick a class and every scan asks /who for only that class. All classes goes back to scanning everyone.
- Each class is its own scan plan: switching class starts from the first level band, the same as changing the level range does.
- The zone picker has a new **Starting zones** group (Elwynn Forest, Dun Morogh, Teldrassil, Durotar, Mulgore, Tirisfal Glades, Eversong Woods, Azuremyst Isle). These zones are still listed under their continent too, and a zone ticked in both places is scanned once.

## 0.4.1 (2026-11-03)

- Forever: gold amounts and hidden names no longer cause errors.
- One-click send is off by default. Your message text is unchanged.
- Auto keeps the Send gap, and stops on ignores, chat limits and chat lockdown.
- Strangers who whisper you first are not added to your list.
- An archived name keeps its re-whisper wait and its past reply.


**New**
- Quick messages: a strip of buttons above the reply box. One click sends the message where your cursor is. With the cursor in the chat box, it goes to whatever the chat box is set to: Party, Say, Guild, Raid, a channel, or a whisper to someone. With the chat box closed, it whispers the person you have open (nothing is sent when nobody is open and the chat box is closed). It starts with a friendly set that includes "Tysm!", "Yes please!", "I'm in front of the AH!" and "I'm rich!!!". A **Quick -** button folds the strip away.
- Settings > **Quick messages**: edit, hide, reorder, delete and add your own (up to 24). The list is kept when you reset the settings and when you use Clear all.
- **Clear all** button next to **Clear**: deletes everything BegBuddy saved, after one "Click again to confirm". Your quick messages, the window's place and the saved profiles are kept. `/beg wipe confirm` does the same.

**Changes**
- `/beg wipe confirm` now keeps the quick messages, the window's place and the saved profiles.
- The counters line at the bottom is a little narrower to make room for the new button.
