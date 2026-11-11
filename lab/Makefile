# ShadowPi lab. Needs Docker Desktop. See docs/LAB.md.
.PHONY: lab-up lab-test lab-down
lab-up:
	docker compose up -d --build
lab-test:
	./lab-test.sh
lab-down:
	docker compose down -v
