# The ci-tools test project. Its targets are what ci.yaml names.
.PHONY: lint test docs-check test-guard release-assets
lint:
	test -z "$$(gofmt -l .)"
test:
	go test ./...
docs-check:
	test -s README.md
# The e2e test passes this label; a real guard checks for removed tests.
test-guard:
	test "$$TEST_GUARD_PR_LABELS" = test-removal-approved
# Writes the release files into $(RELEASE_ASSETS): crds.yaml and the client.
release-assets:
	cat deploy/charts/fixture/templates/crds/*.yaml > "$(RELEASE_ASSETS)/crds.yaml"
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=$(RELEASE_VERSION)" \
		-o "$(RELEASE_ASSETS)/fixture-linux-amd64" ./cmd/fixture
