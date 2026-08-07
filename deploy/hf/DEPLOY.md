# Deploying the demo to Hugging Face Spaces

One-time setup to publish the live demo. Everything is prebuilt in the repo
(`Dockerfile`, `start.sh`, `requirements.txt`); these steps push it to a Space.

## 1. Create the Space
1. Go to https://huggingface.co/new-space
2. **Owner:** your account · **Space name:** `adaptive-rag`
3. **SDK:** select **Docker** → **Blank**
4. **Hardware:** *CPU basic* (free) · **Visibility:** Public
5. Create the Space. Note its git URL, e.g. `https://huggingface.co/spaces/<you>/adaptive-rag`

## 2. Push the project to the Space
From the project root (this repo):

```bash
# Add the Space as a second remote (replace <you>)
git remote add space https://huggingface.co/spaces/<you>/adaptive-rag

# The vector store is normally gitignored — ship it to the Space via Git LFS
git lfs install
git lfs track "*.duckdb"

# Use the Space's README (with the required HF frontmatter) as README.md on the
# Space branch only — do this on a dedicated branch so GitHub's README is untouched.
git checkout -b space
cp deploy/hf/README.md README.md
git add README.md .gitattributes
git add -f rag.duckdb          # force past .gitignore
git commit -m "deploy: hugging face space"

# Push the space branch to the Space's main branch
git push space space:main
```

When prompted, use your Hugging Face **username** and an **access token**
(create one at https://huggingface.co/settings/tokens — role: *write*) as the password.

## 3. Watch it build
- On the Space page, the **Building** log will show Ollama installing and the
  models being pulled (a few minutes the first time).
- When it flips to **Running**, your live URL is:
  `https://<you>-adaptive-rag.hf.space`

## 4. Link it from the GitHub README
Add a badge near the top of the main `README.md`:

```markdown
[![Live Demo](https://img.shields.io/badge/🤗%20Live%20Demo-Hugging%20Face-blue)](https://huggingface.co/spaces/<you>/adaptive-rag)
```

## Notes
- **Model:** hosted demo uses `qwen2.5:3b-instruct` (env `RAG_CHAT_MODEL`); local dev still uses 7b.
- **Cold starts:** free Spaces sleep after ~48h idle and take a few seconds to wake.
- **Updating:** re-run the `cp`/`commit`/`push space` steps on the `space` branch after changes.
