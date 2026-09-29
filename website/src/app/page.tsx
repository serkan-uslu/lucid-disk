import Image from "next/image";
import styles from "./page.module.css";

const github = "https://github.com/serkan-uslu/lucid-disk";
const download = `${github}/releases/latest/download/LucidDisk.dmg`;
const releases = `${github}/releases/latest`;
const mcpDocs = `${github}/blob/main/mcp/README.md`;

type Shot = { src: string; width: number; height: number; alt: string };

const shots = {
  overview: {
    src: "/shots/overview.webp",
    width: 2000,
    height: 1248,
    alt: "Lucid Disk showing a folder as an interactive sunburst map with a sorted file list",
  },
  space: {
    src: "/shots/space.webp",
    width: 2000,
    height: 1975,
    alt: "Space breakdown explaining used space: scanned files, macOS volumes, and space a scan cannot see",
  },
  batch: {
    src: "/shots/batch.webp",
    width: 2000,
    height: 1248,
    alt: "Four files selected and added to the review queue with a Move All to Trash action",
  },
  inspector: {
    src: "/shots/inspector.webp",
    width: 2000,
    height: 1248,
    alt: "An unfamiliar large file selected in Lucid Disk with its size, warning, review action and optional Ask AI control",
  },
} satisfies Record<string, Shot>;

const showcase = [
  {
    id: "map",
    eyebrow: "Find large files",
    title: "See what is using the most space.",
    copy: "Scan your Mac or any drive and explore the biggest folders first. Open a branch of the live map, search the whole scan, and preview a file with Quick Look before you act.",
    points: [
      "Allocated and logical sizes, hard links counted once",
      "Search every file in the scan, sort by size, name or date",
      "Scans reopen instantly — the last one is saved on your Mac",
    ],
    shot: shots.overview,
  },
  {
    id: "system-data",
    eyebrow: "Space breakdown",
    title: "Finally: what is “System Data”?",
    copy: "After a whole-disk scan, Lucid Disk breaks down the gap between visible files and the space macOS reports as used — including volumes, snapshots and estimates a normal scan cannot see.",
    points: [
      "Preboot, Recovery, swap and update volumes, named",
      "Spotlight index, snapshots and APFS metadata the scan cannot see",
      "Purgeable space and folders that need Full Disk Access",
    ],
    shot: shots.space,
  },
  {
    id: "review",
    eyebrow: "Review",
    title: "Review every item before it moves.",
    copy: "Lucid Disk never cleans up on its own. Add only the items you choose to the review queue, confirm them together, and get one last safety check before anything moves to the Trash.",
    points: [
      "Protected system locations are always blocked",
      "Sensitive data needs a stronger confirmation",
      "Trash only — no permanent erase",
    ],
    shot: shots.batch,
  },
] as const;

const providers = ["Apple on-device", "Ollama", "Claude API", "Rules only"] as const;

const extras = [
  ["Universal", "Native Swift app for Apple silicon and Intel, macOS 14 or later."],
  ["Keyboard first", "⌘O, ⌘R, ⌘F, ⌘←, Space for Quick Look, ⌘-click to multi-select."],
  ["Accessible", "VoiceOver labels on the chart and every control."],
  ["Honest numbers", "Estimates and incomplete scans are labeled, never hidden."],
  ["Private", "No accounts, no telemetry, no analytics. Scans stay on your Mac."],
  ["Open source", "Apache 2.0. Audit the safety rules yourself."],
] as const;

const principles = [
  "No accounts, telemetry or analytics",
  "Scans and saved results stay on your Mac",
  "Network AI receives metadata only after you ask",
  "AI explains; safety rules decide",
  "No automatic cleanup, no permanent delete",
  "Protected system paths stay blocked",
];

