let common = ./common_components.dhall

let chainConfig = ./chainConfig.dhall

let Prelude = common.Prelude

let k8s = common.k8s

let pvc =
      common.makePVC
        { metadata = common.tqMeta "zerotier-pv-claim", storage = "1Gi" }

let makeZTConfig =
      λ(opts : chainConfig.Type) →
        k8s.ConfigMap::{
        , metadata = common.tqMeta "zerotier-config"
        , data = Some (toMap { AUTOJOIN = "true" } # opts.zerotier_data)
        }

let app_label = Some (toMap { name = "zerotier-one" })

let bridge =
      let env_vars =
            let var_keys =
                  [ "NETWORK_IDS", "ZTHOSTNAME", "ZTAUTHTOKEN", "AUTOJOIN" ]

            let make_env_var =
                  λ(var_key : Text) →
                    k8s.EnvVar::{
                    , name = var_key
                    , valueFrom = Some k8s.EnvVarSource::{
                      , configMapKeyRef = Some k8s.ConfigMapKeySelector::{
                        , key = var_key
                        , name = Some "zerotier-config"
                        }
                      }
                    }

            in  Prelude.List.map Text k8s.EnvVar.Type make_env_var var_keys

      in  k8s.DaemonSet::{
          , metadata = common.tqMeta "zerotier-bridge"
          , spec = Some k8s.DaemonSetSpec::{
            , selector = k8s.LabelSelector::{ matchLabels = app_label }
            , template = k8s.PodTemplateSpec::{
              , metadata = k8s.ObjectMeta::{ labels = app_label }
              , spec = Some k8s.PodSpec::{
                , hostNetwork = Some True
                , containers =
                  [ k8s.Container::{
                    , name = "zerotier-bridge"
                    , image = Some "tqasmith/zerotier-k8s:latest"
                    , env = Some env_vars
                    , securityContext = Some k8s.SecurityContext::{
                      , privileged = Some True
                      , capabilities = Some k8s.Capabilities::{
                        , add = Some [ "NET_ADMIN", "NET_RAW", "SYS_ADMIN" ]
                        }
                      }
                    , volumeMounts = Some
                      [ k8s.VolumeMount::{
                        , name = "dev-net-tun"
                        , mountPath = "/dev/net/tun"
                        }
                      , k8s.VolumeMount::{
                        , name = "ztdata"
                        , mountPath = "/var/lib/zerotier-one"
                        }
                      ]
                    }
                  ]
                , volumes = Some
                  [ k8s.Volume::{
                    , name = "dev-net-tun"
                    , hostPath = Some k8s.HostPathVolumeSource::{
                      , path = "/dev/net/tun"
                      }
                    }
                  , k8s.Volume::{
                    , name = "ztdata"
                    , persistentVolumeClaim = Some k8s.PersistentVolumeClaimVolumeSource::{
                      , claimName = "zerotier-pv-claim"
                      }
                    }
                  ]
                }
              }
            }
          }

in  { pvc, makeZTConfig, bridge }
