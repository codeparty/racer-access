MOCHA := ./node_modules/.bin/mocha

test:
		$(MOCHA) \
		--reporter spec \
		--grep "$(g)" \
		--compilers .coffee:coffee-script \
		./test/*.coffee | tee $(OUT_FILE)

.PHONY: test
