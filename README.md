# commit-enhancer.nvim

AI-powered Neovim plugin to **enhance git commit messages** using OpenAI's Chat API.

---

## ✨ Features

- Enhance git commit messages using AI (OpenAI Chat API)
- Supports both **characterwise (v)** and **linewise (V)** visual selections
- Lazy-loaded only on `gitcommit` filetype
- Reads user-defined prompt template file (used as `system` message)
- Reads selected commit message (as `user` message)
- Shows a **loading floating window** during API call
- Async, non-blocking HTTP requests (uses `plenary.nvim`)
- Shows AI-enhanced commit message in a **readonly vertical split**
- Interactive prompt:
  - ✅ Yes, replace original
  - ❌ No, reject
  - ✏️ I want to modify manually
- Error handling for:
  - Missing template
  - Missing API key
  - API call failures
  - Empty or malformed API responses

---

## 🛠️ Requirements

- Neovim 0.9+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- OpenAI API key set as `$OPENAI_API_KEY`

---

## 📦 Installation (lazy.nvim example)

```lua
{
  'kansetsu7/commit-enhancer.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  ft = 'gitcommit',
  config = function()
    require('commit-enhancer').setup({
      model = 'gpt-4',
      prompt_template_path = vim.fn.expand('~/.config/prompt/commit-msg-enhance.txt'),
    })
  end,
}
```

---

## ⚙️ Setup

```lua
require('commit-enhancer').setup({
  model = 'gpt-4',
  prompt_template_path = vim.fn.expand('~/.config/prompt/commit-msg-enhance.txt'),
})
```

- **`model`**: OpenAI model name (e.g., `gpt-4`, `gpt-3.5-turbo`)
- **`prompt_template_path`**: Path to your prompt template file

Your OpenAI API key must be set via:

```bash
export OPENAI_API_KEY=sk-...
```

---

## ✏️ Usage

1. Start a commit (`git commit` → Neovim opens `.git/COMMIT_EDITMSG`)
2. Visually select your commit message text (use `v` or `V`)
3. Press `<leader>ce`
4. Plugin will:
   - Load your template as OpenAI `system` role
   - Send selected text as `user` role
   - Call OpenAI API (async)
   - Show a loading floating window while waiting
   - Display AI-enhanced commit in a readonly vertical split
   - Prompt you to Accept / Reject / Modify
5. Accepting will **replace the originally selected text**, safely handling both linewise and characterwise selections.

---

## ✅ Example Prompt Template

Contents of your `commit-msg-enhance.txt`:

```
You are an expert software engineer. Rewrite the following commit message to follow Conventional Commits style with clear, concise language.
```

---

## ✅ What's New

- Supports both **`v` (charwise)** and **`V` (linewise)** selections
- Async API request with **loading floating window**
- Prevents multiple concurrent requests
- Reuses AI preview split window
- Better error handling

---

## ✅ License

MIT

