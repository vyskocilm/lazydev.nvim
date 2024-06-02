---@class lazydev.Pkg
local M = {}

M.PAT_MODULE_BASE = "%-%-%-%s*@module%s*[\"']([%w%.%-_/]+)"
M.PAT_REQUIRE_BASE = "require%s*%(?%s*['\"]([%w%.%-_/]+)"
M.PAT_MODULE_BEFORE = M.PAT_MODULE_BASE .. "$"
M.PAT_REQUIRE_BEFORE = M.PAT_REQUIRE_BASE .. "$"
M.PAT_MODULE = M.PAT_MODULE_BASE .. "[\"']"
M.PAT_REQUIRE = M.PAT_REQUIRE_BASE .. "[\"']"

local is_lazy = type(package.loaded.lazy) == "table"

---@param modname string
---@return string[]
function M.lazy_unloaded(modname)
  local Util = require("lazy.core.util")
  return Util.get_unloaded_rtp(modname)
end

---@type string[]
local packs = nil

---@param modname string
function M.pack_unloaded(modname)
  if packs then
    return packs
  end

  local sites = vim.opt.packpath:get() ---@type string[]
  local default_site = vim.fn.stdpath("data") .. "/site"
  if not vim.tbl_contains(sites, default_site) then
    sites[#sites + 1] = default_site
  end

  packs = {} ---@type string[]
  for _, site in pairs(sites) do
    for _, pack in ipairs(vim.fn.expand(site .. "/pack/*/opt/*/lua", false, true)) do
      if not pack:find("*", 1, true) then
        packs[#packs + 1] = vim.fs.normalize(pack:sub(1, -5))
      end
    end
  end
  return packs
end

M.get_unloaded = is_lazy and M.lazy_unloaded or M.pack_unloaded

---@param modname string
---@return string[]
function M.find_roots(modname)
  local ret = vim.loader.find(modname, {
    rtp = true,
    paths = M.get_unloaded(modname),
    patterns = { "", ".lua" },
    all = true,
  })
  return vim.tbl_map(
    ---@param mod vim.loader.ModuleInfo
    function(mod)
      local path = mod.modpath:gsub("/init%.lua$", ""):gsub("%.lua$", "")
      return path
    end,
    ret
  )
end

---@param fn fun(modname:string, modpath:string)
function M.topmods(fn)
  local ret = vim.loader.find("*", {
    all = true,
    rtp = true,
    paths = M.get_unloaded(""),
  })
  for _, mod in ipairs(ret) do
    fn(mod.modname, mod.modpath)
  end
end

--- Get the module name from a line,
--- either `---@module "modname"` or `require "modname"`
---@param line string
---@param opts? {before?:boolean}
---@return string?, boolean? forward_slash
function M.get_module(line, opts)
  local patterns = opts and opts.before and {
    M.PAT_MODULE_BEFORE,
    M.PAT_REQUIRE_BEFORE,
  } or {
    M.PAT_MODULE,
    M.PAT_REQUIRE,
  }
  for _, pat in ipairs(patterns) do
    local match = line:match(pat)
    if match then
      return match:gsub("/", "."), match:find("/", 1, true)
    end
  end
end

---@param path string
---@return string?
function M.get_plugin_name(path)
  local lua = path:find("/lua/", 1, true)
  if lua then
    local name = path:sub(1, lua - 1)
    local slash = name:reverse():find("/", 1, true)
    if slash then
      name = name:sub(#name - slash + 2)
      return name
    end
  end
end

---@param modname string
---@param fn fun(modname:string, modpath:string)
function M.lsmod(modname, fn)
  local roots = M.find_roots(modname)
  for _, root in ipairs(roots) do
    for name, type in vim.fs.dir(root) do
      local path = vim.fs.joinpath(root, name)
      if name == "init.lua" then
        fn(modname, path)
      elseif (type == "file" or type == "link") and name:sub(-4) == ".lua" then
        fn(modname .. "." .. name:sub(1, -5), path)
      elseif type == "directory" and vim.uv.fs_stat(path .. "/init.lua") then
        fn(modname .. "." .. name, path .. "/init.lua")
      end
    end
  end
end

return M
