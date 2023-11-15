"""A module defining the third party dependency WasmX"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

wasm_runtime_build_file = """
filegroup(
    name = "lib",
    srcs = glob(["**/*.so", "**/*.dylib"]),
    visibility = ["//visibility:public"]
)
"""

vector_binaries = {
    "linux": {
        "x86_64": None,
        "aarch64": None,
    },
    "macos": {
        "x86_64": None,
        "aarch64": None,
    },
}

def vector_repositories():
    vector_version = KONG_VAR["VECTOR"]

    for os in vector_binaries:
        for arch in vector_binaries[os]:
            # normalize macos to darwin used in url
            url_os = os
            if os == "macos":
                url_os = "apple-darwin"
                # for now, always use x86_64 binary as there are no aarch64 release binaries available
                url_arch = "x86_64"
            else:
                url_os = "unknown-linux-gnu"
                url_arch = arch

            http_archive(
                name = "vector-%s-%s" % (os, arch),
                urls = [
                    "https://github.com/vectordotdev/vector/releases/download/v%s/vector-%s-%s-%s.tar.gz" % (vector_version, vector_version, url_arch, url_os),
                ],
                sha256 = vector_binaries[os][arch],
                strip_prefix = "vector-%s-%s" % (url_arch, url_os),
                build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"]
)
""",
            )

    vector_config_settings(name = "vector_config_settings")

# generate boilerplate config_settings
def _vector_config_settings_impl(ctx):
    content = ""
    for os in vector_binaries:
        for arch in vector_binaries[os]:
            content += ("""
config_setting(
    name = "use_vector_{os}_{arch}",
    constraint_values = [
        "@platforms//cpu:{arch}",
        "@platforms//os:{os}",
    ],
    visibility = ["//visibility:public"],
)
        """.format(
                os = os,
                arch = arch,
            ))

    ctx.file("BUILD.bazel", content)

vector_config_settings = repository_rule(
    implementation = _vector_config_settings_impl,
)
