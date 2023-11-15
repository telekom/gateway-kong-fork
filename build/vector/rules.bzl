load("//build/vector:vector_repositories.bzl", "vector_binaries")
load("//build:build_system.bzl", "kong_arch_dependent_binaries_link")

def vector_binaries_rule(**kwargs):
    select_conds = {}
    for os in vector_binaries:
        for arch in vector_binaries[os]:
            select_conds["@vector_config_settings//:use_vector_%s_%s" % (os, arch)] = \
                "@vector-%s-%s//:all_srcs" % (os, arch)

    kong_arch_dependent_binaries_link(
        prefix = kwargs["name"],
        src = select(select_conds),
        **kwargs
    )
