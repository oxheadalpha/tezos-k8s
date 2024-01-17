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
  params, config-init will run `octez-node config init` and grab the resulting
  network params.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldConfigInit" }}
  {{- if not .Values.node_config_network.genesis }}
    {{- "true" }}
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
  Is there a baker in nodes or is the bakers object not empty?
*/}}
{{- define "tezos.shouldDeployBakerConfig" }}
  {{- $hasBakerInNodes := false }}
  {{- range .Values.nodes }}
    {{- if (has "baker" .runs) }}
      {{- $hasBakerInNodes = true }}
    {{- end }}
  {{- end }}
  {{- $hasBakersObject := ne (len .Values.bakers) 0 }}
  {{- if or $hasBakerInNodes $hasBakersObject }}
    {{- "true" }}
  {{- else }}
    {{- "false" }}
  {{- end }}
{{- end }}

{{/* 
  Get list of accounts that are being used to bake, including bake_using_accounts lists from bakers
  object if it is non-empty. Returned as a json serialized dict.
*/}}
{{- define "tezos.getAccountsBaking" }}
  {{- $allAccounts := list }}
  {{- range $node := .Values.nodes }}
    {{- range $instance := $node.instances }}
      {{- if and .bake_using_accounts (kindIs "slice" .bake_using_accounts) }}
        {{- $allAccounts = concat $allAccounts .bake_using_accounts }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if ne (len .Values.bakers) 0 }}
    {{- range $baker := .Values.bakers }}
      {{- if and $baker.bake_using_accounts (kindIs "slice" $baker.bake_using_accounts) }}
        {{- $allAccounts = concat $allAccounts $baker.bake_using_accounts }}
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

{{/*
  Get list of authorized keys. Fails if any of the keys is not defined in the accounts.
*/}}
{{- define "tezos.getAuthorizedKeys" }}
  {{- $allAuthorizedKeys := list }}
  {{- /* Gather keys from nodes */}}
  {{- range $node := .Values.nodes }}
    {{- range $instance := $node.instances }}
      {{- if .authorized_keys }}
        {{- $allAuthorizedKeys = concat $allAuthorizedKeys .authorized_keys }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- /* Gather keys from octezSigners */}}
  {{- range $signer := .Values.octezSigners }}
    {{- if $signer.authorized_keys }}
      {{- $allAuthorizedKeys = concat $allAuthorizedKeys $signer.authorized_keys }}
    {{- end }}
  {{- end }}
  {{- /* Ensure all keys are defined in accounts and fail otherwise */}}
  {{- $allAuthorizedKeys = uniq $allAuthorizedKeys }}
  {{- range $key := $allAuthorizedKeys }}
    {{- if not (index $.Values.accounts $key "key") }}
      {{- fail (printf "Authorized key '%s' is not defined in accounts." $key) }}
    {{- end }}
  {{- end }}
{{- end }}
