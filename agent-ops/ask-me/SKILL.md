---
name: ask-me
description: Ask which skill or flow fits your situation. A router over the skills in this repo.
disable-model-invocation: true
---

# Ask Me

You don't remember every skill, so ask.

A **flow** is a path through the skills. The engineering work runs along one **main flow**, with **on-ramps** that merge onto it. The knowledge base has its own smaller flow. Everything else is standalone, or a vocabulary layer that runs underneath.

Route by **situation**, not by folder: first find the section below that matches where you are, then take the skill it names.

## The main flow: idea → ship

The route most engineering work travels. You have an idea and want it built.

1. **`/grill-with-docs`** — sharpen the idea by interview. Start here whenever you are **working in a working directory**: it's stateful, retaining what it learns in `CONTEXT.md` and ADRs. (No working directory? Use `/grill-me` — see Thinking. Both run the same `/grilling` primitive; `grill-with-docs` is the one that leaves a paper trail, which makes it the better of the two whenever a repo is there to leave it in.)
2. **Branch — can you settle every question in conversation?** If a question needs a runnable answer (state, business logic, a UI you have to see), detour through a prototype, bridged by **`/handoff`** in both directions (a prototype lives in its own directory, which is exactly what `/handoff` is for — see Phase boundaries):
   - **`/handoff`** out, then open a fresh session against that file,
   - **`/prototype`** to answer the question with throwaway code,
   - **`/handoff`** back what you learned, and reference it from the original idea thread.
3. **Branch — is this a multi-session build?**
   - **Yes** → **`/to-spec`** (turn the thread into a spec), then **`/to-tickets`** to split it into tracer-bullet tickets, each declaring its **blocking edges**. On a local tracker that's one file per ticket under `.scratch/<feature>/issues/`, worked blockers-first by hand; on a real tracker the edges become native blocking links, so any ticket whose blockers are done can be grabbed — kick off **`/implement`** per ticket, **`/clear`ing context between each one**. Each ticket is self-contained, so the last one's context is disposable.
   - **No** → **`/implement`** right here, in the same context window.

   Either way, **`/implement`** builds each issue by driving **`/tdd`** internally — one red-green slice at a time — then closes out by running **`/code-review`**, a two-axis review (Standards + Spec) of the diff, before committing. Reach for **`/tdd`** on its own when you just want to build a concrete behaviour test-first without a full spec, and **`/code-review`** on its own whenever you want to review a branch or PR against a fixed point.

### Context hygiene

Keep steps 1–3 in **one unbroken context window** — don't compact or clear until after `/to-tickets` — so the grilling, spec, and tickets all build on the same thinking. Each `/implement` then starts fresh, working from the ticket.

The limit on this is the **[smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone)**: the window (~150k tokens on state-of-the-art models) within which the model still reasons sharply. If a session approaches it before `/to-tickets`, don't push on degraded — `/compact` at the nearest phase boundary and carry on (see Phase boundaries).

## On-ramps

A starting situation that generates work, then merges onto the main flow.

- **Bugs and requests piling up** → **`/triage`**. It moves issues through triage roles and produces agent-ready issues, which **`/implement`** later picks up.

  Triage is only for issues **you didn't create** — bug reports, incoming feature requests, anything that arrives raw. Tickets that `/to-tickets` produced are already agent-ready, so **don't triage them**.

- **You've been using the product and want to report what you found** → **`/qa`**. A conversational QA session: you describe bugs in your own words, it explores the codebase in the background and files proper GitHub issues — which then enter **`/triage`** like any other incoming report.

- **Something's broken** → **`/diagnosing-bugs`**. For the hard ones: the bug that resists a first glance, the intermittent flake, the regression that crept in between two known-good states. It refuses to theorise until it has a **tight feedback loop** — one command that already goes red on *this* bug — then fixes with a regression test. Its post-mortem hands off to **`/improve-codebase-architecture`** when the real finding is that there's no good seam to lock the bug down.

- **A huge, foggy effort — a greenfield project or a huge feature build, too big for one session** → **`/wayfinder`**, the most cognitively demanding flow here. When the way from here to the destination isn't visible yet, it charts a **shared map** of **decision tickets** on the issue tracker and resolves them one at a time — producing **decisions, not deliverables** — until the fog is pushed back and the way is clear. Where **`/grill-with-docs`** sharpens an idea you can hold in one session, wayfinder is for the idea you can't — and it's slower and denser, so save it for exactly that, never a well-scoped feature.

  When the map clears, **it hands off, it doesn't build**: merge onto the main flow at **`/to-spec`**, which collapses the map's linked decisions into a buildable plan, then `/to-tickets` and `/implement` as usual. Looping the map straight into `/implement` skips that collapse and throws the linked detail away — go straight to `/implement` only when the effort turned out genuinely small.

