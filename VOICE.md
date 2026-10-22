# Voice control

Say **"hey canvas"** to the panel, then what you want: *"show the stocks"*,
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
- [How to talk to it](#how-to-talk-to-it)
- [What you can say](#what-you-can-say)
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

`install.sh` doesn't set this up yet. On the Pi, as the kiosk's user (no root
needed):

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

Check it hears you before you switch it on in the kiosk. Run this, say
*"hey canvas, next page"*, and press Ctrl-C:

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
| Listening for "hey canvas" | Ready. |
| Starting… | The listener is loading its models (a few seconds). |
| Not listening: *reason*. Trying again. | It started but couldn't hear: usually the microphone. It keeps trying. |
| Voice control is not installed on this device | The `venv` or models above are missing. |

Turn it off and the listener stops and the microphone is released straight
away.

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

A page you ask for by name or number is **held** there until you say
*"resume"* or tap the page dots. Otherwise the panel would turn away from it
before you'd read it.

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

### Places

| Say | Opens |
|---|---|
| "open the remote", "TV remote" | The dashboard's TV remote, full screen, with the inputs |
| "forecast", "weather forecast" | The full-screen weather: today, the next 7 days and the next 24 hours |
| "photos", "albums", "home" | The photo albums |
| "camera" / "hide the camera" | Shows or hides the camera overlay, if one is set up |
| "back", "close", "close that", "exit" | Closes whatever is open, like the back button |

## Asking Home Assistant

If the panel has no command for what you said, and
[Home Assistant](INSTALL.md#home-assistant) is set up, the request is sent to
Home Assistant's **Assist**, without the "hey canvas":

> "Hey canvas, turn off the lamp."
> "Hey canvas, set the bedroom lights to 30 percent."
> "Hey canvas, what's the temperature indoors?"
> "Hey canvas, what's on the shopping list?"

Assist's answer is shown under what you said, and spoken at the **Speech**
volume unless Do Not Disturb is on. If you've already said something newer
by the time an answer comes back, that answer is dropped.

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

- Check Settings says *Listening for "hey canvas"*.
- Check the right microphone is PipeWire's default (`wpctl status`).
- Run the listener by hand ([above](#installing-it)) and see whether `wake`
  lines appear.
- Say "hey canvas" a little more deliberately, as two words. Both
  recognisers are tried, and common mishearings ("hey campus", "hi canvass",
  "a canvas") are accepted.

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
