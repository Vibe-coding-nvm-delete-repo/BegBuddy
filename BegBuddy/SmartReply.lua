-- BegBuddy / SmartReply.lua
-- Modular, weighted-scoring incoming whisper intent engine, 1-click reply action
-- registry, and FIFO Smart Reply Queue state manager.
--
-- Design goals:
--   1) Declarative & modular: add/tune intents in ns.SMART_RULES and action packs
--      in ns.SMART_ACTION_BUILDERS without touching any UI code.
--   2) Zero false "Send Location" on declines/aways/hostiles/bot-checks:
--      masks positive idioms ("no problem", "no worries", "dont mind") and
--      negated locations ("not in sw", "left stormwind") before scoring, and
--      uses safe non-assumptive actions for ambiguous/general messages.
--   3) Fast & low-GC: all phrase tables are pre-padded once at file load.
--   4) 100% ToS-safe: ns.RunSmartAction runs strictly from a human button click.

local _, ns = ...

local StrLower = ns.StrLower

----------------------------------------------------------------------
-- 1. Intent Metadata & Weighted Rule Registry
----------------------------------------------------------------------

ns.SMART_META = {
  leave_group = { badge = "LEAVE GRP", color = "5cc8ff", tone = "go"      },
  hostile     = { badge = "HOSTILE",   color = "ff6060", tone = "danger"  },
  unavailable = { badge = "AWAY",      color = "ff9933", tone = "warn"    },
  decline     = { badge = "DECLINE",   color = "ff9933", tone = "warn"    },
  skeptic     = { badge = "BOT?",      color = "ffb84d", tone = "warn"    },
  mail        = { badge = "MAIL",      color = "ffd100", tone = "go"      },
  invite      = { badge = "INVITE",    color = "5cc8ff", tone = "go"      },
  location    = { badge = "LOCATION",  color = "7fe07f", tone = "go"      },
  arriving    = { badge = "ARRIVING",  color = "ffd100", tone = "go"      },
  willing     = { badge = "WILLING",   color = "7fe07f", tone = "go"      },
  question    = { badge = "QUESTION",  color = "5cc8ff", tone = "go"      },
  closing     = { badge = "CLOSING",   color = "b8bac6", tone = "neutral" },
  general     = { badge = "REPLY",     color = "b8bac6", tone = "neutral" },
}

