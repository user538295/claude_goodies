# Visual Formatting

How to present the challenge report (and any explanation around it). Use visual elements whenever they improve clarity — never force one where plain text is cleaner and faster to read.

## Pick the format that fits the content

| Content type | Preferred format |
|---|---|
| Comparisons / pros & cons | Table |
| Step-by-step processes / workflows | Numbered list or Mermaid flowchart |
| Relationships between concepts | Mermaid graph or diagram |
| Sequential phases / pipelines | Mermaid flowchart or sequence diagram |
| Key terms / definitions | Table, or bold term + definition |
| File/folder structures | Code block (tree format) |
| Code examples | Code block with language tag |
| Quick reference / cheat sheets | Table |
| Timelines or progressions | Mermaid timeline or table |

## Icons as visual anchors

Use icons/emojis for recurring concepts where they fit: ⚠️ warnings · ✅ best practices · ❌ anti-patterns · 💡 tips · 🔁 loops/cycles · 🧠 mental models.

Icons cost almost no space — use them freely as scanning anchors where they help. No need to be sparing.

The report's own section anchors (🔴 🟠 🟡 🔵 ⚪ 🔄 ✅ 📋) already follow this convention — keep them.

## Mermaid guidelines

- `flowchart LR` / `flowchart TD` for workflows and processes.
- `sequenceDiagram` for agent interactions or multi-step back-and-forth.
- `graph TD` for concept relationships and dependency trees.
- Keep each diagram focused — one concept per diagram, not everything at once.
- Use `<br>` for line breaks, never `\n`.
- Put every node label in double quotes.

Reach for a diagram when it earns its place — e.g. a failure cascade in a pre-mortem, a sequence showing where a race condition bites, a dependency tree behind an integration risk.

⚠️ **Don't overuse diagrams.** If a relationship fits in ~8 words of prose, write the prose — that's the clear case where plain text is simpler. A diagram earns its place only when branching, a cascade, or a cycle is the actual point; a two-node `A → B` graph is noise.

## Defaults and overrides

- Default to plain prose + bullet points for simple factual answers.
- **Each content type in its proper format** — file trees, code, and quoted commands go in a **code block** (with a language tag for code); a comparison goes in a table; a workflow in a numbered list. Match the format to the content, don't blur them.
- ⚠️ **The report wins on concerns.** A list of concerns, one after another, is always **bullets — never a code block** (code blocks are reserved for the actual code/trees/commands above). This overrides the table for concern items.