const faq = [
  [
    "Is Lucid Disk really free?",
    "Yes. Everything on this page is free and open source under the Apache 2.0 license. A paid Pro edition with extra tools is planned; it will never take away free features or safety checks.",
  ],
  [
    "Can it delete my files by accident?",
    "Lucid Disk never acts on its own and never empties the Trash. Only items you add to the review queue and confirm can be moved, and each one is checked again immediately before the move. Protected system locations remain blocked.",
  ],
  [
    "Does the AI read my files?",
    "No. Ask AI uses metadata such as name, path, size, type, dates and the matched safety rule — never file contents, and only after you press the button. Apple on-device and rules-only processing stay on your Mac. Ollama stays local when its server runs on this Mac; a remote Ollama server receives that metadata. Claude is opt-in and requires your own API key.",
  ],
  [
    "Does Ollama keep everything on my Mac?",
    "With the default local Ollama address, the selected item's metadata stays on this Mac. If you point Lucid Disk at Ollama on another machine, that server receives it. File contents are never read or sent.",
  ],
  [
    "What is the MCP server?",
    "An optional companion that lets assistants such as Claude Code, Claude Desktop or Codex inspect disk metadata through read-only tools. It cannot delete, move or change files. Returned metadata can be processed by the model or service used by your MCP client.",
  ],
  [
    "Why does it ask for Full Disk Access?",
    "It doesn't have to. Without it, macOS hides some folders and Lucid Disk labels those parts of the scan as incomplete. Granting access in System Settings lets the scan measure them.",
  ],
  [
    "Which Macs are supported?",
    "Any Mac with macOS 14 Sonoma or later, Apple silicon or Intel. On-device AI needs macOS 26 with Apple Intelligence; Ollama and rules work everywhere.",
  ],
] as const;

function GitHubIcon() {
  return (
    <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24">
      <path
        fill="currentColor"
        d="M12 .8a11.4 11.4 0 0 0-3.6 22.2c.6.1.8-.2.8-.5v-2c-3.3.7-4-1.4-4-1.4-.5-1.4-1.3-1.7-1.3-1.7-1.1-.8.1-.8.1-.8 1.2.1 1.9 1.3 1.9 1.3 1.1 1.9 2.9 1.4 3.5 1.1.1-.8.4-1.4.8-1.7-2.7-.3-5.5-1.3-5.5-5.7 0-1.3.4-2.3 1.2-3.1-.1-.3-.5-1.6.1-3.1 0 0 1-.3 3.1 1.2a10.8 10.8 0 0 1 5.7 0c2.2-1.5 3.2-1.2 3.2-1.2.6 1.5.2 2.8.1 3.1.8.8 1.2 1.8 1.2 3.1 0 4.4-2.8 5.4-5.5 5.7.4.4.8 1.1.8 2.2v3.2c0 .3.2.6.8.5A11.4 11.4 0 0 0 12 .8Z"
      />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg aria-hidden="true" width="17" height="17" viewBox="0 0 24 24">
      <path
        fill="currentColor"
        d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.8-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.6-4.1ZM13.9 5c.7-.8 1.2-2 1-3.1-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.9-1 3 1.1.1 2.2-.6 2.9-1.4Z"
      />
    </svg>
  );
}

function Screenshot({ shot, priority = false }: { shot: Shot; priority?: boolean }) {
  return (
    <Image
      className={styles.shot}
      src={shot.src}
      width={shot.width}
      height={shot.height}
      alt={shot.alt}
      sizes="(max-width: 980px) 100vw, 620px"
      priority={priority}
    />
  );
}

