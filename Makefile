INSTALL_DIR=$(HOME)

bin/lest: bin bin/lest.out
	@echo "#!/usr/bin/env lua" > bin/lest
	@cat bin/lest.out >> bin/lest
	@chmod 700 bin/lest
	@echo "lest executable builded"

bin/lest.out: bin lest.lua
	@luac -o bin/lest.out lest.lua

bin:
	@mkdir -p bin

$(INSTALL_DIR)/bin/lest: bin/lest
	@cp bin/lest $(INSTALL_DIR)/bin
	@chmod 700 $(INSTALL_DIR)/bin/lest
	@echo "lest executable installed"

# Commands
install: bin/lest $(INSTALL_DIR)/bin/lest

uninstall: clean
	@rm -f $(INSTALL_DIR)/bin/lest
	@echo "uninstalled lest"

clean:
	@rm -rf bin

re: clean bin/lest

reinstall: clean install

PHONY: install clean re reinstall
