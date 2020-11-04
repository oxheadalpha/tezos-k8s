let common = ./common_components.dhall

let Prelude = common.Prelude

let JSON = Prelude.JSON

let k8s = common.k8s

let Action = < Create | Invite >

let ChainOpts =
      { 
      , additional_nodes : Natural
      , baker : Bool
      , baker_command : Text
      , bootstrap_accounts : Text
      , bootstrap_mutez : Natural
      , bootstrap_timestamp : Text
      , bootstrap_peer: Text
      , chain_name : Text
      , docker_image : Text
      , genesis_chain_id : Text
      , keys : Prelude.Map.Type Text Text
      , protocol_hash : Text
      , zerotier_enabled: Bool
      , zerotier_data: Prelude.Map.Type Text Text
      }

let makeK8sSecret =
      λ(action : Action) →
      λ(secrets : ChainOpts) →
        let keyType = merge { Create = "c2VjcmV0", Invite = "cHVibGlj" } action

        let header =
              toMap
                { BOOTSTRAP_ACCOUNTS = secrets.bootstrap_accounts
                , KEYS_TYPE = keyType
                }

        in  k8s.Secret::{
            , data = Some (header # secrets.keys)
            , metadata = common.tqMeta "tezos-secret"
            }

let makeChainParams =
      λ(args : ChainOpts) →
        let paramJson =
              JSON.object
                ( toMap
                    { bootstrap_mutez =
                        JSON.string (Natural/show args.bootstrap_mutez)
                    , chain_name = JSON.string args.chain_name
                    , bootstrap_peers =
                        JSON.array [ JSON.string args.bootstrap_peer ]
                    , genesis_block = JSON.string args.genesis_chain_id
                    , timestamp = JSON.string args.bootstrap_timestamp
                    }
                )

        in  k8s.ConfigMap::{
            , data = Some (toMap { CHAIN_PARAMS = JSON.render paramJson })
            , metadata = common.tqMeta "tezos-config"
            }

in  { ChainOpts, makeK8sSecret, makeChainParams, Action, Type = ChainOpts }
