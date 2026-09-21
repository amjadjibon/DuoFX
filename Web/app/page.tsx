import Image from "next/image";
import { site } from "@/site.config";
import { InstallCommand } from "./install-command";
import { ThemeToggle } from "./theme-toggle";

const modes = [
  {
    name: "Blur sweep",
    shot: "/shots/2-blur-sweep.webp",
    blurb:
      "A clean line of blur travels with the lid. Your desktop keeps its exact coordinates, so everything stays where you left it.",
  },
  {
    name: "Soft fold",
    shot: "/shots/3-soft-fold.webp",
    blurb:
      "Blur builds continuously behind the leading edge, followed by a deepening shadow — the screen dimming as it folds toward the hinge.",
  },
  {
    name: "Perspective",
    shot: "/shots/1-perspective-hero.webp",
    blurb:
      "The captured desktop tilts toward the hinge over a dark backdrop, edges fading into black. Opening the lid reverses the same path.",
  },
];

const details = [
  {
    title: "Reads the real lid sensor",
    body: "Follows your MacBook’s built-in lid-angle sensor, calibrated to whatever you consider open. Manual control is always available as a fallback.",
  },
  {
    title: "Up to 120 FPS",
    body: "Visible animation follows Metal’s display refresh callbacks, requesting up to 120 FPS on ProMotion displays.",
  },
  {
    title: "Any direction",
    body: "Top, bottom, left, or right. The hinge anchors to the destination edge, and opening the lid plays the motion in reverse.",
  },
  {
    title: "Your own presets",
    body: "Save appearance and sound together under a name, then apply it anytime. Your lid calibration is never overwritten.",
  },
  {
    title: "Optional sound",
    body: "A soft whoosh for opening and closing, off by default, with its own volume. It never touches your system volume.",
  },
  {
    title: "Respects Reduce Motion",
    body: "Follows the macOS accessibility setting by default, with manual overrides, swapping the animation for an even blur fade.",
  },
];

export default function Home() {
  return (
    <div className="flex min-h-dvh flex-col">
      <Header />
      <main className="flex-1">
        <Hero />
        <Modes />
        <Customize />
        <Privacy />
        <Details />
        <Install />
        <Requirements />
      </main>
      <Footer />
    </div>
  );
}

function Header() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 px-4 pt-3 sm:pt-4">
      <div className="mx-auto flex h-14 max-w-2xl items-center justify-between gap-4 rounded-full border border-line/80 bg-ink/70 py-2 pr-2 pl-5 shadow-lg shadow-shot-shadow backdrop-blur-xl backdrop-saturate-150">
        <a href="#top" className="flex shrink-0 items-center gap-2.5">
          <Image src="/logo.png" alt="" width={24} height={24} className="rounded-[6px]" />
          <span className="text-[15px] font-semibold tracking-tight">{site.name}</span>
        </a>
        <nav className="flex items-center gap-5 text-sm text-muted">
          <a href="#modes" className="hidden transition-colors hover:text-body sm:block">
            Modes
          </a>
          <a href="#privacy" className="hidden transition-colors hover:text-body sm:block">
            Privacy
          </a>
          <a href={site.repoUrl} className="hidden transition-colors hover:text-body sm:block">
            GitHub
          </a>
          <ThemeToggle />
          <a
            href="#install"
            className="rounded-full bg-accent px-4 py-2 text-[13px] font-semibold text-accent-fg transition-opacity hover:opacity-90"
          >
            Install
          </a>
        </nav>
      </div>
    </header>
  );
}

