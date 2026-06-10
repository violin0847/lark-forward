SHELL := /bin/sh

.DEFAULT_GOAL := all

.PHONY: all package list clean install

DIST_DIR := dist
PACKAGE := $(DIST_DIR)/lark-forward.zip
FILELIST := $(DIST_DIR)/package.files

package: $(PACKAGE)

all: clean package

$(PACKAGE): SKILL.md scripts
	@mkdir -p "$(DIST_DIR)"
	@rm -f "$(FILELIST)"
	@echo "SKILL.md" > "$(FILELIST)"
	@find "scripts" -type f ! -name '.*' ! -path '*/.*' ! -name '.DS_Store' ! -path '*/.DS_Store' ! -iname 'README*' >> "$(FILELIST)"
	@rm -f "$(PACKAGE)"
	@zip -q -@ "$(PACKAGE)" < "$(FILELIST)"
	@echo "Created: $(PACKAGE)"

list: $(PACKAGE)
	@unzip -l "$(PACKAGE)"

install:
	@echo 'alias lark-forward=~/.agents/skills/lark-forward/scripts/lark_forward.sh' >> "$$HOME/.zshrc"
	@echo 'Appended alias to $$HOME/.zshrc'

clean:
	@rm -rf "$(DIST_DIR)"

all: package
