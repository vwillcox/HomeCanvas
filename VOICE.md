# Voice control

Say **"hey canvas"** (or [a wake word of your own](#your-own-wake-word)) to
the panel, then what you want: *"show the stocks"*,
*"next page"*, *"open the remote"*, *"pause the music"*. Anything the panel
doesn't know itself — *"turn off the lamp"*, *"what's the temperature
indoors"* — is passed on to Home Assistant, if you have it, and its answer is
shown and spoken.

Everything is heard and understood **on the Pi**. The microphone is read
locally, the speech is turned into words by
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) running two small
Moonshine recognisers, and the sound is held in memory for a few seconds and
then thrown away. Nothing is sent anywhere, with one exception: a request the
panel can't handle goes to *your* Home Assistant, as text. With voice control
switched off there is no listener running and nothing holding the microphone
open.

- [What you need](#what-you-need)
- [Installing it](#installing-it)
- [Switching it on](#switching-it-on)
- [Your own wake word](#your-own-wake-word)
- [How to talk to it](#how-to-talk-to-it)
- [What you can say](#what-you-can-say)
- [The TV, the lights and routines](#the-tv-the-lights-and-routines)
- [Asking Home Assistant](#asking-home-assistant)
- [Trying it without speaking](#trying-it-without-speaking)
- [When it gets it wrong](#when-it-gets-it-wrong)
- [What it won't do](#what-it-wont-do)

---

## What you need

- **A microphone** the Pi can hear: a USB microphone, a USB speakerphone, or
  a webcam with one. The listener follows PipeWire's *default* input,
  whichever that is at the time, so check it with `wpctl status` (the input
  marked `*` under *Sources*) and change it with `wpctl set-default <id>`.
- About **300 MB** of disk for the speech engine and its two models, and a
  little CPU. Recognition only runs once something has been said, not
  continuously.
- *Optional:* [Home Assistant](INSTALL.md#home-assistant), for the lights,
  heating and questions. Without it you still have every command
  [listed below](#what-you-can-say).
- *Optional:* [piper](INSTALL.md#reading-notes-aloud), so Home Assistant's
  answers are spoken as well as shown.

## Installing it

```bash
bash ~/homecanvas/install.sh --voice
```

That opens the installer straight at voice control. It sets up the speech
engine, helps you choose a wake word, and [teaches it how you say
it](#your-own-wake-word). It's also asked about in a full install. No root is
needed unless `pw-record` or Python's `venv` is missing, and it says so first.

### By hand

`scripts/setup-voice.sh` does the setting up on its own (`--check` only
looks). What it does, if you'd rather type it:

```bash
V=~/.local/share/homecanvas/voice
mkdir -p $V/models && cd $V

# The speech engine, in a Python of its own
python3 -m venv venv
venv/bin/pip install sherpa-onnx numpy

# The two recognisers
R=https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models
for m in base tiny; do
  curl -fsSL $R/sherpa-onnx-moonshine-$m-en-int8.tar.bz2 | tar xj -C models
done
```

That leaves:

```
~/.local/share/homecanvas/voice/
├── venv/                                     python with sherpa-onnx
└── models/
    ├── sherpa-onnx-moonshine-base-en-int8/
    └── sherpa-onnx-moonshine-tiny-en-int8/
```

Both models run on everything said. Neither hears "canvas" every time, but
they miss it at different times: of twelve "hey canvas" recorded at the
panel, one heard nine and the other ten, and between them eleven.

To check it hears you, run this, say *"hey canvas, next page"*, and press
Ctrl-C:

```bash
~/.local/share/homecanvas/voice/venv/bin/python ~/homecanvas/deploy/voice_listener.py
```

```
{"event": "ready"}
{"event": "wake"}
{"event": "heard", "text": "hey canvas next page", "other": "hey canvas next page"}
```

An `error` line says why it can't listen: usually a missing model folder, or
no microphone.

## Switching it on

**Settings → Screen → Voice control.** The line under the switch says how it's
going:

| It says | Meaning |
|---|---|
| Listening for "hey canvas" (or your wake word) | Ready. |
| Starting… | The listener is loading its models (a few seconds). |
| Not listening: *reason*. Trying again. | It started but couldn't hear: usually the microphone. It keeps trying. |
| Voice control is not installed on this device | The `venv` or models above are missing. |

Turn it off and the listener stops and the microphone is released straight
away.

## Your own wake word

"Hey canvas" works out of the box, but you can choose anything:

```bash
bash ~/homecanvas/install.sh --voice
```

Pick one of the suggestions ("computer", "hey jarvis", "okay house", "hey
panel"), or type your own. It's checked as you type:

- **Refused:** a command on its own ("next", "stop"), a word too common to
  pick out ("the"), numbers written as digits, or more than four words.
- **Warned about:** anything under three syllables, or a short name with no
  greeting in front. They work, but they're misheard more and go off by
  accident more.

An unusual name with a greeting in front works best: "hey jarvis", "okay
zephyr". Avoid the name of anyone in the house.

Then it learns how you say it:

1. **Microphone.** Choose which one, if there's more than one. It becomes the
   machine's default. Say anything, and a level meter shows whether it hears
   you above the room.
2. **Five times.** Say the wake word on its own, five times, from where you'd
   usually stand. Both recognisers write down what they heard each time.
3. **Learning.** The recognisers turn speech into words; they don't spot a
   sound. An unusual name comes out as whatever ordinary words it sounds
   like: "hey Zorblax" was heard as "hazor blacks", "hey sore blacks" and
   "hades or blacks". Those are kept, as *lookalikes* (another word in place of
   the name, after the greeting) or *variants* (the whole phrase as heard).
   With them, that wake word went from 0 of 6 to 6 of 6.
4. **Everyday speech.** You read two ordinary sentences aloud. If anything it
   learned would wake it on those, it's forgotten again. If the wake word
   itself turns up in everyday speech, it tells you.
5. **The verdict:** how often it heard you, before and after learning. You
   can save it, try again, or choose another.
6. **For real.** It saves the wake word, restarts the panel and asks you to
   say "*your wake word*, next page", then shows what the panel made of it.

It's kept in `~/.config/homecanvas/config.json`, under `screen` →
`wakeWord`:

```json
"wakeWord": {
  "phrase": "hey jarvis",
  "lookalikes": ["service"],
  "variants": ["hijarvis", "hey jar this"]
}
```

You can edit that by hand: add a word you've seen it mishear, or delete one
that sets it off. Stop the panel first (`systemctl --user stop homecanvas`)
so it can't save over your edit, then start it again.

Nothing about learning leaves the machine, and nothing is recorded: what you
said is kept only as the words above.

## How to talk to it

Say **"hey canvas"** and then the command, either in one breath:

> "Hey canvas, show the weather forecast."

or with a pause. Say "hey canvas", wait for the panel to show
**Listening…**, then say the command within about four seconds:

> "Hey canvas." *(Listening…)* "Next page."

When it hears the wake words the panel lights the screen if it was dark,
gives a very quiet beep, and shows a strip at the top of whatever is on screen:

1. **Listening…**: it heard "hey canvas".
2. **The words as it heard them**, then what it did. Or **Didn't understand
   "…"** if they meant nothing, or **Didn't catch that** if you said nothing
   after the wake words.
3. Home Assistant's answer under it, when it was asked.

The words as heard are the most useful part: if you see *"show socks"*, that's
why the stocks didn't appear.

Some things that help:

- **Speak at the panel from across a room, not from the next room.** It tells
  speech from the background by how much louder than the room it is.
- **Keep it short.** Anything over about eight seconds long is taken to be
  the television or music and ignored.
- **"Please", "the", "my", "can you"…** are all ignored, so speak however is
  natural: *"can you show me the calendar please"* works.

## What you can say

Every command below goes after "hey canvas".

### Dashboard pages

The panel learns its vocabulary from the dashboard as it stands. Every page
answers to **its own name** and to the **names of the widgets on it**, so
when you edit the dashboard the commands follow.

| Say | Does |
|---|---|
| "show the stocks", "markets", "bitcoin" | Turns to the page that widget is on |
| "show Media", "open the Bridge page" | Turns to a page by its name |
| "page three", "the third page", "page number 3" | Turns to a page by number, counting from one |
| "next page", "next", "forward" | The next page |
| "previous page", "back one", "page back" | The page before |
| "hold", "stay here", "pause pages", "stop turning" | Stops the pages turning on their own |
| "resume", "continue", "carry on", "start turning" | Lets them turn again |
| "dashboard" | Opens the dashboard |
| "all pages", "show me every page", "overview", "zoom out" | Every page at once, each a picture of how it last looked, to touch the one you want; "back" puts it away |
| "bring the news closer", "zoom in on the calendar", "make the weather bigger", "the stocks up close" | Turns to that widget's page and brings its tile close: it fills the screen, larger, to read from across the room |

A page you ask for by name or number is **held** there until you say
*"resume"* or tap the page dots. Otherwise the panel would turn away from it
before you'd read it.

A tile brought close goes back with *"back"*, or by itself after two minutes,
and the pages turn again once it has. Holding a tile on the screen does the
same.

Part of a widget's name is enough (*"fuel"* finds *Fuel prices*). Plurals
work either way, and a word that's one letter out still matches if it's five
letters or longer. Many widgets also have other names. A few:

| Widget | Also answers to |
|---|---|
| Stocks | shares, markets, stock market |
| Crypto | bitcoin, cryptocurrency |
| Calendar | diary, events |
| Planes | flights, aircraft, aeroplanes |
| Trains, TfL | travel, railway, tube, buses, underground |
| UniFi widgets | network, wifi, unifi, internet |
| Electricity | energy, power, meter, smart meter, bright |
| Home Assistant bridge | bridge, console, lcars, rooms |
| Omarchy | shortcuts, keyboard shortcuts |
| Sun & moon | sunrise, sunset |
| TV | television, telly |

The full list is `aliases` in
[`lib/services/voice_commands.dart`](lib/services/voice_commands.dart).
If two pages match equally well, the earlier page wins. Pages hidden by
their schedule right now are skipped.

### Music

Asked of whatever is playing: Spotify, or a phone's music over Bluetooth.

| Say | Does |
|---|---|
| "play", "play music", "unpause", "resume music" | Play |
| "pause", "stop", "pause the music" | Pause |
| "skip", "next song", "next track" | Next track |
| "previous song", "last track", "skip back" | Previous track |
| "volume up", "louder", "turn it up" | 10% louder |
| "volume down", "quieter", "turn it down" | 10% quieter |
| "mute", "unmute" | Mute and unmute |

*"Pause"* and *"stop"* on their own always mean the music. To stop the pages
turning, say *"hold"*.

### Photos

Anything said with *photos*, *pictures* or *slideshow* in it is looked for
in the whole Immich library. Who is in them, where and when they were taken
narrow it down; what is in them is found by Immich's own image search, which
looks at the photos themselves, so nothing has to be tagged or put in an
album first.

| Say | Finds |
|---|---|
| "show me photos of the beach", "pictures of the dog in the snow", "sunset photos" | What is in them, closest first |
| "photos of Ellie", "Ellie and Sam's photos" | Everyone named, as Immich has named them: a first name is enough |
| "photos from Llandudno", "pictures from Wales" | Taken in a town, a nation or a country |
| "photos from 2019", "twenty nineteen", "last summer", "March 2024", "the nineties", "five years ago" | Taken then |
| "photos of Ellie at the beach in Wales in summer 2019" | All of it at once |
| "play a slideshow of Ellie", "a slideshow of the beach" | The same, straight into a slideshow |

They open over whatever was showing, so *"back"* returns to it. *"Photos"*
on its own is still the albums. A season or a month on its own — *"summer"*,
*"June"* — is what it looks like, or someone of that name; with a year, or
after *"in"*, it is a date. People and places are matched against what
Immich knows, looked up at most once an hour.

### Cooking

| Say | Opens |
|---|---|
| "let's cook the traybake", "cook the chasseur", "the pancake recipe" | That recipe, if it has been cooked here before, read out a step at a time |
| "recipes", "my recipes", "what can I cook" | Every recipe cooked here |

While a recipe is open it hears first, so *"next"* is its next step rather
than the next page:

| Say | Does |
|---|---|
| "next", "done", "what's next", "go back", "step four", "start again" | Turns to that step and reads it out |
| "read it again", "pardon", "where was I" | Reads the step again |
| "how much flour?", "how many eggs do I need?" | Says how much, scaled for however many you are cooking for, and lights it in the list |
| "what do I need", "ingredients" | Reads every ingredient |
| "start the timer" | Starts a timer for the step's time, named for what it is: a Simmer timer, a Bake timer |
| "how long is left" | The timers still running — or, with none, how long the step says |
| "make it for six", "for eight people", "double it", "halve it" | Scales every amount |
| "shush", "stop talking" | Stops reading |
| "stop cooking", "close the recipe", "all done" | Puts the recipe away, where it was left: opened again today, it is back at that step |

Anything else — *"pause the music"*, *"what's the weather"* — goes where it
always does.

### Places

| Say | Opens |
|---|---|
| "open the remote", "TV remote" | The dashboard's TV remote, full screen, with the inputs |
| "forecast", "weather forecast" | The full-screen weather: today, the next 7 days and the next 24 hours |
| "what's my day", "what's on today", "good morning", "brief me" | **Your day**: the weather, today's calendar, reminders, parcels, timers and bins, and tomorrow — and reads it out, pausing the music while it does |
| "photos", "albums", "home" | The photo albums |
| "camera" / "hide the camera" | Shows or hides the camera overlay, if one is set up |
| "back", "close", "close that", "exit" | Closes whatever is open, like the back button |

## The TV, the lights and routines

| Say | Does |
|---|---|
| "turn the TV on", "TV off", "switch off the telly" | Switches the television in **Settings → TV** on or off |
| "turn the lights off", "lights on", "lights out" | Every light Home Assistant's Assist can see |
| "turn the TV and the lights off" | Both |
| "turn the PC off", "switch on the computer", "turn the omarchy PC on" | A computer running the panel's link receiver: see below |
| "turn the Art Matrix off", "Art Matrix on", "switch off the Art Matrix", "Arty off" | Switches the Art Matrix LED display in **Settings → Home → Art Matrix** on or off: see below |
| "Art Matrix brightness 40", "set the Art Matrix to 40 percent", "Art Matrix to forty percent" | Sets the Art Matrix's brightness, 1 to 100, and puts it on |
| "turn off the TV and the Art Matrix" | Both; the lights can go with them too |
| "I'm going to bed", "goodnight", "night night", "bedtime" | The **Bedtime** routine: stops the music, radio and any video, says "Goodnight", switches the TV, the Art Matrix and every light off, then puts the panel's screen out |

**The TV** is switched to what you asked for, not flipped: *"turn the TV
off"* does nothing to a set already in standby. The panel connects first if
it has to, even with no TV tile on screen, and reads whether the set is on
from what it reports. A set switched off beyond standby, which answers
nothing, gets a Wake-on-LAN packet. The panel learns the set's hardware
address the first time it reaches it, so there's nothing to set up.

**The lights** go to Home Assistant's Assist as *"turn off all the lights"*.
That's every light exposed to it (**Settings → Voice assistants → Expose**),
so the lights you keep out of voice stay out of this too. Without a room,
Assist itself can't tell which lights *"turn the lights off"* means. Name a
room or a light — *"the bedroom lights"*, *"the bedroom TV"* — and the request
goes to Assist unchanged, as before.

**Routines** are under **Settings → Screen → Routines**. Each has the
phrases that set it off, one per line. The panel matches the whole of what
you said, but small words don't matter: *"I am going to bed now"* is *"I'm
going to bed"*, and *"good night"* is *"goodnight"*. A routine can switch the
lights, the TV and the Art Matrix on or off, stop what's playing, put the screen out, and ask
Home Assistant for more (*"turn off the purifier"*, *"activate PC mode"*), one
request per line. Its reply is spoken unless Do Not Disturb is on. Only what
went wrong is said aloud otherwise: *"The TV isn't answering."* A routine's
phrase wins over the panel's own, so a *"good morning"* routine replaces
**Your day** for those words.

A routine can also set particular lights and ask a question. These go to
Home Assistant directly, by name, not as sentences to Assist.

- **Lights to set.** Choose lights, or whole rooms, then a brightness and a
  white (warm, neutral or cool). For example: Lounge 1 to 4 at 80%, warm
  white. Each setting is optional; leave one out and the lights keep what
  they had.
- **Turn every other light off.** Every light Home Assistant shows that is
  on, except the ones set above. Hidden lights are left alone: a lamp's
  segments go off with the lamp, and a network switch's LED isn't a light.
- **Questions.** For example *"Do you want the heater on or off?"*, with the
  Home Assistant device the answer switches. The panel asks once the rest
  is done. It then listens for the answer **without the wake words** for
  about seven seconds, and shows **On** and **Off** to touch as well.
  *"On"*, *"yes"* and *"on please"* mean on; *"off"*, *"no"* and *"leave it
  off"* mean off. Saying nothing, or something that is neither, leaves it as
  it was, and the panel says so. With Do Not Disturb on, the question
  appears on screen without being spoken.

  The panel's own voice is never taken for the answer, because the
  listener only starts once the question has been spoken. An answer
  containing both *on* and *off* counts as neither, so the question heard
  back can't switch anything.

A *Work mode* routine, for example, could say: *"Work mode"* → Lounge 1–4
at 80% warm white, every other light off, then *"Do you want the heater on
or off?"*.

**A computer** can be switched too, if it runs the receiver for links from
the panel (`companion_pc/`; see its README). Say *"the PC"* or *"the
computer"*, or use its name as the panel lists it under **Send to…**. A
computer's name next to *"lights"* still means a room, though: *"the office
lights"* goes to Home Assistant even with a computer called *office*.

- **Off.** The panel leaves a sealed *switch off* for the receiver, which
  collects it at once. A notice comes up on the computer for half a minute,
  with **Keep it on** to stop it. Then the computer shuts down. A *switch
  off* that waited while the computer was off isn't carried out when it
  comes back.
- **On.** This uses Wake-on-LAN, sent to the hardware address the receiver
  reports and to the address it last asked from. The panel then waits up to
  three minutes for the receiver to ask again. If it doesn't, the panel says
  *"The PC didn't wake up."*

The panel knows whether a computer is on by whether its receiver is asking.
So *"turn the PC off"* on a computer that isn't asking gets *"The PC is
already off."*, which also covers a computer that is on but signed out.

**The Art Matrix**, an LED display on the home network, is switched and
dimmed through its own HTTP API. Turn on **Art Matrix by voice** under
**Settings → Home → Art Matrix** and give its address: `arty.local`, or its
IP address if the panel can't find it by name. Only an address on the home
network is used. Say *"the Art Matrix"* or *"Arty"*; *"art"* or *"matrix"*
on its own isn't it, so *"turn the art off"* still goes to Home Assistant.
With no Art Matrix set up, everything here goes to Home Assistant, as the
TV's requests do.

- **On and off** are set, not flipped. Off darkens the display and its
  lights and pauses the animations; it stays on Wi-Fi and keeps its clock,
  so it can be put on again by voice. Off isn't kept by the display, so a
  power cut brings it back on.
- **Brightness** is a number from 1 to 100, in figures or in words:
  *"Art Matrix brightness 40"*, *"set the Art Matrix to forty five per
  cent"*, *"turn Arty to 75"*. The display keeps the level and comes on at
  it. Above 100 is taken as 100, and 0 as 1. The number needs
  *"brightness"*, *"percent"*, *"set"* or *"dim"* with it, or *"to"* or
  *"at"* before it: *"Art Matrix 40"* alone goes to Home Assistant, as does
  anything else said with it, such as *"set the Art Matrix to 40 percent
  and the TV off"*.
- Neither wakes the panel's screen, as with the TV and the lights. What
  went wrong is said: *"The Art Matrix isn't answering."*, *"The Art Matrix
  didn't take that."*
- **In a routine**, *The Art Matrix* can be put on or off. The choice shows
  once **Art Matrix by voice** is on, or in a routine that already has it.
  A new **Bedtime** puts it off, but a Bedtime saved before the Art Matrix
  came keeps its own steps: open it under **Settings → Screen → Routines**
  and set *The Art Matrix* to *Off* if you want it. At bedtime an Art Matrix
  that doesn't answer is taken to be off already, and nothing is said.

## Asking Home Assistant

If the panel has no command for what you said, and
[Home Assistant](INSTALL.md#home-assistant) is set up, the request is sent to
Home Assistant's **Assist**, without the "hey canvas":

> "Hey canvas, turn off the lamp."
> "Hey canvas, set the bedroom lights to 30 percent."
> "Hey canvas, what's the temperature indoors?"
> "Hey canvas, what's on the shopping list?"

Assist's answer is shown under what you said, and spoken at the **Speech**
volume unless Do Not Disturb is on. From 22:00 until 06:00 it's said quieter,
at **Speech at night** (Settings → Sound → **Quieter at night**, where the
hours can be changed). If you've already said something newer by the time an
answer comes back, that answer is dropped.

Both recognisers' hearings are tried in turn. An answer that only says why
not (*"not aware of any device called you one"*) doesn't stop the next
hearing being tried. If every hearing fails, a misheard device name is put
right by sound against the names Home Assistant has, and asked once more. So
*"turn around you one on"* becomes *"turn on lounge one"*, but only when one
name is clearly nearest. A number is never guessed: *"lounge five"* isn't
Lounge 4. Assist always hears the words as you said them first, so an alias
it knows is never rewritten.

Questions (*what, how, is, who, when, tell…*) and switching words (*off,
set, dim, brighten, lock, unlock, add, turn … on*) **always** go to Home
Assistant, never to a page. So *"what's the weather"* asks Assist, while
*"show the weather"* turns to the weather widget. A common mishearing of "turn" at
the start ("term the lamp off") is corrected before it's sent.

Assist can only reach what you've **exposed** to it: in Home Assistant,
**Settings → Voice assistants → Expose**. If it answers *"no device is
exposed"*, that's the fix. Give devices and areas the names you'd say
(*"lounge"*, *"lamp"*) as aliases there. For phrasings of your own, add
[custom sentences](https://www.home-assistant.io/voice_control/custom_sentences/)
in `custom_sentences/en/` in Home Assistant's config folder.

## Trying it without speaking

The kiosk's control port on the Pi takes commands as typed text, which is
handy for testing what a phrase does:

```bash
curl -s -X POST "http://127.0.0.1:8766/voice?say=show+the+stocks"
# {"ok":true,"did":"page 7"}

curl -s -X POST "http://127.0.0.1:8766/voice?say=what's+the+temperature+indoors"
# {"ok":true,"did":"<Home Assistant's answer>"}   — and it is spoken, too

curl -s -X POST "http://127.0.0.1:8766/voice?say=show+socks"
# {"error":"not understood","heard":"show socks"}
```

It only answers on the Pi itself (loopback) and refuses requests from web
pages.

The listener has three options for working out a mishearing. Run them from a
terminal on the Pi with voice control switched **off** in Settings, so the
two don't fight over the microphone:

| Option | Does |
|---|---|
| `--post` | Also sends what it hears to the kiosk, so the panel acts on it |
| `--keep FOLDER` | Saves each thing said to it as a `.wav` in `FOLDER`. Only for debugging: don't leave it on |
| `--from FILE` | Hears a raw recording (16 kHz mono 16-bit) instead of the microphone |

## When it gets it wrong

**It doesn't wake.** Watch for *Listening…* at the top. If it never appears:

- Check Settings says *Listening for "…"* with your wake word.
- Check the right microphone is PipeWire's default (`wpctl status`).
- Run the listener by hand ([above](#installing-it)) and see whether `wake`
  lines appear.
- Say the wake word a little more deliberately. Both recognisers are tried,
  and common mishearings ("hey campus", "hi canvass", "a canvas") are
  accepted.
- Teach it again from where you usually stand: `bash ~/homecanvas/install.sh
  --voice`. It learns how *you* say it.

**It wakes but does the wrong thing.** Read the words it shows. If they're
wrong, it misheard you: try a shorter phrase or another name for the widget.
If they're right but nothing happened, the phrase isn't one it knows: try it
with `curl` as above, and rename the page to what you naturally say.

**It wakes on its own.** The television said something like "hey canvas".
Long stretches of speech are ignored, but a short one can get through.
Nothing happens unless the words after it also mean something.

**Home Assistant says it didn't understand.** Assist got the request but
couldn't match it. Try it in Home Assistant's own Assist dialog, check the
device is exposed, and add an alias.

## What it won't do

- **Settings** and the **Locked Folder** can't be opened by voice. Neither
  is for whoever happens to be talking in the room.
- **British English only, for now.** Widgets are matched by their English
  names whatever language the panel is showing.
- It doesn't speak its own replies. The strip at the top is the reply. Only
  Home Assistant's answers are spoken.
