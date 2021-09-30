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
  Should nodes wait for a bootstrap node to be ready.
  Yes if these conditions are met:
  - Node is not an invitee to a private chain
  - There are chain genesis parameters specified, i.e. this is not a public chain
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldWaitForBootstrapNode" -}}
{{- if and (not .Values.is_invitation) (hasKey .Values.node_config_network "genesis")}}
{{- "true" }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{- define "tezos.shouldDeploySignerStatefulset" -}}
{{- $signers := .Values.signers | default dict }}
{{- if and (not .Values.is_invitation) ($signers | len) }}
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
  When activating a protocol, check whether faucet commitments
  should be deterministically generated from a seed.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldInitializeDeterministicFaucet" -}}
{{ $deterministic_faucet := .Values.activation.deterministic_faucet | default dict }}
{{- if and ($deterministic_faucet.seed)  ($deterministic_faucet.number_of_accounts) }}
{{- "true" }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
  Checks if filesystem archive should be downloaded.
*/}}
{{- define "tezos.shouldDownloadTarball" -}}
{{- if (.Values.tarball_url)}}
  {{- if or (.Values.full_snapshot_url)  (.Values.rolling_snapshot_url) }}
    {{- fail ".Values.tarball_url cannot be defined with .Values.full_snapshot_url or .Values.rolling_snapshot_url" }}
  {{- else-}}
  {{- "true" }}
  {{- end }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
  Checks if a snapshot should be downloaded. Either full_snapshot_url or
  rolling_snapshot_url must not be null.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldDownloadSnapshot" -}}
{{- if or (.Values.full_snapshot_url)  (.Values.rolling_snapshot_url) }}
  {{- if (.Values.tarball_url)}}
  {{- fail ".Values.full_snapshot_url or .Values.rolling_snapshot_url cannot be defined with .Values.tarball_url" }}
  {{- else }}
  {{- "true" }}
  {{- end }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
  Checks if we need to run tezos-node config init to help
  config-generator obtain the appropriate parameters to run
  a network.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldConfigInit" }}
{{- if not (.Values.node_config_network.genesis) }}
{{- "true" }}
{{- else }}
{{- "" }}
{{- end }}
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
