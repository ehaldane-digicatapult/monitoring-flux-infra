# Monitoring FluxCD Infrastructure

This is a work-in-progress [FluxCD](https://fluxcd.io/) repository to bring up common monitoring applications and infrastructure for integration across different Kubernetes clusters, depending on the requirements of the respective projects.


## Repository structure

```
.
├── applications
│   ├── kube-prometheus-stack
│   └── loki-stack
├── clusters
│   ├── azure
│   │   └── production
│   │       └── substitutions
│   └── kind
│       └── substitutions
├── examples
│   ├── azure
│   │   └── production
│   │       ├── base
│   │       │   └── flux-system
│   └── kind
│       ├── base
│       │   └── flux-system
├── infrastructure
│   ├── controllers
│   ├── dashboards
│   └── monitors
└── scripts
```


### Applications

This directory serves to aggregate all shareable monitoring applications, primarily to implement [DRY](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself) principles across the various projects at Digital Catapult and reduce the overall replication of YAML throughout the organisation's Git repositories.

For each HelmRelease, there should be two maps: `env-values` and `base-values`, corresponding to the environment-specific substitutions for each cluster type and the minimal viable configuration needed for the application.

Within `sources.yaml`, there are the Helm and OCI repositories for all components needed by the applications.


### Clusters

Where there are references here to clusters or environments, they are best thought of as _types_ of deployment. This repository is intended to abstract monitoring components and be a step removed; each project will need to integrate the relevant type of deployment as a kustomization, with this repository as an extra GitRepository in any base cluster directories. A base directory will contain a unique `flux-system` somewhere along its path.

Anticipate including the following `monitoring-sqnc.yaml` along the base path of new or existing project clusters:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: monitoring
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/ehaldane-digicatapult/monitoring-flux-infra.git
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: monitoring-sync
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./clusters/kind
  prune: true
  sourceRef:
    kind: GitRepository
    name: monitoring
```

Note `spec.url` and `spec.path`, the latter should reflect the cluster type needed. If the project has multiple clusters, then each `monitoring-sync.yaml` would likely need to correspond to a different type.


### Examples

Within the `examples` directory, there are environment-specific demonstrations for different platforms or implementations, e.g. Azure or [Kind](https://kind.sigs.k8s.io/). These examples have their own `flux-system` directory, to better illustrate the abstraction. When adapting the examples to a live environment or some other deployment, there should always be a single `flux-system` GitRepository resource. This repository ought to be used to provide the overlays for the monitoring applications and the accompanying infrastructure configuration for dashboards or additional controllers.


### Infrastructure

As with the applications, the complementing infrastructure has been separated so that cluster types only include the dashboards, monitors, and controllers required for that environment. Such controllers might be implemented by Bitnami's [cert-manager](https://github.com/bitnami/charts/tree/main/bitnami/cert-manager) or [nginx-ingress-controller](https://github.com/bitnami/charts/tree/main/bitnami/nginx-ingress-controller) charts. There will likely be occasions where these need to be considered separately from the monitoring stacks proper, hence the option for additional controllers here.


### Scripts

There are scripts to create a Kind cluster and install FluxCD to it.


## Getting started


### Adding new applications

When adding new applications, check that the namespace is available and that no existing releases in the target cluster are using the same name.

A typical application with have the following components:

```
.
├── kustomization.yaml
├── release.yaml
└── values.yaml
```

At a minimum, any new files and resources will need to be referenced in the following locations:
- `applications/kustomization.yaml`, to capture the base values for the new application in the `base-values` map,
- `clusters/**/kustomization.yaml`, to allow the target environment to substitute the defaults with values more suited to that cluster type via `env-values`.

If the application requires additional repositories, then `applications/sources.yaml` should also be updated with the relevant HelmRepository or OCIRepository.


### Adding secrets

Secrets ideally ought to be kept within individual project repositories, as this is intended to be a modular, abstracted monitoring stack to be added to existing clusters as needed.


### Managing releases

Semantic versions and other environment-specific configuration can be managed separately when using shared applications, so that updates or reversions are not immediately applied across all projects. Such usage is optional, however. When adding HelmRelease resources, a semantic version could still be specified within the `spec` there instead.

```yaml
    spec:
      chart: kube-prometheus-stack
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
      version: ${KUBE_PROMETHEUS_STACK_VERSION}
```

Above, the environment variable is provided by a kustomization within the target cluster. If all monitoring stacks on all projects can be kept up-to-date, which is likely always true with Kind anyway, then the example below would suffice instead:

```yaml
    spec:
      chart: kube-prometheus-stack
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
      version: "75.6.0"
```


### Working with shared values

Some attention needs to be given to the precedence of values; the last values file listed for a given HelmRelease will override anything that precedes it. In the majority of use cases, environment-specific values for the cluster should substitute the shared values for a release.

```yaml
  valuesFrom:
    - kind: ConfigMap
      name: base-values
      valuesKey: kube-prometheus-stack-values.yaml
    - kind: ConfigMap
      name: env-values
      valuesKey: kube-prometheus-stack-values.yaml
```

To provide an example of the above, there could be relevant values files in three separate locations:
- `applications/kube-prometheus-stack/values.yaml`
- `clusters/kind/substitutions/kube-prometheus-stack-values.yaml`
- `clusters/azure/production/substitutions/kube-prometheus-stack-values.yaml`

By default, the specific values for each of the above cluster types will always override the shared ones.
