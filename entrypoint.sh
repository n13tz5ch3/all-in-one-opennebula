#!/bin/bash

MY_IP=$(ip route get 8.8.8.8 | awk 'NR==1 {print $7}')

# Funzione per rilevare la piattaforma
detect_platform() {
    # Controlla se siamo in un container Docker su macOS
    if [ -f /.dockerenv ]; then
        # Dentro un container, controlla indicatori macOS
        if [ -n "$DOCKER_PLATFORM" ] && [ "$DOCKER_PLATFORM" = "darwin" ]; then
            echo "darwin"
            return
        fi

        # Controlla altre indicazioni di macOS Docker Desktop
        if mount | grep -q "osxfs\|virtiofs" || [ -d "/host_mnt" ]; then
            echo "darwin"
            return
        fi

        # Controlla se abbiamo accesso limitato a /dev (tipico di macOS Docker)
        if [ ! -w "/dev/net/tun" ] && [ ! -c "/dev/kvm" ]; then
            # Potrebbe essere macOS o container limitato
            if ! which iptables >/dev/null 2>&1; then
                echo "darwin"
                return
            fi

            # Testa se iptables funziona davvero
            if ! iptables -L >/dev/null 2>&1; then
                echo "darwin"
                return
            fi
        fi
    fi

    # Default: assume Linux
    echo "linux"
}

setup_networking() {
    local platform=$(detect_platform)

    echo "Platform detected: $platform"

    if [ "$platform" = "darwin" ]; then
        echo "Setting up networking for macOS Docker Desktop..."
        echo "🍎 macOS detected - iptables operations disabled"
        echo "📝 Note: Using Docker port mapping instead of iptables NAT"
        echo "🔗 VM access will be handled via Docker port forwarding"

        # Su macOS, documenta le porte che dovrebbero essere mappate
        echo "📋 Required Docker port mappings for VM access:"
        for i in $(seq 0 9); do
            echo "   -p $(expr $i + 1022):$(expr $i + 1022)  # VM $(expr $i + 1) SSH access"
        done

        return 0
    else
        echo "Setting up networking for Linux..."
        echo "🐧 Linux detected - configuring iptables NAT rules"
        echo "🔧 Setting up static PAT to access VMs"

        # Verifica che iptables sia disponibile
        if ! which iptables >/dev/null 2>&1; then
            echo "❌ iptables not found - installing..."
            apt-get update && apt-get install -y iptables
        fi

        # Verifica permessi per iptables
        if ! iptables -L >/dev/null 2>&1; then
            echo "❌ No permission for iptables operations"
            echo "🔒 Container needs --privileged or --cap-add=NET_ADMIN"
            return 1
        fi

        # Configurazione iptables originale per Linux
        echo "📝 Configuring NAT rules for VM access..."
        for i in $(seq 0 9); do
            local host_port=$(expr $i + 1022)
            local vm_ip="192.168.122.$(expr $i + 100)"

            echo "   Mapping port $host_port -> $vm_ip:22"
            iptables -t nat -A PREROUTING -p tcp --dport $host_port -j DNAT --to-destination $vm_ip:22 || {
                echo "⚠️ Failed to add NAT rule for port $host_port"
            }
        done

        # Permetti il forwarding
        echo "🔀 Enabling packet forwarding..."
        iptables -I FORWARD 1 -j ACCEPT || {
            echo "⚠️ Failed to add FORWARD rule"
        }

        # Abilita IP forwarding nel kernel
        echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || {
            echo "⚠️ Could not enable IP forwarding in kernel"
        }

        echo "✅ Linux networking configuration completed"

        # Mostra le regole configurate
        echo "📋 Current NAT rules:"
        iptables -t nat -L PREROUTING -n --line-numbers | grep ":1022\|:1023\|:1024\|:1025\|:1026\|:1027\|:1028\|:1029\|:1030\|:1031" || echo "   No NAT rules found"

        return 0
    fi
}

# Funzione di cleanup per networking
cleanup_networking() {
    local platform=$(detect_platform)

    if [ "$platform" = "linux" ]; then
        echo "🧹 Cleaning up iptables rules..."

        # Rimuovi regole NAT per le VM
        for i in $(seq 0 9); do
            local host_port=$(expr $i + 1022)
            local vm_ip="192.168.122.$(expr $i + 100)"
            iptables -t nat -D PREROUTING -p tcp --dport $host_port -j DNAT --to-destination $vm_ip:22 2>/dev/null || true
        done

        echo "✅ Networking cleanup completed"
    else
        echo "🍎 macOS - no iptables cleanup needed"
    fi
}

# Funzione per mostrare informazioni di networking
show_networking_info() {
    local platform=$(detect_platform)

    echo ""
    echo "🌐 NETWORKING INFORMATION"
    echo "========================"
    echo "Platform: $platform"
    echo "Container IP: $MY_IP"
