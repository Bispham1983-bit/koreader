local _ = require("gettext")
return {
    name = "hawebhook",
    fullname = _("Home Assistant Webhook"),
    description = _([[Trigger Home Assistant webhooks and REST API service calls from configurable gestures. Single tap fires a quick webhook; long press opens an action menu with named actions and live light state.]]),
    version = "2.0.0",
}
