# Kiosk Share

The companion Android app for [HomeCanvas](../README.md)'s Share Inbox.
Registers as a share target — pick "Kiosk Share" from any app's share sheet
(Photos, Chrome, a video, anything) to send a photo, GIF, video, link or
note to the kiosk directly.

There's no separate relay or server for this app to talk to: the kiosk
itself listens for these (see `../lib/services/share_inbox_service.dart`).
This app just needs the kiosk's address and a token, both handed to you by
whoever owns the kiosk (from its Settings → Share Inbox screen).

## Setup

1. Install the app and open it once.
2. Tap the gear icon, enter the kiosk's address (e.g.
   `https://mine.example.com`) and the token you were given.
3. Save. Nothing else to do — the app runs quietly as a share target from
   here on.

## Sharing something

From any other app, use its normal Share button and pick **Kiosk Share**.
That's it — it shows up on the kiosk within a couple of seconds, with a
chime (unless Do Not Disturb is on there).

## Tracking a parcel

Share a carrier's tracking link the same way — from a Royal Mail, DPD, Evri or
Yodel email, or the courier's app — and the panel puts it on its Parcels tile
rather than opening it. For a tracking number on its own, or to say what is
coming ("Trainers"), use **Track a parcel** on the app's main screen.

## Receiving links from the panel

Turn on **Receive links from the panel** on the app's main screen. After that,
**Send to…** on a post, a story or a page on the panel puts it here as a
notification; touch it and the page opens in your browser. Give the phone a
name in Settings so you can tell it from others in the panel's list.

It works with the app closed: a quiet notification says it's waiting, which
you can hide by turning off its "Collecting links" category in Android's
settings for the app. Android asks to leave it out of battery optimisation,
which it needs to keep listening once the phone has been still a while.

It is light on the battery. The phone sleeps while it waits: the panel
answers once every five minutes, or the moment a link is sent, and the
answer wakes it. A panel on your home network is only asked over Wi-Fi (or
a VPN), never over mobile data; away from home the app asks nothing, links
wait on the panel for up to a week, and arrive when you are back. The
notification says "Links wait on the panel" while you are away.

If a reverse proxy sits in front of the panel and gives up on a request
held five minutes, the app notices and asks for under a minute instead.

Links are sealed on the panel to a key only this phone holds. The main screen
shows its id, and the panel lists the same one in Settings → Share Inbox.

## Development

```bash
flutter pub get
flutter run          # needs a connected device/emulator
flutter build apk     # release: flutter build apk --release
```

Multiple people can each have their own copy of this app pointed at the same
kiosk — every person gets their own name + token from the kiosk's Settings,
so shares show up attributed ("From: Mum's phone").
