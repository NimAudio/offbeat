import clap
import types


proc offbeat_audio_ports_count*(clap_plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 1

proc offbeat_audio_ports_get*(clap_plugin: ptr ClapPlugin,
                            index: uint32,
                            is_input: bool,
                            info: ptr ClapAudioPortInfo): bool {.cdecl.} =
    if index > 0:
        return false
    info.id = 0.ClapID
    # echo(info.name)
    info.channel_count = 2
    info.flags = {capfIS_MAIN}
    info.port_type = CLAP_PORT_STEREO
    info.in_place_pair = CLAP_INVALID_ID
    return true

let s_offbeat_audio_ports* = ClapPluginAudioPorts(count: offbeat_audio_ports_count, get: offbeat_audio_ports_get)

proc offbeat_note_ports_count*(clap_plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 0

proc offbeat_note_ports_get*(clap_plugin: ptr ClapPlugin,
                            index: uint32,
                            is_input: bool,
                            info: ptr ClapNotePortInfo): bool {.cdecl.} =
    return false

let s_offbeat_note_ports* = ClapPluginNotePorts(count: offbeat_note_ports_count, get: offbeat_note_ports_get)

proc offbeat_latency_get*(clap_plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    return cast[ptr Plugin](clap_plugin.plugin_data).latency

let s_offbeat_latency* = ClapPluginLatency(get: offbeat_latency_get)