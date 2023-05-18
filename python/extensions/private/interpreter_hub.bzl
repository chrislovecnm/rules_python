# Copyright 2023 The Bazel Authors. All rights reserved
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"Repo rule used by bzlmod extension to create a repo that has a map of Python interpreters and their labels"

load("//python:versions.bzl", "WINDOWS_NAME")
load("//python/private:toolchains_repo.bzl", "get_host_os_arch", "get_host_platform")

_build_file_for_hub_template = """
INTERPRETER_LABELS = {{
{label_lines}
}}
INTERPRETER_VERSIONS = {{
{version_lines}
}}
DEFAULT_INTERPRETER_VERSION = {default_version}
"""

_line_for_hub_template = """\
    "{name}": Label("@{name}_{platform}//:{path}"),
"""
_version_line_for_hub_template = """\
    Label("@{name}_{platform}//:{path}") : {version},
"""

def _hub_repo_impl(rctx):
    (os, arch) = get_host_os_arch(rctx)
    platform = get_host_platform(os, arch)

    rctx.file("BUILD.bazel", "")
    is_windows = (os == WINDOWS_NAME)
    path = "python.exe" if is_windows else "bin/python3"

    label_lines = "\n".join([_line_for_hub_template.format(
        name = name,
        platform = platform,
        path = path,
    ) for name in rctx.attr.toolchains.keys()])

    version_lines = "\n".join([_version_line_for_hub_template.format(
        platform = platform,
        path = path,
    ) for name, version in rctx.attr.toolchains])

    content = _build_file_for_hub_template.format(
                label_lines = label_lines, 
                version_lines = version_lines, 
                default_version = rctx.default_version,
            )

    rctx.file("interpreters.bzl", content)

hub_repo = repository_rule(
    doc = """\
This private rule create a repo with a BUILD file that contains a map of interpreter names
and the labels to said interpreters. This map is used to by the interpreter hub extension.
""",
    implementation = _hub_repo_impl,
    attrs = {
        "toolchains": attr.string_dict(
            doc = "A dictionary of toolchain names and their python version",
            mandatory = True,
        ),
        "default_version": attr.string(
            doc = "The default python version",
            mandatory = True,
        ),
    },
)
