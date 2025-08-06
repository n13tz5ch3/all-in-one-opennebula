FROM ubuntu:24.04
LABEL authors="jar0d"

ARG ONEPASS=onepassword
ARG SSHPATH=./id_rsa*

# Rileva se siamo su macOS (Docker Desktop)
ARG PLATFORM=unknown
ENV DOCKER_PLATFORM=${PLATFORM}

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && apt-get install -y gnupg wget apt-transport-https && \
    wget -q -O- https://downloads.opennebula.io/repo/repo2.key | gpg --dearmor --yes --output /etc/apt/keyrings/opennebula.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/opennebula.gpg] https://downloads.opennebula.io/repo/7.0/Ubuntu/24.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list && \
    apt-get update && \
    apt-get -y install opennebula opennebula-fireedge opennebula-gate opennebula-flow \
    gcc libmysqlclient-dev ruby-dev make sudo lsb-release net-tools \
    vim xml-twig-tools jq openssh-server curl \
    bridge-utils dnsmasq-base -y && \
    /usr/share/one/install_gems --yes

# Installa libvirt solo se non siamo su macOS
RUN if [ "$PLATFORM" != "darwin" ]; then \
        apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients ebtables; \
    else \
        echo "Skipping KVM/libvirt on macOS"; \
    fi

# Create oneadmin user directories
RUN mkdir -p /var/lib/one/.ssh /var/lib/one/.one && \
    chown -R oneadmin:oneadmin /var/lib/one

COPY ${SSHPATH} /var/lib/one/.ssh/

COPY entrypoint.sh /

# Conditional init scripts
ADD init.tar /etc/init.d/

RUN echo "oneadmin:${ONEPASS}" > /var/lib/one/.one/one_auth && \
    chown oneadmin:oneadmin /var/lib/one/.one/one_auth && \
    chmod 600 /var/lib/one/.one/one_auth && \
    chown -R oneadmin:oneadmin /var/lib/one/.ssh && \
    chmod 600 /var/lib/one/.ssh/id_rsa && \
    chmod 644 /var/lib/one/.ssh/id_rsa.pub && \
    chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:2616/ || exit 1

EXPOSE 2616 22

CMD ["/bin/bash", "/entrypoint.sh"]