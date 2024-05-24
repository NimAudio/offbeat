import clap
import types, state, process
import std/[locks, strutils, tables]


proc param_f*(plugin: ptr Plugin, name: string): float =
    return plugin.dsp_param_data[plugin.name_map[name]].f_value

proc param_i*(plugin: ptr Plugin, name: string): int =
    return plugin.dsp_param_data[plugin.name_map[name]].i_value

proc param_b*(plugin: ptr Plugin, name: string): bool =
    return plugin.dsp_param_data[plugin.name_map[name]].b_value

proc offbeat_params_count*(clap_plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    return uint32(len(plugin.params))

proc offbeat_params_get_info*(clap_plugin: ptr ClapPlugin, index: uint32, information: ptr ClapParamInfo): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    # if index >= uint32(len(plugin.params)):
    #     return false
    # else:
    if index notin plugin.id_map:
        return false
    else:
        var param = plugin.params[plugin.id_map[index]]
        var flags: set[ClapParamInfoFlag]
        if param.kind == pkInt or param.kind == pkBool:
            flags.incl(cpiIS_STEPPED)
        if param.is_periodic : flags.incl(cpiIS_PERIODIC)
        if param.is_hidden   : flags.incl(cpiIS_HIDDEN)
        if param.is_readonly : flags.incl(cpiIS_READONLY)
        if param.is_bypass   : flags.incl(cpiIS_BYPASS)
        if param.req_process : flags.incl(cpiREQUIRES_PROCESS)
        if param.is_enum     : flags.incl(cpiIS_ENUM)
        if param.automation.base:
            flags.incl(cpiIS_AUTOMATABLE)
            if param.automation.per_note_id : flags.incl(cpiIS_AUTOMATABLE_PER_NOTE_ID)
            if param.automation.per_key     : flags.incl(cpiIS_AUTOMATABLE_PER_KEY)
            if param.automation.per_channel : flags.incl(cpiIS_AUTOMATABLE_PER_CHANNEL)
            if param.automation.per_port    : flags.incl(cpiIS_AUTOMATABLE_PER_PORT)
        if param.modulation.base:
            flags.incl(cpiIS_MODULATABLE)
            if param.modulation.per_note_id : flags.incl(cpiIS_MODULATABLE_PER_NOTE_ID)
            if param.modulation.per_key     : flags.incl(cpiIS_MODULATABLE_PER_KEY)
            if param.modulation.per_channel : flags.incl(cpiIS_MODULATABLE_PER_CHANNEL)
            if param.modulation.per_port    : flags.incl(cpiIS_MODULATABLE_PER_PORT)

        var min_val     = low(float64)
        var max_val     = high(float64)
        var default_val = 0.0
        case param.kind:
            of pkFloat:
                min_val     = param.f_min
                max_val     = param.f_max
                default_val = param.f_default
            of pkInt:
                min_val     = float64(param.i_min)
                max_val     = float64(param.i_max)
                default_val = float64(param.i_default)
            of pkBool:
                default_val = if param.b_default: 1.0 else: 0.0
        information[] = ClapParamInfo(
            id            : ClapID(param.id),
            flags         : flags,
            cookie        : nil, # figure this out and implement it
            name          : char_arr_name(param.name),
            module        : char_arr_path(param.path),
            min_value     : min_val,
            max_value     : max_val,
            default_value : default_val
        )
        return true
        # return information.min_value != 0 or information.max_value != 0

proc bool_to_float*(b: bool): float64 =
    if b:
        return 1.0
    else:
        return 0.0

proc offbeat_params_get_value*(clap_plugin: ptr ClapPlugin, id: ClapID, value: ptr float64): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    var index = uint32(id)
    if index >= uint32(len(plugin.params)):
        return false
    else:
        withLock(plugin.controls_mutex):
            var param = plugin.params[index]
            value[] = if plugin.ui_param_data[index].has_changed:
                        case plugin.ui_param_data[index].kind:
                            of pkFloat:
                                plugin.ui_param_data[index].f_raw_value
                            of pkInt:
                                float64(plugin.ui_param_data[index].i_raw_value)
                            of pkBool:
                                bool_to_float(plugin.ui_param_data[index].b_value)
                    else:
                        case plugin.dsp_param_data[index].kind:
                            of pkFloat:
                                plugin.dsp_param_data[index].f_raw_value
                            of pkInt:
                                float64(plugin.dsp_param_data[index].i_raw_value)
                            of pkBool:
                                bool_to_float(plugin.dsp_param_data[index].b_value)
        return true

template str_to_char_arr_ptr*(write: ptr UncheckedArray[char], read: string, write_size: uint32): void =
    let min_len = min(write_size, uint32(read.len))
    var i: uint32 = 0
    while i < min_len:
        write[i] = read[i]
        i += 1
    write[i] = '\0'

proc offbeat_params_value_to_text*(clap_plugin: ptr ClapPlugin, id: ClapID, value: float64, display: ptr UncheckedArray[char], size: uint32): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    var index = uint32(id)
    if index >= uint32(len(plugin.params)):
        return false
    else:
        var param = plugin.params[index]
        case param.kind:
            of pkFloat:
                if param.f_as_string != nil:
                    str_to_char_arr_ptr(display, param.f_as_string(value), size)
                else:
                    str_to_char_arr_ptr(display, value.formatBiggestFloat(ffDecimal, 6), size)
            of pkInt:
                if param.i_as_string != nil:
                    str_to_char_arr_ptr(display, param.i_as_string(int64(value)), size)
                else:
                    str_to_char_arr_ptr(display, value.formatBiggestFloat(ffDecimal, 0), size)
            of pkBool:
                if value > 0.5:
                    str_to_char_arr_ptr(display, param.true_str, size)
                else:
                    str_to_char_arr_ptr(display, param.false_str, size)
        return true

proc simple_str_bool*(s: string): bool =
    var c = s[0]
    case c:
        of 'y':
            return true
        of 't':
            return true
        of '1':
            return true
        of 'n':
            return false
        of 'f':
            return false
        of '0':
            return false
        else:
            return false

proc offbeat_params_text_to_value*(clap_plugin: ptr ClapPlugin, id: ClapID, display: cstring, value: ptr float64): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    var index = uint32(id)
    if index >= uint32(len(plugin.params)):
        return false
    else:
        var param = plugin.params[index]
        case param.kind:
            of pkFloat:
                if param.f_as_value != nil:
                    value[] = param.f_as_value($display)
                else:
                    value[] = float64(parseFloat($display))
            of pkInt:
                if param.i_as_value != nil:
                    value[] = float64(param.i_as_value($display))
                else:
                    value[] = float64(parseFloat($display))
            of pkBool:
                value[] = bool_to_float(simple_str_bool($display))
        return true

proc offbeat_params_flush*(clap_plugin: ptr ClapPlugin, input: ptr ClapInputEvents, output: ptr ClapOutputEvents): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    let event_count = input.size(input)
    sync_ui_to_dsp(plugin, output)
    for i in 0 ..< event_count:
        offbeat_process_event(plugin, input.get(input, i))

let s_offbeat_params * = ClapPluginParams(
        count         : offbeat_params_count,
        get_info      : offbeat_params_get_info,
        get_value     : offbeat_params_get_value,
        value_to_text : offbeat_params_value_to_text,
        text_to_value : offbeat_params_text_to_value,
        flush         : offbeat_params_flush
    )