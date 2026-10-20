.PHONY: install test test-live test-api e2e tf-test

install: ## Python and Node test dependencies
	pip install -r requirements-test.txt
	cd tests/e2e && npm install && npx playwright install chromium

test: ## offline: upstream contract on fixtures, PSI vectors, API spec
	pytest -m "not live and not integration"

test-live: ## same schemas against the real data.gov.sg API
	DGS_LIVE=1 pytest -m live tests/contract

test-api: ## WEATHER_API_BASE_URL=https://<host>/Weather_CS/rest/WeatherAPI
	pytest -m integration

e2e: ## WEATHER_APP_URL=https://<host>/Weather/
	cd tests/e2e && npx playwright test

tf-test: ## fmt, validate, terraform test (mocked AWS)
	cd infra/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false && terraform validate && terraform test
