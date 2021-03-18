{{- define "tezos.isThereZerotierConfig" -}}
{{- $zerotier_config := .Values.zerotier_config | default dict }}
{{- if and ($zerotier_config.zerotier_network)  ($zerotier_config.zerotier_token) }}
true
{{- end }}
{{- end }}

{{- define "tezos.shouldActivateProtocol" -}}
{{ $activation := .Values.activation | default dict }}
{{- if and ($activation.protocol_hash)  ($activation.protocol_parameters) }}
true
{{- end }}
{{- end }}
