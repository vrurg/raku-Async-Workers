
MAIN_MOD = Async::Workers
META_MOD = $(MAIN_MOD)

include ./build-tools/makefile.inc

#MAIN_MOD		=  lib/Async/Workers.rakumod
#MOD_VER			:= $(shell raku -Ilib -e 'use Async::Workers; Async::Workers.^ver.say')
#MOD_NAME_PFX	=  Async-Workers
#MOD_DISTRO		=  $(MOD_NAME_PFX)-$(MOD_VER)
#MOD_ARCH		=  $(MOD_DISTRO).tar.gz
#META			=  META6.json
#META_BUILDER	=  ./build-tools/gen-META.raku
#
#PROVE_CMD		=  prove6
#PROVE_FLAGS		=  -l
#TEST_DIRS		=  t
#PROVE			=  $(PROVE_CMD) $(PROVE_FLAGS) $(TEST_DIRS)
#
#DIST_FILES 		:= $(git ls-files)
#
#CLEAN_FILES		=  $(MOD_NAME_PFX)-v*.tar.gz \
#					META6.json.out
#CLEAN_DIRS		=  lib/.precomp
#
#all: release
#
#readme: README.md
#
#README.md: $(MAIN_MOD)
#	@echo "===> Generating $@"
#	@raku -I lib --doc=Markdown $^ >$@
#
#html: README.html
#
#README.html: $(MAIN_MOD)
#	@echo "===> Generating $@"
#	@raku --doc=HTML $^ >$@
#
#test:
#	@$(PROVE)
#
#author-test:
#	@echo "===> Author testing"
#	@AUTHOR_TESTING=1 $(PROVE)
#
#release-test:
#	@echo "===> Release testing"
#	@RELEASE_TESTING=1 $(PROVE)
#
#clean-repo:
#	@git diff-index --quiet HEAD || (echo "*ERROR* Repository is not clean, commit your changes first!"; exit 1)
#
#build: depends readme
#
#depends: meta
#	@echo "===> Installing dependencies"
#	@zef --deps-only install .
#
#release: build clean-repo release-test archive
#	@echo "===> Done releasing"
#
#meta6_mod:
#	@zef locate META6 2>&1 >/dev/null || (echo "===> Installing META6"; zef install META6)
#
#meta: meta6_mod $(META)
#
#archive: $(MOD_ARCH)
#
#$(MOD_ARCH): $(DIST_FILES)
#	@echo "===> Creating release archive" $(MOD_ARCH)
#	@echo "Generating release archive will tag the HEAD with current module version."
#	@echo "Consider carefully if this is really what you want!"
#	@/bin/sh -c 'read -p "Do you really want to tag? (y/N) " answer; [ $$answer = "Y" -o $$answer = "y" ]'
#	@git tag -f $(MOD_VER) HEAD
#	@git push -f --tags
#	@git archive --prefix="$(MOD_DISTRO)/" -o $(MOD_ARCH) $(MOD_VER)
#
#$(META): $(META_BUILDER) $(MAIN_MOD)
#	@echo "===> Generating $(META)"
#	@$(META_BUILDER) >$(META).out && cp $(META).out $(META)
#	@rm $(META).out
#
#upload: release
#	@echo "===> Uploading to CPAN"
#	@/bin/sh -c 'read -p "Do you really want to upload to CPAN? (y/N) " answer; [ $$answer = "Y" -o $$answer = "y" ]'
#	@cpan-upload -d Perl6 --md5 $(MOD_ARCH)
#	@echo "===> Uploaded."
#
#clean:
#	@rm -f $(CLEAN_FILES)
#	@rm -rf $(CLEAN_DIRS)
#
#install: build
#	@echo "===> Installing"
#	@zef install .
