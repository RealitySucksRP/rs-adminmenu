-- Server-only configuration. Keep webhook URLs and other secrets out of shared config.lua.
Config = Config or {}
Config.Webhooks = {
    enabled = true,
    moderation = '', economy = '', staff = '', reports = '', vehicles = '',
    inventory = '', world = '', disasters = '', security = '', builder = '',
}
