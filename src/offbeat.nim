import clap
import std/[locks, math, tables]
import offbeat/[types, ports, state, process, params, param_helpers, utils]
# import jsony
export clap
export types, ports, state, process, params, param_helpers, utils


# entry point

proc convert_plugin_descriptor*(desc: PluginDesc): ClapPluginDescriptor =
    result = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major:    CLAP_VERSION_MAJOR,
            minor:    CLAP_VERSION_MINOR,
            revision: CLAP_VERSION_REVISION),
        id: cstring(desc.id),
        name: cstring(desc.name),
        vendor: cstring(desc.vendor),
        url: cstring(desc.url),
        manual_url: cstring(desc.manual_url),
        support_url: cstring(desc.support_url),
        version: cstring(desc.version),
        description: cstring(desc.description),
        features: allocCStringArray(desc.features))

proc offbeat_get_extension*(clap_plugin: ptr ClapPlugin, id: cstring): pointer {.cdecl.} =
    case id:
        of CLAP_EXT_LATENCY:
            return addr s_offbeat_latency
        of CLAP_EXT_AUDIO_PORTS:
            return addr s_offbeat_audio_ports
        of CLAP_EXT_NOTE_PORTS:
            return addr s_offbeat_note_ports
        of CLAP_EXT_STATE:
            return addr s_offbeat_state
        of CLAP_EXT_PARAMS:
            return addr s_offbeat_params


# var offbeat_desc   *: PluginDesc
var offbeat_desc      *: ClapPluginDescriptor
var offbeat_params    *: seq[Parameter]
var offbeat_id_map    *: Table[uint32, int]
var offbeat_name_map  *: Table[string, int]
var cb_process_sample *: proc (plugin: ptr Plugin, in_left, in_right: float64, out_left, out_right: var float64, latency: uint32): void

var offbeat_user_data *: pointer = nil

var cb_on_start_processing *: proc (plugin: ptr Plugin): bool = nil
var cb_on_stop_processing  *: proc (plugin: ptr Plugin): void = nil
var cb_on_reset            *: proc (plugin: ptr Plugin): void = nil
var cb_pre_save            *: proc (plugin: ptr Plugin): void = nil
var cb_data_to_bytes       *: proc (plugin: ptr Plugin): seq[byte] = nil
var cb_data_byte_count     *: proc (plugin: ptr Plugin): int = proc (plugin: ptr Plugin): int = return 0
var cb_data_from_bytes     *: proc (plugin: ptr Plugin, data: seq[byte]): void = nil
var cb_post_load           *: proc (plugin: ptr Plugin): void = nil

var cb_init           *: proc (plugin: ptr Plugin): void = nil
var cb_destroy        *: proc (plugin: ptr Plugin): void = nil
var cb_activate       *: proc (plugin: ptr Plugin, sample_rate: float64, min_frames_count: uint32, max_frames_count: uint32): void = nil
var cb_deactivate     *: proc (plugin: ptr Plugin): void = nil
var cb_on_main_thread *: proc (plugin: ptr Plugin): void = nil
var cb_create         *: proc (plugin: ptr Plugin, host: ptr ClapHost): void = nil

# let s_offbeat_desc* = convert_plugin_descriptor(offbeat_desc)

