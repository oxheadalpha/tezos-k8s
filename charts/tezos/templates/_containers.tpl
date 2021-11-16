{{- define "tezos.localvars.pod_envvars" }}
- name: MY_POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: MY_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: MY_POD_TYPE
  value: node
  {{- if hasKey . "node_class" }}
- name: MY_NODE_CLASS
  value: {{ .node_class }}
  {{- end }}
{{- end }}

{{- /*
     * Now, we define a generic container template.  We pass in a set
     * of arguments via a dictionary specified as a global variable .call_args.
     * We use this approach as if we pass the dict directly to "include",
     * we lose access to global variables, it overrides $.
     *
     * The arguments are as follows:
     *
     *    type           the container type, e.g.: baker, wait-for-dns
     *    name           the name of the statefulset, defaults to type
     *    image          one of: octez, tezedge, utils
     *    command        the command
     *    args           the list of arguments to the command
     *    run_script     define the command as a script from the scripts
     *                   directory corresponding to the container type,
     *                   so a type of wait-for-dns will include the script
     *                   scripts/wait-for-dns.sh and pass it as a single
     *                   argument to /bin/sh -c.  For image == octez, this
     *                   is the default.
     *    script_command overide the name of the script.  We still look
     *                   in the scripts directory and postpend ".sh"
     *    with_config    bring in the configMap defaults true only on utils.
     *    with_secret    bring in the secrets map.
     *    localvars      set env vars MY_* Defaults to true only on utils.
     * 
     * If you want to have a custom command, just leave out "with_script"
     * and put it after this include indented by 2 spaces.
     */ -}}

{{- define "tezos.generic_container" }}

{{- /*
     * First, we set up all of the default values:
     */ -}}

{{- if not (hasKey .call_args "name") }}
{{- $_ := set .call_args "name" .call_args.type }}
{{- end }}
{{- if not (hasKey .call_args "with_config") }}
{{- $_ := set .call_args "with_config" (eq .call_args.image "utils") }}
{{- end }}
{{- if not (hasKey .call_args "localvars") }}
{{- $_ := set .call_args "localvars" (eq .call_args.image "utils") }}
{{- end }}
{{- if not (hasKey .call_args "run_script") }}
{{- $_ := set .call_args "run_script" (eq .call_args.image "octez") }}
{{- end }}
{{- if not (hasKey .call_args "script_command") }}
{{- $_ := set .call_args "script_command" .call_args.type }}
{{- end }}

{{- /*
     * And, now, we generate the YAML:
     */ -}}

- name: {{ .call_args.name }}
{{- if eq .call_args.image "octez" }}
{{ $node_vals_images := $.node_vals.images | default dict }}
  image: "{{ or $node_vals_images.octez $.Values.images.octez }}"
{{- else if eq .call_args.image "tezedge" }}
{{- else }}
  image: "{{ .Values.tezos_k8s_images.utils }}"
{{- end }}
  imagePullPolicy: IfNotPresent
{{- if .call_args.run_script }}
  command:
    - /bin/sh
  args:
    - "-c"
    - |
{{ tpl (.Files.Get (print "scripts/" .call_args.script_command ".sh")) . | indent 6 }}
{{- end }}
{{- if .call_args.args }}
  args:
{{ range .call_args.args }}
    - {{ . }}
{{ end }}
{{- end }}
  envFrom:
    {{- if .call_args.with_secret }}
    - secretRef:
        name: tezos-secret
    {{- end }}
    {{- if .call_args.with_config }}
    - configMapRef:
        name: tezos-config
    {{- end }}
  env:
  {{- if .call_args.localvars }}
  {{- include "tezos.localvars.pod_envvars" $ | indent 4 }}
  {{- end }}
  - name: DAEMON
    value: {{ .call_args.type }}
  {{- range $key, $val := $.node_vals.env }}
    value: {{ $val }}
  {{- end }}
  {{- range $key, $val := $.Values.node_globals.env }}
  - name:  {{ $key }}
    value: {{ $val }}
  {{- end }}
  volumeMounts:
    - mountPath: /etc/tezos
      name: config-volume
    - mountPath: /var/tezos
      name: var-volume
{{- $_ := unset $ "call_args" }}
{{- end }}

{{- /*
     * We are finished defining tezos.generic_container, and are now
     * on to defining the actual containers.
     */ -}}

{{- define "tezos.init_container.config_init" }}
{{- if include "tezos.shouldConfigInit" . }}
{{- $_ := set $ "call_args" (dict "type"           "config-init"
                                  "image"          "octez"
                                  "with_config"    1
) }}
{{ include "tezos.generic_container" $ }}
{{- end }}
{{- end }}

{{- define "tezos.init_container.config_generator" }}
{{- $_ := set $ "call_args" (dict "type"        "config-generator"
                                  "image"       "utils"
                                  "with_secret" 1
                                  "args"        (list "config-generator"
                                                      "--generate-config-json")
) }}
{{- include "tezos.generic_container" $ }}
{{- end }}

{{- define "tezos.init_container.chain_initiator" }}
{{- $_ := set $ "call_args" (dict "type"           "chain-initiator"
                                  "image"          "octez"
                                  "with_config"    1
) }}
{{- include "tezos.generic_container" $ }}
{{- end }}

{{- define "tezos.init_container.wait_for_dns" }}
{{- if include "tezos.shouldWaitForDNSNode" . }}
{{- $_ := set $ "call_args" (dict "type"           "wait-for-dns"
                                  "image"          "utils"
                                  "localvars"      0
                                  "args"           (list "wait-for-dns")
) }}
{{- include "tezos.generic_container" $ }}
{{- end }}
{{- end }}

