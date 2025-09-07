.PHONY: build-proto build-images deploy test clean

ROOTDIR := $(shell pwd)
OUTPUT_DIR ?= $(ROOTDIR)/_output
DEPSGOBIN := $(OUTPUT_DIR)/.bin

# Important to use binaries built from module.
export PATH:=$(DEPSGOBIN):$(PATH)
export GOBIN:=$(DEPSGOBIN)

.PHONY: install-go-tools
install-go-tools: ## Download and install Go dependencies
	mkdir -p $(DEPSGOBIN)
	go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

PROTOC_VERSION:=3.6.1
PROTOC_URL:=https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}
.PHONY: install-protoc
.SILENT: install-protoc
install-protoc:
	mkdir -p $(DEPSGOBIN)
	if [ $(shell ${DEPSGOBIN}/protoc --version | grep -c ${PROTOC_VERSION}) -ne 0 ]; then \
		echo expected protoc version ${PROTOC_VERSION} already installed ;\
	else \
		if [ "$(shell uname)" = "Darwin" ]; then \
			echo "downloading protoc for osx" ;\
			wget $(PROTOC_URL)-osx-x86_64.zip -O $(DEPSGOBIN)/protoc-${PROTOC_VERSION}.zip ;\
		elif [ "$(shell uname -m)" = "aarch64" ]; then \
			echo "downloading protoc for linux aarch64" ;\
			wget $(PROTOC_URL)-linux-aarch_64.zip -O $(DEPSGOBIN)/protoc-${PROTOC_VERSION}.zip ;\
		else \
			echo "downloading protoc for linux x86-64" ;\
			wget $(PROTOC_URL)-linux-x86_64.zip -O $(DEPSGOBIN)/protoc-${PROTOC_VERSION}.zip ;\
		fi ;\
		unzip $(DEPSGOBIN)/protoc-${PROTOC_VERSION}.zip -d $(DEPSGOBIN)/protoc-${PROTOC_VERSION} ;\
		mv $(DEPSGOBIN)/protoc-${PROTOC_VERSION}/bin/protoc $(DEPSGOBIN)/protoc ;\
		chmod +x $(DEPSGOBIN)/protoc ;\
		rm -rf $(DEPSGOBIN)/protoc-${PROTOC_VERSION} $(DEPSGOBIN)/protoc-${PROTOC_VERSION}.zip ;\
	fi

# Build protocol buffers
build-proto:
	@echo "Building protocol buffers..."
	${DEPSGOBIN}/protoc --go_out=server --go_opt=paths=source_relative \
		--go-grpc_out=server --go-grpc_opt=paths=source_relative \
		proto/ping.proto
	${DEPSGOBIN}/protoc --go_out=client --go_opt=paths=source_relative \
		--go-grpc_out=client --go-grpc_opt=paths=source_relative \
		proto/ping.proto

# Build Docker images
build-images: build-proto
	@echo "Building server image..."
	docker build -t grpc-server:latest -f server/Dockerfile .
	@echo "Building client image..."
	docker build -t grpc-client:latest -f client/Dockerfile .

load-images:
	@echo "Loading images into kind cluster..."
	kind load docker-image grpc-server:latest
	kind load docker-image grpc-client:latest

# Deploy to Kubernetes
deploy:
	@echo "Deploying to Kubernetes..."
	kubectl apply -f k8s/ns.yaml
	kubectl apply -f k8s/server-deployment.yaml
	kubectl apply -f k8s/server-service.yaml
	@echo "Waiting for server to be ready..."
	kubectl wait --for=condition=available --timeout=60s deployment/grpc-server -n test

# Run test
test:
	@echo "Running DNS resolution test..."
	kubectl delete job grpc-client-test -n test --ignore-not-found=true
	kubectl apply -f k8s/client-job.yaml
	@echo "Waiting for test to complete..."
	kubectl wait --for=condition=complete --timeout=60s job/grpc-client-test -n test
	@echo "Test results:"
	kubectl logs job/grpc-client-test -n test

# Clean up
clean:
	@echo "Cleaning up..."
	kubectl delete namespace coredns-test --ignore-not-found=true
	docker rmi grpc-server:latest grpc-client:latest --force

# Full test cycle
full-test: build-images deploy test

# Show DNS debugging info
debug-dns:
	@echo "=== CoreDNS Configuration ==="
	kubectl get configmap coredns -n kube-system -o yaml
	@echo "\n=== CoreDNS Pods ==="
	kubectl get pods -n kube-system -l k8s-app=kube-dns
	@echo "\n=== Service Information ==="
	kubectl get svc -n coredns-test
	kubectl describe svc grpc-server -n coredns-test
	@echo "\n=== Pod DNS Configuration ==="
	kubectl exec -n coredns-test deployment/grpc-server -- cat /etc/resolv.conf

help:
	@echo "Available targets:"
	@echo "  build-proto   - Build protocol buffer files"
	@echo "  build-images  - Build Docker images"
	@echo "  deploy        - Deploy to Kubernetes"
	@echo "  test          - Run the DNS resolution test"
	@echo "  full-test     - Build, deploy, and test"
	@echo "  debug-dns     - Show DNS debugging information"
	@echo "  clean         - Clean up resources"