local ButtonDialog = require("ui/widget/buttondialog")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = ffiutil.template

local HAWebhook = WidgetContainer:extend{
    name = "hawebhook",
    is_doc_only = false,
}

function HAWebhook:init()
    self.webhook_url = G_reader_settings:readSetting("hawebhook_url") or ""
    self.ha_base_url = G_reader_settings:readSetting("ha_base_url") or ""
    self.ha_token    = G_reader_settings:readSetting("ha_token") or ""
    self.ha_actions  = G_reader_settings:readSetting("ha_actions") or {}
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function HAWebhook:onDispatcherRegisterActions()
    Dispatcher:registerAction("trigger_ha_webhook", {
        category = "none",
        event    = "TriggerHAWebhook",
        title    = _("Trigger Home Assistant Webhook"),
        general  = true,
    })
    Dispatcher:registerAction("show_ha_menu", {
        category = "none",
        event    = "ShowHAMenu",
        title    = _("Show Home Assistant Actions Menu"),
        general  = true,
    })
end

function HAWebhook:onTriggerHAWebhook()
    self:triggerWebhook()
end

function HAWebhook:onShowHAMenu()
    NetworkMgr:runWhenOnline(function()
        self:showActionsMenu()
    end)
end

-- Legacy single-tap webhook
function HAWebhook:triggerWebhook()
    local url = self.webhook_url
    if not url or url == "" then
        UIManager:show(InfoMessage:new{
            text    = _("No webhook URL set.\nConfigure it via Tools → Home Assistant."),
            timeout = 3,
        })
        return
    end
    NetworkMgr:runWhenOnline(function()
        logger.info("[HAWebhook] POST", url)
        local cmd = string.format(
            "curl -sk -o /dev/null -w '%%{http_code}' -m 5 -X POST %q 2>/dev/null",
            url
        )
        local f    = io.popen(cmd)
        local code = f and f:read("*l") or ""
        if f then f:close() end
        local n = tonumber(code)
        if n and n >= 200 and n < 300 then
            UIManager:show(InfoMessage:new{ text = _("Done!"), timeout = 1.5 })
        else
            UIManager:show(InfoMessage:new{
                icon    = "notice-warning",
                text    = T(_("Webhook failed (%1)"), code ~= "" and code or _("no response")),
                timeout = 3,
            })
        end
    end)
end

-- REST API helpers
function HAWebhook:getEntityState(entity_id)
    if self.ha_base_url == "" or self.ha_token == "" then return nil end
    local url = self.ha_base_url .. "/api/states/" .. entity_id
    local cmd = string.format(
        "curl -sk -m 3 -H %q %q 2>/dev/null",
        "Authorization: Bearer " .. self.ha_token,
        url
    )
    local f      = io.popen(cmd)
    local result = f and f:read("*a") or ""
    if f then f:close() end
    return result:match('"state"%s*:%s*"([^"]+)"')
end

function HAWebhook:callService(action)
    if self.ha_base_url == "" or self.ha_token == "" then
        UIManager:show(InfoMessage:new{
            text    = _("HA server URL or token not configured.\nCheck Tools → Home Assistant."),
            timeout = 3,
        })
        return
    end
    local url  = string.format("%s/api/services/%s/%s", self.ha_base_url, action.domain, action.service)
    local data = string.format('{"entity_id":"%s"}', action.entity_id)
    local cmd  = string.format(
        "curl -sk -o /dev/null -w '%%{http_code}' -m 5 -X POST -H %q -H 'Content-Type: application/json' -d %q %q 2>/dev/null",
        "Authorization: Bearer " .. self.ha_token,
        data,
        url
    )
    logger.info("[HAWebhook] service", url, action.entity_id)
    logger.info("[HAWebhook] cmd", cmd)
    local f    = io.popen(cmd)
    local code = f and f:read("*l") or ""
    if f then f:close() end
    local n = tonumber(code)
    if n and n >= 200 and n < 300 then
        UIManager:show(InfoMessage:new{ text = _("Done!"), timeout = 1.5 })
    else
        UIManager:show(InfoMessage:new{
            icon    = "notice-warning",
            text    = T(_("Action failed (%1)\n%2"), code ~= "" and code or _("no response"), url),
            timeout = 6,
        })
    end
