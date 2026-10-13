import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { SplitText } from 'gsap/SplitText';

gsap.registerPlugin(ScrollTrigger, SplitText);
ScrollTrigger.config({ ignoreMobileResize: true });

const mm = gsap.matchMedia();
const MOTION = '(prefers-reduced-motion: no-preference)';

/* ---------- Hero: the island story ---------- */

const SCREEN = { width: 1200, height: 740 };
const NAV_SPACE = 72;
// Caption block, the gap above it, and room below it.
const CAPTION_SPACE = 120 + 28 + 56;

type Size = { w: number; h: number };
/** One island state. A state with `frames` plays those captures in turn, all at its size. */
type State = { id: string; w: number; h: number; r: number; frames?: string[] };

const hero = document.querySelector<HTMLElement>('.hero');
const stage = hero?.querySelector<HTMLElement>('[data-stage]');
const frame = hero?.querySelector<HTMLElement>('[data-screen-frame]');
const island = hero?.querySelector<HTMLElement>('[data-island]');

if (hero && stage && frame && island) {
  const sizes = JSON.parse(island.dataset.sizes ?? '{}') as Record<string, Size>;
  // At rest the island is the notch itself; every other state is a real capture of the app.
  const states: State[] = [
    { id: 'idle', w: 185, h: 32, r: 10 },
    { id: 'live', ...sizes.live, r: 12 },
    {
      id: 'banner',
      ...sizes.banner,
      r: 24,
      frames: ['banner-opened', 'banner-ready', 'banner-merged', 'banner-failed', 'banner-review'],
    },
    { id: 'list', ...sizes.list, r: 32 },
    { id: 'board', ...sizes.board, r: 32 },
    { id: 'stats', ...sizes.stats, r: 32 },
  ];
  const image = (id: string) => island.querySelector<HTMLImageElement>(`img[data-state="${id}"]`);
  const frames = (state: State) => state.frames ?? [state.id];
  const caption = (id: string) => hero.querySelector<HTMLElement>(`[data-step="${id}"]`);

  const pad = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--pad')) || 20;
  const roomHeight = () => window.innerHeight - NAV_SPACE - CAPTION_SPACE;
  // Wide viewports show the whole 1200 × 740 screen, scaled to fit beside the captions.
  const fitScreen = () => {
    const byWidth = (window.innerWidth - pad() * 2) / SCREEN.width;
    return Math.max(0.24, Math.min(1, byWidth, roomHeight() / SCREEN.height));
  };
  // Narrow viewports zoom onto the island and follow it, so each state stays readable.
  const zoomFor = (state: State) => Math.min(1, (window.innerWidth - pad() * 2) / (state.w + 56));

  const fit = (zoom: boolean, state: State) => {
    frame.classList.toggle('is-zoom', zoom);
    frame.style.setProperty('--frame-h', `${Math.round(roomHeight())}px`);
    frame.style.setProperty('--s', String(zoom ? zoomFor(state) : fitScreen()));
  };

  const setState = (state: State) => {
    gsap.set(island, { width: state.w, height: state.h, '--r': `${state.r}px`, '--ear': state.id === 'idle' ? 0 : 1 });
    const shown = frames(state)[0];
    island.querySelectorAll<HTMLImageElement>('img[data-state]').forEach((img) => {
      gsap.set(img, { opacity: img.dataset.state === shown ? 1 : 0 });
    });
  };

  mm.add({ motion: MOTION, zoom: '(max-width: 759px)' }, (ctx) => {
    const { motion, zoom } = ctx.conditions as Record<string, boolean>;
    if (!motion) return;
    hero.classList.remove('is-static');
    setState(states[0]);
    fit(zoom, states[0]);
    const refit = () => fit(zoom, states[0]);
    ScrollTrigger.addEventListener('refreshInit', refit);
    const peek = () => parseFloat(getComputedStyle(hero).getPropertyValue('--peek')) || 150;
    const startY = () => hero.clientHeight - peek();
    gsap.set(stage, { y: startY });

    // Intro: the headline rises word by word, then the rest, then the screen lifts into view.
    // These start hidden by CSS before first paint, so they appear only through this intro.
    const introDone = () => document.documentElement.classList.add('intro-done');
    SplitText.create('#hero-title', {
      type: 'words,lines',
      mask: 'lines',
      autoSplit: true,
      onSplit: (self) => {
        gsap.set(self.masks, { paddingBottom: '0.12em', marginBottom: '-0.12em' });
        gsap.set('#hero-title', { visibility: 'visible' });
        return gsap.from(self.words, { yPercent: 115, duration: 1.1, ease: 'expo.out', stagger: 0.06, delay: 0.1 });
      },
    });
    gsap.fromTo(
      '[data-intro]',
      { y: 22, autoAlpha: 0 },
      { y: 0, autoAlpha: 1, duration: 0.9, ease: 'power3.out', stagger: 0.08, delay: 0.4 },
    );
    gsap.fromTo(
      frame,
      { y: 180, rotateX: 16, autoAlpha: 0, transformPerspective: 1400 },
      { y: 0, rotateX: 0, autoAlpha: 1, duration: 1.5, ease: 'expo.out', delay: 0.5, onComplete: introDone },
    );

    const STEP = 1.2;
    // Each extra frame of a state holds for this long before the next one fades in.
    const FRAME = 0.6;
    const lengthOf = (state: State) => STEP + (frames(state).length - 1) * FRAME;
    const totalSteps = states.reduce((sum, state) => sum + lengthOf(state), 0) / STEP;
    const scrollLength = () => window.innerHeight * (1.2 + totalSteps * 0.85);
    const tl = gsap.timeline({
      defaults: { ease: 'none' },
      scrollTrigger: {
        trigger: hero,
        start: 'top top',
        end: () => '+=' + scrollLength(),
        pin: true,
        scrub: 0.6,
        anticipatePin: 1,
        invalidateOnRefresh: true,
      },
    });

    tl.to('.hero-copy', { y: -90, autoAlpha: 0, duration: 0.6 }, 0)
      .to('.hero-glow', { autoAlpha: 0, duration: 0.6 }, 0)
      .fromTo(stage, { y: startY }, { y: NAV_SPACE, duration: 1, ease: 'power2.inOut', immediateRender: false }, 0);

    let at = 1;
    states.forEach((state, i) => {
      const length = lengthOf(state);
      if (i > 0) {
        const previous = states[i - 1];
        const morphAt = at - 0.35;
        // The shape grows or shrinks; the new capture fades in as the old one leaves.
        tl.to(
          island,
          { width: state.w, height: state.h, '--r': `${state.r}px`, '--ear': 1, duration: 0.5, ease: 'power2.inOut' },
          morphAt,
        );
        // On a phone the camera pulls back as the island grows.
        if (zoom) tl.to(frame, { '--s': () => zoomFor(state), duration: 0.5, ease: 'power2.inOut' }, morphAt);
        const last = frames(previous);
        const out = image(last[last.length - 1]);
        if (out) tl.to(out, { opacity: 0, duration: 0.2 }, morphAt);
        const into = image(frames(state)[0]);
        if (into) tl.fromTo(into, { opacity: 0 }, { opacity: 1, duration: 0.3 }, morphAt + 0.12);
      }
      // Further frames crossfade in place, one after another, under the same caption.
      frames(state).slice(1).forEach((id, k) => {
        const swapAt = at + STEP - 0.35 + k * FRAME;
        const out = image(frames(state)[k]);
        const into = image(id);
        if (out) tl.to(out, { opacity: 0, duration: 0.2 }, swapAt);
        if (into) tl.fromTo(into, { opacity: 0 }, { opacity: 1, duration: 0.25 }, swapAt + 0.08);
      });
      const text = caption(state.id);
      if (text) {
        tl.fromTo(text, { autoAlpha: 0, y: 16 }, { autoAlpha: 1, y: 0, duration: 0.3, ease: 'power2.out' }, at);
        if (i < states.length - 1) tl.to(text, { autoAlpha: 0, y: -12, duration: 0.25 }, at + length - 0.4);
      }
      at += length;
    });
    tl.to({}, { duration: 0.5 });

    // "Features" jumps to the start of the story rather than the very top.
    const featuresLink = document.querySelector<HTMLAnchorElement>('a[href="#features"]');
    const toStory = (event: Event) => {
      event.preventDefault();
      const trigger = tl.scrollTrigger;
      if (!trigger) return;
      const target = trigger.start + (trigger.end - trigger.start) * (1 / tl.duration());
      window.scrollTo({ top: target, behavior: 'smooth' });
    };
    featuresLink?.addEventListener('click', toStory);
    return () => {
      featuresLink?.removeEventListener('click', toStory);
      ScrollTrigger.removeEventListener('refreshInit', refit);
    };
  });

  // Without motion, show the expanded island and every caption at once.
  mm.add('(prefers-reduced-motion: reduce)', () => {
    hero.classList.add('is-static');
    setState(states[3]);
    fit(window.innerWidth < 760, states[3]);
    gsap.set(stage, { clearProps: 'transform' });
    hero.querySelectorAll<HTMLElement>('.caption').forEach((el) => gsap.set(el, { autoAlpha: 1 }));
  });
}

