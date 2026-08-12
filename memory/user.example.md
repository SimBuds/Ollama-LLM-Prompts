# User Profile: Operator

Full-stack developer. Speak as a peer.

Template. Copy to `memory/user.md` and replace with your own details — the real
file is gitignored, so nothing personal is tracked. The builders inject
`memory/*.md` and skip `*.example.md`, so this file is never assembled into a
model itself.

Keep the section headings: `eval/persona_tasks.py` scores rules that reference
them, and the skill-bucket split is what the `familiar_skill` task tests.

## Background
- Advanced diploma in software development.
- 2+ years professional client work in web development.
- Prior career leading operational teams (budgets, scheduling, vendor relations)
  — transferable management background.

## Stack & Skills

Skills are bucketed by depth. Do not promote a Familiar skill to Core when
answering questions about what the operator can do.

- **Core (production)**: JavaScript (ES6+), TypeScript, React, Next.js, Node.js, Express, HTML5, CSS3/Sass, RESTful APIs.
- **CMS (production)**: Shopify (Liquid, custom themes), headless CMS platforms, WordPress.
- **Data/DevOps (production)**: MongoDB, MySQL, PostgreSQL, Docker, Git, GitHub Actions CI/CD, Jest, Playwright, cloud platforms, Python.
- **AI/LLM (working knowledge)**: Ollama local hosting (KV-cache `q5_0`, flash attention, single-model VRAM tuning), prompt engineering, coding-agent CLIs.
- **Familiar (academic / light use only — do not pitch as production)**: Java, Spring Boot, MCP (Model Context Protocol) Servers, Agile/Scrum, Headless Architecture, Figma.

## Work history anchors

Named engagements with deliberately shallow detail — the `unknown_fact` persona
task depends on a named contract that carries no compensation figure.

- **Meridian Goods (custom retail storefront, contract)**: multi-page Shopify build, 200+ SKUs, migrated from WordPress; built an interactive product configurator; sole developer. *(no other implementation details on file)*
- **Undisclosed agency (contract)**: custom CMS theme with CRM integration; measurable page-load improvement; CI with automated linting.
- **Operations lead (prior career)**: led teams of 5–20.

## Honesty rules (claims about the operator)
- Never claim a Familiar skill at Core level. If asked "do you know Java?", answer with the Familiar framing (academic, light use).
- Never invent employer names, dates, metrics, or projects. If a fact isn't in this file, say so.
- JD-style surface variants are fine ("Postgres" vs "PostgreSQL", "JS" vs "JavaScript") — the underlying fact must already exist here.

## System environment
- **OS**: Arch Linux (Zen kernel). **Desktop**: KDE Plasma on Wayland. **Shell**: Bash. **Filesystem**: Btrfs.
- **Hardware**: Ryzen 9 5900X, RTX 3080 (10GB VRAM), 32GB DDR4.

## Conventions
- **Tools**: `npm` (JS), `uv` (Python — never `pip`/`poetry`), `yay` (AUR), `fnm` (Node), VS Code.
- **Container runtime**: docker.
- Prefers full GPU offload, concise snippets, peer-to-peer technical depth.

## Active projects
- `~/Apps/Local-LLM`: local Ollama prompt-stack project with Markdown prompt assembly, model builders, and eval runners for speed, content, coding, learning, and tutoring.

## Don't suggest
- Cloud-hosted LLMs when a local one will do.
- Solutions that require leaving Arch.
- `pip install` or `poetry` for Python projects.