end

-- Actions popup menu (assign to long-press gesture)
function HAWebhook:showActionsMenu()
    if not self.ha_actions or #self.ha_actions == 0 then
        UIManager:show(InfoMessage:new{
            text    = _("No actions configured.\nAdd actions via Tools → Home Assistant."),
            timeout = 3,
        })
        return
    end

    -- Fetch current states for all entities
    local states = {}
    for _, action in ipairs(self.ha_actions) do
        if action.entity_id and action.entity_id ~= "" then
            local s = self:getEntityState(action.entity_id)
            if s then states[action.entity_id] = s end
        end
    end

    local buttons = {}
    for _, action in ipairs(self.ha_actions) do
        local label = action.name
        local state = states[action.entity_id]
        if state then
            label = label .. "  [" .. state .. "]"
        end
        local act = action
        table.insert(buttons, {{
            text     = label,
            callback = function()
                UIManager:close(self._actions_dialog)
                self:callService(act)
            end,
        }})
    end
    table.insert(buttons, {{
        text     = _("Cancel"),
        callback = function()
            UIManager:close(self._actions_dialog)
        end,
    }})

    self._actions_dialog = ButtonDialog:new{
        title   = _("Home Assistant"),
        buttons = buttons,
    }
    UIManager:show(self._actions_dialog)
end

