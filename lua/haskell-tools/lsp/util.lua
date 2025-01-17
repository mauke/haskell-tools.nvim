---@mod haskell-tools.lsp.util

---@brief [[

---WARNING: This is not part of the public API.
---Breaking changes to this module will not be reflected in the semantic versioning of this plugin.

--- LSP utilities
---@brief ]]

local util = {}

util.client_name = 'haskell-tools.nvim'

---@param bufnr number the buffer to get clients for
function util.get_active_ht_clients(bufnr)
  return vim.lsp.get_active_clients { bufnr = bufnr, name = util.client_name }
end

return util
