import clap
import types
import std/[tables, algorithm]


#TODO when modulation is supported, add modulation support input

proc newFloatParameter*(
        name            : string,
        min             : float64,
        max             : float64,
        default         : float64,
        id              : uint32,
        smooth_mode     : SmoothMode = smNone,
        smooth_val      : float64 = 10.0,
        as_value        : proc (str: string): float64 = nil,
        as_string       : proc (val: float64): string = nil,
        remap           : proc (val: float64): float64 = nil,
        calculate       : proc (plugin: ptr Plugin, val: float64, id: int): void = nil,
        path            : string = "",
        is_periodic     : bool = false,
        is_hidden       : bool = false,
        is_readonly     : bool = false,
        is_bypass       : bool = false,
        is_enum         : bool = false,
        req_process     : bool = true,
        automation      : AutoModuSupport = true): Parameter =
    return Parameter(
        name            : name,
        path            : path,
        kind            : pkFloat,
        f_min           : min,
        f_max           : max,
        f_default       : default,
        f_as_value      : as_value,
        f_as_string     : as_string,
        f_remap         : remap,
        f_smooth_cutoff : if smooth_mode == smFilter: smooth_val else: 0,
        f_smooth_ms     : if smooth_mode == smFilter: smooth_val else: 0,
        f_smooth_mode   : smooth_mode,
        f_calculate     : calculate,
        id              : id,
        is_periodic     : is_periodic,
        is_hidden       : is_hidden,
        is_readonly     : is_readonly,
        is_bypass       : is_bypass,
        is_enum         : is_enum,
        req_process     : req_process,
        automation      : automation
    )

proc newIntParameter*(
        name            : string,
        min             : int64,
        max             : int64,
        default         : int64,
        id              : uint32,
        as_value        : proc (str: string): int64 = nil,
        as_string       : proc (val: int64): string = nil,
        remap           : proc (val: int64): int64 = nil,
        path            : string = "",
        is_periodic     : bool = false,
        is_hidden       : bool = false,
        is_readonly     : bool = false,
        is_bypass       : bool = false,
        is_enum         : bool = false,
        req_process     : bool = true,
        automation      : AutoModuSupport = true): Parameter =
    return Parameter(
        name            : name,
        path            : path,
        kind            : pkInt,
        i_min           : min,
        i_max           : max,
        i_default       : default,
        i_as_value      : as_value,
        i_as_string     : as_string,
        i_remap         : remap,
        id              : id,
        is_periodic     : is_periodic,
        is_hidden       : is_hidden,
        is_readonly     : is_readonly,
        is_bypass       : is_bypass,
        is_enum         : is_enum,
        req_process     : req_process,
        automation      : automation
    )

proc newBoolParameter*(
        name            : string,
        default         : bool,
        id              : uint32,
        true_str        : string = "True",
        false_str       : string = "False",
        path            : string = "",
        is_periodic     : bool = false,
        is_hidden       : bool = false,
        is_readonly     : bool = false,
        is_bypass       : bool = false,
        is_enum         : bool = true,
        req_process     : bool = true,
        automation      : AutoModuSupport = true): Parameter =
    return Parameter(
        name            : name,
        path            : path,
        kind            : pkBool,
        b_default       : default,
        true_str        : true_str,
        false_str       : false_str,
        id              : id,
        is_periodic     : is_periodic,
        is_hidden       : is_hidden,
        is_readonly     : is_readonly,
        is_bypass       : is_bypass,
        is_enum         : is_enum,
        req_process     : req_process,
        automation      : automation
    )

proc repeat*(
        param : Parameter,
        name  : seq[string],
        id    : seq[uint32]
        ): seq[Parameter] =
    if len(name) == len(id):
        for i in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[i]
            p.id = id[i]
            result.add(p)
    elif len(id) == 1:
        for i in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[i]
            p.id = id[0] + uint32(i)
            result.add(p)
    elif len(name) == 1:
        for i in 0 ..< len(id):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[0] & " " & $(i + 1)
            p.id = id[i]
            result.add(p)

proc repeat*(
        param  : Parameter,
        repeat : int,
        name   : seq[string],
        id     : uint32
        ): seq[Parameter] =
    for i in 0 ..< repeat:
        for j in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[j] & " " & $(j + 1)
            p.id = id + uint32(j) + uint32(i * len(name))
            result.add(p)

proc repeat_parameter*(
        param  : Parameter,
        repeat : int,
        name   : seq[string],
        id     : seq[uint32]
        ): seq[Parameter] =
    assert repeat * len(name) == len(id)
    for i in 0 ..< repeat:
        for j in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[j] & " " & $(j + 1)
            p.id = id[j + i * len(name)]
            result.add(p)

proc id_from_index*(params: var seq[Parameter]): void =
    for i in 0 ..< len(params):
        params[i].id = uint32(i)

proc param_id_cmp*(p1, p2: Parameter): int =
    cmp(int(p1.id), int(p2.id))

proc sort_by_id*(params: var seq[Parameter]): void =
    params.sort(param_id_cmp)

# proc fill_ids*(params: var seq[Parameter]): void =
#     var ids: seq[uint32]
#     for p in params:
#         ids.add(p.id)
#     ids.sort()
#     var new_ids: seq[uint32]
#     var last: uint32 = 0
#     for i in ids:
#         assert i != last
#         if i - last > 1:
#             for j in 0 ..< (i - last):
#                 new_ids.add(i + uint32(j))
#     for n in new_ids:
#         params.add newBoolParameter(
#             name: "hidden"
#         )

proc id_table*(params: seq[Parameter]): Table[uint32, int] =
    for i in 0 ..< len(params):
        result[params[i].id] = i

proc name_table*(params: seq[Parameter]): Table[string, int] =
    for i in 0 ..< len(params):
        result[params[i].name] = i