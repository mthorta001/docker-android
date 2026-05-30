.PHONY: help install-hooks lint lint-shell lint-python fmt fmt-shell fmt-python test test-unit test-shell

# Shell scripts to lint/format (all *.sh in the repo).
SHELL_FILES := $(shell find . -type f -name '*.sh')

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install-hooks: ## Install pre-commit git hooks
	pip install pre-commit
	pre-commit install

lint: lint-shell lint-python ## Run all linters

lint-shell: ## Lint shell scripts (shellcheck + shfmt)
	shellcheck --shell=bash --external-sources $(SHELL_FILES)
	shfmt -d -i 4 -ci $(SHELL_FILES)

lint-python: ## Lint Python sources (flake8 + mypy)
	flake8 src
	mypy src --ignore-missing-imports

fmt: fmt-shell fmt-python ## Auto-format all sources

fmt-shell: ## Format shell scripts in place (shfmt)
	shfmt -w -i 4 -ci $(SHELL_FILES)

fmt-python: ## Format Python sources (isort + black)
	isort --profile black --line-length 120 src
	black --line-length 120 src

test: test-unit test-shell ## Run all tests (Python + shell)

test-unit: ## Run Python unit tests
	pytest src/tests/unit --cov=src --cov-report=term-missing

test-shell: ## Run shell unit tests (bats)
	bats src/tests/shell
