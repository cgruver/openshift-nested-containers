# Test Repo for enabling podman in an OpenShift Pod

This repo is for my attempts to get full `podman` capabilities working in OpenShift Dev Spaces (Eclipse Che)

The capability is needed for the following non-exclusive list:

* Java test-containers
* AWS development with Localstack
* Ansible development

## Early Demo Here - [Eclipse Che / OpenShift Dev Spaces - Podman With Fuse Overlay](https://upstreamwithoutapaddle.com/blog%20post/2023/08/10/Podman-In-Dev-Spaces-With-Fuse-Overlay.html)

## Notes for Fully Working Demo

```bash
NODE_ROLE=master

cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.13.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${NODE_ROLE}
  name: nested-podman-${NODE_ROLE}
storage:
  files:
  - path: /etc/crio/crio.conf.d/99-podman-fuse
    mode: 0644
    overwrite: true
    contents:
      inline: |
        [crio.runtime.workloads.podman-fuse]
        activation_annotation = "io.openshift.podman-fuse"
        allowed_annotations = [
          "io.kubernetes.cri-o.Devices"
        ]
        [crio.runtime]
        allowed_devices = [
          "/dev/fuse",
          "/dev/net/tun"
        ]
  - path: /etc/modules-load.d/podman-fuse.conf
    mode: 0644
    overwrite: true
    contents:
      inline: |
        tun
        rtnl-link-bridge
        ipt_addrtype
  - path: /etc/nested-podman/nested-podman.te
    mode: 0644
    overwrite: true
    contents:
      inline: |
        module nested-podman 1.0;

        require {
          type container_t;
          type cgroup_t;
          type devpts_t;
          type tmpfs_t;
          type sysfs_t;
          type nsfs_t;
          class chr_file open;
          class filesystem { mount remount unmount };
        }
        allow container_t tmpfs_t:filesystem mount;
        allow container_t devpts_t:filesystem mount;
        allow container_t devpts_t:filesystem remount;
        allow container_t devpts_t:chr_file open;
        allow container_t nsfs_t:filesystem unmount;
        allow container_t sysfs_t:filesystem mount;
        allow container_t sysfs_t:filesystem remount;
        allow container_t cgroup_t:filesystem remount;
systemd:
  units:
  - contents: |
      [Unit]
      Description=Modify SeLinux Type container_t to allow devpts_t and tmpfs_t
      DefaultDependencies=no
      After=kubelet.service

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=bash -c "/bin/checkmodule -M -m -o /tmp/nested-podman.mod /etc/nested-podman/nested-podman.te && /bin/semodule_package -o /tmp/nested-podman.pp -m /tmp/nested-podman.mod && /sbin/semodule -i /tmp/nested-podman.pp"
      TimeoutSec=0

      [Install]
      WantedBy=multi-user.target
    enabled: true
    name: systemd-nested-podman-selinux.service
EOF
```

```bash
oc patch FeatureGate cluster --type merge --patch '{"spec":{"featureSet":"CustomNoUpgrade","customNoUpgrade":{"enabled":["ProcMountType"]}}}'

cat << EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: FeatureGate
metadata:
  name: cluster 
spec:
  customNoUpgrade:
    enabled:
      - ProcMountType
  featureSet: CustomNoUpgrade
EOF
```

```bash
CHE_CSV=$(oc get csv -n openshift-operators -o name | grep "eclipse-che")
oc edit ${CHE_CSV} -n openshift-operators
```

Find: `CHE_DEFAULT_SPEC_DEVENVIRONMENTS_CONTAINERSECURITYCONTEXT`

Replace the value with: `'{"allowPrivilegeEscalation": true,"procMount": "Unmasked","capabilities": {"add": ["SETGID", "SETUID"]}}'`

```bash
cd /projects
nohup podman system service --time=0 unix:///tmp/podman.sock > podman-sys.log &
export DOCKER_HOST="unix:///tmp/podman.sock"
export TESTCONTAINERS_RYUK_DISABLED=true 
export TESTCONTAINERS_CHECKS_DISABLE=true
git clone https://github.com/cgruver/quarkus-kafka.git
cd quarkus-kafka
mvn clean
mvn test
```

```bash
cd /projects
git clone https://github.com/aws/aws-sam-cli-app-templates.git
sam init --name sam-py-app --architecture=x86_64 --location="aws-sam-cli-app-templates/python3.9/hello" --no-tracing --no-application-insights --no-input
cd sam-py-app
sam build
nohup podman system service --time=0 unix:///tmp/podman.sock > /projects/podman-sys.log &
export DOCKER_HOST="unix:///tmp/podman.sock"
nohup sam local start-api --debug --docker-network=podman > /projects/sam.out &
curl http://127.0.0.1:3000/hello
```
