local M = {}

local buffer_event = require("csvview.buffer_event")
local config = require("csvview.config")
local metrics = require("csvview.metrics")
local view = require("csvview.view")

--- @type integer[]
local enable_buffers = {}

--- Function to get the starting line of the CSV data
local function get_csv_start_line(bufnr)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  for i = 0, total_lines - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if not line:match("^%s*--") then
      return i
    end
  end
  return total_lines
end

--- check if csv table view is enabled
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  return vim.tbl_contains(enable_buffers, bufnr)
end

--- enable csv table view
---@param bufnr integer?
---@param opts CsvViewOptions?
function M.enable(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = config.get(opts)

  if M.is_enabled(bufnr) then
    vim.notify("csvview: already enabled for this buffer.")
    return
  end
  table.insert(enable_buffers, bufnr)

  -- Determine the start line (skip comment lines at the top)
  local start_line = get_csv_start_line(bufnr)

  -- Calculate fields and enable csv table view.
  local fields = {}
  metrics.compute_csv_metrics(bufnr, opts, function(f, column_max_widths)
    fields = f
    view.attach(bufnr, fields, column_max_widths, opts)
  end, start_line + 1)

  -- Register buffer events.
  buffer_event.register(bufnr, {
    on_lines = function(_, _, _, first, last, last_updated)
      -- detach if disabled
      if not M.is_enabled(bufnr) then
        return true
      end

      -- Determine the start line (skip comment lines at the top)
      local start_line = get_csv_start_line(bufnr)

      -- Ignore updates in the comment lines at the top
      if last_updated < start_line then
        return
      end

      -- Adjust indices to skip comment lines
      first = math.max(first, start_line)
      last = math.max(last, start_line)
      last_updated = math.max(last_updated, start_line)

      -- handle line deletion and addition
      if last > last_updated then
        -- when line deleted.
        for _ = last_updated + 1, last do
          table.remove(fields, last_updated + 1)
        end
      elseif last < last_updated then
        -- when line added.
        for i = last + 1, last_updated do
          table.insert(fields, i, {})
        end
      else
        -- when updated within a line.
      end

      -- Recalculate only the difference.
      local startlnum = first + 1
      local endlnum = last_updated
      metrics.compute_csv_metrics(bufnr, opts, function(f, column_max_widths)
        fields = f
        view.update(bufnr, fields, column_max_widths)
      end, startlnum, endlnum, fields)
    end,

    on_reload = function()
      -- detach if disabled
      if not M.is_enabled(bufnr) then
        return true
      end

      -- Determine the start line (skip comment lines at the top)
      local start_line = get_csv_start_line(bufnr)

      -- Recalculate all fields.
      view.detach(bufnr)
      metrics.compute_csv_metrics(bufnr, opts, function(f, column_max_widths)
        fields = f
        view.attach(bufnr, fields, column_max_widths, opts)
      end, start_line + 1)
    end,
  })
end

--- disable csv table view
---@param bufnr integer?
function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M.is_enabled(bufnr) then
    vim.notify("csvview: not enabled for this buffer.")
    return
  end

  -- Remove buffer from enabled list.
  for i = #enable_buffers, 1, -1 do
    if enable_buffers[i] == bufnr then
      table.remove(enable_buffers, i)
    end
  end

  -- Unregister buffer events and detach view.
  buffer_event.unregister(bufnr)
  view.detach(bufnr)
end

--- toggle csv table view
---@param bufnr integer?
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if M.is_enabled(bufnr) then
    M.disable(bufnr)
  else
    M.enable(bufnr)
  end
end

--- setup
---@param opts CsvViewOptions?
function M.setup(opts)
  config.setup(opts)
  view.setup()
  vim.api.nvim_create_user_command("CsvViewEnable", function()
    M.enable()
  end, {})
  vim.api.nvim_create_user_command("CsvViewDisable", function()
    M.disable()
  end, {})
  vim.api.nvim_create_user_command("CsvViewToggle", function()
    M.toggle()
  end, {})
end

return M