## Codebase health

Not feature work — upkeep.

- **`/improve-codebase-architecture`** — run whenever you have a spare moment to keep the codebase good for agents to operate in. It surfaces **deepening opportunities**; picking one _generates an idea_ you can take into the main flow at `/grill-with-docs`. It's the survey that finds the candidates; **`/codebase-design`** (below) is the bench you design the chosen one on.
- **`/impeccable`** — everything frontend: design, critique, polish, accessibility, motion, typography, design systems. When the work is *how the UI looks and feels* rather than what it does, this is the specialist — reach for it directly instead of routing through the main flow.
- **`/git-worktree`** — run several agents in parallel on one repo without collisions: one worktree per task, made as complete as the main checkout, merged back and cleaned up. Reach for it whenever agents keep overwriting each other, or before fanning out `/implement` across tickets.

## Vocabulary underneath

Two model-invoked references that run *beneath* the other skills — each the single source of truth for its vocabulary. Reach for them directly when the **words**, not the process, are the problem; or let the skills above pull them in.

- **`/domain-modeling`** — sharpen the project's *domain* language: challenge a fuzzy term, resolve an overloaded word ("account" doing three jobs), record a hard-to-reverse decision as an ADR. It's the active discipline `/grill-with-docs` drives to keep `CONTEXT.md` a clean glossary.
- **`/codebase-design`** — the deep-module vocabulary (module, interface, depth, seam, adapter, leverage, locality) for designing a module's *shape*: a lot of behaviour behind a small interface at a clean seam. `/tdd` and `/improve-codebase-architecture` both speak it.

## Phase boundaries

A **phase** is a chunk of work inside a session — the grilling, the implementation, the QA. At the **boundary** between two of them you have five options, and picking between them is the fuzziest decision in this whole map:

- **Continue** — stay put. Costs nothing, loses nothing.
- **`/clear`** — empty the window, when nothing here matters to what's next.
- **`/handoff`** — write a portable markdown file. Narrow: only for a **new harness**, a **new directory**, a **colleague**, or forking a side task **mid-phase**. What it buys is portability.
- **Subagent** — send a tightly-scoped task to its own window and get a report back.
- **`/compact`** — compress this context and seed a fresh session with it. The **default**, at the bottom of the tree rather than the first reach.

Read [PHASE-BOUNDARIES.md](PHASE-BOUNDARIES.md) for the ordered tree — the five questions, the reasoning behind each branch, and why the primary-source cost makes **Continue** the one to rule out first. Make the decision **at** a boundary; mid-phase, continue or split the rest into subagents.

## Thinking

The grilling family — one interviewing primitive, several stances — plus the tools for answering what talking can't.

- **`/grilling`** — the interview primitive itself. It maps the design tree and works it in **rounds**: each round asks the whole **frontier** — every decision whose prerequisites are already settled — numbered, each with a recommended answer, then waits. Facts are the agent's job, dispatched to sub-agents rather than put to you; the **decisions** are yours. `/grill-me` and `/grill-with-docs` are the two named ways in, and `/triage`, `/wayfinder` and `/improve-codebase-architecture` all run it internally. Reach for it directly only when you want the interview with no wrapper around it.
- **`/grill-me`** — the same relentless interview as `/grill-with-docs`, but **stateless**: it saves nothing locally and builds no `CONTEXT.md`. Reach for it when you are **not working in a working directory** — sharpening a plan, a design, a piece of writing, anything with no repo under it. If you are in a working directory, use `/grill-with-docs` instead: it runs the same interview and leaves a paper trail, so it is strictly the better one.
- **`/prototype`** — a small, throwaway program that answers one design question: does this state model feel right, or what should this UI look like. Throwaway is a constraint on how the code is written, not a promise to destroy it: the answer folds into the real code, and the prototype itself is kept as a **primary source** on a `prototype/<name>` branch out of main, pointed at from the implementation issue. It's the detour in step 2 of the main flow, but reach for it any time a design question is hard to settle on paper.
- **`/to-questionnaire`** — when the thing blocking you isn't in your head or the codebase but in **someone else's**, this writes them a questionnaire to fill in. It's the inverse of `/grill-me`: instead of interviewing you about the subject, it interviews you about the **send** — who it's going to, what you need back — and aims the questions at the gap. What comes back is material for `/grill-with-docs` or `/to-spec`.
- **`/decisions`** — turn the interrogation around: ask the *agent* to list every choice it made during the current work that it's not confident about. Run it before trusting a long unsupervised stretch.

