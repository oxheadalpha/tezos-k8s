let common = ./common_components.dhall

let chainConfig = ./chainConfig.dhall

let jobs = ./jobs.dhall

let k8s = common.k8s

let app_label = Some (toMap { app = "tezos-node" })

let makeNode =
      \(opts : chainConfig.Type) ->
        let specTemplate =
              k8s.PodTemplateSpec::{
              , metadata = k8s.ObjectMeta::{ labels = app_label }
              , spec = Some k8s.PodSpec::{
                , containers =
                  [ jobs.TezosNode::{
                    , image = Some opts.docker_image
                    , args = Some
                      [ "run", "--config-file", "/etc/tezos/config.json" ]
                    }
                  ]
                , initContainers = Some
                  [ jobs.make_import_key_job opts
                  , jobs.config_generator
                  , jobs.make_identity_job opts
                  ]
                , volumes = Some [ common.volumes.config, common.volumes.utils ]
                }
              }

        let spec =
              k8s.StatefulSetSpec::{
              , serviceName = "tezos-node"
              , podManagementPolicy = Some "Parallel"
              , selector = k8s.LabelSelector::{ matchLabels = app_label }
              , template = specTemplate
              , replicas = Some opts.additional_nodes
              , volumeClaimTemplates = Some
                [     common.makePVC
                        { metadata = common.tqMeta "var-volume"
                        , storage = "15Gi"
                        }
                  //  { apiVersion = None Text, kind = None Text }
                ]
              }

        in  k8s.StatefulSet::{
            , metadata = common.tqMeta "tezos-node"
            , spec = Some spec
            }

in  makeNode
