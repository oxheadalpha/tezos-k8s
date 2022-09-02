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
     * Now, we define a generic container template.  We pass in a dictionary
     * of named arguments.  Because helm templates overrides both . and $
     * with this, we have to pass in $ via the "root" argument so that
     * we can access externally defined variables.
     *
     * The arguments are as follows:
     *
     *    root           this is required to be $
     *    type           the container type, e.g.: baker, wait-for-dns
     *    name           the name of the container, defaults to type, this
     *                   is used for containers like baker which can have
     *                   multiple instances of the same type
     *    image          one of: octez, tezedge, utils
     *    command        the command
     *    args           the list of arguments to the command, will default
     *                   to the type if using a "utils" image
     *    run_script     define the command as a script from the scripts
     *                   directory corresponding to the container type,
     *                   so a type of wait-for-dns will include the script
     *                   scripts/wait-for-dns.sh and pass it as a single
     *                   argument to /bin/sh -c.  For image == octez, this
     *                   is the default.
     *    script_command overide the name of the script.  We still look
     *                   in the scripts directory and postpend ".sh"
     *    with_config    bring in the configMap defaults true only on utils.
     *    with_secret    bring in the secrets map including the identities.
     *    localvars      set env vars MY_* Defaults to true only on utils.
     */ -}}

{{- define "tezos.generic_container" }}
{{- $ := .root }}
{{- if not (hasKey $ "Values") }}
  {{- fail "must pass root -> $ to generic_container" }}
{{- end }}

{{- /*
     * First, we set up all of the default values:
     */ -}}

{{- if not (hasKey . "name") }}
  {{- $_ := set . "name" .type }}
{{- end }}
{{- if not (hasKey . "with_config") }}
  {{- $_ := set . "with_config" (eq .image "utils") }}
{{- end }}
{{- if not (hasKey . "localvars") }}
  {{- $_ := set . "localvars" (eq .image "utils") }}
{{- end }}
{{- if not (hasKey . "run_script") }}
  {{- $_ := set . "run_script" (eq .image "octez") }}
{{- end }}
{{- if not (hasKey . "script_command") }}
  {{- $_ := set . "script_command" .type }}
{{- end }}
{{- if not (hasKey . "args") }}
  {{- if eq .image "utils" }}
    {{- $_ := set . "args" (list .type) }}
  {{- end }}
{{- end }}

{{- /*
     * And, now, we generate the YAML:
     */ -}}
- name: {{ .name }}
{{- $node_vals_images := $.node_vals.images | default dict }}
{{- if eq .image "octez" }}
  image: "{{ or $node_vals_images.octez $.Values.images.octez }}"
{{- else if eq .image "tezedge" }}
  image: "{{ or $node_vals_images.tezedge $.Values.images.tezedge }}"
{{- else }}
  image: "{{ $.Values.tezos_k8s_images.utils }}"
{{- end }}
  imagePullPolicy: IfNotPresent
{{- if .run_script }}
  command:
    - /bin/sh
  args:
    - "-c"
    - |
{{ tpl ($.Files.Get (print "scripts/" .script_command ".sh")) $ | indent 6 }}
{{- else if .command }}
  command:
    - {{ .command }}
{{- end }}
{{- if .args }}
  args:
{{- range .args }}
    - {{ . }}
{{- end }}
{{- end }}
  envFrom:
    {{- if .with_secret }}
    {{- if len $.node_identities }}
    - secretRef:
        name: {{ $.node_class }}-identities-secret
    {{- end }}
    {{- end }}
    {{- if .with_config }}
    - configMapRef:
        name: tezos-config
    {{- end }}
  env:
  {{- if .localvars }}
  {{- include "tezos.localvars.pod_envvars" $ | indent 4 }}
  {{- end }}
    - name: DAEMON
      value: {{ .type }}
{{- $envdict := dict }}
{{- $lenv := $.node_vals.env           | default dict }}
{{- $genv := $.Values.node_globals.env | default dict }}
{{- range $curdict := concat
          (pick $lenv .type | values)
          (pick $lenv "all"           | values)
          (pick $genv .type | values)
          (pick $genv "all"           | values)
}}
{{- $envdict := merge $envdict ($curdict | default dict) }}
{{- end }}
{{- range $key, $val := $envdict }}
    - name:  {{ $key  }}
      value: {{ $val | quote }}
{{- end }}
  volumeMounts:
    - mountPath: /etc/tezos
      name: config-volume
    - mountPath: /var/tezos
      name: var-volume
    {{- if .with_secret }}
    - mountPath: /etc/secret-volume
      name: tezos-accounts
    {{- end }}
  {{- if eq .type "baker" }}
    - mountPath: /etc/tezos/per-block-votes
      name: per-block-votes
  {{- end }}
  {{- if (or (eq .type "octez-node")
             (eq .type "tezedge-node")) }}
  ports:
    - containerPort: 8732
      name: tezos-rpc
    - containerPort: 9732
      name: tezos-net
    {{- if or (not (hasKey $.node_vals "readiness_probe")) $.node_vals.readiness_probe }}
  readinessProbe:
    httpGet:
      path: /is_synced
      port: 31732
    {{- end }}
  {{- end }}
{{- end }}


{{- /*
     * We are finished defining tezos.generic_container, and are now
     * on to defining the actual containers.
     */ -}}