function Hero() {
  return (
    <section id="top" className="relative overflow-hidden px-6 pt-28 pb-16 sm:pt-36">
      <div
        aria-hidden
        className="pointer-events-none absolute top-[-14rem] left-1/2 h-[30rem] w-[52rem] -translate-x-1/2 rounded-full bg-accent/12 blur-[120px]"
      />
      <div className="relative mx-auto max-w-3xl text-center">
        <p className="inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3.5 py-1.5 text-xs text-muted">
          <span className="size-1.5 rounded-full bg-accent" />
          macOS menu-bar app · {site.requirements}
        </p>
        <h1 className="mt-7 text-5xl font-semibold tracking-[-0.03em] text-balance sm:text-7xl">
          {site.tagline}
        </h1>
        <p className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-muted text-pretty sm:text-xl">
          DuoFX animates your desktop as your MacBook’s lid closes — a blur sweep, a progressive
          fold, or a cinematic perspective tilt. Every frame is rendered and discarded on your Mac.
        </p>
        <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <a
            href="#install"
            className="w-full rounded-full bg-accent px-7 py-3.5 text-[15px] font-semibold text-accent-fg transition-opacity hover:opacity-90 sm:w-auto"
          >
            Download for macOS
          </a>
          <a
            href="#modes"
            className="w-full rounded-full border border-line bg-surface px-7 py-3.5 text-[15px] font-medium text-body transition-colors hover:border-muted/40 sm:w-auto"
          >
            See how it looks
          </a>
        </div>
        <p className="mt-5 text-sm text-muted">Free and open source · Version {site.version}</p>
      </div>
      <div className="relative mx-auto mt-16 max-w-5xl">
        <Shot
          src="/shots/1-perspective-hero.webp"
          alt="DuoFX tilting the desktop toward the hinge as the lid closes"
          priority
        />
      </div>
    </section>
  );
}

function Modes() {
  return (
    <Section id="modes" eyebrow="Animations" title="Three ways to close.">
      <div className="mt-16 flex flex-col gap-20">
        {modes.map((mode, i) => (
          <div key={mode.name} className="grid items-center gap-8 lg:grid-cols-5 lg:gap-14">
            <div className={i % 2 === 1 ? "lg:order-2 lg:col-span-3" : "lg:col-span-3"}>
              <Shot src={mode.shot} alt={`${mode.name} animation in DuoFX`} />
            </div>
            <div className={i % 2 === 1 ? "lg:order-1 lg:col-span-2" : "lg:col-span-2"}>
              <h3 className="text-2xl font-semibold tracking-tight">{mode.name}</h3>
              <p className="mt-3 leading-relaxed text-muted text-pretty">{mode.blurb}</p>
            </div>
          </div>
        ))}
      </div>
    </Section>
  );
}

function Customize() {
  return (
    <Section
      eyebrow="Settings"
      title="Tune it until it feels right."
      lead="Blur radius, edge softness, dimming, motion easing, tilt strength, edge fade, fold shadow, transition width — each one is a slider with a live preview that needs no permissions."
    >
      <div className="mt-14 dark:hidden">
        <Shot src="/shots/5-settings.webp" alt="The DuoFX settings window" height={1248} />
      </div>
      <div className="mt-14 hidden dark:block">
        <Shot
          src="/shots/5-settings-dark.webp"
          alt="The DuoFX settings window in dark appearance"
          height={1248}
        />
      </div>
    </Section>
  );
}

function Privacy() {
  return (
    <section id="privacy" className="scroll-mt-24 px-6 py-24">
      <div className="mx-auto max-w-4xl rounded-3xl border border-line bg-surface p-10 sm:p-14">
        <svg
          aria-hidden
          viewBox="0 0 24 24"
          fill="none"
          className="size-7 text-accent"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M12 2.5 4.5 5.5v6c0 4.4 3.1 8.5 7.5 10 4.4-1.5 7.5-5.6 7.5-10v-6L12 2.5Z" />
          <path d="M9.5 12.2l1.9 1.9 3.6-3.8" />
        </svg>
        <h2 className="mt-5 text-3xl font-semibold tracking-tight sm:text-4xl">
          On this Mac only.
        </h2>
        <p className="mt-5 leading-relaxed text-muted text-pretty">
          Frames are captured, blurred, and discarded in memory. Nothing is written to disk, nothing
          is uploaded, and there is no analytics, no telemetry, and no audio recording. Mouse input
          always passes through to the desktop underneath.
        </p>
        <p className="mt-4 leading-relaxed text-muted text-pretty">
          DuoFX makes no network requests at all — not for licensing, not for updates, not for
          anything. You can verify that yourself in the source.
        </p>
      </div>
    </section>
  );
}