{{- define "tezos.init_container.snapshot_downloader" }}
{{- if include "tezos.shouldDownloadSnapshot" . }}
{{- $_ := set $ "call_args" (dict "type"        "snapshot-downloader"
                                  "image"       "utils"
                                  "args"        (list "snapshot-downloader")
) }}
{{- include "tezos.generic_container" $ }}
{{- end }}
{{- end }}

{{- define "tezos.init_container.snapshot_importer" }}
{{- if include "tezos.shouldDownloadSnapshot" . }}
{{- $_ := set $ "call_args" (dict "type"           "snapshot-importer"
                                  "image"          "octez"
                                  "with_config"    1
) }}
{{- include "tezos.generic_container" $ }}
{{- end }}
{{- end }}

{{- define "tezos.getNodeImplementation" }}
{{- $containers := $.node_vals.runs }}
  {{- if and (has "tezedge_node" $containers) (has "octez_node" $containers) }}
    {{- fail "Only either tezedge_node or octez_node container can be specified in 'runs' field " }}
  {{- else if (has "octez_node" $containers) }}
    {{- "octez" }}
  {{- else if (has "tezedge_node" $containers) }}
    {{- "tezedge" }}
  {{- else }}
    {{- fail "No Tezos node container was specified in 'runs' field. Must specify tezedge_node or octez_node" }}
  {{- end }}
{{- end }}

{{- define "tezos.container.node" }}
{{- if eq (include "tezos.getNodeImplementation" $) "octez" }}
{{- $_ := set $ "call_args" (dict "type"           "octez-node"
                                  "image"          "octez"
                                  "with_config"    0
) }}
{{- include "tezos.generic_container" $ }}
  ports:
    - containerPort: 8732
      name: tezos-rpc
    - containerPort: 9732
      name: tezos-net
  readinessProbe:
    httpGet:
      path: /is_synced
      port: 31732
{{- end }}
{{- end }}

{{- define "tezos.container.tezedge" }}
{{- if eq (include "tezos.getNodeImplementation" $) "tezedge" }}
{{- $node_vals_images := $.node_vals.images | default dict }}
- name: tezedge-node
  image: {{ or ($node_vals_images.tezedge) (.Values.images.tezedge) }}
  command:
    - /light-node
  args:
    - "--config-file=/etc/tezos/tezedge.conf"
  imagePullPolicy: IfNotPresent
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
  env:
{{- include "tezos.localvars.pod_envvars" $ | indent 4 }}
{{- end }}
{{- end }}

{{- define "tezos.container.bakers" }}
{{- if has "baker" $.node_vals.runs }}
{{ $node_vals_images := $.node_vals.images | default dict }}
{{- range .Values.protocols }}
{{- if eq (include "tezos.getNodeImplementation" $) "octez" }}
{{- $_ := set $ "command_in_tpl" .command }}
{{- $_ := set $ "call_args" (dict "name"      (print "baker-" (lower .command))
                                  "type"        "baker"
                                  "image"       "octez"
                                  "with_config" 1
                                  "localvars"   1
) }}
{{- include "tezos.generic_container" $ }}

{{- if or (regexFind "GRANAD" .command) (regexFind "Hangz" .command) }}
{{- /*
Also start endorser for protocols that need it.
*/}}
{{- $_ := set $ "call_args" (dict "name"  (print "endorser-" (lower .command))
                                  "type"        "endorser"
                                  "image"       "octez"
                                  "script"      "baker"
                                  "with_config" 1
                                  "localvars"   1
) }}
{{- include "tezos.generic_container" $ }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}


{{- define "tezos.container.logger" }}
{{- if has "logger" $.node_vals.runs }}
{{- $_ := set $ "call_args" (dict "type"        "logger"
                                  "image"       "utils"
                                  "args"        (list "logger")
	"with_secret" 1
	"with_config" 1
) }}
{{- include "tezos.generic_container" $ }}
{{- end }}
{{- end }}

{{- define "tezos.container.metrics" }}
{{- if has "metrics" $.node_vals.runs }}
- image: "registry.gitlab.com/nomadic-labs/tezos-metrics"
  args:
    - "--listen-prometheus=6666"
    - "--data-dir=/var/tezos/node/data"
  imagePullPolicy: IfNotPresent
  name: metrics
  ports:
    - containerPort: 6666
      name: tezos-metrics
  volumeMounts:
    - mountPath: /etc/tezos
      name: config-volume
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
      value: tezos-metrics
{{- end }}
{{- end }}

{{/*
// * The zerotier containers:
*/}}

{{- define "tezos.init_container.zerotier" }}
{{- if (include "tezos.doesZerotierConfigExist" .) }}
- envFrom:
    - configMapRef:
        name: tezos-config
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
    - mountPath: /etc/tezos
      name: config-volume
    - mountPath: /var/tezos
      name: var-volume
    - mountPath: /dev/net/tun
      name: dev-net-tun
  env:
{{- include "tezos.localvars.pod_envvars" . | indent 4 }}
{{- end }}
{{- end }}

{{- define "tezos.container.sidecar" }}
- command:
    - python
  args:
    - "-c"
    - |
{{ tpl (.Files.Get "scripts/tezos-sidecar.py") . | indent 6 }}
  image: {{ .Values.tezos_k8s_images.utils }}
  imagePullPolicy: IfNotPresent
  name: sidecar
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

{{/*
  Node selector config section
*/}}
{{- define "tezos.nodeSelectorConfig" -}}
{{- if hasKey $.node_vals "node_selector" }}
nodeSelector:
{{ toYaml $.node_vals.node_selector | indent 2 }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}
