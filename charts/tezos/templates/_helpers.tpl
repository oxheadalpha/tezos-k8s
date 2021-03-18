{{/*
  Checks if Zerotier config has a network and token set.
  Returns a string "true" or empty string which is falsey.
*/}}
{{- define "tezos.isThereZerotierConfig" -}}
{{- $zerotier_config := .Values.zerotier_config | default dict }}
{{- if and ($zerotier_config.zerotier_network)  ($zerotier_config.zerotier_token) }}
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