/* ---------- Copy buttons ---------- */

/** Copies text, falling back to the older copy command where the clipboard API is blocked. */
async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const field = document.createElement('textarea');
    field.value = text;
    field.setAttribute('readonly', '');
    field.style.position = 'fixed';
    field.style.opacity = '0';
    document.body.append(field);
    field.select();
    const copied = document.execCommand('copy');
    field.remove();
    return copied;
  }
}

// The install command button: copy, then show the check for a moment. If copying isn't
// allowed at all, select the command so Cmd-C works.
document.querySelectorAll<HTMLButtonElement>('[data-micro-copy]').forEach((button) => {
  const status = button.querySelector('[role="status"]');
  let timer = 0;
  button.addEventListener('click', async () => {
    if (await copyText(button.dataset.microCopy ?? '')) {
      button.classList.add('is-copied');
      if (status) status.textContent = 'Copied';
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        button.classList.remove('is-copied');
        if (status) status.textContent = '';
      }, 1600);
    } else {
      const command = button.querySelector('.micro-command');
      if (command) window.getSelection()?.selectAllChildren(command);
      if (status) status.textContent = 'Command selected; press Command-C to copy';
    }
  });
});

document.querySelectorAll<HTMLElement>('[data-copy]').forEach((block) => {
  const button = block.querySelector('button');
  button?.addEventListener('click', async () => {
    if (await copyText(block.dataset.copy ?? '')) {
      block.classList.add('is-copied');
      button.textContent = 'Copied';
      window.setTimeout(() => {
        block.classList.remove('is-copied');
        button.textContent = 'Copy';
      }, 1600);
    } else {
      button.textContent = 'Select and copy';
    }
  });
});

/* ---------- Section reveals ---------- */

mm.add(MOTION, () => {
  gsap.set('.reveal', { y: 32, autoAlpha: 0 });
  ScrollTrigger.batch('.reveal', {
    start: 'top 88%',
    once: true,
    onEnter: (els) => gsap.to(els, { y: 0, autoAlpha: 1, duration: 0.9, ease: 'power3.out', stagger: 0.08 }),
  });
});
