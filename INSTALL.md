# Install RS Admin Menu

1. Extract the download with its folder named `rs-adminmenu`.
2. Enable OneSync and start your framework, inventory, garage and key providers first.
3. Review `config.lua` and `server_config.lua` for your setup.
4. Bootstrap the first owner through ACE. Replace the placeholder in `server.cfg.example` with your own identifier, then start the resource.

```cfg
add_principal identifier.license:REPLACE_ME group.rsowner
add_ace group.rsowner rsadmin.owner allow
add_ace group.rsowner rsadmin.all allow
ensure rs-adminmenu
```

Open `/rsadmin`. The quick menu is `/fadminmenu`; duty is `/aduty`.

**Updating an installed server:** back up the resource and keep your live `data/`, `config.lua` and `server_config.lua`. The full download contains clean first-install data templates.

For optional Pathways guide items and provider milestones, use the examples in `install/pathway_items.lua` and `install/pathway_hooks.lua`.
