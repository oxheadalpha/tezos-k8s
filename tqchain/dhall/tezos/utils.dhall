let common = ./common_components.dhall

let k8s = common.k8s

let `generateTezosConfig.py` = ./utils/generateTezosConfig.py as Text

let `import_keys.sh` = ./utils/import_keys.sh as Text

in  k8s.ConfigMap::{
    , data = Some (toMap { `generateTezosConfig.py`, `import_keys.sh` })
    , metadata = common.tqMeta "tqtezos-utils"
    }
