local gh = require"octo.gh"
local utils = require "octo.utils"
local graphql = require"octo.notifications.graphql"
local conf = require "telescope.config".values
local previewers = require "telescope.previewers"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local actions = require "telescope.actions"
local action_set = require "telescope.actions.set"
local entry_display = require "telescope.pickers.entry_display"
local defaulter = require "telescope.utils".make_default_callable
local format = string.format
local api = vim.api
local json = {
  parse = vim.fn.json_decode
}

local M = {}

--
-- Startify
--
-- function M.startify(query)
--   query = query or ""
--   local output = gh.run(
--     {
--       args = {"api", "graphql", "-H", "GraphQL-Schema: internal", "-f", format("query=%s", format(graphql.inbox_query, query))},
--       mode = "sync",
--     }
--   )
--   local resp = json.parse(output)
--   local entries = {}
--   for _, item in ipairs(resp.data.viewer.notificationThreads.nodes) do
--     table.insert(entries, {
--       line = format("%s %s [%s]", item.isUnread and "🔹" or "", item.title, item.reason),
--       cmd = format("lua require'octo.utils'.parse_url('%s')", item.url)
--     })
--   end
--   return entries
-- end

--
-- Telescope menu
--
function M.gen_from_entry(max_reason)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.reason:lower(), "TelescopeResultsNumber"},
      {entry.isUnread and "🔹" or "  "},
      {entry.title},
    }

    local displayer =
      entry_display.create {
        separator = " ",
        items = {
          {width = max_reason},
          {width = 2},
          {remaining = true},
        }
      }

    return displayer(columns)
  end

  return function(entry)
    if not entry or vim.tbl_isempty(entry) then
      return nil
    end

    return {
      value = entry.id,
      ordinal = entry.title,
      title = entry.title,
      isUnread = entry.isUnread,
      reason = entry.reason,
      url = entry.url,
      summaryItemBody = entry.summaryItemBody,
      display = make_display
    }
  end
end

local function open_entry(command)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    if command == 'split' then
      vim.cmd [[:sbuffer %]]
    elseif command == 'vsplit' then
      vim.cmd [[:vert sbuffer %]]
    elseif command == 'tabedit' then
      vim.cmd [[:tab sb %]]
    end

    local repo, number, kind = utils.parse_url(selection.url)
    if repo and number and (kind == "issue" or not kind) then
      utils.get_issue(repo, number)
    elseif repo and number and kind == "pull" then
      utils.get_pull_request(repo, number)
    end
  end
end

M.entry_previewer =
  defaulter(
  function()
    return previewers.new_buffer_previewer {
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        local bufnr = self.state.bufnr
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(bufnr) == 1 then
          api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(entry.summaryItemBody:gsub([[]], ""), "\n"))
        end
      end
    }
  end
)

local function mark_as(action)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    local id = selection.value
    local queries = {
      read = format(graphql.mark_as_read_mutation, id),
      unread = format(graphql.mark_as_unread_mutation, id),
      done = format(graphql.mark_as_done_mutation, id),
      saved = format(graphql.mark_as_saved_mutation, id)
    }
    gh.run(
      {
        args = {"api", "graphql", "-H", "GraphQL-Schema: internal", "-f", format("query=%s", queries[action])},
        cb = function(output, stderr)
          if stderr and not utils.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            local resp = json.parse(output)
            print(vim.inspect(resp))
            actions.close(prompt_bufnr)
            M.telescope()
          end
        end
      }
    )
  end
end

function M.telescope(query)
  query = query or ""
  gh.run(
    {
      args = {"api", "graphql", "-H", "GraphQL-Schema: internal", "-f", format("query=%s", format(graphql.inbox_query, query))},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local entries = resp.data.viewer.notificationThreads.nodes

          -- max reason length
          local max_reason = -1
          for _, entry in ipairs(entries) do
            if #tostring(entry.reason) > max_reason then
              max_reason = #tostring(entry.reason)
            end
          end

          local opts = {}
          pickers.new(
            opts,
            {
              prompt_title = "",
              finder = finders.new_table {
                results = entries,
                entry_maker = M.gen_from_entry(max_reason)
              },
              sorter = conf.generic_sorter(opts),
              previewer = M.entry_previewer.new(opts),
              attach_mappings = function(_, map)
                action_set.select:replace(function(prompt_bufnr, type)
                  open_entry(type)(prompt_bufnr)
                end)
                map("i", "<c-r>", mark_as("read"))
                map("i", "<c-u>", mark_as("unread"))
                map("i", "<c-d>", mark_as("done"))
                map("i", "<c-s>", mark_as("saved"))
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

return M
