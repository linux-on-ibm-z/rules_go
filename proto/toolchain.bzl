# Copyright 2017 The Bazel Authors. All rights reserved.
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

load("@io_bazel_rules_go//go/private:common.bzl",
    "sets",
)

_protoc_prefix = "protoc-gen-"

def _emit_proto_compile(ctx, proto_toolchain, go_proto_toolchain, lib, importpath):
  go_srcs = []
  outpath = None
  for proto in lib.proto.direct_sources:
    out = ctx.actions.declare_file(ctx.label.name + "/" + importpath + "/" + proto.basename[:-len(".proto")] + go_proto_toolchain.suffix)
    go_srcs.append(out)
    if outpath == None:
        outpath = out.dirname[:-len(importpath)]
  plugin_base_name = go_proto_toolchain.plugin.basename
  if plugin_base_name.startswith(_protoc_prefix):
    plugin_base_name = plugin_base_name[len(_protoc_prefix):]
  args = ctx.actions.args()
  args.add([
      "--{}_out={}:{}".format(plugin_base_name, ",".join(go_proto_toolchain.options), outpath),
      "--plugin={}={}".format(go_proto_toolchain.plugin.basename, go_proto_toolchain.plugin.path),
      "--descriptor_set_in", ":".join(
          [s.path for s in lib.proto.transitive_descriptor_sets])
  ])
  args.add(lib.proto.direct_sources, map_fn=_all_proto_paths)
  ctx.actions.run(
      inputs = sets.union([
          proto_toolchain.protoc,
          go_proto_toolchain.plugin,
      ], lib.proto.transitive_descriptor_sets),
      outputs = go_srcs,
      progress_message = "Generating into %s" % go_srcs[0].dirname,
      mnemonic = "GoProtocGen",
      executable = proto_toolchain.protoc,
      arguments = [args],
  )
  return go_srcs

def _all_proto_paths(protos):
  return [_proto_path(proto) for proto in protos]

def _proto_path(proto):
  """
  The proto path is not really a file path
  It's the path to the proto that was seen when the descriptor file was generated.
  """
  path = proto.path
  root = proto.root.path
  ws = proto.owner.workspace_root
  if path.startswith(root): path = path[len(root):]
  if path.startswith("/"): path = path[1:]
  if path.startswith(ws): path = path[len(ws):]
  if path.startswith("/"): path = path[1:]
  return path

def _proto_toolchain_impl(ctx):
  return [platform_common.ToolchainInfo(
      protoc = ctx.file._protoc,
  )]

proto_toolchain = rule(
    _proto_toolchain_impl,
    attrs = {
        "_protoc": attr.label(
            allow_files = True,
            single_file = True,
            executable = True,
            cfg = "host",
            default = Label("@com_github_google_protobuf//:protoc"),
        ),
    },
)

def _go_proto_toolchain_impl(ctx):
  return [platform_common.ToolchainInfo(
      plugin = ctx.file.plugin,
      deps = ctx.attr.deps,
      options = ctx.attr.options,
      suffix = ctx.attr.suffix,
      compile = _emit_proto_compile,
  )]

go_proto_toolchain = rule(
    _go_proto_toolchain_impl,
    attrs = {
        "deps": attr.label_list(),
        "options": attr.string_list(),
        "suffix": attr.string(default = ".pb.go"),
        "plugin": attr.label(
            allow_files = True,
            single_file = True,
            executable = True,
            cfg = "host",
            default = Label("@com_github_golang_protobuf//protoc-gen-go"),
        ),
    },
)
