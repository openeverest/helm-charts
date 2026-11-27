# OpenEverest Helm Charts

> [!IMPORTANT]
> This branch (`main`) carries the chart for OpenEverest v2, progressing toward GA — not yet for production.
>
> The chart for OpenEverest v1, the current GA release, is on [`v1.x`](https://github.com/openeverest/helm-charts/tree/v1.x). After v2 GA, v1 receives bug and security fixes for 6 months — see [RELEASE.md](https://github.com/openeverest/openeverest/blob/main/RELEASE.md).

This repository contains the official Helm charts for [OpenEverest](https://openeverest.io/), the open-source cloud-native database platform.

OpenEverest helps you deploy and manage databases on Kubernetes without the operational overhead. These charts provide a simple way to install and configure the OpenEverest control plane in your cluster.

For more information about the project, visit the [main OpenEverest repository](https://github.com/openeverest/openeverest).

## Quick Start

To install OpenEverest with default settings:

```bash
helm repo add openeverest https://openeverest.github.io/helm-charts/
helm repo update
helm install everest openeverest/openeverest \
  --namespace everest-system \
  --create-namespace
```

This deploys the core OpenEverest components and sets up the management interface.

## Configuration

The Helm chart supports various configuration options for production deployments, custom resource limits, and integration with existing infrastructure. Refer to the [Chart documentation](charts/everest/README.md) for more information.

For detailed installation instructions, upgrade procedures, and advanced configuration options, see the [OpenEverest documentation](https://openeverest.io/documentation/current/).

## Contributing

Contributions are welcome. If you find issues with these charts or have suggestions for improvements, please open an issue or submit a pull request in this repository.

For broader questions about OpenEverest or to contribute to the core project, see the [main repository](https://github.com/openeverest/openeverest).

## License

These Helm charts are licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