-- Add action wizard (3 steps)
function HAWebhook:addActionDialog(touchmenu_instance)
    local d
    d = InputDialog:new{
        title      = _("Action name"),
        input      = "",
        input_hint = _("e.g. Turn off downstairs lights"),
        buttons    = {{{
            text     = _("Cancel"),
            id       = "close",
            callback = function() UIManager:close(d) end,
        }, {
            text             = _("Next"),
            is_enter_default = true,
            callback         = function()
                local name = d:getInputText()
                UIManager:close(d)
                if name and name ~= "" then
                    self:_addActionStep2(name, touchmenu_instance)
                end
            end,
        }}},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function HAWebhook:_addActionStep2(name, touchmenu_instance)
    local d
    d = InputDialog:new{
        title      = _("Entity ID"),
        input      = "",
        input_hint = _("e.g. light.downstairs_lights"),
        buttons    = {{{
            text     = _("Cancel"),
            id       = "close",
            callback = function() UIManager:close(d) end,
        }, {
            text             = _("Next"),
            is_enter_default = true,
            callback         = function()
                local entity_id = d:getInputText()
                UIManager:close(d)
                if entity_id and entity_id ~= "" then
                    self:_addActionStep3(name, entity_id, touchmenu_instance)
                end
            end,
        }}},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function HAWebhook:_addActionStep3(name, entity_id, touchmenu_instance)
    local domain = entity_id:match("^([^.]+)") or "homeassistant"
    local d
    d = ButtonDialog:new{
        title   = _("Choose service"),
        buttons = {
            {{ text = _("Turn On"),  callback = function() UIManager:close(d) self:_saveAction(name, entity_id, domain, "turn_on",  touchmenu_instance) end }},
            {{ text = _("Turn Off"), callback = function() UIManager:close(d) self:_saveAction(name, entity_id, domain, "turn_off", touchmenu_instance) end }},
            {{ text = _("Toggle"),   callback = function() UIManager:close(d) self:_saveAction(name, entity_id, domain, "toggle",   touchmenu_instance) end }},
            {{ text = _("Cancel"),   callback = function() UIManager:close(d) end }},
        },
    }
    UIManager:show(d)
end

function HAWebhook:_saveAction(name, entity_id, domain, service, touchmenu_instance)
    table.insert(self.ha_actions, { name = name, entity_id = entity_id, domain = domain, service = service })
    G_reader_settings:saveSetting("ha_actions", self.ha_actions)
    UIManager:show(InfoMessage:new{ text = _("Action saved."), timeout = 1.5 })
    if touchmenu_instance then touchmenu_instance:updateItems() end
end

function HAWebhook:_deleteActionDialog(idx, touchmenu_instance)
    local action = self.ha_actions[idx]
    if not action then return end
    local d
    d = ButtonDialog:new{
        title   = T(_("Delete \"%1\"?"), action.name),
        buttons = {
            {{ text = _("Delete"), callback = function()
                UIManager:close(d)
                table.remove(self.ha_actions, idx)
                G_reader_settings:saveSetting("ha_actions", self.ha_actions)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end }},
            {{ text = _("Cancel"), callback = function() UIManager:close(d) end }},
        },
    }
    UIManager:show(d)
end

-- Settings dialogs
function HAWebhook:_showBaseUrlDialog(tmi)
    local d
    d = InputDialog:new{
        title      = _("HA Server URL"),
        input      = self.ha_base_url,
        input_hint = "http://homeassistant.local:8123",
        buttons    = {{{
            text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end,
        }, {
            text = _("Save"), is_enter_default = true, callback = function()
                self.ha_base_url = (d:getInputText() or ""):gsub("/$", "")
                G_reader_settings:saveSetting("ha_base_url", self.ha_base_url)
                UIManager:close(d)
                if tmi then tmi:updateItems() end
            end,
        }}},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function HAWebhook:_showTokenDialog(tmi)
    local d
    d = InputDialog:new{
        title      = _("HA Long-Lived Access Token"),
        input      = self.ha_token,
        input_hint = _("Paste token from HA Profile → Security"),
        buttons    = {{{
            text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end,
        }, {
            text = _("Save"), is_enter_default = true, callback = function()
                self.ha_token = d:getInputText() or ""
                G_reader_settings:saveSetting("ha_token", self.ha_token)
                UIManager:close(d)
                if tmi then tmi:updateItems() end
            end,
        }}},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function HAWebhook:showUrlDialog(tmi)
    local d
    d = InputDialog:new{
        title      = _("Quick Webhook URL"),
        input      = self.webhook_url,
        input_hint = "http://homeassistant.local:8123/api/webhook/my-webhook-id",
        buttons    = {{{
            text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end,
        }, {
            text = _("Save"), is_enter_default = true, callback = function()
                self.webhook_url = d:getInputText() or ""
                G_reader_settings:saveSetting("hawebhook_url", self.webhook_url)
                UIManager:close(d)
                if tmi then tmi:updateItems() end
            end,
        }}},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function HAWebhook:addToMainMenu(menu_items)
    menu_items.hawebhook = {
        text         = _("Home Assistant"),
        sorting_hint = "tools",
        sub_item_table_func = function()
            local items = {
                {
                    text_func    = function()
                        local u = self.ha_base_url
                        if u == "" then return _("Server URL: (not set)") end
                        if #u > 35 then u = u:sub(1, 32) .. "..." end
                        return T(_("Server: %1"), u)
                    end,
                    keep_menu_open = true,
                    callback     = function(tmi) self:_showBaseUrlDialog(tmi) end,
                },
                {
                    text_func    = function()
                        return self.ha_token ~= "" and _("Token: (set)") or _("Token: (not set)")
                    end,
                    keep_menu_open = true,
                    callback     = function(tmi) self:_showTokenDialog(tmi) end,
                },
                {
                    text         = _("Add action…"),
                    keep_menu_open = true,
                    callback     = function(tmi) self:addActionDialog(tmi) end,
                },
            }

            for i, action in ipairs(self.ha_actions) do
                local idx = i
                local act = action
                table.insert(items, {
                    text_func      = function() return T(_("  [%1] %2"), idx, act.name) end,
                    keep_menu_open = true,
                    callback       = function(tmi) self:_deleteActionDialog(idx, tmi) end,
                })
            end

            table.insert(items, {
                text_func    = function()
                    local u = self.webhook_url
                    if u == "" then return _("Quick webhook: (not set)") end
                    if #u > 32 then u = u:sub(1, 29) .. "..." end
                    return T(_("Quick webhook: %1"), u)
                end,
                keep_menu_open = true,
                callback     = function(tmi) self:showUrlDialog(tmi) end,
            })
            table.insert(items, {
                text     = _("Test quick webhook"),
                callback = function() self:triggerWebhook() end,
            })
            table.insert(items, {
                text     = _("Gesture manager → assign 'Show Home Assistant Actions Menu'"),
                callback = function() end,
            })
            return items
        end,
    }
end

return HAWebhook
