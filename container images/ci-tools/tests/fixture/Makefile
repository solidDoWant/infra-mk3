# The ci-tools test project. Its targets are what ci.yaml names.
.PHONY: lint test docs-check release-assets
lint:
	test -z "$$(gofmt -l .)"
test:
	go test ./...
docs-check:
	test -s README.md
# Writes the release files into $(RELEASE_ASSETS): crds.yaml and the client.
release-assets:
	cat deploy/charts/fixture/templates/crds/*.yaml > "$(RELEASE_ASSETS)/crds.yaml"
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=$(RELEASE_VERSION)" \
		-o "$(RELEASE_ASSETS)/fixture-linux-amd64" ./cmd/fixture
