# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Definition of JavaInfo and JavaPluginInfo provider.
"""

load(":common/cc/cc_common.bzl", "cc_common")
load(":common/cc/cc_info.bzl", "CcInfo")

# TODO(hvd): remove this when:
# - we have a general provider-type checking API
# - no longer need to check for --experimental_google_legacy_api
_java_common_internal = _builtins.internal.java_common_internal_do_not_use

_JavaOutputInfo = provider(
    doc = "The outputs of Java compilation.",
    fields = {
        "class_jar": "(File) A classes jar file.",
        "compile_jar": "(File) An interface jar file.",
        "ijar": "Deprecated: Please use compile_jar.",
        "compile_jdeps": "(File) Compile time dependencies information (deps.proto file).",
        "generated_class_jar": "(File) A jar containing classes generated via annotation processing.",
        "generated_source_jar": "(File) The source jar created as a result of annotation processing.",
        "native_headers_jar": "(File) A jar of CC header files supporting native method implementation.",
        "manifest_proto": "(File) The manifest protobuf file of the manifest generated from JavaBuilder.",
        "jdeps": "(File) The jdeps protobuf file of the manifest generated from JavaBuilder.",
        "source_jars": "(depset[File]) A depset of sources archive files.",
        "source_jar": "Deprecated: Please use source_jars instead.",
    },
)
_ModuleFlagsInfo = provider(
    doc = "Provider for the runtime classpath contributions of a Java binary.",
    fields = {
        "add_exports": "(depset[str]) Add-Exports configuration.",
        "add_opens": "(depset[str]) Add-Opens configuration.",
    },
)
_JavaRuleOutputJarsInfo = provider(
    doc = "Deprecated: use java_info.java_outputs. Information about outputs of a Java rule.",
    fields = {
        "jdeps": "Deprecated: Use java_info.java_outputs.",
        "native_headers": "Deprecated: Use java_info.java_outputs[i].jdeps.",
        "jars": "Deprecated: Use java_info.java_outputs[i].native_headers_jar.",
    },
)
_JavaGenJarsInfo = provider(
    doc = "Deprecated: Information about jars that are a result of annotation processing for a Java rule.",
    fields = {
        "enabled": "Deprecated. Returns true if annotation processing was applied on this target.",
        "class_jar": "Deprecated: Please use JavaInfo.java_outputs.generated_class_jar instead.",
        "source_jar": "Deprecated: Please use JavaInfo.java_outputs.generated_source_jar instead.",
        "transitive_class_jars": "Deprecated. A transitive set of class file jars from annotation " +
                                 "processing of this rule and its dependencies.",
        "transitive_source_jars": "Deprecated. A transitive set of source archives from annotation " +
                                  "processing of this rule and its dependencies.",
        "processor_classpath": "Deprecated: Please use JavaInfo.plugins instead.",
        "processor_classnames": "Deprecated: Please use JavaInfo.plugins instead.",
    },
)

_JavaCompilationInfo = provider(
    doc = "Compilation information in Java rules, for perusal of aspects and tools.",
    fields = {
        "boot_classpath": "Boot classpath for this Java target.",
        "javac_options": "Options to the java compiler.",
        "compilation_classpath": "Compilation classpath for this Java target.",
        "runtime_classpath": "Run-time classpath for this Java target.",
    },
)

_EMPTY_COMPILATION_INFO = _JavaCompilationInfo(
    compilation_classpath = depset(),
    runtime_classpath = depset(),
    boot_classpath = None,
    javac_options = [],
)

def merge(
        providers,
        # private to @_builtins:
        merge_java_outputs = True,
        merge_source_jars = True):
    """Merges the given providers into a single JavaInfo.

    Args:
        providers: ([JavaInfo]) The list of providers to merge.
        merge_java_outputs: (bool)
        merge_source_jars: (bool)

    Returns:
        (JavaInfo) The merged JavaInfo
    """
    return _java_common_internal.merge(
        providers,
        merge_java_outputs = merge_java_outputs,
        merge_source_jars = merge_source_jars,
    )

def to_java_binary_info(java_info):
    """Get a copy of the given JavaInfo with minimal info returned by a java_binary

    Args:
        java_info: (JavaInfo) A JavaInfo provider instance

    Returns:
        (JavaInfo) A JavaInfo instance representing a java_binary target
    """
    result = {
        "transitive_runtime_jars": depset(),
        "transitive_runtime_deps": depset(),  # deprecated
        "transitive_compile_time_jars": depset(),
        "transitive_deps": depset(),  # deprecated
        "compile_jars": depset(),
        "full_compile_jars": depset(),
        "_transitive_full_compile_time_jars": depset(),
        "_compile_time_java_dependencies": depset(),
        "runtime_output_jars": [],
        "plugins": _EMPTY_PLUGIN_DATA,
        "api_generating_plugins": _EMPTY_PLUGIN_DATA,
        "module_flags_info": _ModuleFlagsInfo(add_exports = depset(), add_opens = depset()),
        "_neverlink": False,
        "_constraints": [],
        "annotation_processing": java_info.annotation_processing,
        "transitive_native_libraries": java_info.transitive_native_libraries,
        "source_jars": java_info.source_jars,
        "transitive_source_jars": java_info.transitive_source_jars,
    }
    if hasattr(java_info, "cc_link_params_info"):
        result.update(cc_link_params_info = java_info.cc_link_params_info)

    compilation_info = _EMPTY_COMPILATION_INFO
    if java_info.compilation_info:
        compilation_info = java_info.compilation_info
    elif java_info.transitive_compile_time_jars or java_info.transitive_runtime_jars:
        compilation_info = _JavaCompilationInfo(
            boot_classpath = None,
            javac_options = [],
            compilation_classpath = java_info.transitive_compile_time_jars,
            runtime_classpath = java_info.transitive_runtime_jars,
        )
    result["compilation_info"] = compilation_info

    java_outputs = [
        _JavaOutputInfo(
            compile_jar = None,
            ijar = None,  # deprecated
            compile_jdeps = None,
            class_jar = output.class_jar,
            generated_class_jar = output.generated_class_jar,
            generated_source_jar = output.generated_source_jar,
            native_headers_jar = output.native_headers_jar,
            manifest_proto = output.manifest_proto,
            jdeps = output.jdeps,
            source_jars = output.source_jars,
            source_jar = output.source_jar,  # deprecated
        )
        for output in java_info.java_outputs
    ]
    all_jdeps = [output.jdeps for output in java_info.java_outputs if output.jdeps]
    all_native_headers = [output.native_headers_jar for output in java_info.java_outputs if output.native_headers_jar]
    result.update(
        java_outputs = java_outputs,
        outputs = _JavaRuleOutputJarsInfo(
            jars = java_outputs,
            jdeps = all_jdeps[0] if len(all_jdeps) == 1 else None,
            native_headers = all_native_headers[0] if len(all_native_headers) == 1 else None,
        ),
    )

    # so that translation into native JavaInfo does not add JavaCompilationArgsProvider
    result.update(_is_binary = True)
    return _new_javainfo(**result)

def _to_mutable_dict(java_info):
    return {
        key: getattr(java_info, key)
        for key in dir(java_info)
        if key not in ["to_json", "to_proto"]
    }

def add_constraints(java_info, constraints = []):
    """Returns a copy of the given JavaInfo with the given constraints added.

    Args:
        java_info: (JavaInfo) The JavaInfo to enhance
        constraints: ([str]) Constraints to add

    Returns:
        (JavaInfo)
    """
    result = _to_mutable_dict(java_info)
    old_constraints = java_info._constraints if java_info._constraints else []
    result.update(
        _constraints = depset(constraints + old_constraints).to_list(),
    )
    return _new_javainfo(**result)

def make_non_strict(java_info):
    """Returns a new JavaInfo instance whose direct-jars part is the union of both the direct and indirect jars of the given Java provider.

    Args:
        java_info: (JavaInfo) The java info to make non-strict.

    Returns:
        (JavaInfo)
    """
    result = _to_mutable_dict(java_info)
    result.update(
        compile_jars = java_info.transitive_compile_time_jars,
        full_compile_jars = java_info._transitive_full_compile_time_jars,
    )

    # Omit jdeps, which aren't available transitively and aren't useful for reduced classpath
    # pruning for non-strict targets: the direct classpath and transitive classpath are the same,
    # so there's nothing to prune, and reading jdeps at compile-time isn't free.
    result.update(
        _compile_time_java_dependencies = depset(),
    )
    return _new_javainfo(**result)

def set_annotation_processing(
        java_info,
        enabled = False,
        processor_classnames = [],
        processor_classpath = None,
        class_jar = None,
        source_jar = None):
    """Returns a copy of the given JavaInfo with the given annotation_processing info.

    Args:
        java_info: (JavaInfo) The JavaInfo to enhance.
        enabled: (bool) Whether the rule uses annotation processing.
        processor_classnames: ([str]) Class names of annotation processors applied.
        processor_classpath: (depset[File]) Class names of annotation processors applied.
        class_jar: (File) Optional. Jar that is the result of annotation processing.
        source_jar: (File) Optional. Source archive resulting from annotation processing.

    Returns:
        (JavaInfo)
    """
    gen_jars_info = java_info.annotation_processing
    if gen_jars_info:
        # Existing Jars would be a problem b/c we can't remove them from transitiveXxx sets
        if gen_jars_info.class_jar and gen_jars_info.class_jar != class_jar:
            fail("Existing gen_class_jar:", gen_jars_info.class_jar)
        if gen_jars_info.source_jar and gen_jars_info.source_jar != source_jar:
            fail("Existing gen_source_jar:", gen_jars_info.class_jar)
        transitive_class_jars = depset([class_jar] if class_jar else [], transitive = [gen_jars_info.transitive_class_jars])
        transitive_source_jars = depset([source_jar] if source_jar else [], transitive = [gen_jars_info.transitive_source_jars])
    else:
        transitive_class_jars = depset([class_jar] if class_jar else [])
        transitive_source_jars = depset([source_jar] if source_jar else [])

    result = _to_mutable_dict(java_info)
    result.update(
        annotation_processing = _JavaGenJarsInfo(
            enabled = enabled,
            class_jar = class_jar,
            source_jar = source_jar,
            processor_classnames = processor_classnames,
            processor_classpath = processor_classpath if processor_classpath else depset(),
            transitive_class_jars = transitive_class_jars,
            transitive_source_jars = transitive_source_jars,
        ),
    )
    return _new_javainfo(**result)

def _validate_provider_list(provider_list, what, expected_provider_type):
    _java_common_internal.check_provider_instances(provider_list, what, expected_provider_type)

def _javainfo_init(
        output_jar,
        compile_jar,
        source_jar = None,
        compile_jdeps = None,
        generated_class_jar = None,
        generated_source_jar = None,
        native_headers_jar = None,
        manifest_proto = None,
        neverlink = False,
        deps = [],
        runtime_deps = [],
        exports = [],
        exported_plugins = [],
        jdeps = None,
        native_libraries = []):
    """The JavaInfo constructor

    Args:
        output_jar: (File) The jar that was created as a result of a compilation.
        compile_jar: (File) A jar that is the compile-time dependency in lieu of `output_jar`.
        source_jar: (File) The source jar that was used to create the output jar. Optional.
        compile_jdeps: (File) jdeps information about compile time dependencies to be consumed by
            JavaCompileAction. This should be a binary proto encoded using the deps.proto protobuf
            included with Bazel. If available this file is typically produced by a header compiler.
            Optional.
        generated_class_jar: (File) A jar file containing class files compiled from sources
            generated during annotation processing. Optional.
        generated_source_jar: (File) The source jar that was created as a result of annotation
            processing. Optional.
        native_headers_jar: (File) A jar containing CC header files supporting native method
            implementation (typically output of javac -h). Optional.
        manifest_proto: (File) Manifest information for the rule output (if available). This should
            be a binary proto encoded using the manifest.proto protobuf included with Bazel. IDEs
            and other tools can use this information for more efficient processing. Optional.
        neverlink: (bool) If true, only use this library for compilation and not at runtime.
        deps: ([JavaInfo]) Compile time dependencies that were used to create the output jar.
        runtime_deps: ([JavaInfo]) Runtime dependencies that are needed for this library.
        exports: ([JavaInfo]) Libraries to make available for users of this library.
        exported_plugins: ([JavaPluginInfo]) Optional. A list of exported plugins.
        jdeps: (File) jdeps information for the rule output (if available). This should be a binary
            proto encoded using the deps.proto protobuf included with Bazel. If available this file
            is typically produced by a compiler. IDEs and other tools can use this information for
            more efficient processing. Optional.
        native_libraries: ([CcInfo]) Native library dependencies that are needed for this library.

    Returns:
        (dict) arguments to the JavaInfo provider constructor
    """
    _validate_provider_list(deps, "deps", JavaInfo)
    _validate_provider_list(runtime_deps, "runtime_deps", JavaInfo)
    _validate_provider_list(exports, "exports", JavaInfo)
    _validate_provider_list(native_libraries, "native_libraries", CcInfo)

    source_jars = [source_jar] if source_jar else []
    plugin_info = _merge_plugin_info_without_outputs(exported_plugins + exports)
    if neverlink:
        transitive_runtime_jars = depset()
    else:
        transitive_runtime_jars = depset(
            order = "preorder",
            direct = [output_jar],
            transitive = [dep.transitive_runtime_jars for dep in exports + deps + runtime_deps],
        )
    transitive_compile_time_jars = depset(
        order = "preorder",
        direct = [compile_jar] if compile_jar else [],
        transitive = [dep.transitive_compile_time_jars for dep in exports + deps],
    )
    java_outputs = [_JavaOutputInfo(
        class_jar = output_jar,
        compile_jar = compile_jar,
        ijar = compile_jar,  # deprecated
        compile_jdeps = compile_jdeps,
        generated_class_jar = generated_class_jar,
        generated_source_jar = generated_source_jar,
        native_headers_jar = native_headers_jar,
        manifest_proto = manifest_proto,
        jdeps = jdeps,
        source_jars = depset(source_jars) if _java_common_internal._incompatible_depset_for_java_output_source_jars() else source_jars,
        source_jar = source_jar,  # deprecated
    )]

    result = {
        "transitive_runtime_jars": transitive_runtime_jars,
        "transitive_runtime_deps": transitive_runtime_jars,  # deprecated
        "transitive_compile_time_jars": transitive_compile_time_jars,
        "transitive_deps": transitive_compile_time_jars,  # deprecated
        "compile_jars": depset(
            order = "preorder",
            direct = [compile_jar] if compile_jar else [],
            transitive = [dep.compile_jars for dep in exports],
        ),
        "full_compile_jars": depset(
            order = "preorder",
            direct = [output_jar],
            transitive = [
                dep.full_compile_jars
                for dep in exports
            ],
        ),
        "source_jars": source_jars,
        "runtime_output_jars": [output_jar],
        "transitive_source_jars": depset(
            direct = source_jars,
            # TODO(hvd): native also adds source jars from deps, but this should be unnecessary
            transitive = [
                dep.transitive_source_jars
                for dep in deps + runtime_deps + exports
            ],
        ),
        "module_flags_info": _ModuleFlagsInfo(
            add_exports = depset(transitive = [
                dep.module_flags_info.add_exports
                for dep in deps + exports
            ]),
            add_opens = depset(transitive = [
                dep.module_flags_info.add_opens
                for dep in deps + exports
            ]),
        ),
        "plugins": plugin_info.plugins,
        "api_generating_plugins": plugin_info.api_generating_plugins,
        "java_outputs": java_outputs,
        # deprecated
        "outputs": _JavaRuleOutputJarsInfo(
            jars = java_outputs,
            jdeps = jdeps,
            native_headers = native_headers_jar,
        ),
        "annotation_processing": _JavaGenJarsInfo(
            enabled = False,
            class_jar = generated_class_jar,
            source_jar = generated_source_jar,
            transitive_class_jars = depset(
                direct = [generated_class_jar] if generated_class_jar else [],
                transitive = [
                    dep.annotation_processing.transitive_class_jars
                    for dep in deps + exports
                    if dep.annotation_processing
                ],
            ),
            transitive_source_jars = depset(
                direct = [generated_source_jar] if generated_source_jar else [],
                transitive = [
                    dep.annotation_processing.transitive_source_jars
                    for dep in deps + exports
                    if dep.annotation_processing
                ],
            ),
            processor_classnames = [],
            processor_classpath = depset(),
        ),
        "compilation_info": None,
        "_neverlink": neverlink,
        "_transitive_full_compile_time_jars": depset(
            order = "preorder",
            direct = [output_jar],
            transitive = [dep._transitive_full_compile_time_jars for dep in exports + deps],
        ),
        "_compile_time_java_dependencies": depset(
            order = "preorder",
            transitive = [dep._compile_time_java_dependencies for dep in exports] +
                         ([depset([compile_jdeps])] if compile_jdeps else []),
        ),
        "_constraints": [],
    }
    if _java_common_internal._google_legacy_api_enabled():
        cc_info = cc_common.merge_cc_infos(
            cc_infos = [dep.cc_link_params_info for dep in runtime_deps + exports + deps] +
                       ([cc_common.merge_cc_infos(cc_infos = native_libraries)] if native_libraries else []),
        )
        result.update(
            cc_link_params_info = cc_info,
            transitive_native_libraries = cc_info.transitive_native_libraries(),
        )
    else:
        result.update(
            transitive_native_libraries = depset(
                order = "topological",
                transitive = [dep.transitive_native_libraries for dep in runtime_deps + exports + deps] +
                             ([cc_common.merge_cc_infos(cc_infos = native_libraries).transitive_native_libraries()] if native_libraries else []),
            ),
        )
    return result

JavaInfo, _new_javainfo = provider(
    doc = "Info object encapsulating all information by java rules.",
    fields = {
        "transitive_runtime_jars": "(depset[File]) A transitive set of jars required on the runtime classpath.",
        "transitive_compile_time_jars": "(depset[File]) The transitive set of jars required to build the target.",
        "compile_jars": """(depset[File]) The jars required directly at compile time. They can be interface jars
                (ijar or hjar), regular jars or both, depending on whether rule
                implementations chose to create interface jars or not.""",
        "full_compile_jars": """(depset[File]) The regular, full compile time Jars required by this target directly.
                They can be:
                 - the corresponding regular Jars of the interface Jars returned by JavaInfo.compile_jars
                 - the regular (full) Jars returned by JavaInfo.compile_jars

                Note: JavaInfo.compile_jars can return a mix of interface Jars and
                regular Jars.<p>Only use this method if interface Jars don't work with
                your rule set(s) (e.g. some Scala targets) If you're working with
                Java-only targets it's preferable to use interface Jars via
                JavaInfo.compile_jars""",
        "source_jars": """([File]) A list of Jars with all the source files (including those generated by
                annotations) of the target itself, i.e. NOT including the sources of the
                transitive dependencies.""",
        "outputs": "Deprecated: use java_outputs.",
        "annotation_processing": "Deprecated: Please use plugins instead.",
        "runtime_output_jars": "([File]) A list of runtime Jars created by this Java/Java-like target.",
        "transitive_deps": "Deprecated: Please use transitive_compile_time_jars instead.",
        "transitive_runtime_deps": "Deprecated: please use transitive_runtime_jars instead.",
        "transitive_source_jars": "(depset[File]) The Jars of all source files in the transitive closure.",
        "transitive_native_libraries": """(depset[LibraryToLink]) The transitive set of CC native
                libraries required by the target.""",
        "cc_link_params_info": "Deprecated. Do not use. C++ libraries to be linked into Java targets.",
        "module_flags_info": "(_ModuleFlagsInfo) The Java module flag configuration.",
        "plugins": """(_JavaPluginDataInfo) Data about all plugins that a consuming target should
               apply.
               This is typically either a `java_plugin` itself or a `java_library` exporting
               one or more plugins.
               A `java_library` runs annotation processing with all plugins from this field
               appearing in <code>deps</code> and `plugins` attributes.""",
        "api_generating_plugins": """"(_JavaPluginDataInfo) Data about API generating plugins
               defined or exported by this target.
               Those annotation processors are applied to a Java target before
               producing its header jars (which contain method signatures). When
               no API plugins are present, header jars are generated from the
               sources, reducing critical path.
               The `api_generating_plugins` is a subset of `plugins`.""",
        "java_outputs": "(_JavaOutputInfo) Information about outputs of this Java/Java-like target.",
        "compilation_info": """(java_compilation_info) Compilation information for this
               Java/Java-like target.""",
        "_transitive_full_compile_time_jars": "internal API, do not use",
        "_compile_time_java_dependencies": "internal API, do not use",
        "_neverlink": "internal API, do not use",
        "_constraints": "internal API, do not use",
        "_is_binary": "internal API, do not use",
    },
    init = _javainfo_init,
)

_JavaPluginDataInfo = provider(
    doc = "Provider encapsulating information about a Java compatible plugin.",
    fields = {
        "processor_classes": "depset(str) The fully qualified classnames of entry points for the compiler",
        "processor_jars": "depset(file) Deps containing an annotation processor",
        "processor_data": "depset(file) Files needed during execution",
    },
)

_EMPTY_PLUGIN_DATA = _JavaPluginDataInfo(
    processor_classes = depset(),
    processor_jars = depset(),
    processor_data = depset(),
)

def _merge_plugin_info_without_outputs(infos):
    """ Merge plugin information from a list of JavaPluginInfo or JavaInfo

    Args:
        infos: ([JavaPluginInfo|JavaInfo]) list of providers to merge

    Returns:
        (JavaPluginInfo)
    """
    plugins = []
    api_generating_plugins = []
    for info in infos:
        if _has_plugin_data(info.plugins):
            plugins.append(info.plugins)
        if _has_plugin_data(info.api_generating_plugins):
            api_generating_plugins.append(info.api_generating_plugins)
    return _new_javaplugininfo(
        plugins = _merge_plugin_data(plugins),
        api_generating_plugins = _merge_plugin_data(api_generating_plugins),
        java_outputs = [],
    )

def _has_plugin_data(plugin_data):
    return plugin_data and (
        plugin_data.processor_classes or
        plugin_data.processor_jars or
        plugin_data.processor_data
    )

def _merge_plugin_data(datas):
    return _JavaPluginDataInfo(
        processor_classes = depset(transitive = [p.processor_classes for p in datas]),
        processor_jars = depset(transitive = [p.processor_jars for p in datas]),
        processor_data = depset(transitive = [p.processor_data for p in datas]),
    )

def _javaplugininfo_init(
        runtime_deps,
        processor_class,
        data = [],
        generates_api = False):
    """ Constructs JavaPluginInfo

    Args:
        runtime_deps: ([JavaInfo]) list of deps containing an annotation
             processor.
        processor_class: (String) The fully qualified class name that the Java
             compiler uses as an entry point to the annotation processor.
        data: (depset[File]) The files needed by this annotation
             processor during execution.
        generates_api: (boolean) Set to true when this annotation processor
            generates API code. Such an annotation processor is applied to a
            Java target before producing its header jars (which contains method
            signatures). When no API plugins are present, header jars are
            generated from the sources, reducing the critical path.
            WARNING: This parameter affects build performance, use it only if
            necessary.

    Returns:
        (JavaPluginInfo)
    """

    java_infos = merge(runtime_deps)
    processor_data = data if type(data) == "depset" else depset(data)
    plugins = _JavaPluginDataInfo(
        processor_classes = depset([processor_class]) if processor_class else depset(),
        processor_jars = java_infos.transitive_runtime_jars,
        processor_data = processor_data,
    )
    return {
        "plugins": plugins,
        "api_generating_plugins": plugins if generates_api else _EMPTY_PLUGIN_DATA,
        "java_outputs": java_infos.java_outputs,
    }

JavaPluginInfo, _new_javaplugininfo = provider(
    doc = "Provider encapsulating information about Java plugins.",
    fields = {
        "plugins": """
            Returns data about all plugins that a consuming target should apply.
            This is typically either a <code>java_plugin</code> itself or a
            <code>java_library</code> exporting one or more plugins.
            A <code>java_library</code> runs annotation processing with all
            plugins from this field appearing in <code>deps</code> and
            <code>plugins</code> attributes.""",
        "api_generating_plugins": """
            Returns data about API generating plugins defined or exported by
            this target.
            Those annotation processors are applied to a Java target before
            producing its header jars (which contain method signatures). When
            no API plugins are present, header jars are generated from the
            sources, reducing critical path.
            The <code>api_generating_plugins</code> is a subset of
            <code>plugins</code>.""",
        "java_outputs": """
            Returns information about outputs of this Java/Java-like target.
        """,
    },
    init = _javaplugininfo_init,
)
