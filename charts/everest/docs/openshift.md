# Installing OpenEverest on OpenShift

The OpenEverest Helm chart can be installed on OpenShift with some additional configuration steps.

> Note: Support for OpenShift is currently in progress, so it may not work as expected. If you encounter any issues, please report them by creating a new issue [here](https://github.com/openeverest/openeverest) or contact us via other [community channels](https://openeverest.io/#community).

## 1. Install Everest

Run the following command to install Everest with OpenShift compatibility enabled:

```sh
helm install everest-core openeverest/openeverest \
    --namespace everest-system \
    --create-namespace
```

For detailed instructions, refer to the guide linked [here](../README.md), but adjust the installation parameters according to the values specified in this document.

