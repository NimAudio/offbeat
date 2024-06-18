import clap
import std/[locks, tables]


type
    AutoModuSupport* = object
        base        *: bool
        per_note_id *: bool
        per_key     *: bool
        per_channel *: bool
        per_port    *: bool

converter auto_modu_support_from_bool*(b: bool): AutoModuSupport =
    return AutoModuSupport(
        base        : b,
        per_note_id : false,
        per_key     : false,
        per_channel : false,
        per_port    : false
    )

type
    ParameterKind* = enum
        pkFloat,
        pkInt,
        pkBool

    SmoothMode* = enum
        smNone,
        smFilter,
        smLerp

    Parameter* = ref object
        name *: string
        path *: string
        case kind *: ParameterKind:
            of pkFloat:
                f_min           *: float64
                f_max           *: float64
                f_default       *: float64
                f_as_value      *: proc (str: string): float64
                f_as_string     *: proc (val: float64): string
                f_remap         *: proc (val: float64): float64
            of pkInt: # maybe add enum kind eventually
                i_min       *: int64
                i_max       *: int64
                i_default   *: int64
                i_as_value  *: proc (str: string): int64
                i_as_string *: proc (val: int64): string
                i_remap     *: proc (val: int64): int64
            of pkBool:
                b_default   *: bool
                true_str    *: string
                false_str   *: string
                b_map       *: proc (val: bool): float64
        smooth_cutoff *: float64 = 10
        smooth_ms     *: float64 = 50
        smooth_mode   *: SmoothMode = smLerp
        calculate     *: proc (plugin: ptr Plugin, val: float64, id: int): void = nil
        id            *: uint32
        is_periodic   *: bool
        is_hidden     *: bool
        is_readonly   *: bool
        is_bypass     *: bool
        is_enum       *: bool
        req_process   *: bool
        automation    *: AutoModuSupport = true
        modulation    *: AutoModuSupport = false

    ParameterValue* = ref object
        #TODO add modulation arrays or whatever
        #TODO - probably doesn't need to be saved/loaded
        #TODO - does need to be handled in event processing
        param *: Parameter
        case kind *: ParameterKind:
            of pkFloat:
                f_raw_value *: float64
            of pkInt:
                i_raw_value *: int64
                i_value     *: int64
            of pkBool:
                b_value     *: bool
        has_changed *: bool
        next_value            *: float64
        value                 *: float64
        smooth_coef           *: float64
        smooth_samples        *: uint64
        smooth_step           *: float64
        smooth_sample_counter *: uint64

    PluginDesc* = object
        id          *: string
        name        *: string
        vendor      *: string
        url         *: string
        manual_url  *: string
        support_url *: string
        version     *: string
        description *: string
        features    *: seq[string]

    PluginVersion* = array[4, uint32]

    Plugin* = object
        # clap pointers
        clap_plugin       *: ptr ClapPlugin
        host              *: ptr ClapHost
        host_latency      *: ptr ClapHostLatency
        host_log          *: ptr ClapHostLog
        host_thread_check *: ptr ClapHostThreadCheck
        host_state        *: ptr ClapHostState
        host_params       *: ptr ClapHostParams
        # managed data
        params          *: seq[Parameter]
        ui_param_data   *: seq[ParameterValue]
        dsp_param_data  *: seq[ParameterValue]
        smoothed_params *: seq[int] # indices into arrays
        # calc_cb_params  *: seq[int] # indices into arrays
        id_map          *: Table[uint32, int]
        name_map        *: Table[string, int]
        save_handlers   *: Table[uint32, proc (plugin: ptr Plugin, data: ptr UncheckedArray[byte], data_length: uint64, offset: uint64): void]
        controls_mutex  *: Lock
        # basics
        latency     *: uint32
        sample_rate *: float64
        desc        *: PluginDesc
        version     *: PluginVersion
        # your data
        # sorry it's a raw pointer, maybe i can change it to a generic without it affecting much of unrelated procs
        # use this for like, your wavetables, filter state variables, etc
        #
        # in the future, i would like to create a multi-process system,
        # in which it contains a seq of self contained processors,
        # each with their own state, start, stop, reset, and process procs, and whatever else
        data *: pointer
        cb_on_start_processing           *: proc (plugin: ptr Plugin): bool
        cb_on_stop_processing            *: proc (plugin: ptr Plugin): void
        cb_on_reset                      *: proc (plugin: ptr Plugin): void
        cb_process_sample                *: proc (plugin: ptr Plugin, in_left, in_right: float64, out_left, out_right: var float64, latency: uint32): void
        cb_pre_save                      *: proc (plugin: ptr Plugin): void
        cb_data_to_bytes                 *: proc (plugin: ptr Plugin): seq[byte]
        cb_data_byte_count               *: proc (plugin: ptr Plugin): int = proc (plugin: ptr Plugin): int = return 0
        cb_data_from_bytes               *: proc (plugin: ptr Plugin, data: seq[byte]): void
        cb_data_version_check            *: proc (stored, running: PluginVersion): int
        cb_data_create_plugin_of_version *: proc (version: PluginVersion): ptr Plugin
        cb_data_upgrade_patch            *: seq[tuple[version: PluginVersion, upgrade: proc (plugin: ptr Plugin): ptr Plugin]]
        cb_post_load                     *: proc (plugin: ptr Plugin): void

    StateTree* = object
        key         *: uint32
        data_length *: uint64 # do not include size of tree
        data        *: ptr UncheckedArray[byte]
        tree        *: seq[StateTree]