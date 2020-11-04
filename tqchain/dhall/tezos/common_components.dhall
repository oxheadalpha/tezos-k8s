let k8s = ./lightK8s.dhall

let Prelude =
      https://prelude.dhall-lang.org/package.dhall

let volumeMounts =
      { var = k8s.VolumeMount::{ mountPath = "/var/tezos", name = "var-volume" }
      , config = k8s.VolumeMount::{
        , mountPath = "/etc/tezos"
        , name = "config-volume"
        }
      , utils = k8s.VolumeMount::{
        , mountPath = "/opt/tqtezos"
        , name = "tqtezos-utils"
        }
      }

let volumes =
      { var = k8s.Volume::{
        , name = "var-volume"
        , emptyDir = Some k8s.EmptyDirVolumeSource.default
        }
      , config = k8s.Volume::{
        , name = "config-volume"
        , emptyDir = Some k8s.EmptyDirVolumeSource.default
        }
      , utils = k8s.Volume::{
        , name = "tqtezos-utils"
        , configMap = Some k8s.ConfigMapVolumeSource::{
          , name = Some "tqtezos-utils"
          }
        }
      , bootstrap_pvc_var = k8s.Volume::{
        , name = "var-volume"
        , persistentVolumeClaim = Some k8s.PersistentVolumeClaimVolumeSource::{
          , claimName = "tezos-bootstrap-node-pv-claim"
          }
        }
      }

let ports =
      { rpc = k8s.ContainerPort::{
        , containerPort = 8732
        , name = Some "tezos-rpc"
        }
      , p2p = k8s.ContainerPort::{
        , containerPort = 9732
        , name = Some "tezos-p2p"
        }
      , net = k8s.ContainerPort::{
        , containerPort = 9732
        , name = Some "tezos-net"
        }
      }

let probes =
      { readiness = k8s.Probe::{
        , timeoutSeconds = Some 1
        , periodSeconds = Some 2
        , initialDelaySeconds = Some 2
        , exec = Some k8s.ExecAction::{
          , command = Some [ "nc", "-z", "127.0.0.1", "8732" ]
          }
        }
      }

let makePVC =
      \(args : { metadata : k8s.ObjectMeta.Type, storage : Text }) ->
        k8s.PersistentVolumeClaim::{
        , metadata = args.metadata
        , spec = Some k8s.PersistentVolumeClaimSpec::{
          , accessModes = Some [ "ReadWriteOnce" ]
          , resources = Some k8s.ResourceRequirements::{
            , requests = Some (toMap { storage = args.storage })
            }
          }
        }

let tqMeta =
      \(name : Text) ->
        k8s.ObjectMeta::{ name = Some name, namespace = Some "tqtezos" }

in  { volumeMounts, volumes, ports, probes, makePVC, k8s, Prelude, tqMeta }