proc offbeat_init*(clap_plugin: ptr ClapPlugin): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    plugin.host_log          = cast[ptr ClapHostLog         ](plugin.host.get_extension(plugin.host, CLAP_EXT_LOG          ))
    plugin.host_thread_check = cast[ptr ClapHostThreadCheck ](plugin.host.get_extension(plugin.host, CLAP_EXT_THREAD_CHECK ))
    plugin.host_latency      = cast[ptr ClapHostLatency     ](plugin.host.get_extension(plugin.host, CLAP_EXT_LATENCY      ))
    plugin.host_state        = cast[ptr ClapHostState       ](plugin.host.get_extension(plugin.host, CLAP_EXT_STATE        ))
    plugin.host_params       = cast[ptr ClapHostParams      ](plugin.host.get_extension(plugin.host, CLAP_EXT_PARAMS       ))
    for i in 0 ..< len(plugin.params):
        var p = plugin.params[i]
        case p.kind:
            of pkFloat:
                var remapped = if p.f_remap != nil:
                                p.f_remap(p.f_default)
                            else:
                                p.f_default
                plugin.dsp_param_data[i].f_raw_value = p.f_default
                plugin.dsp_param_data[i].f_value     = remapped
                plugin.ui_param_data[i].f_raw_value = p.f_default
                plugin.ui_param_data[i].f_value     = remapped
                if p.f_calculate != nil:
                    p.f_calculate(plugin, remapped, i)
            of pkInt:
                var remapped = if p.i_remap != nil:
                                p.i_remap(p.i_default)
                            else:
                                p.i_default
                plugin.dsp_param_data[i].i_raw_value = p.i_default
                plugin.dsp_param_data[i].i_value     = remapped
                plugin.ui_param_data[i].i_raw_value = p.i_default
                plugin.ui_param_data[i].i_value     = remapped
            of pkBool:
                plugin.dsp_param_data[i].b_value = plugin.params[i].b_default
                plugin.ui_param_data[i].b_value = plugin.params[i].b_default
    initLock(plugin.controls_mutex)
    if cb_init != nil:
        cb_init(plugin)
    return true

proc offbeat_destroy*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if cb_destroy != nil:
        cb_destroy(plugin)
    dealloc(plugin)

proc offbeat_activate*(clap_plugin: ptr ClapPlugin,
                        sample_rate: float64,
                        min_frames_count: uint32,
                        max_frames_count: uint32): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    withLock(plugin.controls_mutex):
        plugin.sample_rate = sample_rate
        plugin.smoothed_params = @[]
        for i in 0 ..< len(plugin.params):
            if plugin.params[i].kind == pkFloat:
                case plugin.params[i].f_smooth_mode:
                    of smFilter:
                        if plugin.params[i].f_smooth_cutoff > 0:
                            var coef = simple_lp_coef(plugin.params[i].f_smooth_cutoff, sample_rate)
                            plugin.dsp_param_data[i].f_smooth_coef = coef
                            plugin.ui_param_data[i].f_smooth_coef = coef
                            plugin.smoothed_params.add(i)
                        else:
                            plugin.params[i].f_smooth_mode = smNone
                    of smLerp:
                        if plugin.params[i].f_smooth_ms > 0:
                            var samples = uint64(floor(plugin.params[i].f_smooth_ms * sample_rate * 0.001))
                            plugin.dsp_param_data[i].f_smooth_samples = samples
                            plugin.ui_param_data[i].f_smooth_samples = samples
                            plugin.smoothed_params.add(i)
                        else:
                            plugin.params[i].f_smooth_mode = smNone
                    of smNone:
                        discard
        # plugin.calc_cb_params = @[]
        # for i in 0 ..< len(plugin.params):
        #     if plugin.params[i].kind == pkFloat: # maybe int and bool should get calculate callbacks, this should handle that better than doing it in the 
        #         if plugin.params[i].f_calculate != nil
        if cb_activate != nil:
            cb_activate(plugin, sample_rate, min_frames_count, max_frames_count)
    return true

proc offbeat_deactivate*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if cb_deactivate != nil:
        cb_deactivate(plugin)

proc offbeat_on_main_thread*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if cb_on_main_thread != nil:
        cb_on_main_thread(plugin)