-- Idiom & context masking applied BEFORE weighted phrase scoring.
-- Order matters: longer/more-specific idioms first.
local IDIOM_MASKS = {
  -- Positive "no / dont" idioms that must NEVER trigger decline:
  { " no problem ",       " __pos_np__ "       },
  { " no prob ",          " __pos_np__ "       },
  { " no worries ",       " __pos_np__ "       },
  { " dont mind ",        " __pos_ok__ "       },
  { " dont care ",        " __pos_ok__ "       },
  { " i dont need ",      " __offer_spare__ "  },
  { " dont need it ",     " __offer_spare__ "  },
  { " dont need them ",   " __offer_spare__ "  },
  { " no cap ",           " "                  },
  { " no need ",          " "                  },
  -- Layer/visibility idioms ("cant see you" -> invite/layer, NOT decline):
  { " cant see you ",     " __layer_issue__ "  },
  { " cant see u ",       " __layer_issue__ "  },
  { " dont see you ",     " __layer_issue__ "  },
  { " dont see u ",       " __layer_issue__ "  },
  { " diff layer ",       " __layer_issue__ "  },
  { " diff later ",       " __layer_issue__ "  },
  { " same layer ",       " __layer_issue__ "  },
  { " on someones layer "," __layer_issue__ "  },
  -- Asking where you are with "not sure where":
  { " not sure where ",   " __ask_where__ "    },
  -- Explicit group-exit requests (NOT invite requests):
  { " leave grp ",        " __leave_grp__ "    },
  { " leave group ",      " __leave_grp__ "    },
  { " drop group ",       " __leave_grp__ "    },
  { " drop grp ",         " __leave_grp__ "    },
  -- Busy-in-party (NOT an invite request):
  { " in a party ",       " __busy_party__ "   },
  { " says youre in a group ", " __layer_issue__ " },
  -- Negated / departed city phrases (MUST trigger away/unavailable, NOT location):
  { " no where near ",    " __away_city__ "    },
  { " nowhere near ",     " __away_city__ "    },
  { " left the city ",    " __away_city__ "    },
  { " left stormwind ",   " __away_city__ "    },
  { " left storm wind ",  " __away_city__ "    },
  { " left ironforge ",   " __away_city__ "    },
  { " left sw ",          " __away_city__ "    },
  { " left if ",          " __away_city__ "    },
  { " not in sw ",        " __away_city__ "    },
  { " not in stormwind ", " __away_city__ "    },
  { " not in if ",        " __away_city__ "    },
  { " not in ironforge ", " __away_city__ "    },
  { " not in town ",      " __away_city__ "    },
  { " not in the city ",  " __away_city__ "    },
  { " were not in ",      " __away_city__ "    },
  { " omw to auberdine ", " __away_city__ "    },
  { " omw to ironforge ", " __away_city__ "    },
  { " omw to if ",        " __away_city__ "    },
  { " omw to westfall ",  " __away_city__ "    },
  { " omw to darkshore ", " __away_city__ "    },
  -- Non-offer / advice phrases that must NEVER falsely match willing/invite/mail:
  { " p sure ",           " "                  },
  { " pretty sure ",      " "                  },
  { " not sure ",         " "                  },
  { " find someone in sw "," __soft_no__ "     },
  { " find someone ",     " __soft_no__ "      },
  { " you can make ",     " "                  },
  { " u can make ",       " "                  },
  { " group up ",         " "                  },
  { " sent msgs ",        " "                  },
  { " sent messages ",    " "                  },
  { " been at ah ",       " "                  },
  { " cheap on the auction house ", " __ah_advice__ " },
  { " on the auction house ",       " __ah_advice__ " },
  -- Negated positive words ("ofc not", "would not", "not new"):
  { " ofc not ",          " __hard_no__ "      },
  { " of course not ",    " __hard_no__ "      },
  { " would not ",        " __hard_no__ "      },
  { " i would but ",      " __soft_no__ "      },
  { " i would send ",     " __soft_no__ "      },
  { " or i would ",       " __soft_no__ "      },
  { " or iw ould ",       " __soft_no__ "      },
  { " not a skinner ",    " __soft_no__ "      },
  { " not a girl ",       " __skeptic_hit__ "  },
  { " not new ",          " __skeptic_hit__ "  },
  { " not a bot ",        " __skeptic_hit__ "  },
  -- Softener apology right before an active offer:
  { " sorry was afk ",    " __was_afk__ "      },
  { " sry was afk ",      " __was_afk__ "      },
}

