let common = ./common_components.dhall

let chainConfig = ./chainConfig.dhall

let k8s = common.k8s

let ensure_node_dir
    : k8s.Container.Type
    = k8s.Container::{
      , name = "ensure-node-dir-job"
      , image = Some "busybox"
      , command = Some [ "/bin/mkdir" ]
      , args = Some [ "-p", "/var/tezos/node" ]
      , volumeMounts = Some [ common.volumeMounts.var ]
      }

let wait_for_node =
      k8s.Container::{
      , name = "wait-for-node"
      , image = Some "busybox"
      , command = Some
        [ "sh"
        , "-c"
        , "until nslookup tezos-bootstrap-node-rpc; do echo waiting for tezos-bootstrap-node-rpc; sleep 2; done;"
        ]
      }

let make_identity_job
    : chainConfig.Type -> k8s.Container.Type
    = \(o : chainConfig.Type) ->
        k8s.Container::{
        , name = "identity-job"
        , image = Some o.docker_image
        , command = Some [ "/bin/sh" ]
        , args = Some
          [ "-c"
          , "[ -f /var/tezos/node/identity.json ] || (mkdir -p /var/tezos/node && /usr/local/bin/tezos-node identity generate 0 --data-dir /var/tezos/node --config-file /etc/tezos/config.json)"
          ]
        , volumeMounts = Some
          [ common.volumeMounts.config, common.volumeMounts.var ]
        }

let make_activate_container =
      \(o : chainConfig.Type) ->
        k8s.Container::{
        , name = "activate"
        , command = Some [ "/usr/local/bin/tezos-client" ]
        , image = Some o.docker_image
        , volumeMounts = Some
          [ common.volumeMounts.config, common.volumeMounts.var ]
        , args = Some
          [ "-A"
          , "tezos-bootstrap-node-rpc"
          , "-P"
          , "8732"
          , "-d"
          , "/var/tezos/client"
          , "-l"
          , "--block"
          , "genesis"
          , "activate"
          , "protocol"
          , o.protocol_hash
          , "with"
          , "fitness"
          , "-1"
          , "and"
          , "key"
          , "genesis"
          , "and"
          , "parameters"
          , "/etc/tezos/parameters.json"
          ]
        }

let make_import_key_job
    : chainConfig.Type -> k8s.Container.Type
    = \(o : chainConfig.Type) ->
        k8s.Container::{
        , name = "import-keys"
        , image = Some o.docker_image
        , command = Some [ "sh", "/opt/tqtezos/import_keys.sh" ]
        , envFrom = Some
          [ k8s.EnvFromSource::{
            , secretRef = Some k8s.SecretEnvSource::{
              , name = Some "tezos-secret"
              }
            }
          ]
        , volumeMounts = Some
          [ common.volumeMounts.utils, common.volumeMounts.var ]
        }

let make_baker_job
    : chainConfig.Type -> k8s.Container.Type
    = \(o : chainConfig.Type) ->
        k8s.Container::{
        , name = "baker-job"
        , image = Some o.docker_image
        , command = Some [ o.baker_command ]
        , args = Some
          [ "-A"
          , "localhost"
          , "-P"
          , "8732"
          , "-d"
          , "/var/tezos/client"
          , "run"
          , "with"
          , "local"
          , "node"
          , "/var/tezos/node"
          , "baker"
          ]
        , volumeMounts = Some [ common.volumeMounts.var ]
        }

let make_bake_once
    : chainConfig.Type -> k8s.Container.Type
    = \(o : chainConfig.Type) ->
        k8s.Container::{
        , name = "bake-once"
        , image = Some o.docker_image
        , command = Some [ "/usr/local/bin/tezos-client" ]
        , args = Some
          [ "-A"
          , "tezos-bootstrap-node-rpc"
          , "-P"
          , "8732"
          , "-d"
          , "/var/tezos/client"
          , "-l"
          , "bake"
          , "for"
          , "baker"
          , "--minimal-timestamp"
          ]
        , volumeMounts = Some
          [ common.volumeMounts.config, common.volumeMounts.var ]
        }

let TezosNode =
      { Type = k8s.Container.Type
      , default = k8s.Container::{
        , command = Some [ "/usr/local/bin/tezos-node" ]
        , image = Some "tezos/tezos:v7-release"
        , imagePullPolicy = Some "Always"
        , name = "tezos-node"
        , ports = Some [ common.ports.rpc, common.ports.p2p ]
        , readinessProbe = Some common.probes.readiness
        , volumeMounts = Some
          [ common.volumeMounts.config, common.volumeMounts.var ]
        }
      }

let config_generator =
      k8s.Container::{
      , imagePullPolicy = Some "Always"
      , name = "tezos-config-generator"
      , image = Some "python:alpine"
      , command = Some [ "python", "/opt/tqtezos/generateTezosConfig.py" ]
      , envFrom = Some
        [ k8s.EnvFromSource::{
          , configMapRef = Some k8s.ConfigMapEnvSource::{
            , name = Some "tezos-config"
            }
          }
        ]
      , volumeMounts = Some
        [ common.volumeMounts.config
        , common.volumeMounts.utils
        , common.volumeMounts.var
        ]
      }

in  { ensure_node_dir
    , make_identity_job
    , make_import_key_job
    , make_baker_job
    , wait_for_node
    , make_activate_container
    , TezosNode
    , config_generator
    , make_bake_once
    }