function Details() {
  return (
    <Section eyebrow="Details" title="Built like a native app, because it is one.">
      <dl className="mt-14 grid gap-x-10 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
        {details.map((item) => (
          <div key={item.title}>
            <dt className="text-[15px] font-semibold">{item.title}</dt>
            <dd className="mt-2 text-sm leading-relaxed text-muted text-pretty">{item.body}</dd>
          </div>
        ))}
      </dl>
    </Section>
  );
}

function Install() {
  return (
    <section id="install" className="scroll-mt-24 px-6 py-24">
      <div className="mx-auto max-w-xl text-center">
        <p className="text-sm font-medium tracking-[0.18em] text-accent uppercase">Install</p>
        <h2 className="mt-4 text-4xl font-semibold tracking-tight sm:text-5xl">
          Free and open source.
        </h2>
        <p className="mt-5 leading-relaxed text-muted text-pretty">
          DuoFX is {site.license} licensed. No purchase, no license key, no account. Install it with
          Homebrew, or download the DMG from GitHub and drag it to Applications.
        </p>

        <div className="mt-10">
          <InstallCommand command={site.brewCommand} />
        </div>

        <div className="mt-6 flex flex-col gap-3 sm:flex-row">
          <a
            href={site.releasesUrl}
            className="w-full rounded-full bg-accent px-7 py-3.5 text-[15px] font-semibold text-accent-fg transition-opacity hover:opacity-90"
          >
            Download the DMG
          </a>
          <a
            href={site.repoUrl}
            className="w-full rounded-full border border-line bg-surface px-7 py-3.5 text-[15px] font-medium text-body transition-colors hover:border-muted/40"
          >
            View the source
          </a>
        </div>
        <p className="mt-4 text-xs text-muted">{site.requirements}</p>

        <div className="mt-8 rounded-2xl border border-line bg-surface-2 p-6 text-left">
          <p className="text-sm font-medium">First launch needs one extra step</p>
          <p className="mt-2 text-sm leading-relaxed text-muted text-pretty">
            DuoFX is not notarized yet, so macOS blocks the first double-click and says the app
            &ldquo;is damaged&rdquo;. It is not. That is Gatekeeper declining an un-notarized app.
            Right-click DuoFX in Applications, choose <strong className="text-body">Open</strong>,
            and confirm. Only the first launch needs it.
          </p>
        </div>

        <div className="mt-12 rounded-3xl border border-line bg-surface p-8 text-left">
          <ul className="space-y-3.5 text-[15px]">
            {[
              "Every animation, unlocked. There is no paid tier",
              "No account, no telemetry, no network requests at all",
              "Readable source you can audit, fork, and build yourself",
              "Delete it by dragging to the Trash. Nothing else is installed",
            ].map((line) => (
              <li key={line} className="flex gap-3">
                <svg
                  aria-hidden
                  viewBox="0 0 20 20"
                  fill="none"
                  className="mt-0.5 size-5 shrink-0 text-accent"
                  stroke="currentColor"
                  strokeWidth="1.75"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="m4.5 10.5 3.5 3.5 7.5-8" />
                </svg>
                <span className="text-muted">{line}</span>
              </li>
            ))}
          </ul>
          <p className="mt-7 border-t border-line pt-6 text-sm leading-relaxed text-muted text-pretty">
            DuoFX is built and maintained in spare time. If it earns a place in your menu bar,{" "}
            <a
              href={site.sponsorUrl}
              className="font-medium text-body underline decoration-line underline-offset-4 transition-colors hover:decoration-accent"
            >
              sponsoring the project
            </a>{" "}
            keeps it moving. Entirely optional, and it changes nothing about the app.
          </p>
        </div>
      </div>
    </section>
  );
}