## Researching web informations

Delegating reading, and watching instead of reading.

- **`/research`** — delegate reading legwork to a **background agent**: it investigates a question against **primary sources**, then leaves a cited Markdown file in the repo. Keep working while it reads. The file it produces is something to take *into* the main flow at `/grill-with-docs` — research feeds the thinking, it doesn't replace it.
- **`/storm-research`** — the heavy sibling: five expert lenses, a contradiction map, an adversarial peer review, an HTML briefing. For topics where **multiple viewpoints and fact-checked claims** matter; overkill for a factual lookup — that's `/research`.
- **`/last30days`** — what people are *saying right now*: posts and engagement from Reddit, X, YouTube, Hacker News and the web over the last 30 days. Sentiment and chatter, where the other two chase primary sources.
- **`/watch`** — hand a video (URL or file) to the agent: it downloads it, extracts frames and transcript, then answers questions about what's in it.

## The knowledge-base flow

Its own small pipeline: raw documents in, linked knowledge out. Runs in order.

1. **Ingest** — pick the converter matching the source, each producing canonical agent-readable Markdown in `tmp_output/`: **`/ingest_docx`** (Word), **`/ingest_pptx`** (PowerPoint), **`/ingest_xlsx`** (Excel), **`/extract-pdf-pictures`** (PDFs of photos/scans, read by vision).
2. **`/classify_output`** — file the transcription into `docs/refs/for_agents/` and its original into `docs/refs/for_human/`, mirrored trees plus the `index.md` register.
3. **`/inject_into_knowledge_base`** — promote a classified document into `docs/kb/`: atomic linked pages, traced provenance, contradictions flagged, lint at zero.

For YouTube as a source, **`/channel-to-kb-ytdlp`** builds an OKF knowledge base from a whole channel (free, most reliable); `/channel-to-kb` (pytubefix) and `/channel-to-kb-supadata` (paid API) are the fallbacks when yt-dlp won't do.

## Learning

Stateful — both keep progress across sessions in the current directory.

- **`/teach`** — learn a concept over multiple sessions, using the current directory as a stateful workspace.
- **`/quiz`** — adaptive quiz on the ASAP corpus: failures come back fast, mastery spaces out. The testing half to `/teach`'s teaching.

## Explaining and recording

Getting what's in your head, or in the thread, onto durable paper.

- **`/mermaid-diagram`** — a diagram that **argues visually**, embedded as a ` ```mermaid ` block inside a markdown doc. The default: cheap, renders on GitHub.
- **`/excalidraw-diagram`** — the same visual-argument discipline as a standalone `.excalidraw` file, when the diagram *is* the deliverable or needs hand-editing after.
- **`/brain-to-docs`** — extract a project's vision, decisions and preferences from your head into README + ADRs through a Q&A loop. It's `/grill-with-docs`'s cousin aimed at *documentation* rather than a build.
- **`/remind`** — mid-conversation reset: rewrites the last response simpler and shorter, prefixed with a TLDR of the thread so far.
- **`/wait-what`** — the corrective for a message that didn't land. Use it mid-conversation, inside any other skill, and the agent re-pitches what it just said with the context you were missing, in plain English, using the `CONTEXT.md` vocabulary. It works after the fact; `/grill-with-docs` is the upfront cure, because a shared language agreed early is what stops the jargon arriving at all.

## Agents and the machine

Keeping the tooling itself in shape.

- **`/setup-help`** — walk through setting *anything* up, one step at a time, with the remaining steps listed after each response.
- **`/goal-loop`** — write effective instructions for a long-running autonomous `/goal` run (plan → act → test → review → iterate). Reach for it before kicking one off.
- **`/global-agent-guardrails`** — the shared denylist of catastrophic shell commands enforced across every coding agent on the machine. Use it to add patterns, wire in a new agent, or debug why a command was blocked.
- **`/anti-sleep`** — keep the machine awake (Windows from WSL) for a duration or while a process runs; survives agent-shell cleanup, unlike a plain background job. There is a script that is available and advised to used over anti-sleep.
- **`/writing-for-agents`** — reference for writing documents agents consume: skills, `AGENTS.md`, pointed-at docs. Including this one. Model-invoked, so the agent pulls it in by itself the moment you edit a skill.

## Precondition

**`/setup-matt-pocock-skills`** — run before your first engineering flow to configure the issue tracker, triage labels, and doc layout the engineering skills assume. Custom issue trackers also work. The other sections have no setup step.
