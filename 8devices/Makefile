# 8devices overlay for OpenWrt: quilt patch series and data files applied onto
# the pristine upstream tree. Used by ../quick_start.sh; see README.md.
#
# Targets (make -C 8devices <target>):
#   apply      patch series onto the tree, Kiwi board file, pinned feeds.conf,
#              feeds update, luci series onto feeds/luci, feeds install
#              (FEEDS=no: skip everything feeds-related)
#   unapply    everything out again (tree == upstream)
#   check      on an unapplied tree: push every series, report, pop again

HERE  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TREE  ?= $(abspath $(HERE)/..)
FEEDS ?= yes

export QUILT_REFRESH_ARGS := -p ab --no-timestamps --no-index
export QUILT_DIFF_OPTS    := -p

# quilt invocation for a series: $(call Q,<dir under HERE>)  e.g. patches/openwrt
Q = QUILT_PATCHES=$(HERE)/$(1) QUILT_PC=$(HERE)/.pc/$(1) quilt --quiltrc -

# series on the openwrt tree, in push order (backports = upstream fixes carried
# between re-pins, usually empty); pop order is the reverse
SERIES_OPENWRT     := patches/backports patches/openwrt
SERIES_OPENWRT_POP := patches/openwrt patches/backports
SERIES_LUCI        := patches/luci

BOARD_FILE := board-files/8devices_kiwi/board-8devices_kiwi.qcn9274
BOARD_DST  := $(TREE)/package/firmware/ipq-wifi/src/board-8devices_kiwi.qcn9274

# A series file with no patch lines (only comments / blank): quilt reports
# "No patches in series" with a non-zero status, so such a series is skipped.
series_empty = ! grep -q '^[^\#[:space:]]' $(HERE)/$(1)/series

# Push a series, or verify that an already-applied series is really in the tree.
# $(1) = series dir under HERE; runs in the current directory (tree or feeds/luci).
define push_series
	if $(call series_empty,$(1)); then \
		echo "== $(1): empty"; \
	elif $(call Q,$(1)) unapplied >/dev/null 2>&1; then \
		echo "== $(1)"; $(call Q,$(1)) push -a || exit 1; \
	else \
		top=$$($(call Q,$(1)) top 2>/dev/null); \
		if [ -n "$$top" ] && ! git apply --check -R $(HERE)/$(1)/$$top >/dev/null 2>&1; then \
			echo "== $(1): quilt state says '$$top' is applied but the tree does not contain it." >&2; \
			echo "   Stale $(HERE)/.pc/$(1)? Remove that directory and run make apply again." >&2; \
			exit 1; \
		fi; \
		echo "== $(1): already applied"; \
	fi
endef

# Pop every applied series of $(1) (a list); runs in the current directory.
define pop_series
	for s in $(1); do \
		if $(call Q,$$s) applied >/dev/null 2>&1; then echo "== $$s"; $(call Q,$$s) pop -a || exit 1; fi; \
	done
endef

# Check a list of series $(1): push each onto the unapplied directory, report,
# then pop everything again ($(2) = pop order). A failing patch stops its push.
define check_series
	for s in $(1); do \
		if $(call series_empty,$$s); then echo "ok   $$s (empty)"; continue; fi; \
		$(call Q,$$s) applied >/dev/null 2>&1 && { echo "$$s: already applied, run make -C 8devices unapply first" >&2; exit 1; }; \
		if $(call Q,$$s) push -a -q >/dev/null 2>&1; then echo "ok   $$s ($$($(call Q,$$s) applied | wc -l) patches)"; \
		else echo "FAIL $$s at $$($(call Q,$$s) next 2>/dev/null)"; rc=1; fi; \
	done; \
	for s in $(2); do $(call Q,$$s) applied >/dev/null 2>&1 && $(call Q,$$s) pop -a -q >/dev/null; done; \
	exit $${rc:-0}
endef

.PHONY: apply unapply check

apply:
	@cd $(TREE) && $(foreach s,$(SERIES_OPENWRT),$(call push_series,$(s));) true
	install -D -m 644 $(HERE)/$(BOARD_FILE) $(BOARD_DST)
	cp $(HERE)/feeds.conf $(TREE)/feeds.conf
ifneq ($(FEEDS),no)
	@if [ -d $(TREE)/feeds/luci ]; then cd $(TREE)/feeds/luci && $(call pop_series,$(SERIES_LUCI)); fi
	cd $(TREE) && ./scripts/feeds update luci packages
	@cd $(TREE)/feeds/luci && $(foreach s,$(SERIES_LUCI),$(call push_series,$(s));) true
	cd $(TREE) && ./scripts/feeds install -p luci luci luci-ssl && ./scripts/feeds install -p packages sudo
endif
	@echo "overlay applied to $(TREE)"

unapply:
	rm -f $(BOARD_DST); rmdir $(dir $(BOARD_DST)) 2>/dev/null || true
	@cd $(TREE) && $(call pop_series,$(SERIES_OPENWRT_POP))
	@if [ -d $(TREE)/feeds/luci ]; then cd $(TREE)/feeds/luci && $(call pop_series,$(SERIES_LUCI)); fi
	rm -f $(TREE)/feeds.conf
	@echo "overlay removed from $(TREE)"

check:
	@cd $(TREE) && $(call check_series,$(SERIES_OPENWRT),$(SERIES_OPENWRT_POP))
	@if [ -d $(TREE)/feeds/luci ]; then cd $(TREE)/feeds/luci && $(call check_series,$(SERIES_LUCI),$(SERIES_LUCI)); \
	else echo "SKIP $(SERIES_LUCI) (no feeds/luci yet: needs one ./quick_start.sh run, then make -C 8devices unapply)"; fi