function Requirements() {
  return (
    <section className="px-6 pb-24">
      <div className="mx-auto max-w-3xl border-t border-line pt-12">
        <h2 className="text-lg font-semibold">Before you install</h2>
        <dl className="mt-6 space-y-5 text-sm leading-relaxed">
          <div>
            <dt className="font-medium">Which Macs does it run on?</dt>
            <dd className="mt-1 text-muted text-pretty">
              macOS 14 Sonoma or later on Apple silicon. The lid animation needs a MacBook; on a
              desktop Mac you can still drive the effect manually.
            </dd>
          </div>
          <div>
            <dt className="font-medium">Does the lid sensor work on every MacBook?</dt>
            <dd className="mt-1 text-muted text-pretty">
              Sensor availability is model-dependent, since Apple does not document the interface.
              DuoFX reports exactly what it finds in Settings, and manual control works everywhere.
            </dd>
          </div>
          <div>
            <dt className="font-medium">Why does it ask for Screen Recording?</dt>
            <dd className="mt-1 text-muted text-pretty">
              To blur your real desktop, DuoFX has to read it, and macOS gates that behind the
              Screen Recording permission. You can try every animation before deciding: the bundled
              sample desktop and the whole Settings preview work with nothing granted.
            </dd>
          </div>
          <div>
            <dt className="font-medium">
              The macOS prompt mentions system audio. Does DuoFX record audio?
            </dt>
            <dd className="mt-1 text-muted text-pretty">
              No. That prompt is written for the whole capture API, not for this app, which is why
              it mentions audio and &ldquo;bypassing the private window picker&rdquo;. DuoFX sets{" "}
              <code className="font-mono text-[0.92em] text-body">capturesAudio = false</code> and{" "}
              <code className="font-mono text-[0.92em] text-body">showsCursor = false</code>, and
              excludes its own windows from capture. Bypassing the picker simply means it reads the
              display continuously instead of asking you to re-pick a window every time, which is
              what lets the animation follow your lid. The source is public if you want to check.
            </dd>
          </div>
        </dl>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-line px-6 py-10">
      <div className="mx-auto flex max-w-6xl flex-col gap-4 text-sm text-muted sm:flex-row sm:items-center sm:justify-between">
        <p>
          © {new Date().getFullYear()}{" "}
          <a href={site.author.url} className="transition-colors hover:text-body">
            {site.author.name}
          </a>
          . Released under {site.license} on{" "}
          <a href={site.repoUrl} className="transition-colors hover:text-body">
            GitHub
          </a>
          .
        </p>
        <p className="text-xs">
          Contains code from LidAngleSensor (Apache-2.0) and iphone-duo (MIT).
        </p>
      </div>
    </footer>
  );
}

function Section({
  id,
  eyebrow,
  title,
  lead,
  children,
}: {
  id?: string;
  eyebrow: string;
  title: string;
  lead?: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="scroll-mt-24 px-6 py-24">
      <div className="mx-auto max-w-6xl">
        <p className="text-sm font-medium tracking-[0.18em] text-accent uppercase">{eyebrow}</p>
        <h2 className="mt-4 max-w-3xl text-4xl font-semibold tracking-tight text-balance sm:text-5xl">
          {title}
        </h2>
        {lead ? (
          <p className="mt-5 max-w-2xl leading-relaxed text-muted text-pretty">{lead}</p>
        ) : null}
        {children}
      </div>
    </section>
  );
}

// Desktop captures are 4:3; the settings window is its own shape, so each shot
// declares the size of the file it points at rather than being stretched to fit.
function Shot({
  src,
  alt,
  priority,
  width = 1600,
  height = 1200,
}: {
  src: string;
  alt: string;
  priority?: boolean;
  width?: number;
  height?: number;
}) {
  return (
    <div className="overflow-hidden rounded-2xl border border-line bg-surface-2 shadow-2xl shadow-shot-shadow">
      <Image
        src={src}
        alt={alt}
        width={width}
        height={height}
        priority={priority}
        sizes="(min-width: 1024px) 60rem, 100vw"
        className="w-full"
      />
    </div>
  );
}
