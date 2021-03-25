{{- define "tezos.localvars.pod_envvars" }}
- name: MY_POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: MY_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: MY_NODE_TYPE
{{- if contains "baker" .Template.Name }}
  value: {{ .Values.baker_statefulset.node_type }}
{{- else }}
  value: {{ .Values.regular_node_statefulset.node_type }}
{{- end }}
{{- end }}

{{- define "tezos.init_container.config_generator" }}
- image: {{ .Values.tezos_k8s_images.config_generator }}
  imagePullPolicy: IfNotPresent
  name: config-generator
  args:
    - "--generate-config-json"
  envFrom:
    - secretRef:
        name: tezos-secret
    - configMapRef:
        name: tezos-config
  env:
{{- include "tezos.localvars.pod_envvars" . | indent 4 }}
  volumeMounts:
    - mountPath: /etc/tezos
      name: config-volume
    - mountPath: /var/tezos
      name: var-volume
{{- end }}

{{- define "tezos.init_container.wait_for_bootstrap" }}
{{- if include "tezos.shouldWaitForBootstrapNode" . }}
- image: {{ .Values.tezos_k8s_images.wait_for_bootstrap }}
  imagePullPolicy: IfNotPresent
  name: wait-for-bootstrap
  envFrom:
    - configMapRef:
        name: tezos-config
  volumeMounts:
    - mountPath: /var/tezos
      name: var-volume
{{- end }}
{{- end }}

{{- define "tezos.init_container.snapshot_downloader" }}
{{- if include "tezos.shouldDownloadSnapshot" . }}
- image: "{{ .Values.tezos_k8s_images.snapshot_downloader }}"
  imagePullPolicy: IfNotPresent
  name: snapshot-downloader
  volumeMounts:
    - mountPath: /var/tezos
      name: var-volume
    - mountPath: /etc/tezos
      name: config-volume
  envFrom:
    - configMapRef:
        name: tezos-config
  env:
{{- include "tezos.localvars.pod_envvars" . | indent 4 }}
{{- end }}
{{- end }}

{{- define "tezos.container.node" }}
- args:
    - run
    - "--bootstrap-threshold"
    - '0'
    - "--config-file"
    - /etc/tezos/config.json
  command:
    - /usr/local/bin/tezos-node
  image: "{{ .Values.images.tezos }}"
  imagePullPolicy: IfNotPresent
  name: tezos-node
  ports:
    - containerPort: 8732
      name: tezos-rpc
    - containerPort: 9732
      name: tezos-net
  volumeMounts:
    - mountPath: /etc/tezos
      name: config-volume
    - mountPath: /var/tezos
      name: var-volume
{{- end }}

{{- define "tezos.container.baker" }}
- image: "{{ .Values.tezos_k8s_images.baker_endorser }}"
  imagePullPolicy: IfNotPresent
  name: baker
  volumeMounts:
  - mountPath: /var/tezos
    name: var-volume
  envFrom:
    - configMapRef:
        name: tezos-config
    - secretRef:
        name: tezos-secret
  env:
{{- include "tezos.localvars.pod_envvars" . | indent 4 }}
    - name: DAEMON
      value: baker
{{- end }}

{{- define "tezos.container.endorser" }}
- image: "{{ .Values.tezos_k8s_images.baker_endorser }}"
  imagePullPolicy: IfNotPresent
  name: endorser
  volumeMounts:
  - mountPath: /var/tezos
    name: var-volume
  envFrom:
    - configMapRef:
        name: tezos-config
    - secretRef:
        name: tezos-secret
  env:
{{- include "tezos.localvars.pod_envvars" . | indent 4 }}
    - name: DAEMON
      value: endorser
{{- end }}

{{/*
// * The zerotier containers:
*/}}

{{- define "tezos.init_container.zerotier" }}
{{- if (include "tezos.doesZerotierConfigExist" .) }}
- envFrom:
    - configMapRef:
        name: zerotier-config
  image: "{{ .Values.tezos_k8s_images.zerotier }}"
  imagePullPolicy: IfNotPresent
  name: get-zerotier-ip
  securityContext:
    capabilities:
      add:
        - NET_ADMIN
        - NET_RAW
        - SYS_ADMIN
    privileged: true
  volumeMounts:
    - mountPath: /var/tezos
      name: var-volume
    - mountPath: /dev/net/tun
      name: dev-net-tun
  env:
{{- include "tezos.localvars.pod_envvars" . | indent 4 }}
{{- end }}
{{- end }}

{{- define "tezos.container.zerotier" }}
{{- if (include "tezos.doesZerotierConfigExist" .) }}
- args:
    - "-c"
    - "echo 'starting zerotier' && zerotier-one /var/tezos/zerotier"
  command:
    - sh
  image: "{{ .Values.tezos_k8s_images.zerotier }}"
  imagePullPolicy: IfNotPresent
  name: zerotier
  securityContext:
    capabilities:
      add:
        - NET_ADMIN
        - NET_RAW
        - SYS_ADMIN
    privileged: true
  volumeMounts:
    - mountPath: /var/tezos
      name: var-volume
{{- end }}
{{- end }}
