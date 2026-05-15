---
description: Vault-first NotebookLM workflow — bundle vault notes as a source, prompt template, capture response. The source-grounded parallel to /research-deep (Perplexity-based, open-web).
category: research
triggers_en: ["notebooklm", "research grounded", "ground research in vault", "ask my notebook"]
---

Use the obsidian-second-brain skill. Execute `/notebooklm [topic]`:

1. Resolve the topic from the user's argument. If no topic, ask: "What topic for NotebookLM research?"

2. Run the Python command from the repo root (`~/Projects/personal/obsidian-second-brain/`):
   ```bash
   uv run -m scripts.research.notebooklm --topic "<topic>"
   ```

3. The script does the vault scan (same logic as `/research-deep` Phase 1), bundles the top 12 most relevant vault notes into a single markdown source file at `Research/NotebookLM/YYYY-MM-DD — <slug> — bundle.md`, prints a structured prompt template, and emits a `<<<NOTEBOOKLM_BUNDLE_PAYLOAD>>>` JSON block.

4. **Walk the user through the manual NotebookLM step** (NotebookLM has no full programmatic API as of 2026-01 — workspace-gated beta only). Surface these steps verbatim:
   - Open `notebooklm.google.com` (personal Google account).
   - Create a new notebook (or reuse one if relevant).
   - Click "Add source" -> "Paste text" and paste the contents of the bundle file the script printed.
   - Optionally add PDFs, web URLs, Google Docs as additional sources.
   - Paste the structured prompt the script printed into the NotebookLM chat box.
   - Wait for the response.
   - Copy the full response.

5. When the user pastes the response back into the chat, run:
   ```bash
   uv run -m scripts.research.notebooklm --save-response --topic "<topic>" --slug "<slug-from-payload>"
   ```
   Feed the user's response into stdin. The script writes the synthesis to `Research/NotebookLM/YYYY-MM-DD — <slug>.md` in AI-first format and emits a `<<<NOTEBOOKLM_PROPAGATION_PAYLOAD>>>` JSON block.

6. **After save: do the propagation step.** Same flow as `/research-deep`:
   - Parse the propagation payload.
   - Read the saved synthesis at `saved_note`.
   - Treat the synthesis as the "conversation context" input to `/obsidian-save`.
   - Run the standard `/obsidian-save` flow: spawn parallel subagents (People, Projects, Tasks, Decisions, Ideas) and update vault notes per any "Recommended next reads or angles" bullets if they map to entities or projects.
   - Link the new synthesis note from today's daily note.

7. Report back to the user: "Saved [[YYYY-MM-DD — <slug>]] to Research/NotebookLM/. Linked from today's daily note. Updated [[X]], created [[Y]]."

8. Plain English triggers: "notebooklm this", "ask my notebook about X", "ground a research on X using my vault", "source-grounded research on X".

9. When to choose `/notebooklm` over `/research-deep`:
   - `/research-deep` (Perplexity + Grok): when you want OPEN-WEB + X-discourse coverage. Cost: $0.20-0.80.
   - `/notebooklm` (Google source-grounded): when you want answers GROUNDED IN your own sources (vault, papers, PDFs). Cost: ~$0 (uses your free NotebookLM access).
   - Run both for a topic when the cost+time is worth it. The web view + the grounded view rarely contradict, and the contradictions are where the insight is.

10. If the user has no Google account or doesn't want to use NotebookLM, the bundle file alone is still useful — it's a curated context dump they can feed to any other tool.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md`. The saved synthesis at `Research/NotebookLM/YYYY-MM-DD — <slug>.md` follows the template baked into the script (preamble, frontmatter, vault-baseline links, response verbatim). Do not strip those.

**Why a bundle file:** NotebookLM accepts "paste text" sources up to roughly 500K characters per source. The bundle is small enough to paste, large enough to be useful (12 notes × ~2K chars = ~24K chars, well within limits). If a topic needs more, the user can paste multiple bundles or run the command multiple times with refined topics.

**Cost:** ~$0 in API spend. NotebookLM is free (with Google account). The vault scan is local. The script costs nothing.
