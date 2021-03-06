local assert = require('luassert')
local builtin = require('telescope.builtin')

local Job = require("plenary.job")

local tester = {}

local replace_terms = function(input)
  return vim.api.nvim_replace_termcodes(input, true, false, true)
end

local nvim_feed = function(text, feed_opts)
  feed_opts = feed_opts or "m"

  vim.api.nvim_feedkeys(text, feed_opts, true)
end

tester.picker_feed = function(input, test_cases, debug)
  input = replace_terms(input)

  return coroutine.wrap(function()
    for i = 1, #input do
      local char = input:sub(i, i)
      nvim_feed(char, "")

      -- TODO: I'm not 100% sure this is a hack or not...
      -- it's possible these characters  could still have an on_complete... but i'm not sure.
      if string.match(char, "%g") then
        coroutine.yield()
      end
    end

    vim.wait(100, function() end)

    local timer = vim.loop.new_timer()
    timer:start(200, 0, vim.schedule_wrap(function()
      if test_cases.post_close then
        for k, v in ipairs(test_cases.post_close) do
          io.stderr:write(vim.fn.json_encode({ case = k, expected = v[1], actual = v[2]() }))
          io.stderr:write("\n")
        end
      end
      vim.wait(10)

      if debug then
        return
      end

      vim.defer_fn(function()
        vim.cmd [[qa!]]
      end, 15)
    end))

    if not debug then
      vim.schedule(function()
        if test_cases.post_typed then
          for k, v in ipairs(test_cases.post_typed) do
            io.stderr:write(vim.fn.json_encode({ case = k, expected = v[1], actual = v[2]() }))
            io.stderr:write("\n")
          end
        end

        nvim_feed(replace_terms("<CR>"), "")
      end)
    end
    coroutine.yield()
  end)
end

-- local test_cases = {
--   post_typed = {
--   },
--   post_close = {
--     { "README.md", function() return "README.md" end },
--   },
-- }
tester.builtin_picker = function(key, input, test_cases, opts)
  opts = opts or {}
  local debug = opts.debug or false

  opts.on_complete = {
    tester.picker_feed(input, test_cases, debug)
  }

  builtin[key](opts)
end

local get_results_from_file = function(file)
  local j = Job:new {
    command = 'nvim',
    args = {
      '--noplugin',
      '-u',
      'scripts/minimal_init.vim',
      '-c',
      'luafile ' .. file
    },
  }

  j:sync()

  local results = j:stderr_result()
  local result_table = {}
  for _, v in ipairs(results) do
    table.insert(result_table, vim.fn.json_decode(v))
  end

  return result_table
end

local check_results = function(results)
  -- TODO: We should get all the test cases here that fail, not just the first one.
  for _, v in ipairs(results) do
    assert.are.same(v.expected, v.actual)
  end
end

tester.run_string = function(contents)
  local tempname = vim.fn.tempname()

  contents = [[
  -- TODO: Add globals!
  -- local tester = require('telescope.pickers._tests')
  local tester = require('telescope.pickers._tests')

  local get_picker = function()
    local state = require('telescope.state')
    return state.get_status(vim.api.nvim_get_current_buf()).picker
  end

  local get_results_bufnr = function()
    local state = require('telescope.state')
    return state.get_status(vim.api.nvim_get_current_buf()).results_bufnr
  end

  local GetFile = function() return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t") end

  local GetPrompt = function() return vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] end

  local GetResults = function()
    return vim.api.nvim_buf_get_lines(get_results_bufnr(), 0, -1, false)
  end

  local GetLastResult = function()
    local results = GetResults()
    return results[#results]
  end
  ]] .. contents

  vim.fn.writefile(vim.split(contents, "\n"), tempname)
  local result_table = get_results_from_file(tempname)
  vim.fn.delete(tempname)

  check_results(result_table)
  -- assert.are.same(result_table.expected, result_table.actual)
end

tester.run_file = function(filename)
  local file = './lua/tests/pickers/' .. filename .. '.lua'

  local result_table = get_results_from_file(file)
  assert.are.same(result_table.expected, result_table.actual)
end



return tester
