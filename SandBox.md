# OpenShift Sandboxed Containers

```bash
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: kataconfig-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/openshift_sandboxed-containers/openshift-sandboxed-containers-catalog:latest
  displayName: Kata container Operators
  publisher: Red Hat
  updateStrategy:
    registryPoll: 
      interval: 30m
EOF
```