{{- define "tezos.init_container.config_init" }}
  {{- if include "tezos.shouldConfigInit" . }}
    {{- include "tezos.generic_container" (dict "root"        $
                                                "type"        "config-init"
                                                "image"       "octez"
                                                "with_config" 1
                                                "localvars"   1
    ) | nindent 0 }}
  {{- end }}
{{- end }}

{{- define "tezos.init_container.config_generator" }}
  {{- include "tezos.generic_container" (dict "root"        $
                                              "type"        "config-generator"
                                              "image"       "utils"
                                              "with_secret" 1
  ) | nindent 0 }}
{{- end }}

{{- define "tezos.init_container.chain_initiator" }}
  {{- include "tezos.generic_container" (dict "root"        $
                                              "type"        "chain-initiator"
                                              "image"       "octez"
  ) | nindent 0 }}
{{- end }}

{{- define "tezos.init_container.wait_for_dns" }}
  {{- if include "tezos.shouldWaitForDNSNode" . }}
    {{- include "tezos.generic_container" (dict "root"      $
                                                "type"      "wait-for-dns"
                                                "image"     "utils"
                                                "localvars" 0
    ) | nindent 0 }}
  {{- end }}
{{- end }}

{{- define "tezos.init_container.snapshot_downloader" }}
  {{- if include "tezos.shouldDownloadSnapshot" . }}
    {{- include "tezos.generic_container" (dict "root"  $
                                                "type"  "snapshot-downloader"
                                                "image" "utils"
    ) | nindent 0 }}
  {{- end }}
{{- end }}

{{- define "tezos.init_container.snapshot_importer" }}
  {{- if include "tezos.shouldDownloadSnapshot" . }}
    {{- include "tezos.generic_container" (dict "root"   $
                                           "type"        "snapshot-importer"
                                           "image"       "octez"
                                           "with_config" 1
                                           "localvars"   1
    )  | nindent 0 }}
  {{- end }}
{{- end }}

{{- define "tezos.container.sidecar" }}
  {{- if or (not (hasKey $.node_vals "readiness_probe")) $.node_vals.readiness_probe }}
    {{- include "tezos.generic_container" (dict "root"  $
                                                "type"  "sidecar"
                                                "image" "utils"
    ) | nindent 0 }}
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
    {{- include "tezos.generic_container" (dict "root"        $
                                                "type"        "octez-node"
                                                "image"       "octez"
                                                "with_config" 0
    ) | nindent 0 }}
{{- end }}
{{- end }}

{{- define "tezos.container.tezedge" }}
  {{- if eq (include "tezos.getNodeImplementation" $) "tezedge" }}
    {{- include "tezos.generic_container" (
            dict "root"        $
                 "type"        "tezedge-node"
                 "image"       "tezedge"
                 "with_config" 0
                 "command"     "/light-node"
                 "args"        (list "--config-file=/etc/tezos/tezedge.conf")
    ) | nindent 0 }}
  {{- end }}
{{- end }}

{{- define "tezos.container.bakers" }}
  {{- if has "baker" $.node_vals.runs }}
    {{- $node_vals_images := $.node_vals.images | default dict }}
    {{- range .Values.protocols }}
      {{- if (not .vote) }}
        {{ fail (print "You did not specify the liquidity baking toggle vote in 'protocols' for protocol " .command ".") }}
      {{- end -}}
      {{- $_ := set $ "command_in_tpl" .command }}
      {{- include "tezos.generic_container" (dict "root" $
                                                  "name" (print "baker-"
                                                          (lower .command))
                                                  "type"        "baker"
                                                  "image"       "octez"
      ) | nindent 0 }}
    {{- end }}
  {{- end }}
{{- end }}


{{- define "tezos.container.accusers" }}
  {{- if has "accuser" $.node_vals.runs }}
  {{ $node_vals_images := $.node_vals.images | default dict }}
    {{- range .Values.protocols }}
- name: accuser-{{ lower .command }}
  image: "{{ or $node_vals_images.octez $.Values.images.octez }}"
  imagePullPolicy: IfNotPresent
  command:
    - /usr/local/bin/tezos-accuser-{{ .command }}
  args:
    - run
    {{- end }}
  {{- end }}
{{- end }}

{{- define "tezos.container.vdf" }}
  {{- if has "vdf" $.node_vals.runs }}
  {{ $node_vals_images := $.node_vals.images | default dict }}
    {{- range .Values.protocols }}
      {{- if or (regexFind "Kathma" .command) (regexFind "alpha" .command) }}
      {{- /*
      Only protos higher than Kathmandu support VDF
      */}}
- name: vdf-{{ lower .command }}
  image: "{{ or $node_vals_images.octez $.Values.images.octez }}"
  imagePullPolicy: IfNotPresent
  command:
    - /usr/local/bin/tezos-baker-{{ .command }}
  args:
    - run
    - vdf
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}


{{- define "tezos.container.logger" }}
  {{- if has "logger" $.node_vals.runs }}
    {{- include "tezos.generic_container" (dict "root"        $
                                                "type"        "logger"
                                                "image"       "utils"
    ) | nindent 0 }}
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
    - mountPath: /etc/secret-volume
      name: tezos-accounts
  envFrom:
    - configMapRef:
        name: tezos-config
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
