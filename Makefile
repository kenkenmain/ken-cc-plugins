.PHONY: lint test

lint:
	@echo "Checking shell script syntax..."
	@errors=0; \
	for sh_file in $$(find plugins -name "*.sh" -type f); do \
		if bash -n "$$sh_file" 2>/dev/null; then \
			echo "  OK: $$sh_file"; \
		else \
			echo "  FAIL: $$sh_file"; \
			bash -n "$$sh_file"; \
			errors=$$((errors + 1)); \
		fi; \
	done; \
	if [ $$errors -gt 0 ]; then \
		echo "FAILED: $$errors script(s) with syntax errors"; \
		exit 1; \
	fi; \
	echo "All shell scripts pass syntax check"

test:
	@command -v bats >/dev/null 2>&1 || { echo "bats not found. Install: npm install -g bats"; exit 1; }
	bats plugins/subagents/tests/
