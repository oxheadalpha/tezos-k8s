-- For performance reasons we rexport from the kubernetes library only the types we are using
-- This makes the speed of dhall-python's rendering more than 2x faster on my machine than simply using plain dhall-kubernetes
let k8s = https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/package.dhall

let Resource =
      < ConfigMap : k8s.ConfigMap.Type
      | DaemonSet : k8s.DaemonSet.Type
      | Deployment : k8s.Deployment.Type
      | Job : k8s.Job.Type
      | Namespace : k8s.Namespace.Type
      | PersistentVolumeClaim : k8s.PersistentVolumeClaim.Type
      | Secret : k8s.Secret.Type
      | Service : k8s.Service.Type
      | StatefulSet : k8s.StatefulSet.Type
      >

in  { Capabilities = k8s.Capabilities
    , ConfigMap = k8s.ConfigMap
    , ConfigMapEnvSource = k8s.ConfigMapEnvSource
    , ConfigMapKeySelector = k8s.ConfigMapKeySelector
    , ConfigMapVolumeSource = k8s.ConfigMapVolumeSource
    , Container = k8s.Container
    , ContainerPort = k8s.ContainerPort
    , DaemonSet = k8s.DaemonSet
    , DaemonSetSpec = k8s.DaemonSetSpec
    , Deployment = k8s.Deployment
    , DeploymentSpec = k8s.DeploymentSpec
    , DeploymentStrategy = k8s.DeploymentStrategy
    , EnvFromSource = k8s.EnvFromSource
    , EnvVar = k8s.EnvVar
    , EnvVarSource = k8s.EnvVarSource
    , EmptyDirVolumeSource = k8s.EmptyDirVolumeSource
    , ExecAction = k8s.ExecAction
    , HostPathVolumeSource = k8s.HostPathVolumeSource
    , Job = k8s.Job
    , JobSpec = k8s.JobSpec
    , LabelSelector = k8s.LabelSelector
    , Namespace = k8s.Namespace
    , ObjectMeta = k8s.ObjectMeta
    , PersistentVolumeClaim = k8s.PersistentVolumeClaim
    , PersistentVolumeClaimSpec = k8s.PersistentVolumeClaimSpec
    , PersistentVolumeClaimVolumeSource = k8s.PersistentVolumeClaimVolumeSource
    , PodSecurityContext = k8s.PodSecurityContext
    , PodSpec = k8s.PodSpec
    , PodTemplateSpec = k8s.PodTemplateSpec
    , Probe = k8s.Probe
    , ResourceRequirements = k8s.ResourceRequirements
    , Secret = k8s.Secret
    , SecretEnvSource = k8s.SecretEnvSource
    , SecurityContext = k8s.SecurityContext
    , Service = k8s.Service
    , ServicePort = k8s.ServicePort
    , ServiceSpec = k8s.ServiceSpec
    , StatefulSet = k8s.StatefulSet
    , StatefulSetSpec = k8s.StatefulSetSpec
    , Volume = k8s.Volume
    , VolumeMount = k8s.VolumeMount
    , Resource
    }
