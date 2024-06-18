import src/offbeat
import std/[math, strutils]

var p_level * = newFloatParameter(
    "Level",
    -90,
    30,
    0,
    0'u32,
    smLerp,
    500,
    proc (s: string): float64 = float64(parseFloat(s.strip().split(" ")[0])),
    proc (x: float64): string = x.formatBiggestFloat(ffDecimal, 6) & " db",
    db_af
)

type UserData* = object
    cutoff_coef    *: float64
    cutoff_last    *: float64
    last_lp_dist_1 *: float64
    last_lp_dist_2 *: float64
    last_lp_orig_1 *: float64
    last_lp_orig_2 *: float64

var userdata = cast[ptr UserData](alloc0(UserData.sizeof))
cb_destroy = proc (plugin: ptr Plugin): void = dealloc(userdata)

proc cutoff_remap(x: float64): float64 = lerp(30, 5000, x * x * x)
proc cutoff_remap_inv(x: float64): float64 = cbrt((x - 30) / 4970)

var p_cutoff * = newFloatParameter(
    "Cutoff",
    0,
    1,
    0.5,
    1'u32,
    smLerp,
    100,
    proc (s: string): float64 = cutoff_remap_inv(float64(parseFloat(s.strip().split(" ")[0]))),
    proc (x: float64): string = cutoff_remap(x).formatBiggestFloat(ffDecimal, 6) & " hz",
    remap = cutoff_remap,
    calculate = proc (plugin: ptr Plugin, val: float64, id: int): void =
        # stdout.write("c")
        cast[ptr UserData](plugin.data).cutoff_coef = onepole_lp_coef(val, plugin.sample_rate)
)

var p_amount * = newFloatParameter(
    "Amount",
    -24,
    12,
    0,
    2'u32,
    smLerp,
    100,
    proc (s: string): float64 = float64(parseFloat(s.strip().split(" ")[0])),
    proc (x: float64): string = x.formatBiggestFloat(ffDecimal, 6) & " db",
    db_af
)

var p_polarity * = newBoolParameter(
    "Polarity",
    false,
    3'u32,
    smLerp,
    100,
    "Inverse",
    "Normal"
)

var params * = @[p_level, p_cutoff, p_amount, p_polarity]
var id_map * = params.id_table()
var name_map * = params.name_table()

let one_over_1_5: float64 = 0.6666666666666666666666666666666666666666666666666666666666666666
let c3softclip_constant: float64 = 0.3849001794597505096727658536679716370984011675134179173457348843
# ((1.0 / sqrt3) - (1.0 / (3.0 * sqrt3)));
let c3softclip_invconstant: float64 = 2.5980762113533159402911695122588085504142078807155709420837104691
# (1.0 / ((1.0 / sqrt3) - (1.0 / (3.0 * sqrt3))));

proc c3cheapsat_internal(x: float64): float64 =
    return x - (x * x * x)

proc c3cheapsat(y: float64): float64 =
    result = y * one_over_1_5
    if (result > 1.5):
        result = 1.5
    elif (result < -1.5):
        result = -1.5
    result *= c3softclip_constant
    result = c3cheapsat_internal(result)
    result *= 1.5
    result = c3cheapsat_internal(result)
    result *= c3softclip_invconstant

proc c3cheapsat_l(x: float64, level: float64, invlevel: float64): float64 =
    # external inv_level allows for caching the result or using a fixed level
    return c3cheapsat(x * invlevel) * level

let db_m30_sq = db_af(-30) * db_af(-30)

proc process_channel(plugin: ptr Plugin, input: float64, output: var float64): void =
    var inv_scale = 1 / plugin.dsp_param_data[0].value
    var in_scaled = input * inv_scale
    var user_data = cast[ptr UserData](plugin.data)
    var lp = onepole_lp(user_data.cutoff_last, user_data.cutoff_coef, in_scaled)
    var hp = in_scaled - lp
    var dist_level = hp * 2
    dist_level *= dist_level
    dist_level += db_m30_sq
    dist_level = sqrt(dist_level)
    var dist = c3cheapsat_l(in_scaled, dist_level, 1 / dist_level)
    # output = dist * plugin.dsp_param_data[0].f_value
    var dist_lp2 = onepole_lp(user_data.last_lp_dist_1, userdata.cutoff_coef, dist)
    dist_lp2 = onepole_lp(user_data.last_lp_dist_2, userdata.cutoff_coef, dist_lp2)
    # output = dist_lp2 * plugin.dsp_param_data[0].f_value
    var orig_lp2 = onepole_lp(user_data.last_lp_orig_1, userdata.cutoff_coef, in_scaled)
    orig_lp2 = onepole_lp(user_data.last_lp_orig_2, userdata.cutoff_coef, orig_lp2)
    output = ((orig_lp2 - dist_lp2) * plugin.dsp_param_data[2].value + in_scaled) * plugin.dsp_param_data[0].value
    output = (lerp(orig_lp2 - dist_lp2, dist_lp2 - orig_lp2, plugin.dsp_param_data[3].value) * plugin.dsp_param_data[2].value + in_scaled) * plugin.dsp_param_data[0].value

proc process*(plugin: ptr Plugin, in_left, in_right: float64, out_left, out_right: var float64, latency: uint32): void =
    process_channel(plugin, in_left, out_left)
    process_channel(plugin, in_right, out_right)

let features*: cstringArray = allocCStringArray([CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
                                                CLAP_PLUGIN_FEATURE_DISTORTION,
                                                CLAP_PLUGIN_FEATURE_STEREO])

let clap_desc* = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major    : CLAP_VERSION_MAJOR,
            minor    : CLAP_VERSION_MINOR,
            revision : CLAP_VERSION_REVISION),
        id          : "com.offbeat.example3",
        name        : "offbeat bass enhancer",
        vendor      : "offbeat",
        url         : "https://www.github.com/morganholly/offbeat",
        manual_url  : "https://www.github.com/morganholly/offbeat",
        support_url : "https://www.github.com/morganholly/offbeat",
        version     : "0.1",
        description : "actually useful plugin to test clap wrappers, made with offbeat plugin framework",
        features    : features)

offbeat_desc      = clap_desc
offbeat_params    = params
offbeat_id_map    = id_map
offbeat_name_map  = name_map
offbeat_user_data = userdata
cb_process_sample = process