-- Declarative weighted phrase rules per intent.
-- Each entry: { phrase, weight }. Pre-padded at load time for fast plain find().
ns.SMART_RULES = {
  leave_group = {
    { "__leave_grp__", 25 },
  },

  hostile = {
    { "__profanity__", 12 },
    { "fuck", 14 }, { "fck", 14 }, { "fk", 10 }, { "stfu", 14 }, { "sybau", 14 },
    { "gtfo", 14 }, { "loser", 12 }, { "get lost", 14 }, { "kick rocks", 14 },
    { "out my dms", 14 }, { "stop whispering", 14 }, { "stop tryin", 12 },
    { "get a job", 14 }, { "go play the game", 12 }, { "play the game", 10 },
    { "go do quests", 12 }, { "go do some quests", 12 }, { "earn your own", 12 },
    { "earn it", 10 }, { "go grind", 12 }, { "just grind", 10 }, { "grind", 7 },
    { "go lvl", 10 }, { "get better", 8 }, { "ask your mom", 12 },
    { "scam", 12 }, { "scams", 12 }, { "scammin", 12 }, { "scamming", 12 },
    { "beggar", 12 }, { "begger", 12 }, { "beggy", 12 }, { "hatebeggars", 14 },
    { "handouts", 14 }, { "asking for handouts", 14 },
    { "chud", 12 }, { "u bum", 12 }, { "bum", 8 }, { "e girl", 10 },
    { "blocked", 12 }, { "ignored", 12 }, { "reported", 12 }, { "fbi", 10 },
    { "spamming all my friends", 14 }, { "kill humanoid mobs", 8 },
    { "kill a few animals", 8 }, { "hard earned money", 10 },
  },

  unavailable = {
    { "__away_city__", 14 },
    { "__busy_party__", 12 },
    { "just left", 12 }, { "already left", 12 },
    { "flight path", 12 }, { "flightpath", 12 }, { "on a flight", 12 },
    { "on a long fp", 12 }, { "on fp", 12 }, { "in flight", 12 },
    { "flying to", 12 }, { "flyin thru", 12 }, { "just flew out", 12 },
    { "took a boat", 12 }, { "boat to", 10 }, { "by boat", 8 },
    { "hearthed", 12 }, { "earthed", 10 }, { "hearth to", 10 },
    { "far away", 12 }, { "relly far", 12 }, { "really far", 12 },
    { "in a dungeon", 12 }, { "in dungeon", 12 }, { "for a dung", 12 },
    { "do the dungeon", 10 }, { "in raid", 12 }, { "in a raid", 12 },
    { "in bg", 12 }, { "in av", 12 }, { "in wsg", 12 },
    { "passing through", 12 }, { "busy", 10 }, { "im busy", 12 },
    { "very afk", 12 }, { "afk at work", 12 }, { "afk", 8 },
    { "heading to", 10 }, { "getting my mount", 10 }, { "doing summons", 10 },
    { "free trial", 12 }, { "multiboxing", 10 }, { "in arathi", 10 },
    { "in duskwood", 10 }, { "in dustwallow", 10 }, { "in westfall", 10 },
    { "in wetlands", 10 }, { "in desolace", 10 }, { "in darkshore", 10 },
    { "in if", 8 }, { "to southshore", 10 }, { "wont make it", 12 },
    { "journey to attend", 10 }, { "sleepy", 8 },
  },

  decline = {
    { "__hard_no__", 14 },
    { "__soft_no__", 12 },
    { "__ah_advice__", 10 },
    { "no", 7 }, { "nope", 10 }, { "nah", 10 }, { "pass", 9 },
    { "no thanks", 12 }, { "no thank you", 12 }, { "no can do", 12 },
    { "sorry", 8 }, { "sry", 8 }, { "srry", 8 }, { "sorrry", 8 }, { "sory", 8 }, { "soz", 8 },
    { "sadly", 10 },
    { "cant", 9 }, { "cannot", 10 }, { "cannot spare", 12 }, { "cant spare", 12 },
    { "broke", 12 }, { "boke", 10 }, { "poor", 10 }, { "brokies", 10 },
    { "dont have", 11 }, { "dont got", 11 }, { "do not", 8 },
    { "got none", 12 }, { "have none", 12 }, { "no have", 11 }, { "out of them", 11 },
    { "no gold", 12 }, { "no silver", 12 }, { "no money", 12 }, { "no moneys", 12 },
    { "no leather", 12 }, { "no leathers", 12 }, { "no light leather", 12 },
    { "spent all", 11 }, { "just trained", 10 }, { "just sold", 10 }, { "sold all", 10 },
    { "used mine", 11 }, { "using it", 10 }, { "need it myself", 12 },
    { "running low", 11 }, { "unfortunately", 10 },
    { "im good", 10 }, { "ask your guild", 11 }, { "ask ur guild", 11 },
    { "just started myself", 11 }, { "only level 2", 10 }, { "only have", 8 },
    { "doing lw", 9 }, { "herb guy", 9 }, { "an herby", 9 }, { "leveling herborism", 9 },
    { "no trade", 12 }, { "already started it", 9 }, { "i have 91 copper", 11 },
    { "in the bank", 8 }, { "on the ah", 7 }, { "auction house for", 9 },
    { "not sure why you would need", 10 },
  },

  skeptic = {
    { "__skeptic_hit__", 10 },
    { "are you a bot", 14 }, { "are u a bot", 14 }, { "clever bot", 14 },
    { "you are a bot", 14 }, { "sound like a bot", 14 }, { "robot", 12 },
    { "caught bpt", 14 }, { "beep boop", 14 },
    { "copy pasta", 12 }, { "copypasta", 12 }, { "copy paste", 12 },
    { "spam message", 12 }, { "sending this to everyone", 12 },
    { "does this work", 12 }, { "does this actually work", 12 },
    { "does this strat work", 12 }, { "how often does that", 12 },
    { "how much money have you made", 12 }, { "how much have u actually made", 12 },
    { "who fallin for this", 12 }, { "nice try", 13 }, { "ragebait", 12 },
    { "simp", 10 }, { "why r u lying", 12 }, { "you cannot lie", 10 }, { "is a lie", 12 },
    { "how do u know", 11 }, { "how did u know", 11 },
    { "are u really brand new", 11 }, { "you new to wow", 9 }, { "you new new", 9 },
    { "howd you just run by me", 11 }, { "ran by me while i was", 11 },
    { "how did u find me", 10 }, { "born at night", 10 },
    { "this addon u got", 11 }, { "response was too fast", 11 },
    { "crazy tech", 10 }, { "respect the hustle", 10 }, { "cap", 6 },
  },

  mail = {
    { "mail", 11 }, { "mailed", 12 }, { "mailing", 12 }, { "mailbox", 13 },
    { "ill send you", 12 }, { "i can send u", 12 }, { "i can send you", 12 },
    { "send you some", 11 }, { "at a box", 10 }, { "just sent", 12 },
    { "sent", 10 }, { "arrive in", 11 }, { "cod", 9 },
  },

  invite = {
    { "__layer_issue__", 13 },
    { "inv", 12 }, { "invite", 12 }, { "party", 8 }, { "grp", 10 }, { "group", 8 },
    { "layer", 11 }, { "layered", 11 },
  },

  location = {
    { "__ask_where__", 12 },
    { "where are you", 14 }, { "where are u", 14 }, { "where u at", 14 },
    { "where you at", 14 }, { "where ya at", 14 }, { "where r u", 14 },
    { "wher eu at", 14 }, { "were are u", 14 }, { "where are thee", 14 },
    { "where", 11 }, { "wher", 10 }, { "wya", 14 },
    { "u at", 11 }, { "you at", 11 }, { "ya at", 11 }, { "coords", 13 },
    { "location", 12 }, { "meet at", 12 }, { "meet you", 12 }, { "meet", 9 },
    { "come to", 12 }, { "come find me", 13 }, { "come here", 12 },
    { "come open", 12 }, { "come back to", 11 }, { "come i will", 12 },
    { "by the ah", 11 }, { "at ah", 11 }, { "at the ah", 11 },
    { "by the bank", 11 }, { "by the church", 11 }, { "tailor shop", 11 },
    { "water fountain", 11 }, { "deeprun tram", 10 }, { "city gate", 10 },
    { "at the auction house", 11 }, { "by the auction house", 11 },
    { "in stormwind", 8 }, { "in sw", 8 },
  },

  arriving = {
    { "omw", 13 }, { "on my way", 13 }, { "coming", 11 }, { "ill come", 11 },
    { "running over", 12 }, { "trade me", 13 }, { "open trade", 13 },
    { "im here", 12 }, { "here", 9 }, { "making your bags", 13 },
    { "got you the bags", 13 }, { "real fast", 9 }, { "1 sec", 9 }, { "one sec", 9 },
    { "ok 1 sec", 11 }, { "let me travel back", 11 }, { "just flew over", 11 },
  },

  willing = {
    { "__pos_ok__", 8 },
    { "__offer_spare__", 10 },
    { "sure", 9 }, { "ssure", 9 }, { "yes", 8 }, { "ye", 7 }, { "yeah", 8 },
    { "ya sure", 11 }, { "of course", 10 }, { "ofc", 8 },
    { "i can help", 12 }, { "still need help", 12 }, { "still need", 10 },
    { "you need bags", 12 }, { "want them", 12 },
    { "i got you", 12 }, { "i got u", 12 },
    { "ill give", 13 }, { "i will give", 13 }, { "i can give", 12 },
    { "giving you", 12 }, { "take all my gold", 12 },
    { "can make", 12 }, { "ill make", 12 }, { "i will make", 12 },
    { "can craft", 12 }, { "make one for you", 13 }, { "make you a wand", 13 },
    { "make u a wand", 13 }, { "make u one", 12 }, { "make u it", 12 },
    { "i can trade", 13 }, { "i have 2", 10 }, { "i have a bunch", 10 },
    { "some junk you can vendor", 11 }, { "ill be nice", 10 },
    { "nope free", 12 },
  },

  question = {
    { "how much", 12 }, { "how many", 11 }, { "how amny", 11 },
    { "what do u need", 12 }, { "what do you need", 12 }, { "what u need", 12 },
    { "what wand", 12 }, { "wat wand", 12 }, { "which bags", 12 },
    { "what kind of bag", 12 }, { "lesser magic wand", 11 },
    { "mke n offer", 11 }, { "make an offer", 11 }, { "what are you offering", 11 },
    { "what lvl are you", 10 }, { "what level are you", 10 },
    { "bag slots", 10 },
  },

  closing = {
    { "__pos_np__", 8 },
    { "__heart__", 9 },
    { "np", 10 }, { "yw", 10 }, { "all good", 9 },
    { "youre very welcome", 12 }, { "your welcome", 12 }, { "youre welcome", 12 },
    { "enjoy", 11 }, { "take care", 11 }, { "have fun", 10 },
    { "have a good", 10 }, { "welcome to wow", 10 }, { "happy gaming", 10 },
    { "pay it forward", 12 }, { "pay it foward", 12 },
    { "add me if you need", 11 }, { "goodnight", 10 }, { "youre good", 9 },
  },
}

