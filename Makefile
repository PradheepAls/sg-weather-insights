.PHONY: help install test test-live test-api e2e load stub fixtures tf-fmt tf-test tf-plan

TF        ?= terraform
TF_DIR    := infra/terraform
ENV       ?= dev

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

install: ## python + node test dependencies
	pip install -r requirements-test.txt
	cd tests/e2e && npm install && npx playwright install chromium

test: ## offline tests: upstream contract (fixtures), rule vectors, normaliser, API spec
	pytest -m "not live and not integration"

test-live: ## contract tests against the real data.gov.sg API
	DGS_LIVE=1 pytest -m live tests/contract

test-api: ## black-box API tests (WEATHER_API_BASE_URL=https://<host>/Weather_API/rest/v1)
	pytest -m integration

e2e: ## Playwright + axe (WEATHER_APP_URL=https://<host>/Weather/)
	cd tests/e2e && npx playwright test

load: ## k6 smoke (BASE=https://<host>/Weather_API/rest/v1)
	k6 run -e BASE=$(BASE) tests/load/smoke.js

stub: ## WireMock data.gov.sg stub on :8089
	docker compose -f tests/mocks/docker-compose.yml up

fixtures: ## re-capture fixtures from the live API and mirror them into the stub
	python tests/contract/capture_fixtures.py
	cp tests/contract/fixtures/*.json tests/mocks/wiremock/__files/

tf-fmt: ## format Terraform
	$(TF) fmt -recursive $(TF_DIR)

tf-test: ## fmt check, validate, terraform test (mocked AWS), tflint, checkov
	$(TF) fmt -check -recursive $(TF_DIR)
	@for d in $(TF_DIR)/modules/*/; do \
	  $(TF) -chdir=$$d init -backend=false -input=false >/dev/null && \
	  $(TF) -chdir=$$d validate && $(TF) -chdir=$$d test || exit 1; done
	cd $(TF_DIR) && tflint --init --config "$$PWD/.tflint.hcl" && tflint --recursive --config "$$PWD/.tflint.hcl"
	checkov -d $(TF_DIR) --config-file .checkov.yaml

tf-plan: ## plan one environment (ENV=lifetime|dev|test|prod, needs backend.hcl and STATE_BUCKET)
	$(TF) -chdir=$(TF_DIR)/stacks/environment init -reconfigure -backend-config=../../backend.hcl -backend-config="key=env/$(ENV).tfstate"
	$(TF) -chdir=$(TF_DIR)/stacks/environment plan -var-file=envs/$(ENV).tfvars -var="state_bucket=$(STATE_BUCKET)"
