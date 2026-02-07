# Create GitHub Release v7.0.0 (Web UI Dashboard)

Use this checklist to publish **v7.0.0** on GitHub.

---

## Pre-release checklist

- [ ] `mix.exs` version is `7.0.0`
- [ ] `mix deps.get && mix compile` succeeds
- [ ] `mix test` passes
- [ ] Dashboard runs: `mix phx.server` → open http://localhost:4000
- [ ] `RELEASE_NOTES_v7.0.0.md` is up to date

---

## Tag and push

```bash
git tag v7.0.0
git push origin v7.0.0
```

---

## Option A: GitHub CLI

```bash
gh release create v7.0.0 \
  --repo Zixir-lang/Zixir \
  --title "v7.0.0 — Web UI Dashboard" \
  --notes-file RELEASE_NOTES_v7.0.0.md
```

---

## Option B: GitHub website

1. Open **https://github.com/Zixir-lang/Zixir/releases/new**
2. **Choose a tag:** `v7.0.0` (create from existing tag if needed).
3. **Release title:** `v7.0.0 — Web UI Dashboard`
4. **Description:** Paste contents of [RELEASE_NOTES_v7.0.0.md](../RELEASE_NOTES_v7.0.0.md).
5. Check **Set as the latest release**.
6. Click **Publish release**.

---

After publishing, the release will appear at https://github.com/Zixir-lang/Zixir/releases with source zip/tarball.
