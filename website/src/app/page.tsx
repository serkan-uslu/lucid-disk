import Image from "next/image";
import styles from "./page.module.css";

const github = "https://github.com/serkan-uslu/lucid-disk";
const download = `${github}/releases/latest/download/LucidDisk.dmg`;
const releases = `${github}/releases/latest`;

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
  ai: {
    src: "/shots/ai.webp",
    width: 2000,
    height: 2034,
    alt: "AI settings with Apple on-device, Ollama, Claude API and rules-only providers",
  },
  mcp: {
    src: "/shots/mcp.webp",
    width: 2000,
    height: 2036,
    alt: "MCP settings listing five read-only tools and setup commands",
  },
} satisfies Record<string, Shot>;

const showcase = [
  {
    id: "map",
    eyebrow: "Map",
    title: "Every byte, at a glance.",
    copy: "Scan your Mac or any drive and explore it as a live sunburst. Click into folders, jump back from the center, search the whole scan, and preview anything with Quick Look.",
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
    copy: "After scanning a whole disk, Lucid Disk explains the gap between what a scan can see and what macOS reports as used — straight from macOS, with parts that add up exactly.",
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
    title: "You decide what goes.",
    copy: "Nothing is removed automatically. Select several items, queue them, and move them to the Trash with one confirmation. Every item is checked again right before it moves.",
    points: [
      "Protected system locations are always blocked",
      "Sensitive data needs a stronger confirmation",
      "Trash only — restore anything from Finder",
    ],
    shot: shots.batch,
  },
] as const;

const providers = [
  { name: "Apple on-device", note: "Default. Runs on your Mac.", tone: "private" },
  { name: "Ollama", note: "Any local model you run.", tone: "private" },
  { name: "Claude API", note: "Your key, opt-in only.", tone: "cloud" },
  { name: "Rules only", note: "No model at all.", tone: "private" },
] as const;

const tools = [
  [
    "summarize_known_locations",
    "Sizes of DerivedData, caches, logs, Downloads, Trash and more, with risk.",
  ],
  ["find_large_files", "The largest files below a folder, on one volume."],
  ["inventory_directory", "A folder's children ranked by allocated size."],
  ["assess_paths", "Size, accuracy and cleanup risk for up to 50 paths."],
  ["create_cleanup_plan", "Groups paths by risk, with blockers and questions."],
] as const;

const extras = [
  ["Universal", "Native Swift app for Apple silicon and Intel, macOS 14 or later."],
  ["Keyboard first", "⌘O, ⌘R, ⌘F, ⌘←, Space for Quick Look, ⌘-click to multi-select."],
  ["Accessible", "VoiceOver labels on the chart and every control."],
  ["Honest numbers", "Estimates and incomplete scans are labeled, never hidden."],
  ["Private", "No accounts, no telemetry, no analytics. Scans stay on your Mac."],
  ["Open source", "Apache 2.0. Audit the safety rules yourself."],
] as const;

const principles = [
  "No telemetry or analytics",
  "Nothing leaves your Mac unless you choose a cloud AI",
  "AI explains; safety rules decide",
  "No automatic cleanup, no permanent delete",
  "Protected system paths stay blocked",
  "MCP tools are read-only",
];

