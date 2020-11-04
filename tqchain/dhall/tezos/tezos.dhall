let common = ./common_components.dhall

let JSON = common.Prelude.JSON

let k8s = common.k8s

let resource = k8s.Resource

let chainConfig = ./chainConfig.dhall

let utilsConfigMap = ./utils.dhall

let jobs = ./jobs.dhall

let makeNode = ./makeNode.dhall

let bootstrap = ./bootstrap.dhall

let zerotier = ./zerotier.dhall

let namespace
    : k8s.Namespace.Type
    = k8s.Namespace::{ metadata = k8s.ObjectMeta::{ name = Some "tqtezos" } }

in  { common
    , namespace
    , chainConfig
    , utilsConfigMap
    , jobs
    , makeNode
    , bootstrap
    , zerotier
    }
