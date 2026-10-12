# GitIsle launch video

A 40-second HyperFrames composition (`index.html`) built on real footage of the
app. `STORYBOARD.md` has the beats; `BRIEF.md` has the intent.

## Render

```bash
curl -fsSL -o audio/mixkit-tech-house-vibes-130.mp3 --create-dirs https://assets.mixkit.co/music/130/130.mp3
npm run check
npx hyperframes render --quality high --video-frame-format png --output renders/video.mp4
```

Music: "Tech House vibes" from [Mixkit](https://mixkit.co/free-stock-music/),
under the Mixkit free licence (not redistributed here).

## Re-record the footage

The app's `--tour` flag (example data only) drives the island through every
state in about 25 seconds. `tools/capture-window.swift` records just the app's
windows, with transparency, from the top centre of the display:

```bash
bash scripts/build-app.sh   # from the repository root
swiftc -O videos/gitisle-launch/tools/capture-window.swift -o /tmp/capture-window
open -n dist/GitIsle.app --args --tour -AppleLocale en_US -AppleLanguages "(en)"
/tmp/capture-window "$(pgrep -n -f GitIsle.app/Contents/MacOS/GitIsle)" 30 videos/gitisle-launch/recordings/tour.mov 1100 700
ffmpeg -i videos/gitisle-launch/recordings/tour.mov -t 25.5 -vf fps=30 -c:v libvpx-vp9 -pix_fmt yuva420p \
  -b:v 0 -crf 18 -an videos/gitisle-launch/assets/island-tour.webm
```

The composition's timings are tied to the tour's beats; change one, change both.
