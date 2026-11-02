# Moniker

**Your files, named for what's inside. On your Mac, by Apple Intelligence.**

`Screenshot 2026-11-02 at 16.52.04.png` becomes `2026-11-02 XYZ Invoice October.png`.
`IMG_4821.HEIC` becomes `2026-11-02 Receipt Blue Bottle Coffee.heic`.
`document (3).pdf` becomes `2026-11-02 Flight Booking Istanbul Berlin.pdf`.

Moniker lives in the menu bar and watches the folders where badly named files pile up:
your screenshot folder and Downloads. When one arrives, it reads it on your Mac and gives
it a name you could actually search for. Nothing is uploaded, nothing costs anything.

<!-- TODO: before/after GIF -->

## How it works

1. **Only new, badly named files.** Moniker never touches what was there before it started,
   and leaves alone any file whose name already means something. Screenshots, `IMG_1234`,
   `document (3)`, `Untitled`, `scan`, numbers-only and hash-like names are fair game.
2. **Read it like a person would.** Images go through Vision: text recognition plus a
   classifier that says what the picture shows. PDFs give up their text and stored title;
   a scanned PDF without text has its first page read like a picture.
3. **Ask Apple Intelligence for a title.** The on-device model gets what was read and returns
   a short, specific title through guided generation (`@Generable`). It writes in the language
   of the file, so a Turkish invoice gets a Turkish name.
4. **Rename safely.** Characters macOS dislikes are removed, the name is kept short, the date
   goes in front so files sort by time, and an existing file is never overwritten.
5. **Undo.** Every rename is listed in the menu with Undo and Show in Finder.

Prefer to decide yourself? Turn off **Rename automatically** and suggestions wait in the menu
until you confirm them. **Name Files…** names any files you pick, whatever they're called now.

## Works with Hearth

[Hearth](https://github.com/seckinbeduk/hearth) runs models on your Mac and shows which app uses
how much. When it's running, Moniker talks to Apple Intelligence through it, with no slowdown, so
every name it writes shows up in Hearth's **Who's using it**. When it isn't, Moniker uses Apple
Intelligence directly. Moniker uses [HearthKit](https://github.com/seckinbeduk/hearthkit) for this.

In settings, **Engine** picks Automatic (the above), Apple Intelligence only or Hearth only, and
**Hearth model** picks Apple Intelligence or Hearth's local model (Qwen, Gemma…). No Apple
Intelligence on this Mac? Run Hearth with a local model and Moniker uses that.

## Install

Needs an Apple silicon Mac with Apple Intelligence turned on, or [Hearth](https://github.com/seckinbeduk/hearth) running,
and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Pick the version for your macOS:

| macOS | Moniker | Builds with | What you get |
|---|---|---|---|
| 27 or later | [latest](https://github.com/seckinbeduk/moniker/releases/latest) (0.2.0+) | Xcode 27 | Everything, and Hearth is used automatically when it's running |
| 26 | [0.1.0](https://github.com/seckinbeduk/moniker/releases/tag/v0.1.0) | Xcode 26 | Everything except automatic Hearth; choose Hearth as the engine in settings |

```sh
git clone https://github.com/seckinbeduk/moniker.git
cd moniker
git checkout v0.1.0   # macOS 26 only
./run.sh
```

The first time, macOS asks whether Moniker may access your Desktop and Downloads.

## Develop

```sh
./run.sh test   # MonikerCore tests
./run.sh        # build and launch
```

`MonikerCore` holds the decisions that don't need the model: which names are generic,
how a title becomes a safe file name, collisions, undo, the journal, the prompt. The app
adds the folder watcher, Vision and PDFKit reading, the Apple Intelligence namer and the
menu bar UI.

## License

MIT
