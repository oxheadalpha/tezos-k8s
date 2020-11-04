-- TODO: refactor for reusability and readability
let common = ./common_components.dhall

let chainConfig = ./chainConfig.dhall

let jobs = ./jobs.dhall

let k8s = common.k8s

let app_label = Some (toMap { app = "tezos-bootstrap-node" })

let makeActivateJob =
      \(opts : chainConfig.Type) ->
        let varVolume = common.volumes.bootstrap_pvc_var

        let spec =
              k8s.JobSpec::{
              , template = k8s.PodTemplateSpec::{
                , metadata = k8s.ObjectMeta::{ name = Some "activate-job" }
                , spec = Some k8s.PodSpec::{
                  , initContainers = Some
                    [     jobs.make_import_key_job opts
                      //  { args = None (List Text) }
                    , jobs.config_generator
                    , jobs.wait_for_node
                    , jobs.make_activate_container opts
                    , jobs.make_bake_once opts
                    ]
                  , containers =
                    [ k8s.Container::{
                      , name = "job-done"
                      , image = Some "busybox"
                      , command = Some
                        [ "sh", "-c", "echo \"private chain activated\"" ]
                      }
                    ]
                  , restartPolicy = Some "Never"
                  , volumes = Some
                    [ common.volumes.config, varVolume, common.volumes.utils ]
                  }
                }
              }

        in  k8s.Job::{
            , metadata = common.tqMeta "activate-job"
            , spec = Some spec
            }

let port_services =
      let info_type = { name : Text, port : Natural, nodePort : Natural }

      let make_service =
            \(port_info : info_type) ->
              k8s.Service::{
              , metadata =
                  common.tqMeta "tezos-bootstrap-node-${port_info.name}"
              , spec = Some k8s.ServiceSpec::{
                , type = Some "NodePort"
                , ports = Some
                  [ k8s.ServicePort::{
                    , port = port_info.port
                    , nodePort = Some port_info.nodePort
                    }
                  ]
                , selector = app_label
                }
              }

      in  { rpc = make_service { name = "rpc", port = 8732, nodePort = 31732 }
          , p2p = make_service { name = "p2p", port = 9732, nodePort = 30732 }
          }

let makeDeployment =
      \(opts : chainConfig.Type) ->
        let bakerJob =
              if    opts.baker
              then  [ jobs.make_baker_job opts ]
              else  [] : List k8s.Container.Type

        let specTemplate =
              k8s.PodTemplateSpec::{
              , metadata = k8s.ObjectMeta::{ labels = app_label }
              , spec = Some k8s.PodSpec::{
                , securityContext = Some k8s.PodSecurityContext::{
                  , fsGroup = Some 100
                  }
                , initContainers = Some
                  [ jobs.make_import_key_job opts
                  , jobs.config_generator
                  , jobs.make_identity_job opts
                  ]
                , containers =
                      [ jobs.TezosNode::{
                        , image = Some opts.docker_image
                        , args = Some
                          [ "run"
                          , "--bootstrap-threshold"
                          , "0"
                          , "--config-file"
                          , "/etc/tezos/config.json"
                          ]
                        , ports = Some [ common.ports.rpc, common.ports.net ]
                        }
                      ]
                    # bakerJob
                , volumes = Some
                  [ common.volumes.config
                  , common.volumes.utils
                  , common.volumes.bootstrap_pvc_var
                  ]
                }
              }

        let spec =
              Some
                k8s.DeploymentSpec::{
                , selector = k8s.LabelSelector::{ matchLabels = app_label }
                , strategy = Some k8s.DeploymentStrategy::{
                  , type = Some "Recreate"
                  }
                , template = specTemplate
                }

        in  k8s.Deployment::{
            , metadata = common.tqMeta "tezos-bootstrap-node"
            , spec
            }

let pvc =
      common.makePVC
        { metadata = common.tqMeta "tezos-bootstrap-node-pv-claim"
        , storage = "15Gi"
        }

in  { makeActivateJob, port_services, makeDeployment, pvc }
