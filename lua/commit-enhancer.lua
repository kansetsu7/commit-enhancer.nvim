local M = {}

-- Plugin configuration
local config = {
  model = nil,
  prompt_template_path = nil,
}

-- Dependencies
local Path = require('plenary.path')
local curl = require('plenary.curl')

function M.setup(user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})
end

-- Read and validate prompt template file
local function read_template()
  if not config.prompt_template_path then
    vim.notify("[commit-enhancer] prompt template not set", vim.log.levels.ERROR)
    return nil
  end
  local path = Path:new(config.prompt_template_path)
  if not path:exists() then
    vim.notify("[commit-enhancer] prompt template " .. config.prompt_template_path .. " not found!", vim.log.levels.ERROR)
    return nil
  end
  return path:read()
end

-- Get the visual selection text and exact byte-range (0-indexed)
local function get_visual_selection()
  local buf = 0
  -- Marks '< and '> hold the start/end of visual selection (line,col)
  local start_pos = vim.fn.getpos("'<")
  local end_pos   = vim.fn.getpos("'>")
  local sl = start_pos[2] - 1
  local sc = start_pos[3] - 1
  local el = end_pos[2]   - 1
  local ec = end_pos[3]

  -- Fallback to whole line if marks invalid
  if sl < 0 or el < 0 then
    sl = vim.fn.line('.') - 1
    sc = 0
    el = sl
    local line_txt = vim.api.nvim_buf_get_lines(buf, sl, sl + 1, false)[1] or ""
    ec = #line_txt
  end

  -- Ensure ec does not exceed line length
  local line2_txt = vim.api.nvim_buf_get_lines(buf, el, el + 1, false)[1] or ""
  if ec > #line2_txt then ec = #line2_txt end

  -- Extract the selected text
  local lines = vim.api.nvim_buf_get_text(buf, sl, sc, el, ec, {})
  local selection = table.concat(lines, "\n")
  return selection, sl, sc, el, ec
end

-- Display AI result in a readonly vertical split
local function show_ai_result_window(content)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
end

-- Prompt the user to accept/reject/modify
local function prompt_user_action(callback)
  local options = { "Yes, replace original", "No, reject", "I want to modify manually" }
  vim.ui.select(options, { prompt = "Commit message enhanced, accept?" }, callback)
end

-- Main entrypoint: enhance the commit message
function M.enhance_commit_message()
  -- Capture selection and its range
  local selection, sl, sc, el, ec = get_visual_selection()
  if not selection or selection == "" then return end

  -- Load and validate template
  local template = read_template()
  if not template then return end

  -- Get API key
  local api_key = os.getenv("OPENAI_API_KEY")
  if not api_key then
    vim.notify("[commit-enhancer] OPENAI_API_KEY environment variable not set", vim.log.levels.ERROR)
    return
  end

  -- Remember the buffer to modify
  local target_buf = vim.api.nvim_get_current_buf()

  -- Async API call
  vim.schedule(function()
    curl.post("https://api.openai.com/v1/chat/completions", {
      headers = {
        ["Authorization"]    = "Bearer " .. api_key,
        ["Content-Type"]     = "application/json",
      },
      body = vim.fn.json_encode({
        model    = config.model,
        messages = {
          { role = "system", content = template },
          { role = "user",   content = selection },
        },
        temperature = 0.7,
      }),
      callback = vim.schedule_wrap(function(res)
        if res.status ~= 200 then
          vim.notify("[commit-enhancer] OpenAI API Error: " .. res.status .. "\n" .. (res.body or ""), vim.log.levels.ERROR)
          return
        end

        local ok, decoded = pcall(vim.fn.json_decode, res.body)
        if not ok or not decoded.choices or not decoded.choices[1] then
          vim.notify("[commit-enhancer] Invalid API response", vim.log.levels.ERROR)
          return
        end

        local ai_message = decoded.choices[1].message.content or ""
        show_ai_result_window(ai_message)

        prompt_user_action(function(choice)
          if choice == "Yes, replace original" then
            local new_lines = vim.split(ai_message, "\n")
            -- Replace the original selection
            vim.api.nvim_buf_set_text(target_buf, sl, sc, el, ec, new_lines)
            vim.cmd("close")
          elseif choice == "No, reject" then
            vim.cmd("close")
          else
            -- Leave the AI window open for manual editing
          end
        end)
      end),
    })
  end)
end

-- Lazy-load mapping for gitcommit filetype
vim.api.nvim_create_autocmd("FileType", {
  pattern = "gitcommit",
  callback = function()
    vim.keymap.set("v", "<leader>ce", function()
      require("commit-enhancer").enhance_commit_message()
    end, { noremap = true, silent = true, buffer = true })
  end,
})

return M
