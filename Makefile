.PHONY: install db-up db-down sql seed test lint secrets previews

install:
	python -m pip install -r sync-b24/requirements.txt -r requirements-dev.txt

db-up:
	docker compose up -d db

db-down:
	docker compose down -v

sql:
	@for f in sql/*.sql; do echo "applying $$f"; \
		psql "$${DATABASE_URL:-postgres://postgres:postgres@localhost:5433/analytics_dw}" -v ON_ERROR_STOP=1 -f "$$f"; \
	done

seed:
	python scripts/seed_mock_data.py --days 14 --users 20

test:
	pytest -q

lint:
	ruff check .

secrets:
	python scripts/check_secrets.py

previews:
	python scripts/make_previews.py
