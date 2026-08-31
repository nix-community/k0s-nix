# Upstream's static flag is dropped rather than reproduced, for the reasons
# README.md gives. The assert is so that anything else in the field stops the
# build instead of going with it; etcd leaves the field out, so absent passes.
component:
let
  staticLinking = "-extldflags=-static";
  extra = component.build_go_ldflags_extra or staticLinking;
in
assert extra == staticLinking;
component.build_go_ldflags or ""
