local M = {}

-- Plugin configuration
local config = { model = nil, prompt_template_path = nil }

-- Internal state
local is_pending = false
local ai_bufnr, ai_winnr
local loading_bufnr, loading_winnr
local spinner = {"|","/","-","\\"}
local spinner_index = 1
local loading_timer

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

-- Get the visual selection text and byte-range
local function get_visual_selection()
  local buf = 0
  local start_pos = vim.fn.getpos("'<")
  local end_pos   = vim.fn.getpos("'>")
  local sl = start_pos[2] - 1
  local sc = start_pos[3] - 1
  local el = end_pos[2]   - 1
  local ec = end_pos[3]
  if sl < 0 or el < 0 then
    sl = vim.fn.line('.') - 1
    sc = 0
    el = sl
    local text = vim.api.nvim_buf_get_lines(buf, sl, sl + 1, false)[1] or ""
    ec = #text
  end
  local line_text = vim.api.nvim_buf_get_lines(buf, el, el + 1, false)[1] or ""
  if ec > #line_text then ec = #line_text end
  local lines = vim.api.nvim_buf_get_text(buf, sl, sc, el, ec, {})
  return table.concat(lines, "\n"), sl, sc, el, ec
end

-- Show loading floating window with spinner
local function show_loading()
  if loading_winnr and vim.api.nvim_win_is_valid(loading_winnr) then return end
  loading_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[loading_bufnr].buftype = 'nofile'
  vim.bo[loading_bufnr].bufhidden = 'wipe'
  local width, height = 30, 1
  local opts = {
    style = 'minimal', relative = 'editor',
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  }
  loading_winnr = vim.api.nvim_open_win(loading_bufnr, false, opts)
  spinner_index = 1
  loading_timer = vim.loop.new_timer()
  loading_timer:start(0, 100, vim.schedule_wrap(function()
    if not (loading_bufnr and vim.api.nvim_buf_is_valid(loading_bufnr)) then
      loading_timer:stop(); loading_timer:close(); loading_timer = nil
      return
    end
    local frame = spinner[spinner_index]
    spinner_index = spinner_index % #spinner + 1
    vim.api.nvim_buf_set_lines(loading_bufnr, 0, -1, false, { frame .. ' Loading AI response...' })
  end))
end

-- Close loading window and stop spinner
local function close_loading()
  if loading_timer then
    loading_timer:stop(); loading_timer:close(); loading_timer = nil
  end
  if loading_winnr and vim.api.nvim_win_is_valid(loading_winnr) then
    vim.api.nvim_win_close(loading_winnr, true)
  end
  loading_bufnr, loading_winnr = nil, nil
end

-- Show AI result in single split (reuse previous)
local function show_ai_result_window(content)
  -- Close old AI window if exists
  if ai_winnr and vim.api.nvim_win_is_valid(ai_winnr) then
    vim.api.nvim_win_close(ai_winnr, true)
    ai_bufnr, ai_winnr = nil, nil
  end
  -- Create new buffer for AI content
  ai_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(ai_bufnr, 0, -1, false, vim.split(content, '\n'))
  vim.bo[ai_bufnr].buftype = 'nofile'
  vim.bo[ai_bufnr].bufhidden = 'wipe'
  vim.bo[ai_bufnr].modifiable = false
  -- Open vertical split and set buffer
  vim.cmd('vsplit')
  ai_winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ai_winnr, ai_bufnr)
end

-- Prompt the user to accept/reject/modify
local function prompt_user_action(callback)
  local options = { 'Yes, replace original', 'No, reject', 'I want to modify manually' }
  vim.ui.select(options, { prompt = 'Commit message enhanced, accept?' }, callback)
end

-- Main function: enhance commit message
function M.enhance_commit_message()
  if is_pending then
    vim.notify('[commit-enhancer] Request already in progress', vim.log.levels.WARN)
    return
  end

  local selection, sl, sc, el, ec = get_visual_selection()
  if not selection or selection == '' then return end

  local template = read_template()
  if not template then return end

  local api_key = os.getenv('OPENAI_API_KEY')
  if not api_key then
    vim.notify('[commit-enhancer] OPENAI_API_KEY not set', vim.log.levels.ERROR)
    return
  end

  local target_buf = vim.api.nvim_get_current_buf()
  is_pending = true
  show_loading()

  curl.post('https://api.openai.com/v1/chat/completions', {
    headers = { Authorization = 'Bearer '..api_key, ['Content-Type'] = 'application/json' },
    body = vim.fn.json_encode({
      model    = config.model,
      messages = { { role = 'system', content = template }, { role = 'user', content = selection } },
      temperature = 0.7,
    }),
    callback = vim.schedule_wrap(function(res)
      is_pending = false
      close_loading()
      if res.status ~= 200 then
        vim.notify('[commit-enhancer] API Error: '..res.status, vim.log.levels.ERROR)
        return
      end
      local ok, decoded = pcall(vim.fn.json_decode, res.body)
      if not ok or not decoded.choices or not decoded.choices[1] then
        vim.notify('[commit-enhancer] Invalid API response', vim.log.levels.ERROR)
        return
      end
      local ai_message = decoded.choices[1].message.content or ''
      show_ai_result_window(ai_message)
      prompt_user_action(function(choice)
        if choice == 'Yes, replace original' then
          if ai_winnr and vim.api.nvim_win_is_valid(ai_winnr) then
            vim.api.nvim_win_close(ai_winnr, true)
            ai_bufnr, ai_winnr = nil, nil
          end
          local new_lines = vim.split(ai_message, '\n')
          vim.api.nvim_buf_set_text(target_buf, sl, sc, el, ec, new_lines)
        elseif choice == 'No, reject' then
          if ai_winnr and vim.api.nvim_win_is_valid(ai_winnr) then
            vim.api.nvim_win_close(ai_winnr, true)
            ai_bufnr, ai_winnr = nil, nil
          end
        elseif choice == 'I want to modify manually' then
          -- Keep the AI split open; make it modifiable for manual edits
          if ai_bufnr and vim.api.nvim_buf_is_valid(ai_bufnr) then
            vim.bo[ai_bufnr].modifiable = true
          end
        end
      end)
    end),
  })
end

-- Lazy-load mapping for gitcommit filetype
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'gitcommit',
  callback = function()
    vim.keymap.set('v', '<leader>ce', function()
      require('commit-enhancer').enhance_commit_message()
    end, { noremap = true, silent = true, buffer = true })
  end,
})

return M
