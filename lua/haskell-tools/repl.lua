---@mod haskell-tools.repl haskell-tools GHCi REPL module

---@bruief [[
---Tools for interaction with a GHCi REPL
---@bruief ]]

local ht = require('haskell-tools')
local project = require('haskell-tools.project.util')

local repl = {}

---Extend a repl command for `file`.
---If `file` is `nil`, create a repl the nearest package.
---@param cmd string[] The command to extend
---@param file string|nil An optional project file
---@return string[]|nil
local function extend_repl_cmd(cmd, file)
  if file == nil then
    file = vim.api.nvim_buf_get_name(0)
    ht.log.debug('extend_repl_cmd: No file specified. Using current buffer: ' .. file)
    local project_root = project.match_project_root(file)
    local subpackage = project_root and project.get_package_name(file)
    if subpackage then
      table.insert(cmd, subpackage)
      ht.log.debug { 'extend_repl_cmd: Extended cmd with package.', cmd }
      return cmd
    else
      ht.log.debug { 'extend_repl_cmd: No subpackage or no package found.', cmd }
      return cmd
    end
  end
  ht.log.debug('extend_repl_cmd: File: ' .. file)
  local project_root = project.match_project_root(file)
  local subpackage = project_root and project.get_package_name(file)
  if not subpackage then
    ht.log.debug { 'extend_repl_cmd: No package found.', cmd }
    return cmd
  end
  if vim.endswith(file, '.hs') then
    table.insert(cmd, file)
  else
    ht.log.debug('extend_repl_cmd: Not a Haskell file.')
    table.insert(cmd, subpackage)
  end
  ht.log.debug { 'extend_repl_cmd', cmd }
  return cmd
end

---Create a cabal repl command for `file`.
---If `file` is `nil`, create a repl the nearest package.
---@param file string|nil
---@return string[]|nil command
local function mk_cabal_repl_cmd(file)
  return extend_repl_cmd({ 'cabal', 'repl' }, file)
end

---Create a stack repl command for `file`.
---If `file` is `nil`, create a repl the nearest package.
---@param file string|nil
---@return string[]|nil command
local function mk_stack_repl_cmd(file)
  return extend_repl_cmd({ 'stack', 'ghci' }, file)
end

---Create the command to create a repl for a file.
---If `file` is `nil`, create a repl for the nearest package.
---@param file string|nil
---@return table|nil command
function repl.mk_repl_cmd(file)
  local chk_path = file
  if not chk_path then
    chk_path = vim.api.nvim_buf_get_name(0)
    if vim.fn.filewritable(chk_path) == 0 then
      local err_msg = 'haskell-tools.repl: File not found. Has it been saved? ' .. chk_path
      ht.log.error(err_msg)
      vim.notify(err_msg, vim.log.levels.ERROR)
      return nil
    end
  end
  if project.is_cabal_project(chk_path) then
    return mk_cabal_repl_cmd(file)
  end
  if project.is_stack_project(chk_path) then
    return mk_stack_repl_cmd(file)
  end
  if vim.fn.executable('ghci') == 1 then
    local cmd = vim.tbl_flatten { 'ghci', file and { file } or {} }
    ht.log.debug { 'mk_repl_cmd', cmd }
    return cmd
  end
  local err_msg = 'haskell-tools.repl: No ghci executable found.'
  ht.log.error(err_msg)
  vim.notify(err_msg, vim.log.levels.ERROR)
  return nil
end

---Create the command to create a repl for the current buffer.
---@return table|nil command
function repl.buf_mk_repl_cmd()
  local file = vim.api.nvim_buf_get_name(0)
  return repl.mk_repl_cmd(file)
end

---Set up this module. Called by the haskell-tools setup.
function repl.setup()
  local opts = ht.config.options.tools.repl
  local handler
  if opts.handler == 'toggleterm' then
    ht.log.info('handler = toggleterm')
    local toggleterm = require('haskell-tools.repl.toggleterm')
    toggleterm.setup(repl.mk_repl_cmd, opts)
    handler = toggleterm
  else
    ht.log.info('handler = builtin')
    local builtin = require('haskell-tools.repl.builtin')
    builtin.setup(repl.mk_repl_cmd, opts)
    handler = builtin
  end

  ---Toggle a GHCi REPL
  repl.toggle = handler.toggle

  ---Quit the REPL
  repl.quit = handler.quit

  ---@param lines string[]
  local function repl_send_lines(lines)
    if #lines > 1 then
      handler.send_cmd(':{')
      for _, line in ipairs(lines) do
        handler.send_cmd(line)
      end
      handler.send_cmd(':}')
    else
      handler.send_cmd(lines[1])
    end
  end

  ---Can be used to send text objects to the repl.
  ---@usage [[
  ---vim.keymap.set('n', 'ghc', ht.repl.operator, {noremap = true})
  ---@usage ]]
  ---@see operatorfunc
  function repl.operator()
    local old_operator_func = vim.go.operatorfunc
    _G.op_func_send_to_repl = function()
      local start = vim.api.nvim_buf_get_mark(0, '[')
      local finish = vim.api.nvim_buf_get_mark(0, ']')
      local text = vim.api.nvim_buf_get_text(0, start[1] - 1, start[2], finish[1], finish[2] + 1, {})
      repl_send_lines(text)
      vim.go.operatorfunc = old_operator_func
      _G.op_func_formatting = nil
    end
    vim.go.operatorfunc = 'v:lua.op_func_send_to_repl'
    vim.api.nvim_feedkeys('g@', 'n', false)
  end

  vim.keymap.set('n', 'ghc', repl.operator, { noremap = true })

  ---Paste from register `reg` to the REPL
  ---@param reg string|nil register (defaults to '"')
  function repl.paste(reg)
    local data = vim.fn.getreg(reg or '"')
    if vim.endswith(data, '\n') then
      data = data:sub(1, #data - 1)
    end
    local lines = vim.split(data, '\n')
    if #lines <= 1 then
      lines = { data }
    end
    repl_send_lines(lines)
  end

  local function handle_reg(cmd, reg)
    local data = vim.fn.getreg(reg or '"')
    handler.send_cmd(cmd .. ' ' .. data)
  end

  local function handle_cword(cmd)
    local cword = vim.fn.expand('<cword>')
    handler.send_cmd(cmd .. ' ' .. cword)
  end

  ---Query the REPL for the type of register `reg`
  ---@param reg string|nil register (defaults to '"')
  function repl.paste_type(reg)
    handle_reg(':t', reg)
  end

  ---Query the REPL for the type of word under the cursor
  function repl.cword_type()
    handle_cword(':t')
  end

  ---Query the REPL for info on register `reg`
  ---@param reg string|nil register (defaults to '"')
  function repl.paste_info(reg)
    handle_reg(':i', reg)
  end

  ---Query the REPL for the type of word under the cursor
  function repl.cword_info()
    handle_cword(':i')
  end

  ---Load a file into the REPL
  ---@param filepath string The absolute file path
  function repl.load_file(filepath)
    if vim.fn.filereadable(filepath) == 0 then
      local err_msg = 'File: ' .. filepath .. ' does not exist or is not readable.'
      ht.log.error(err_msg)
      vim.notify(err_msg, vim.log.levels.ERROR)
    end
    handler.send_cmd(':l ' .. filepath)
  end

  ---Reload the repl
  function repl.reload()
    handler.send_cmd(':r')
  end
end

return repl
