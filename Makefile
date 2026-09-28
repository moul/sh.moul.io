# sh.moul.io. See README.md.
.DEFAULT_GOAL := help
.PHONY: help test run serve clean

help: ## Show targets
	@grep -hE '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  %-6s %s\n",$$1,$$2}'

test: ## Syntax, lint, help parity, and a dry run of every subcommand
	@tests/test.sh

run: ## What a visitor gets: the subcommand list
	@sh index.sh

serve: ## Preview the built site on http://localhost:8000
	@./bin/build.sh >/dev/null && cd public && python3 -m http.server 8000

clean: ## Remove the build output
	@rm -rf public
