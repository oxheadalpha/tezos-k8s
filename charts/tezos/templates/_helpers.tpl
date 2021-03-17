{{- define "tezos.isThereZerotierConfig" -}}
{{- $zerotier_config := .Values.zerotier_config | default dict }}
{{- if and ($zerotier_config.zerotier_network)  ($zerotier_config.zerotier_token) }}
true
{{- end }}
{{- end }}
