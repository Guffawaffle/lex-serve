COMPOSE_PROJECT_NAME ?= smartergpt

.DEFAULT_GOAL := help

# Colors (optional)
GREEN=\033[32m
YELLOW=\033[33m
RESET=\033[0m

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_.-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*?## "} {printf "%-20s %s\n", $$1, $$2}' | sort

up: ## Start stack detached
	@echo "${GREEN}Bringing up stack (project: $(COMPOSE_PROJECT_NAME))...${RESET}" && \
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose up -d

down: ## Stop and remove stack
	@COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose down

ps status: ## Show container status + health endpoint
	@COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose ps && echo && \
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose exec nginx sh -lc 'curl -kfsS https://localhost/healthz || curl -fsS http://localhost/healthz || true'

logs: ## Tail all service logs
	@COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose logs -f --tail=100

reload-nginx: ## Validate and reload nginx
	@COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose exec nginx sh -lc 'nginx -t && nginx -s reload && echo "✔ reloaded"'

config: ## Validate merged compose config
	@COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose config > /dev/null && echo "compose config OK"

cloudflared-shell: ## Shell into cloudflared (debug)
	@COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose exec cloudflared sh || true

.PHONY: up down logs reload-nginx status ps config cloudflared-shell help