function ShowcaseSection({
  item,
  flip = false,
  priority = false,
}: {
  item: (typeof showcase)[number];
  flip?: boolean;
  priority?: boolean;
}) {
  return (
    <section className={`${styles.showcase} ${flip ? styles.flip : ""}`} id={item.id}>
      <div className={styles.showcaseCopy}>
        <p className={styles.eyebrow}>{item.eyebrow}</p>
        <h2>{item.title}</h2>
        <p className={styles.body}>{item.copy}</p>
        <ul className={styles.points}>
          {item.points.map((point) => (
            <li key={point}>{point}</li>
          ))}
        </ul>
      </div>
      <div className={styles.showcaseMedia}>
        <Screenshot shot={item.shot} priority={priority} />
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <main>
      <header className={styles.header}>
        <a className={styles.brand} href="#top" aria-label="Lucid Disk home">
          <Image src="/brand/logo.webp" alt="" width={34} height={34} priority />
          <span>Lucid Disk</span>
        </a>
        <nav className={styles.nav} aria-label="Primary">
          <a href="#demo">How it works</a>
          <a href="#map">Features</a>
          <a href="#privacy">Privacy</a>
          <a href="#faq">FAQ</a>
        </nav>
        <div className={styles.headerActions}>
          <a
            className={styles.iconButton}
            href={github}
            target="_blank"
            rel="noreferrer"
            aria-label="Lucid Disk on GitHub"
          >
            <GitHubIcon />
          </a>
          <a className={styles.smallCta} href={download}>
            Download free
          </a>
        </div>
      </header>

      <section className={styles.hero} id="top">
        <div className={styles.heroGlow} aria-hidden="true" />
        <div className={styles.heroCopy}>
          <span className={styles.pill}>
            <span className={styles.pillDot} /> Free &amp; open source for macOS
          </span>
          <h1>
            Find what&apos;s taking up space on your Mac.
            <span className={styles.gradientText}>
              Understand it before you remove it.
            </span>
          </h1>
          <p className={styles.lede}>
            Explore large files and folders, make sense of macOS storage, and get
            optional AI explanations for anything unfamiliar. Lucid Disk moves only what
            you select and confirm to the Trash.
          </p>
          <div className={styles.heroActions}>
            <a className={styles.primary} href={download}>
              <AppleIcon /> Download free for Mac
            </a>
            <a className={styles.secondary} href="#demo">
              <span aria-hidden="true">▶</span> Watch the 30-second demo
            </a>
          </div>
          <p className={styles.meta}>
            Free · macOS 14+ · Apple silicon &amp; Intel · No account required
          </p>
          <a
            className={styles.sourceLink}
            href={github}
            target="_blank"
            rel="noreferrer"
          >
            View the Apache 2.0 source on GitHub →
          </a>
        </div>
        <figure className={styles.videoFrame} id="demo">
          <video
            className={styles.video}
            src="/media/lucid-disk-promo.mp4"
            poster="/media/promo-poster.jpg"
            autoPlay
            muted
            loop
            playsInline
            controls
            preload="metadata"
            aria-label="30-second tour of Lucid Disk: the disk map, review queue, Ask AI and the MCP server"
          />
          <figcaption className={styles.videoCaption}>
            A 30-second tour of the disk map, explanations and review queue. Turn sound
            on for Glassy Pulse.
          </figcaption>
        </figure>
      </section>

      <section className={styles.strip} aria-label="Highlights">
        <span>Find the space hogs</span>
        <span>Explain System Data</span>
        <span>Understand unfamiliar folders</span>
        <span>Review before Trash</span>
        <span>Free &amp; open source</span>
      </section>

      <ShowcaseSection item={showcase[0]} priority />
      <ShowcaseSection item={showcase[1]} flip />

      <section className={styles.feature} id="ai">
        <div className={styles.featureHead}>
          <p className={styles.eyebrow}>Understand before you act</p>
          <h2>
            Know what a folder is.{" "}
            <span className={styles.gradientText}>Then decide.</span>
          </h2>
          <p className={styles.body}>
            Select something unfamiliar to see its related app and fixed safety verdict,
            then optionally ask AI for a probable-purpose explanation. File contents
            stay unread, and deterministic safety rules — not AI — keep the final word.
          </p>
        </div>
        <div className={`${styles.featureGrid} ${styles.insightGrid}`}>
          <div className={styles.insightStory}>
            <ol className={styles.storySteps}>
              <li>
                <span>1</span>
                <div>
                  <strong>Spot something unfamiliar</strong>
                  <p>Select a large folder or file from the map or list.</p>
                </div>
              </li>
              <li>
                <span>2</span>
                <div>
                  <strong>Get the missing context</strong>
                  <p>
                    Ask for its probable purpose without reading the file&apos;s
                    contents.
                  </p>
                </div>
              </li>
              <li>
                <span>3</span>
                <div>
                  <strong>Make the call yourself</strong>
                  <p>
                    Review the fixed safety verdict before adding anything to the queue.
                  </p>
                </div>
              </li>
            </ol>
            <div className={styles.answer}>
              <span className={styles.answerLabel}>✦ Ask AI · DerivedData · 54 GB</span>
              <p>
                Xcode&apos;s build products and indexes for projects you have opened.
                Xcode recreates them the next time those projects build.
              </p>
              <span className={styles.answerFoot}>
                Probable purpose explained · safety verdict stays “Rebuildable”
              </span>
            </div>
            <div className={styles.providerSupport}>
              <span>Choose how explanations run:</span>
              <div className={styles.providerChips}>
                {providers.map((provider) => (
                  <span key={provider}>{provider}</span>
                ))}
              </div>
              <small>
                Apple on-device requires macOS 26 with Apple Intelligence. Ollama
                remains on this Mac only when its server runs locally. Network providers
                receive metadata only after you press Ask AI.
              </small>
            </div>
          </div>
          <div className={styles.featureMedia}>
            <Screenshot shot={shots.inspector} />
          </div>
        </div>
      </section>

      <ShowcaseSection item={showcase[2]} flip />

      <section className={styles.extras} aria-label="More features">
        {extras.map(([title, copy]) => (
          <div className={styles.extra} key={title}>
            <strong>{title}</strong>
            <p>{copy}</p>
          </div>
        ))}
      </section>

      <section className={styles.privacy} id="privacy">
        <div>
          <p className={styles.eyebrow}>Privacy &amp; safety</p>
          <h2>Your disk stays yours.</h2>
          <p className={styles.body}>
            Lucid Disk scans locally and keeps scan results on this Mac. Ask AI sends
            selected-item metadata to a configured network provider only when you press
            the button. Whichever provider you choose, deterministic safety rules decide
            what can move to the Trash.
          </p>
          <a
            className={styles.textLink}
            href={`${github}/blob/main/PRIVACY.md`}
            target="_blank"
            rel="noreferrer"
          >
            Read the privacy policy →
          </a>
        </div>
        <ul className={styles.principles}>
          {principles.map((principle) => (
            <li key={principle}>
              <span aria-hidden="true">✓</span>
              {principle}
            </li>
          ))}
        </ul>
      </section>

      <section className={styles.developer} id="mcp">
        <div className={styles.developerCopy}>
          <p className={styles.eyebrow}>For developers</p>
          <h2>Connect your assistant to disk analysis.</h2>
          <p className={styles.body}>
            The optional MCP companion gives Claude Code, Claude Desktop or Codex
            read-only disk context backed by the same path-based risk rules as the app.
          </p>
          <a
            className={styles.secondary}
            href={mcpDocs}
            target="_blank"
            rel="noreferrer"
          >
            Developer setup &amp; tool reference →
          </a>
        </div>
        <ul className={styles.developerPoints}>
          <li>
            <strong>Read-only by design</strong>
            <span>No delete, move or write tools.</span>
          </li>
          <li>
            <strong>Entirely optional</strong>
            <span>You choose whether to install and enable the companion.</span>
          </li>
          <li>
            <strong>A clear disclosure boundary</strong>
            <span>
              Returned metadata can be processed by your client&apos;s model or service.
            </span>
          </li>
        </ul>
      </section>

      <section className={styles.faq} id="faq">
        <p className={styles.eyebrow}>FAQ</p>
        <h2>Questions, answered.</h2>
        <div className={styles.faqList}>
          {faq.map(([question, answer]) => (
            <details key={question}>
              <summary>{question}</summary>
              <p>{answer}</p>
            </details>
          ))}
        </div>
      </section>

      <section className={styles.cta}>
        <Image src="/brand/logo.webp" alt="" width={96} height={96} />
        <p className={styles.brandPromise}>See your disk. Keep your judgment.</p>
        <h2>Make space with the context to decide.</h2>
        <p className={styles.body}>Free, open source, and ready without an account.</p>
        <div className={styles.heroActions}>
          <a className={styles.primary} href={download}>
            <AppleIcon /> Download free for Mac
          </a>
          <a className={styles.secondary} href="#demo">
            <span aria-hidden="true">▶</span> Watch the demo
          </a>
        </div>
        <div className={styles.supportLinks}>
          <a href={github} target="_blank" rel="noreferrer">
            View source
          </a>
          <a href={releases} target="_blank" rel="noreferrer">
            Release notes and checksums
          </a>
        </div>
      </section>

      <footer className={styles.footer}>
        <div className={styles.brand}>
          <Image src="/brand/logo.webp" alt="" width={26} height={26} />
          <span>Lucid Disk</span>
        </div>
        <p>Open-source disk clarity for macOS.</p>
        <nav aria-label="Footer">
          <a href={`${github}/blob/main/LICENSE`}>License</a>
          <a href={`${github}/blob/main/PRIVACY.md`}>Privacy</a>
          <a href={`${github}/blob/main/SECURITY.md`}>Security</a>
          <a href={`${github}/blob/main/ROADMAP.md`}>Roadmap</a>
        </nav>
      </footer>
    </main>
  );
}
