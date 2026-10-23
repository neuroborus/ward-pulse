# Commit Message Draft

Read before drafting a message through [finalization](../SKILL.md#8-commit-message-draft).

Draft commit messages in Conventional Commits form:

```text
type(scope): imperative summary
```

Rules:

- Prefer a small single-line message with no body. A subject line alone is the default and the preferred form; do not append details, rationale, or file lists just because they exist.
- Use `type(scope):` with a lowercase type and a short scope. Do not draft bare subjects such as `docs: …` when a scope applies.
- Keep the subject imperative, about 72 characters or fewer, and focused on why the change lands.
- Add a body only when the change is genuinely unclear without it. Treat a body as the exception, not the habit.
- Do not insert line breaks without a reason. Write each body paragraph as one single line and let the git client wrap it; never hard-wrap a sentence across several lines.
- Use a line break only to separate the subject from the body, to separate paragraphs, or to list items.
- Match recent `git log` style. Prefer existing scopes over inventing new ones.

Common types:

| Type | Use for |
| --- | --- |
| `feat` | user-visible capability or contract addition |
| `fix` | bug or incorrect behavior correction |
| `chore` | planning, maintenance, tooling, or non-user-facing docs/process updates |
| `docs` | documentation-only product/site prose when `chore(docs)` is too weak a fit |
| `test` | tests only |
| `ci` | GitHub Actions or check wiring |
| `refactor` | internal restructuring without behavior change |

Common scopes:

| Scope | Owns |
| --- | --- |
| `docs` | `docs/`, Vocs site, planning, provider/security/release notes |
| `core` | Rust domain crates |
| `providers` | provider adapters and contracts spanning providers |
| `openai` / `codex` / `claude` / `cursor` | one provider family |
| `phone` | Flutter phone shell |
| `wear` | Wear OS shell |
| `watchface` | WFF package |
| `sync` | phone-to-watch transport |
| `design` | OpenPencil sources and brand exports |
| `agents` | `.agents/skills/` and agent workflow |
| `android` | shared Android harness or toolchain notes |

Preferred examples, single line and no body:

```text
chore(docs): plan adaptive provider UI, polling, and watch rings
feat(providers): add on-device Codex usage reporting
fix(wear): sync live provider data to watch surfaces
chore(agents): document conventional commit drafting
```

When a body is genuinely required, keep it on one line:

```text
chore(docs): plan adaptive provider UI, polling, and watch rings

Record the dual plan/platform model and phases 9–13, and set the global refresh floor to 5–60 minutes.
```
