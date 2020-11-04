let tezos = ./tezos/tezos.dhall

let config = tezos.chainConfig

let k8s = tezos.common.k8s.Resource

let makeZerotier =
      λ(opts : tezos.chainConfig.Type) →
        if    opts.zerotier_enabled
        then  [ k8s.PersistentVolumeClaim tezos.zerotier.pvc
              , k8s.ConfigMap (tezos.zerotier.makeZTConfig opts)
              , k8s.DaemonSet tezos.zerotier.bridge
              ]
        else  [] : List k8s

let create =
      λ(opts : tezos.chainConfig.Type) →
          [ k8s.Namespace tezos.namespace
          , k8s.Secret
              (tezos.chainConfig.makeK8sSecret config.Action.Create opts)
          , k8s.ConfigMap tezos.utilsConfigMap
          , k8s.ConfigMap (tezos.chainConfig.makeChainParams opts)
          , k8s.StatefulSet (tezos.makeNode opts)
          , k8s.Job (tezos.bootstrap.makeActivateJob opts)
          , k8s.Service tezos.bootstrap.port_services.rpc
          , k8s.Service tezos.bootstrap.port_services.p2p
          , k8s.Deployment (tezos.bootstrap.makeDeployment opts)
          , k8s.PersistentVolumeClaim tezos.bootstrap.pvc
          ]
        # makeZerotier opts

let invite =
      λ(opts : tezos.chainConfig.Type) →
          [ k8s.Namespace tezos.namespace
          , k8s.Secret
              (tezos.chainConfig.makeK8sSecret config.Action.Invite opts)
          , k8s.ConfigMap tezos.utilsConfigMap
          , k8s.ConfigMap (tezos.chainConfig.makeChainParams opts)
          , k8s.StatefulSet (tezos.makeNode opts)
          ]
        # makeZerotier opts

in  { tezos, create, invite }
