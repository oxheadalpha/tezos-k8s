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

{{/*
  Don't deploy the baker statefulset and its headless service if
  there are no bakers specified.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldDeployBakerStatefulset" -}}
{{- $baking_nodes := .Values.nodes.baking | default dict }}
{{- if and (not .Values.is_invitation) ($baking_nodes | len) }}
{{- "true" }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
  Don't deploy the regular node statefulset and its headless service if
  there are no regular nodes specified.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldDeployRegularNodeStatefulset" -}}
{{- $regular_nodes := .Values.nodes.regular | default dict }}
{{- if ($regular_nodes | len) }}
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
  Checks if a snapshot should be downloaded. Either full_snapshot_url or
  rolling_snapshot_url must not be null.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.shouldDownloadSnapshot" -}}
{{- if or (.Values.full_snapshot_url)  (.Values.rolling_snapshot_url) }}
{{- "true" }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
  BCD indexer
  Checks if indexer config has an indexer and rpc_url set.
  Then checks if indexer name is "bcd".
  Returns the true type or empty string which is falsey.
*/}}
{{- define "tezos.shouldDeployBcdIndexer" -}}
{{- $index_config := .Values.indexer | default dict }}
{{- if and $index_config.name $index_config.rpc_url }}
{{- if eq $index_config.name "bcd" }}
{{- "true" }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
  Nomadic indexer
*/}}
{{- define "tezos.shouldDeployNomadicIndexer" -}}
{{- $index_config := .Values.indexer | default dict }}
{{- if and $index_config.name $index_config.rpc_url }}
{{- if eq $index_config.name "nomadic" }}
{{- "true" }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}
{{- end }}
