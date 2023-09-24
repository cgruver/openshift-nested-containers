FROM registry.access.redhat.com/ubi9/ubi-minimal

ENV HOME="/home/user"
ENV BUILDAH_ISOLATION=chroot

# Note: compat-openssl11 & libbrotli are needed for che-code (Che build of VS Code)

RUN microdnf --disableplugin=subscription-manager install -y openssl compat-openssl11 libbrotli git tar which shadow-utils bash zsh wget jq podman buildah skopeo; \
    microdnf update -y ; \
    microdnf clean all ; \
    mkdir -p ${HOME} ; \
    #
    # Setup for root-less podman
    #
    setcap cap_setuid+ep /usr/bin/newuidmap ; \
    setcap cap_setgid+ep /usr/bin/newgidmap ; \
    touch /etc/subgid /etc/subuid ; \
    mkdir -p ${HOME}/.config/containers ; \
    (echo '[containers]';echo 'netns="private"';echo 'default_sysctls = []';echo '[engine]';echo 'network_cmd_options=[';echo '  "enable_ipv6=false"';echo ']') > ${HOME}/.config/containers/containers.conf ; \
    chgrp -R 0 /home ; \
    chmod -R g=u /etc/passwd /etc/group /etc/subuid /etc/subgid /home

ENTRYPOINT [ "/entrypoint.sh" ]
