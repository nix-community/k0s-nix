# Loaded beside upstream's embedded-bins/Makefile:
#
#   make -f Makefile -f extract.mk extract
#
# make is the reader because Makefile.variables composes values with
# $(word ...) and $(subst ...), which a shell `source` would not resolve,
# and `make -p` reports definitions rather than expansions.

# Not derived: make cannot report which variables its recipes expand.
# extract.py asserts this list against the --build-arg lines in upstream's
# Makefile, so a suffix added there fails rather than passing through
# unread.
extract_suffixes = \
  _version _revision _buildimage \
  _build_go_tags _build_go_cgo_enabled _build_go_cgo_cflags \
  _build_shim_go_cgo_enabled _build_go_flags \
  _build_go_ldflags _build_go_ldflags_extra \
  _build_cflags _build_ldflags _build_configure_flags

extract_names = go_version alpine_patch_version images posix_bins \
  $(foreach c,$(images),$(foreach s,$(extract_suffixes),$(c)$(s)))

.PHONY: extract
extract:
	@$(foreach n,$(extract_names),printf '%s\t%s\n' '$(n)' '$($(n))';)
