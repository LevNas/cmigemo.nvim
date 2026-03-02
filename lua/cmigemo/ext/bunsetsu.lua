local M = {}
local parser = nil

local function get_parser()
  if parser then return parser end
  local ok, budoux = pcall(require, "budoux")
  if not ok then return nil end
  parser = budoux.load_japanese_model()
  return parser
end

function M.is_available()
  return get_parser() ~= nil
end

--- テキストを文節分割し、group_size個ずつまとめた範囲を返す
---@param text string
---@param group_size? number グルーピングする文節数 (default: 1)
---@return {start: number, finish: number}[] 各グループの開始・終了バイトオフセット(0-indexed)
function M.segment_ranges(text, group_size)
  group_size = group_size or 1
  local p = get_parser()
  if not p or text == "" then return {} end
  local segments = p.parse(text)
  if not segments or #segments == 0 then return {} end

  -- 各文節の開始・終了バイトオフセットを収集
  local boundaries = {}
  local byte_offset = 0
  for _, segment in ipairs(segments) do
    if segment ~= "" then
      boundaries[#boundaries + 1] = { start = byte_offset, finish = byte_offset + #segment - 1 }
    end
    byte_offset = byte_offset + #segment
  end

  -- group_size個ずつまとめる
  local ranges = {}
  for i = 1, #boundaries, group_size do
    local last = math.min(i + group_size - 1, #boundaries)
    ranges[#ranges + 1] = {
      start = boundaries[i].start,
      finish = boundaries[last].finish,
    }
  end
  return ranges
end

--- flash matcher: 可視行の文節境界をFlash.Match[]として返す
---@param win number
---@param state Flash.State
---@param opts? {from: number[], to: number[], group_size: number}
function M.matcher(win, state, opts)
  local info = vim.fn.getwininfo(win)[1]
  local top = (opts and opts.from) and opts.from[1] or info.topline
  local bot = (opts and opts.to) and opts.to[1] or info.botline
  local buf = vim.api.nvim_win_get_buf(win)
  local line_count = vim.api.nvim_buf_line_count(buf)
  top = math.max(1, top)
  bot = math.min(line_count, bot)
  local lines = vim.api.nvim_buf_get_lines(buf, top - 1, bot, false)
  local group_size = (opts and opts.group_size) or state._bunsetsu_group_size or 2
  local labels = state:labels()
  local matches = {}
  for i, line in ipairs(lines) do
    local row = top + i - 1
    for _, range in ipairs(M.segment_ranges(line, group_size)) do
      matches[#matches + 1] = {
        win = win,
        pos = { row, range.start },
        end_pos = { row, range.finish },
        label = table.remove(labels, 1),
      }
    end
  end
  return matches
end

return M
