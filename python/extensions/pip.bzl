# Copyright 2023 The Bazel Authors. All rights reserved.
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

"pip module extension for use with bzlmod"

load("@rules_python//python:pip.bzl", "whl_library_alias")
load("@rules_python//python/pip_install:pip_repository.bzl", "locked_requirements_label", "pip_repository_attrs", "pip_repository_bzlmod", "use_isolated", "whl_library")
load("@rules_python//python/pip_install:requirements_parser.bzl", parse_requirements = "parse")
load("@pythons_hub//:interpreters.bzl", "INTERPRETER_VERSIONS", "DEFAULT_INTERPRETER_VERSION")

def _create_pip(module_ctx, pip_attr, name, requirements_map):
    whl_map = {}
    requrements_lock = locked_requirements_label(module_ctx, pip_attr)

    # Parse the requirements file directly in starlark to get the information
    # needed for the whl_libary declarations below. This is needed to contain
    # the pip_repository logic to a single module extension.
    requirements_lock_content = module_ctx.read(requrements_lock)
    parse_result = parse_requirements(requirements_lock_content)
    requirements = parse_result.requirements
    extra_pip_args = attr.extra_pip_args + parse_result.options

    # Create the repository where users load the `requirement` macro. Under bzlmod
    # this does not create the install_deps() macro.
    pip_repository_bzlmod(
        name = pip_attr.name,
        repo_name = pip_attr.name,
        requirements_lock = attr.requirements_lock,
        incompatible_generate_aliases = attr.incompatible_generate_aliases,
    )

    for whl_name, requirement_line in requirements:
        whl_library(
            name = "%s_%s" % (name, _sanitize_name(whl_name)),
            requirement = requirement_line,
            repo = name,
            repo_prefix = name + "_",
            annotation = pip_attr.annotations.get(whl_name),
            python_interpreter = attr.python_interpreter,
            python_interpreter_target = attr.python_interpreter_target,
            quiet = attr.quiet,
            timeout = attr.timeout,
            isolated = use_isolated(module_ctx, attr),
            extra_pip_args = extra_pip_args,
            download_only = attr.download_only,
            pip_data_exclude = attr.pip_data_exclude,
            enable_implicit_namespace_pkgs = attr.enable_implicit_namespace_pkgs,
            environment = attr.environment,
        )

        # TODO get a way to pull the python version from the interpreter_repo
        # based on python_interpreter_target
        version = INTERPRETER_VERSIONS[attr.python_interpreter_target]
        whl_map[whl_name][pip_attr.name] = { "pip_name": pip_attr.name, "version": attr.python_interpreter_target }

    if name in requirements_map:
        requirements_map[name].append(requirements)
    else:
        requirements_map[name] = [requirements]
    return requirements_map, whl_map

def _pip_impl(module_ctx):

    root_hubs = {} 
    requirements_map = {}
    submodules_hubs = {}
    wheel_map = {}

    for mod in module_ctx.modules:
        for pip_attr in mod.tags.parse:
            if mod.is_root:
                if attr.hub_name in root_hubs:
                    root_hubs[attr.hub_name].append(pip_attr)
                else:
                    root_hubs[attr.hub_name] = [pip_attr]
            else:
                if attr.hub_name in submodules_hubs:
                    submodules_hubs[attr.hub_name].append(pip_attr)
                else:
                    submodules_hubs[attr.hub_name] = [pip_attr]
    
    i = 0
    for name, pip_attr in root_hubs:
        name = pip_attr + "_{}".format(i)
        requirements_map = _create_pip(module_ctx, pip_attr, name, requirements_map)
        i = i + 1

    for name, pip_attr in submodules_hubs:
        if name in root_hubs:
            print("Not creating pip with the hub_name {}, same hub name found in the root module.".format(name))
            continue

        name = pip_attr + "_{}".format(i)
        requirements_map, wheel_map[name] = _create_pip(module_ctx, pip_attr, name, requirements_map)
        i = i + 1 

    for name, requirement in requirements_map:
        version_map = wheel_map[name]
        for whl_name in requirement:
            whl_library_alias(
                name = name + "_" + whl_name,
                wheel_name = whl_name,
                default_version = DEFAULT_INTERPRETER_VERSION,
                version_map = version_map[whl_name],
            )


# Keep in sync with python/pip_install/tools/bazel.py
def _sanitize_name(name):
    return name.replace("-", "_").replace(".", "_").lower()

def _pip_parse_ext_attrs():
    attrs = dict({
        "hub_name": attr.string(mandatory = True),
    }, **pip_repository_attrs)

    # Like the pip_repository rule, we end up setting this manually so
    # don't allow users to override it.
    attrs.pop("repo_prefix")

    return attrs

pip = module_extension(
    doc = """\
This extension is used to create a pip respository and create the various wheel libaries if
provided in a requirements file.
""",
    implementation = _pip_impl,
    tag_classes = {
        "parse": tag_class(attrs = _pip_parse_ext_attrs()),
    },
)
