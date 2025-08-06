VERSION ?= latest
PLATFORM := $(shell uname -s)

.PHONY: all build image start clean logs

all: clean prepare build start

build:
	docker build -t opennebula:$(VERSION) .

start:
ifeq ($(PLATFORM),Darwin)
	# macOS: Usa capabilities specifiche invece di --privileged
	docker run --rm --name one -d \
		--cap-add=NET_ADMIN \
		--cap-add=SYS_ADMIN \
		--device=/dev/net/tun \
		-p 2616:2616 \
		-p 1022-1031:1022-1031 \
		-v /var/run/docker.sock:/var/run/docker.sock \
		opennebula:$(VERSION)
else
	# Linux: Usa --privileged completo
	docker run --rm --name one -d --privileged \
		-p 2616:2616 \
		-p 1022-1031:1022-1031 \
		opennebula:$(VERSION)
endif

start-dev:
	# Modalità sviluppo senza KVM/libvirt
	docker run --rm --name one -d \
		-p 2616:2616 \
		-e OPENNEBULA_MODE=dev \
		opennebula:$(VERSION)

clean:
	-docker rm -f one

logs:
	docker logs one

prepare: id_rsa

id_rsa:
	ssh-keygen -t rsa -b 4096 -P "" -f ./id_rsa

# Target specifici per macOS
macos-setup:
	@echo "Setting up for macOS development..."
	@echo "Note: Full virtualization not available on macOS Docker"

macos-start: macos-setup start-dev

# Mostra informazioni sulla piattaforma
info:
	@echo "Platform: $(PLATFORM)"
	@echo "Available targets:"
	@echo "  - start: Normal start (privileged on Linux, limited on macOS)"
	@echo "  - start-dev: Development mode (no virtualization)"
	@echo "  - macos-start: macOS optimized start"