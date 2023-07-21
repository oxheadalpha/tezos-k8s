{{/*
  Checks if Zerotier config has a network and token set.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.doesZerotierConfigExist" -}}
  {{- $zerotier_config := .Values.zerotier_config | default dict }}
  {{- if and ($zerotier_config.zerotier_network)  ($zerotier_config.zerotier_token) }}
    {{- "true" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}

{{/*
  Should nodes wait for DNS to be ready for peers
  Yes if these conditions are met:
  - Node is not an invitee to a private chain
  - There are chain genesis parameters specified, i.e. this is not a public chain
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldWaitForDNSNode" -}}
  {{- if and (not .Values.is_invitation) (hasKey .Values.node_config_network "genesis")}}
    {{- "true" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}

{{/*
  Checks if a protocol should be activated. There needs to be a protocol_hash
  and protocol_parameters.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldActivateProtocol" -}}
  {{ $activation := .Values.activation | default dict }}
  {{- if and ($activation.protocol_hash)  ($activation.protocol_parameters) }}
    {{- "true" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}

{{/*
  Checks if a snapshot/tarball should be downloaded.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldDownloadSnapshot" -}}
  {{- if or (.Values.full_snapshot_url) (.Values.full_tarball_url)
            (.Values.rolling_snapshot_url) (.Values.rolling_tarball_url)
            (.Values.archive_tarball_url) (.Values.snapshot_source) }}
    {{- if or (and (.Values.rolling_tarball_url) (.Values.rolling_snapshot_url))
        (and (.Values.full_tarball_url) (.Values.full_snapshot_url))
    }}
      {{- fail "Either only a snapshot url or tarball url may be specified per Tezos node history mode" }}
    {{- else }}
      {{- "true" }}
    {{- end }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}

{{/*
  Checks if we need to run octez-node config init to help config-generator
  obtain the appropriate parameters to run a network. If there are no genesis
  params, we are dealing with a public network and want its default config.json
  to be created. If we are dealing with a custom chain, we validate that the
  `join_public_network` field is not set to true.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldConfigInit" }}
  {{- if not .Values.node_config_network.genesis }}
    {{- "true" }}
  {{- else if .Values.node_config_network.join_public_network }}
    {{- fail "'node_config_network' is defining a custom chain while being instructed to join a public network" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}

{{/*
  If a Tezos node identity is defined for an instance, create a secret
  for its node class. All identities for all instances of the node
  class will be stored in it. Each instance will look up its identity
  values by its hostname, e.g. archive-node-0.
*/}}
{{- define "tezos.includeNodeIdentitySecret" }}
  {{- range $index, $config := $.node_vals.instances }}
    {{- if .identity }}
      {{- $_ := set $.node_identities (print $.node_class "-" $index) .identity }}
    {{- end }}
  {{- end }}
  {{- if len $.node_identities }}
apiVersion: v1
data:
  NODE_IDENTITIES: {{ $.node_identities | toJson | b64enc }}
kind: Secret
metadata:
  name: {{ $.node_class }}-identities-secret
  namespace: {{ $.Release.Namespace }}
---
  {{- end }}
{{- end }}

{{/*
  Is there a baker?
*/}}
{{- define "tezos.shouldDeployBakerConfig" }}
  {{- range .Values.nodes }}
    {{- if (has "baker" .runs) }}
      {{- "true" }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
  Get list of accounts that are being used to bake. Returned as a json
  serialized dict because of how Helm renders everything returned from
  a template as string. Function callers need to parse the returned
  value like so: `fromJson | values | first`. A dict and not list is
  returned because of the way `fromJson` works which expects a type of
  map[string]interface {}.
*/}}
{{- define "tezos.getAccountsBaking" }}
  {{- $allAccounts := list }}
  {{- range $node := .Values.nodes }}
    {{- range $instance := $node.instances }}
    {{- if and .bake_using_accounts (kindIs "slice" .bake_using_accounts) }}
        {{- $allAccounts = concat $allAccounts .bake_using_accounts }}
      {{- else if and .bake_using_account (kindIs "string" .bake_using_account) }}
        {{- $allAccounts = append $allAccounts .bake_using_account }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- dict "data" (uniq $allAccounts) | toJson }}
{{- end }}

{{/*
  Should deploy TZKT indexer?
*/}}
{{- define "tezos.shouldDeployTzktIndexer" -}}
  {{- $indexers := .Values.indexers | default dict }}
  {{- if $indexers.tzkt }}
    {{- $tzkt_config := $indexers.tzkt.config | default dict }}
    {{- if $tzkt_config.rpc_url }}
      {{- "true" }}
    {{- else }}
      {{- "" }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
  Checks if `bcdIndexer` has `rpcUrl` and `dbPassword` set.
  Returns the true type or empty string which is falsey.
*/}}
{{- define "tezos.shouldDeployBcdIndexer" -}}
  {{- if and .rpcUrl .db.password }}
    {{- "true" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}

{{- /* Make sure only a single signer signs for an account */}}
{{- define "tezos.checkDupeSignerAccounts" }}
  {{- $accountNames := dict }}
  {{- range $signer := concat list
    (values (.Values.octezSigners | default dict ))
    (values (.Values.tacoinfraSigners | default dict ))
  }}

    {{- range $account := $signer.accounts }}
      {{- if hasKey $accountNames $account }}
        {{- fail (printf "Account '%s' is specified by more than one remote signer" $account) }}
      {{- else }}
        {{- $_ := set $accountNames $account "" }}
      {{- end }}
    {{- end }}

  {{- end }}
{{- end }}

{{- define "tezos.hasKeyPrefix" }}
  {{- $keyPrefixes := list "edsk" "edpk" "spsk" "sppk" "p2sk" "p2pk" }}
  {{- has (substr 0 4 .) $keyPrefixes | ternary "true" "" }}
{{- end }}

{{- define "tezos.hasKeyHashPrefix" }}
  {{- $keyHashPrefixes := list "tz1" "tz2" "tz3" }}
  {{- has (substr 0 3 .) $keyHashPrefixes | ternary "true" "" }}
{{- end }}

{{- define "tezos.hasSecretKeyPrefix" }}
  {{- if not (include "tezos.hasKeyPrefix" .key) }}
    {{- fail (printf "'%s' account's key is not a valid key." .account_name) }}
  {{- end }}
  {{- substr 2 4 .key | eq "sk" | ternary "true" "" }}
{{- end }}

{{- define "tezos.validateAccountKeyPrefix" }}
  {{- if (not (or
      (include "tezos.hasKeyPrefix" .key)
      (include "tezos.hasKeyHashPrefix" .key)
    )) }}
    {{- fail (printf "'%s' account's key is not a valid key or key hash." .account_name) }}
  {{- end }}
  {{- "true" }}
{{- end }}
