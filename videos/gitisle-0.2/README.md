# GitIsle 0.2 launch video

A 46-second HyperFrames composition (`index.html`) built on real footage of the
app opening a PR's page. `STORYBOARD.md` has the beats; `BRIEF.md` has the intent.

## Render

```bash
curl -fsSL -o audio/mixkit-techno-fest-feel-125.mp3 --create-dirs https://assets.mixkit.co/music/125/125.mp3
npm run check
npx hyperframes render --quality high --video-frame-format png --output renders/video.mp4
```

Music: "Techno Fest Feel" by Alejandro Magaña, from [Mixkit](https://mixkit.co/free-stock-music/),
under the Mixkit free licence (not redistributed here). 126 BPM; the video starts 32.01 s into
the track so its drop lands on the PR page opening.

## Re-record the footage

The app's `--tour pages` flag (example data only) plays a preview landing, a PR's page and
its diff, a stack on the board, and a failed merge, in about 32 seconds.
`../gitisle-launch/tools/capture-window.swift` records just the app's windows, with
transparency, from the top centre of the display:

```bash
bash scripts/build-app.sh   # from the repository root
swiftc -O videos/gitisle-launch/tools/capture-window.swift -o /tmp/capture-window
open -n dist/GitIsle.app --args --tour pages -AppleLocale en_US -AppleLanguages "(en)"
/tmp/capture-window "$(pgrep -n -f GitIsle.app/Contents/MacOS/GitIsle)" 34 videos/gitisle-0.2/recordings/tour.mov 1100 700
ffmpeg -i videos/gitisle-0.2/recordings/tour.mov -t 32 -vf fps=30 -c:v libvpx-vp9 -pix_fmt yuva420p \
  -b:v 0 -crf 18 -an videos/gitisle-0.2/assets/island-tour.webm
```

The composition cuts the footage into three clips whose `data-media-start` values are tied to
the tour's steps; change one, change both.
