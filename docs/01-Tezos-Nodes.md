nodes:
  archive-baking-node:
    instances:
    - bake_using_accounts:
      - archive-baking-node-0
      config:
        shell:
          history_mode: archive
      is_bootstrap_node: true
    runs:
    - octez_node
    - baker
    storage_size: 15Gi
  rolling-node: null
