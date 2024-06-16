import src/offbeat
import std/[math, strutils]

# proc db_af*(db: float64): float64 =
#     result = pow(10, 0.05 * db)

# proc af_db*(af: float64): float64 =
#     result = 20 * log10(af)

var p_gain * = newFloatParameter(
    "Level",
    -48,
    24,
    0,
    0'u32,
    smLerp,
    100,
    proc (s: string): float64 = float64(parseFloat(s.strip().split(" ")[0])),
    proc (x: float64): string = x.formatBiggestFloat(ffDecimal, 6) & " db",
    db_af
)
var p_flip * = newFloatParameter(
    "Flip",
    0,
    1,
    0,
    1'u32,
    smLerp,
    100
)
var p_rotate * = newFloatParameter(
    "Rotate",
    -1,
    1,
    0,
    2'u32,
    smLerp,
    100,
    remap = proc (x: float64): float64 = PI * x
)

var params * = @[p_gain, p_flip, p_rotate]
var id_map * = params.id_table()
var name_map * = params.name_table()

proc lerp*(x, y, mix: float32): float32 =
    result = (y - x) * mix + x

proc process*(plugin: ptr Plugin, in_left, in_right: float64, out_left, out_right: var float64, latency: uint32): void =
    var scaled_l = plugin.dsp_param_data[0].f_value * in_left
    var scaled_r = plugin.dsp_param_data[0].f_value * in_right
    var flipped_l = lerp(scaled_l, scaled_r, plugin.dsp_param_data[1].f_value)
    var flipped_r = lerp(scaled_r, scaled_l, plugin.dsp_param_data[1].f_value)
    let a_cos: float32 = cos(plugin.dsp_param_data[2].f_value)
    let a_sin: float32 = sin(plugin.dsp_param_data[2].f_value)
    out_left = flipped_l * a_cos + flipped_r * a_sin
    out_right = flipped_r * a_cos - flipped_l * a_sin

let features*: cstringArray = allocCStringArray([CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
                                                CLAP_PLUGIN_FEATURE_UTILITY,
                                                CLAP_PLUGIN_FEATURE_STEREO])

let clap_desc* = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major    : CLAP_VERSION_MAJOR,
            minor    : CLAP_VERSION_MINOR,
            revision : CLAP_VERSION_REVISION),
        id          : "com.offbeat.example2",
        name        : "offbeat plugin framework example plugin",
        vendor      : "offbeat",
        url         : "https://www.github.com/morganholly/offbeat",
        manual_url  : "https://www.github.com/morganholly/offbeat",
        support_url : "https://www.github.com/morganholly/offbeat",
        version     : "0.2",
        description : "example effect plugin",
        features    : features)

offbeat_desc      = clap_desc
offbeat_params    = params
offbeat_id_map    = id_map
offbeat_name_map  = name_map
cb_process_sample = process
