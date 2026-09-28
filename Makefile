# sh.moul.io. See README.md.
.DEFAULT_GOAL := help
.PHONY: help lint test test-net run serve clean

help: ## Show targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  %-9s %s\n",$$1,$$2}'

lint: ## Dangerous patterns, formatting, and shellcheck when it is installed
	@tests/lint-danger.sh
	@command -v shellcheck >/dev/null && shellcheck -s sh -S warning index.sh agents.sh bin/*.sh tests/*.sh && echo ' ok  shellcheck' || echo 'warn shellcheck absent, CI runs it'

test: lint ## Everything that needs no network: help parity, every shell, idempotency, serving
	@tests/test.sh
	@tests/test-shells.sh
	@tests/test-idempotency.sh
	@tests/test-serve.sh

test-net: ## The endpoints this repo points at are still alive (needs the internet)
	@tests/test-network.sh

run: ## What a visitor gets: the subcommand list
	@sh index.sh

serve: ## Preview the built site on http://localhost:8000
	@./bin/build.sh >/dev/null && cd public && python3 -m http.server 8000

clean: ## Remove the build output
	@rm -rf public