const faq = [
  [
    "Is Lucid Disk really free?",
    "Yes. Everything on this page is free and open source under the Apache 2.0 license. A paid Pro edition with extra tools is planned; it will never take away free features or safety checks.",
  ],
  [
    "Can it delete my files by accident?",
    "No. Lucid Disk never deletes anything on its own and never empties the Trash. Items move to the Trash only after you queue and confirm them, and each one is checked again just before it moves. Protected system locations are blocked.",
  ],
  [
    "Does the AI read my files?",
    "No. Ask AI sends metadata only — name, path, size, type, dates and the matched safety rule — and only when you press the button. With Apple's on-device model or Ollama nothing leaves your Mac. The Claude API is used only if you add your own key and allow it.",
  ],
  [
    "What is the MCP server?",
    "An optional companion that lets assistants like Claude Code, Claude Desktop or Codex look at your disk through five read-only tools. It cannot delete, move or change files. Settings → MCP shows the setup commands.",
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

export default function Home() {
  return (
    <main>
      <header className={styles.header}>
        <a className={styles.brand} href="#top" aria-label="Lucid Disk home">
          <Image src="/brand/logo.webp" alt="" width={34} height={34} priority />
          <span>Lucid Disk</span>
        </a>
        <nav className={styles.nav} aria-label="Primary">
          <a href="#map">Features</a>
          <a href="#ai">AI</a>
          <a href="#mcp">MCP</a>
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
            Download
          </a>
        </div>
      </header>

      <section className={styles.hero} id="top">
        <div className={styles.heroGlow} aria-hidden="true" />
        <div className={styles.heroCopy}>
          <a className={styles.pill} href={github} target="_blank" rel="noreferrer">
            <span className={styles.pillDot} /> Free &amp; open source for macOS
          </a>
          <h1>
            See your disk.
            <br />
            <span className={styles.gradientText}>Keep your judgment.</span>
          </h1>
          <p className={styles.lede}>
            Lucid Disk maps your storage, explains what “System Data” really is, and
            lets you ask AI what an unfamiliar folder is — then cleans up only what you
            approve.
          </p>
          <div className={styles.heroActions}>
            <a className={styles.primary} href={download}>
              <AppleIcon /> Download for Mac
            </a>
            <a
              className={styles.secondary}
              href={github}
              target="_blank"
              rel="noreferrer"
            >
              <GitHubIcon /> View source
            </a>
          </div>
          <p className={styles.meta}>
            Free · macOS 14+ · Apple silicon &amp; Intel · Apache 2.0
          </p>
        </div>
        <figure className={styles.videoFrame}>
          <video
            className={styles.video}
            src="/media/lucid-disk-promo.mp4"
            poster="/media/promo-poster.jpg"
            autoPlay
            muted
            loop
            playsInline
            preload="metadata"
            aria-label="30-second tour of Lucid Disk: the disk map, review queue, Ask AI and the MCP server"
          />
        </figure>
      </section>

      <section className={styles.strip} aria-label="Highlights">
        <span>Sunburst disk map</span>
        <span>System Data explained</span>
        <span>AI on your terms</span>
        <span>Read-only MCP</span>
        <span>Trash-only cleanup</span>
      </section>

      {showcase.map((item, index) => (
        <section
          className={`${styles.showcase} ${index % 2 ? styles.flip : ""}`}
          id={item.id}
          key={item.id}
        >
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
            <Screenshot shot={item.shot} priority={index === 0} />
          </div>
        </section>
      ))}

      <section className={styles.feature} id="ai">
        <div className={styles.featureHead}>
          <p className={styles.eyebrow}>Lucid Insight</p>
          <h2>
            AI that explains.{" "}
            <span className={styles.gradientText}>Never decides.</span>
          </h2>
          <p className={styles.body}>
            Select a folder you don&apos;t recognize and press Ask AI. You choose the
            model; the safety rules keep the final word. File contents are never read.
          </p>
        </div>
        <div className={styles.featureGrid}>
          <div className={styles.providerList}>
            {providers.map((provider) => (
              <div className={styles.provider} key={provider.name}>
                <div>
                  <strong>{provider.name}</strong>
                  <span>{provider.note}</span>
                </div>
                <em
                  className={
                    provider.tone === "cloud" ? styles.badgeCloud : styles.badgePrivate
                  }
                >
                  {provider.tone === "cloud" ? "Cloud · opt-in" : "Private"}
                </em>
              </div>
            ))}
            <div className={styles.answer}>
              <span className={styles.answerLabel}>✦ Ask AI · DerivedData · 54 GB</span>
              <p>
                Xcode&apos;s build products and index for projects you have opened.
                Xcode recreates it on the next build.
              </p>
              <span className={styles.answerFoot}>
                Ollama · local · risk stays “Rebuildable”
              </span>
            </div>
          </div>
          <div className={styles.featureMedia}>
            <Screenshot shot={shots.ai} />
          </div>
        </div>
      </section>

      <section className={styles.feature} id="mcp">
        <div className={styles.featureHead}>
          <p className={styles.eyebrow}>MCP server</p>
          <h2>
            Eyes for your assistant.{" "}
            <span className={styles.gradientText}>No hands.</span>
          </h2>
          <p className={styles.body}>
            An optional, read-only MCP server lets Claude Code, Claude Desktop or Codex
            answer “what&apos;s eating my disk?” with real numbers and the same safety
            rules as the app.
          </p>
        </div>
        <div className={styles.featureGrid}>
          <div className={styles.toolColumn}>
            <pre className={styles.terminal}>
              <code>
                <span className={styles.prompt}>$</span> claude mcp add luciddisk -- \
                {"\n"}
                {"    "}uv run --project ./mcp luciddisk-mcp
              </code>
            </pre>
            <ul className={styles.tools}>
              {tools.map(([name, copy]) => (
                <li key={name}>
                  <code>{name}</code>
                  <span>{copy}</span>
                </li>
              ))}
            </ul>
            <p className={styles.note}>
              No delete, move or write tools — by design. Your assistant asks before
              each call.
            </p>
          </div>
          <div className={styles.featureMedia}>
            <Screenshot shot={shots.mcp} />
          </div>
        </div>
      </section>

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
          <h2>The guardrails are the product.</h2>
          <p className={styles.body}>
            Lucid Disk scans on your Mac and keeps its results there. Deterministic
            safety rules decide what can be moved, whichever AI you pick — and every
            item is re-checked right before it goes to the Trash.
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
        <h2>Make space without losing context.</h2>
        <p className={styles.body}>Free, open source, and yours to inspect.</p>
        <div className={styles.heroActions}>
          <a className={styles.primary} href={download}>
            <AppleIcon /> Download for Mac
          </a>
          <a
            className={styles.secondary}
            href={github}
            target="_blank"
            rel="noreferrer"
          >
            <GitHubIcon /> Star on GitHub
          </a>
        </div>
        <a className={styles.textLink} href={releases} target="_blank" rel="noreferrer">
          Release notes and checksums →
        </a>
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