-- Pre-pad every phrase once at load time so hot-path classification allocates zero rule strings.
local COMPILED_RULES = {}
for intentId, phrases in pairs(ns.SMART_RULES) do
  local list = {}
  for i = 1, #phrases do
    list[i] = { " " .. phrases[i][1] .. " ", phrases[i][2] }
  end
  COMPILED_RULES[intentId] = list
end

local GOODLUCK_ONLY = {
  " gl ", " good luck ", " goodluck ", " gl out there ", " goodluck out there ",
  " fare well ", " farewell ", " best of luck ",
}

local function HasAnyPadded(padded, list)
  for i = 1, #list do
    if padded:find(list[i], 1, true) then return true end
  end
  return false
end

local function NormalizeWhisper(text)
  local raw = tostring(text or "")
  local s = StrLower(raw)
  -- Preserve censored WoW profanity & heart emoticon before stripping punctuation.
  if s:find("[!@#$%%^&*][!@#$%%^&*][!@#$%%^&*]") then
    s = s:gsub("[!@#$%%^&*]+", " __profanity__ ")
  end
  s = s:gsub("<3", " __heart__ ")
  -- Collapse apostrophes inside contractions (don't -> dont, i'm -> im, can't -> cant).
  s = s:gsub("['\226\128\153`]", "")
  s = s:gsub("[^%w_]", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^ ", ""):gsub(" $", "")
  local padded = " " .. s .. " "
  for i = 1, #IDIOM_MASKS do
    local m = IDIOM_MASKS[i]
    if padded:find(m[1], 1, true) then
      padded = padded:gsub(m[1], m[2])
    end
  end
  padded = padded:gsub("%s+", " ")
  return padded
end

local function IsFundedContact(contact)
  if not contact then return false end
  if contact.status == ns.STATUS.FUNDED then return true end
  return (tonumber(contact.goldIn) or 0) > 0 or (tonumber(contact.itemsIn) or 0) > 0
end

local SCORE_ORDER = {
  "leave_group", "hostile", "mail", "invite", "location", "arriving",
  "unavailable", "decline", "skeptic", "willing", "question", "closing",
}

-- Returns intentId, metaTable, winningScore
function ns.ClassifyWhisper(text, contact)
  local padded = NormalizeWhisper(text)
  if padded == " " or padded == "  " then
    return "general", ns.SMART_META.general, 0
  end

  local scores = {}
  for i = 1, #SCORE_ORDER do
    local id = SCORE_ORDER[i]
    local rules = COMPILED_RULES[id]
    local total = 0
    for j = 1, #rules do
      if padded:find(rules[j][1], 1, true) then
        total = total + rules[j][2]
      end
    end
    scores[id] = total
  end

  -- Context-sensitive "gl / good luck": post-trade goodbye if funded, polite brush-off otherwise.
  if HasAnyPadded(padded, GOODLUCK_ONLY) then
    if IsFundedContact(contact) then
      scores.closing = scores.closing + 10
    else
      scores.decline = scores.decline + 7
    end
  end

  -- Contrastive "but" + decline/unavailable dampens an opening "yes / sure / i would".
  -- Example: "yes absolutely but I'm on the flight path out... so sorry :("
  if padded:find(" but ", 1, true) and (scores.unavailable >= 10 or scores.decline >= 8) then
    scores.willing = math.floor(scores.willing * 0.4)
  end

  -- "sorry was afk, you need bags?" -> active offer cancels the afk apology.
  if padded:find(" __was_afk__ ", 1, true) then
    if scores.willing >= 8 or scores.location >= 10 or scores.mail >= 10 or scores.question >= 10 then
      scores.unavailable = 0
      scores.decline = math.max(0, scores.decline - 8)
    else
      scores.unavailable = scores.unavailable + 10
    end
  end

  -- Clear "leave grp" always wins immediately.
  if scores.leave_group >= 20 then
    return "leave_group", ns.SMART_META.leave_group, scores.leave_group
  end

  -- Clear hostility beats soft/ambiguous matches unless a genuine trade/location offer outweighs it.
  if scores.hostile >= 12 and (scores.location + scores.willing + scores.mail) < 16 then
    return "hostile", ns.SMART_META.hostile, scores.hostile
  end

  -- If someone explicitly says they are away/left city AND doesn't offer to mail/meet, away wins over generic location words.
  if scores.unavailable >= 10 and scores.mail < 12 and scores.invite < 12 then
    if scores.location < 14 and scores.willing < 12 then
      return "unavailable", ns.SMART_META.unavailable, scores.unavailable
    end
  end

  -- Find highest-scoring intent across all categories.
  local bestId, bestScore = "general", 0
  for i = 1, #SCORE_ORDER do
    local id = SCORE_ORDER[i]
    local sc = scores[id] or 0
    if sc > bestScore then
      bestId, bestScore = id, sc
    end
  end

  if bestScore < 6 then
    return "general", ns.SMART_META.general, bestScore
  end

  -- Post-trade contact saying "sure no problem" / "np" / "enjoy" -> closing, not willing.
  if bestId == "willing" and IsFundedContact(contact) and scores.closing >= 8 then
    bestId, bestScore = "closing", scores.closing
  end

  return bestId, ns.SMART_META[bestId] or ns.SMART_META.general, bestScore
end

-- Backwards-compatible helper.
function ns.DetectWhisperIntent(text, contact)
  local intent = ns.ClassifyWhisper(text, contact)
  return intent
end

----------------------------------------------------------------------
-- 2. Modular Action Pack Registry
----------------------------------------------------------------------

local function LocationText()
  local s = BegDB and BegDB.settings or {}
  if type(s.smartReplyLocation) == "string" and s.smartReplyLocation ~= "" then
    return s.smartReplyLocation
  end
  return "right outside the Stormwind AH steps"
end

ns.SMART_ACTION_BUILDERS = {
  leave_group = function()
    return
      { id = "leave",        label = "Leave group",          leave = true, dismiss = true, tone = "go" },
      { id = "thanks_leave", label = "Thanks + Leave",       reply = "tysm again!! gl out there <3", leave = true, dismiss = true, tone = "go" },
      { id = "open",         label = "Open",                 open = true, tone = "neutral" }
  end,

  hostile = function()
    return
      { id = "silent_dec",   label = "Mark Declined",        decline = true, dismiss = true, tone = "danger" },
      { id = "polite_exit",  label = "Polite exit + Decline",reply = "my bad sorry for bothering u, gl!", decline = true, dismiss = true, tone = "warn" },
      { id = "block",        label = "Block",                block = true, dismiss = true, tone = "danger" }
  end,

  unavailable = function()
    return
      { id = "polite_exit",  label = "Polite exit + Decline",reply = "all good no worries at all, gl out there!", decline = true, dismiss = true, tone = "warn" },
      { id = "ask_mail",     label = "Ask Mail",             reply = "no worries at all! if u ever pass a mailbox id really appreciate it, gl!", dismiss = true, tone = "neutral" },
      { id = "silent_dec",   label = "Mark Declined",        decline = true, dismiss = true, tone = "neutral" }
  end,

  decline = function()
    return
      { id = "polite_exit",  label = "Polite exit + Decline",reply = "all good no worries, gl out there!", decline = true, dismiss = true, tone = "warn" },
      { id = "silent_dec",   label = "Mark Declined",        decline = true, dismiss = true, tone = "neutral" },
      { id = "open",         label = "Open",                 open = true, tone = "neutral" }
  end,

  skeptic = function()
    return
      { id = "not_bot",      label = "Say: not a bot",       reply = "haha not a bot! just new & nervous lol, totally fine if not!", dismiss = true, tone = "warn" },
      { id = "polite_exit",  label = "Polite exit + Decline",reply = "haha fair enough, sorry for bothering u! gl out there", decline = true, dismiss = true, tone = "warn" },
      { id = "silent_dec",   label = "Mark Declined",        decline = true, dismiss = true, tone = "neutral" }
  end,

  mail = function(_, loc)
    return
      { id = "mail_ok",      label = "Mail works! tysm",     reply = "mail works awesome!! tysm, really appreciate it!", dismiss = true, tone = "go" },
      { id = "loc",          label = "Send Location",        reply = "tysm!! mail works great or im " .. loc .. " if ur nearby!", dismiss = true, tone = "go" },
      { id = "open",         label = "Open",                 open = true, tone = "neutral" }
  end,

  invite = function(_, loc)
    return
      { id = "inv_loc",      label = "Invite + Location",    invite = true, reply = "tysm!! inv sent, im " .. loc, dismiss = true, tone = "go" },
      { id = "inv_only",     label = "Invite only",          invite = true, dismiss = true, tone = "go" },
      { id = "loc",          label = "Send Location",        reply = "tysm! im " .. loc, dismiss = true, tone = "neutral" }
  end,

  location = function(_, loc)
    return
      { id = "loc",          label = "Send Location",        reply = "tysm! im " .. loc .. ", can i inv u?", dismiss = true, tone = "go" },
      { id = "inv_loc",      label = "Invite + Location",    invite = true, reply = "tysm!! inv sent, im " .. loc, dismiss = true, tone = "go" },
      { id = "open",         label = "Open",                 open = true, tone = "neutral" }
  end,

  arriving = function(_, loc)
    return
      { id = "here",         label = "Right here! tysm",     reply = "tysm!! right here, appreciate it so much!", dismiss = true, tone = "go" },
      { id = "inv_loc",      label = "Invite + Location",    invite = true, reply = "inv sent! im " .. loc, dismiss = true, tone = "go" },
      { id = "open",         label = "Open",                 open = true, tone = "neutral" }
  end,

  willing = function(_, loc)
    return
      { id = "loc",          label = "Send Location",        reply = "tysm!! im " .. loc .. ", can i inv u?", dismiss = true, tone = "go" },
      { id = "inv_loc",      label = "Invite + Location",    invite = true, reply = "tysm!! inv sent, im " .. loc, dismiss = true, tone = "go" },
      { id = "yes_plz",      label = "Yes plz! tysm",        reply = "yes plz!! tysm, really appreciate it!", dismiss = true, tone = "go" }
  end,

  question = function(_, loc)
    return
      { id = "amt",          label = "Reply: 1-2s / bag",    reply = "honestly even 1-2 silver or a spare bag/wand helps a ton, tysm!", dismiss = true, tone = "go" },
      { id = "loc",          label = "Send Location",        reply = "im " .. loc .. " if u have a sec, tysm!", dismiss = true, tone = "go" },
      { id = "open",         label = "Open",                 open = true, tone = "neutral" }
  end,

  closing = function()
    return
      { id = "thanks_gl",    label = "Thanks + GL",          reply = "tysm again!! gl out there <3", dismiss = true, tone = "neutral" },
      { id = "dismiss",      label = "Dismiss",              dismiss = true, tone = "neutral" },
      { id = "open",         label = "Open",                 open = true, tone = "neutral" }
  end,

  general = function(_, loc)
    return
      { id = "checkin",      label = "Friendly check-in",    reply = "hey! totally fine if u cant, just thought id ask :)", dismiss = true, tone = "neutral" },
      { id = "loc",          label = "Send Location",        reply = "im " .. loc .. " if u have a sec, tysm!", dismiss = true, tone = "go" },
      { id = "silent_dec",   label = "Mark Declined",        decline = true, dismiss = true, tone = "warn" }
  end,
}

function ns.SmartReplyActions(contact, incomingText)
  local intent, meta = ns.ClassifyWhisper(incomingText, contact)
  local loc = LocationText()
  local builder = ns.SMART_ACTION_BUILDERS[intent] or ns.SMART_ACTION_BUILDERS.general
  local a1, a2, a3 = builder(contact, loc, incomingText)
  if a1 then a1.warn = (a1.tone == "warn" or a1.tone == "danger") end
  return intent, a1, a2, a3, meta
end

-- Finds the latest real player whisper in contact.history (skipping [trade]/[mail] logs).
-- Returns text, unansweredBool, timestamp.
function ns.LastIncomingWhisper(contact)
  if not contact or type(contact.history) ~= "table" then return nil, false, nil end
  local h = contact.history
  local seenOut = false
  for i = #h, 1, -1 do
    local entry = h[i]
    if entry then
      if entry.dir == "out" then
        seenOut = true
      elseif entry.dir == "in" and type(entry.text) == "string" and entry.text ~= "" then
        local t = entry.text
        if t:sub(1, 8) ~= "[trade] " and t:sub(1, 7) ~= "[mail] " then
          return t, not seenOut, entry.t
        end
      end
    end
  end
  return nil, false, nil
end

----------------------------------------------------------------------
-- 3. Centralized Click Action Executor (Fail-Safe on replyGap/Combat)
----------------------------------------------------------------------

function ns.RunSmartAction(contact, act, opts)
  if not contact or not act then return false end
  local preview = opts and opts.preview

  if not preview then
    -- Send reply FIRST; if throttled (replyGap) or in combat, abort cleanly so
    -- the item stays in the queue and is never lost or prematurely declined.
    if act.reply and act.reply ~= "" then
      if not ns.SendReply(contact, act.reply) then
        return false
      end
    end
    if act.invite then ns.InviteContact(contact) end
    if act.leave then ns.LeaveGroup() end
    if act.decline then ns.SetStatus(contact, ns.STATUS.DECLINED, "declined") end
    if act.block then ns.SetStatus(contact, ns.STATUS.BLOCKED, "blocked") end
    if act.open then
      ns.activeContact = contact
      if ns.unread then ns.unread[contact.key] = nil end
      if ns.UI and ns.UI.Open then ns.UI.Open() end
      if ns.UI and ns.UI.frame then
        ns.UI.frame.activeTab = contact.status or ns.STATUS.REPLIED
        ns.RefreshUI()
      end
    end
  else
    -- Preview mode: print what would happen without sending real whispers.
    if act.reply and act.reply ~= "" then
      ns.Print("|cff5cc8ff[Preview]|r Would whisper " .. tostring(contact.name) .. ": " .. act.reply)
    else
      ns.Print("|cff5cc8ff[Preview]|r Would run action: " .. tostring(act.label) .. " on " .. tostring(contact.name))
    end
  end

  if act.dismiss or act.reply or act.decline or act.block or act.invite or act.leave then
    if contact.key then
      ns.SmartReplyRemove(contact.key)
      if ns.unread then ns.unread[contact.key] = nil end
    end
  end

  return true
end

----------------------------------------------------------------------
-- 4. FIFO Smart Reply Queue Manager (O(1) Lookup, Anti-Misclick Order)
----------------------------------------------------------------------

local MAX_QUEUE = 50
ns.smartQueue = ns.smartQueue or {}
local byKey = {}

local function NotifyQueue()
  if ns.UI and ns.UI.RefreshSmartQueue then
    ns.UI.RefreshSmartQueue()
  end
end

function ns.SmartReplyCount()
  return #ns.smartQueue
end

function ns.SmartReplyFind(key)
  return key and byKey[key] or nil
end

function ns.SmartReplyEnqueue(contact, incomingText, preview)
  if not contact or not contact.key then return nil end
  local text = tostring(incomingText or "")
  if text == "" then
    text = ns.LastIncomingWhisper(contact) or ""
  end
  if text == "" then return nil end

  local existing = byKey[contact.key]
  if existing then
    -- Keep their FIFO position so rows never jump under the cursor right as you click.
    existing.contact = contact
    existing.text = text
    existing.count = (existing.count or 1) + 1
    existing.at = time()
    existing.preview = preview and true or existing.preview
    existing.intent = ns.ClassifyWhisper(text, contact)
    NotifyQueue()
    return existing
  end

  local entry = {
    key     = contact.key,
    contact = contact,
    text    = text,
    count   = 1,
    at      = time(),
    preview = preview and true or false,
    intent  = ns.ClassifyWhisper(text, contact),
  }
  ns.smartQueue[#ns.smartQueue + 1] = entry
  byKey[contact.key] = entry

  while #ns.smartQueue > MAX_QUEUE do
    local dropped = table.remove(ns.smartQueue, 1)
    if dropped then byKey[dropped.key] = nil end
  end

  NotifyQueue()
  return entry
end

function ns.SmartReplyRemove(key)
  if not key or not byKey[key] then return false end
  byKey[key] = nil
  for i = 1, #ns.smartQueue do
    if ns.smartQueue[i].key == key then
      table.remove(ns.smartQueue, i)
      break
    end
  end
  NotifyQueue()
  return true
end

function ns.SmartReplyClear()
  if #ns.smartQueue == 0 then return 0 end
  local n = #ns.smartQueue
  for i = #ns.smartQueue, 1, -1 do ns.smartQueue[i] = nil end
  for k in pairs(byKey) do byKey[k] = nil end
  NotifyQueue()
  return n
end