proc offbeat_create*(host: ptr ClapHost): ptr ClapPlugin {.cdecl.} =
    var plugin = cast[ptr Plugin](alloc0(Plugin.sizeof))
    plugin.host = host
    plugin.clap_plugin = cast[ptr ClapPlugin](alloc0(ClapPlugin.sizeof)) # remove if changed to not a pointer
    plugin.clap_plugin.desc             = addr offbeat_desc
    plugin.clap_plugin.plugin_data      = plugin
    plugin.clap_plugin.init             = offbeat_init
    plugin.clap_plugin.destroy          = offbeat_destroy
    plugin.clap_plugin.activate         = offbeat_activate
    plugin.clap_plugin.deactivate       = offbeat_deactivate
    plugin.clap_plugin.start_processing = offbeat_start_processing
    plugin.clap_plugin.stop_processing  = offbeat_stop_processing
    plugin.clap_plugin.reset            = offbeat_reset
    plugin.clap_plugin.process          = offbeat_process
    plugin.clap_plugin.get_extension    = offbeat_get_extension
    plugin.clap_plugin.on_main_thread   = offbeat_on_main_thread
    plugin.params   = offbeat_params
    plugin.id_map   = offbeat_id_map
    plugin.name_map = offbeat_name_map
    plugin.save_handlers[0'u32] = offbeat_load_handle_tree
    plugin.save_handlers[1'u32] = offbeat_load_handle_parameter
    plugin.dsp_param_data = @[]
    plugin.ui_param_data  = @[]
    for i in 0 ..< len(plugin.params):
        plugin.dsp_param_data.add(ParameterValue(
            param: plugin.params[i],
            kind:  plugin.params[i].kind
        ))
        plugin.ui_param_data.add(ParameterValue(
            param: plugin.params[i],
            kind:  plugin.params[i].kind
        ))
    plugin.data                   = offbeat_user_data
    plugin.cb_on_start_processing = cb_on_start_processing
    plugin.cb_on_stop_processing  = cb_on_stop_processing
    plugin.cb_on_reset            = cb_on_reset
    plugin.cb_process_sample      = cb_process_sample
    plugin.cb_pre_save            = cb_pre_save
    plugin.cb_data_to_bytes       = cb_data_to_bytes
    plugin.cb_data_byte_count     = cb_data_byte_count
    plugin.cb_data_from_bytes     = cb_data_from_bytes
    plugin.cb_post_load           = cb_post_load
    if cb_create != nil:
        cb_create(plugin, host)
    return plugin.clap_plugin
    # return addr plugin.clap_plugin # if it wasn't a pointer

type
    ClapDescCreate* = object
        desc *: ptr ClapPluginDescriptor
        create *: proc (host: ptr ClapHost): ptr ClapPlugin {.cdecl.}

const plugin_count*: uint32 = 1

let s_plugins: array[plugin_count, ClapDescCreate] = [
    ClapDescCreate(desc: addr offbeat_desc, create: offbeat_create)
]

proc plugin_factory_get_plugin_count*(factory: ptr ClapPluginFactory): uint32 {.cdecl.} =
    return plugin_count

proc plugin_factory_get_plugin_descriptor*(factory: ptr ClapPluginFactory, index: uint32): ptr ClapPluginDescriptor {.cdecl.} =
    return s_plugins[index].desc

proc plugin_factory_create_plugin*(factory: ptr ClapPluginFactory,
                                    host: ptr ClapHost,
                                    plugin_id: cstring): ptr ClapPlugin {.cdecl.} =
    if host.clap_version.major < 1:
        return nil

    for i in 0 ..< plugin_count:
        if plugin_id == s_plugins[i].desc.id:
            return s_plugins[i].create(host)

    return nil

let s_plugin_factory* = ClapPluginFactory(
    get_plugin_count: plugin_factory_get_plugin_count,
    get_plugin_descriptor: plugin_factory_get_plugin_descriptor,
    create_plugin: plugin_factory_create_plugin)

proc entry_init*(plugin_path: cstring): bool {.cdecl.} =
    return true

proc entry_deinit*(): void {.cdecl.} =
    discard

var g_entry_init_counter = 0

proc entry_init_guard*(plugin_path: cstring): bool {.cdecl.} =
    # add mutex lock
    g_entry_init_counter += 1
    var succeed = true
    if g_entry_init_counter == 1:
        succeed = entry_init(plugin_path)
        if not succeed:
            g_entry_init_counter = 0
    # mutex unlock
    return succeed

proc entry_deinit_guard*(): void {.cdecl.} =
    # add mutex lock
    g_entry_init_counter -= 1
    if g_entry_init_counter == 0:
        entry_deinit()
    # mutex unlock

proc entry_get_factory*(factory_id: cstring): ptr ClapPluginFactory {.cdecl.} =
    if g_entry_init_counter <= 0:
        return nil
    if factory_id == CLAP_PLUGIN_FACTORY_ID:
        return addr s_plugin_factory
    return nil

let clap_entry* {.global, exportc: "clap_entry", dynlib.} = ClapPluginEntry(
    clap_version: CLAP_VERSION_INIT,
    init: entry_init_guard,
    deinit: entry_deinit_guard,
    get_factory: entry_get_factory
)
