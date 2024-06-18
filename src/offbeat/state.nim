import clap
import types
import std/[locks, bitops, tables, algorithm]


proc cond_set*(c_to, c_from: var ParameterValue): void =
    if c_from.has_changed:
        c_from.has_changed = false
        c_to.has_changed = false
        case c_from.kind:
            of pkFloat:
                c_to.f_raw_value = c_from.f_raw_value
                c_to.value = c_from.value
            of pkInt:
                c_to.i_raw_value = c_from.i_raw_value
                c_to.i_value = c_from.i_value
            of pkBool:
                c_to.b_value = c_from.b_value

proc cond_set_with_event*(c_to, c_from: var ParameterValue, id: ClapID, output: ptr ClapOutputEvents): void =
    if c_from.has_changed:
        c_from.has_changed = false
        c_to.has_changed = false
        var value: float64 = 0.0
        case c_from.kind:
            of pkFloat:
                c_to.f_raw_value = c_from.f_raw_value
                c_to.value = c_from.value
                value = c_from.f_raw_value
            of pkInt:
                c_to.i_raw_value = c_from.i_raw_value
                c_to.i_value = c_from.i_value
                value = float64(c_from.i_raw_value)
            of pkBool:
                c_to.b_value = c_from.b_value
                value = if c_from.b_value:
                            1.0
                        else:
                            0.0
        # c_to = c_from

        var event: ClapEventUnion
        event.kindParamValMod = ClapEventParamValue(
            header     : ClapEventHeader(
                size       : uint32(ClapEventParamValue.sizeof),
                time       : 0,
                space_id   : 0,
                event_type : cetPARAM_VALUE,
                flags      : {}
            ),
            param_id   : id,
            cookie     : nil,
            note_id    : -1,
            port_index : -1,
            channel    : -1,
            key        : -1,
            val_amt    : value
        )

        discard output.try_push(output, addr event)

proc sync_ui_to_dsp*(plugin: ptr Plugin, output: ptr ClapOutputEvents): void =
    withLock(plugin.controls_mutex):
        for i in 0 ..< len(plugin.ui_param_data):
            cond_set_with_event(plugin.dsp_param_data[i],  plugin.ui_param_data[i],  ClapID(i), output)

proc sync_dsp_to_ui*(plugin: ptr Plugin): void =
    withLock(plugin.controls_mutex):
        for i in 0 ..< len(plugin.ui_param_data):
            cond_set(plugin.ui_param_data[i],  plugin.dsp_param_data[i])

proc get_byte_at*[T: SomeInteger](val: T, position: int): byte =
    # result = cast[byte]((val shr (position shl 3)) and 0b1111_1111)
    result = cast[byte](val.bitsliced(position ..< position + 8))

template `+`*[T](p: ptr T, off: int): ptr T =
    cast[ptr type(p[])](cast[ByteAddress](p) +% off * sizeof(p[]))

template `+`*[T](p: ptr T, off: uint): ptr T =
    cast[ptr type(p[])](cast[uint](p) + off * uint(sizeof(p[])))

template `+`*(p: pointer, off: uint): pointer =
    cast[pointer](cast[uint](p) + off)

proc `[]=`*[T](p: ptr[T], i: int, x: T) =
    (p + i)[] = x

proc `[]=`*(p: ptr[byte], i: int, x: byte) =
    (p + i)[] = x

# proc `[]=`[T](p: ptr[byte]; i: var uint; x: T) =
#     for j in 0 ..< (T.sizeof):
#         i += 1
#         p[i] = get_byte_at[T](x, uint8(i))

proc `[]=`*[T](p: ptr[byte], i: int, x: T) =
    for j in 0 ..< (T.sizeof):
        p[int(j) + i] = get_byte_at[T](x, int(i))

proc `[]`*[T](p: ptr[T], i: int): T =
    result = (p + i)[]

proc read_as*[T](p: ptr[byte]): T =
    var temp: uint64
    for j in 0 ..< (T.sizeof):
        temp.setMask((p + j)[] shl (j * 8))
    result = cast[T](temp)

proc read_as*[T](data: ptr UncheckedArray[byte], offset: uint = 0): T =
    assert T.sizeof <= 8
    # echo(T.sizeof)
    var temp: uint64 = 0
    for i in 0 ..< uint(T.sizeof):
        # stdout.write("read: ")
        # stdout.write(cast[uint64](data))
        # stdout.write(" + ")
        # stdout.write(i + offset)
        # stdout.write(" byte is ")
        # stdout.write(cast[uint64](data[i + offset]) shl (8 * i))
        # stdout.write(" accum is ")
        temp = temp or (cast[uint64](data[i + offset]) shl (8 * i))
        # stdout.write(temp)
        # stdout.write("\n")
    return cast[T](temp)

proc read_as_ptr*[T](data: ptr UncheckedArray[byte], offset: uint = 0): ptr T =
    var temp = alloc0(T.sizeof)
    copyMem(temp, data + offset, T.sizeof)
    result = cast[ptr T](temp)

proc read_as_walk*[T](data: ptr UncheckedArray[byte], offset: var uint64 = 0): T =
    result = read_as[T](data, offset)
    offset += uint64(T.sizeof)

proc write_as*[T](data: ptr UncheckedArray[byte], value: T, offset: var uint64 = 0): void =
    assert T.sizeof <= 8
    # echo(T.sizeof)
    for i in 0 ..< uint(T.sizeof):
        # stdout.write("write: ")
        # stdout.write(cast[uint64](data))
        # stdout.write(" + ")
        # stdout.write(i + offset)
        # stdout.write("\n")
        data[i + offset] = cast[byte]((cast[uint64](value) shr (8 * i)) and 0b1111_1111)
    # copyMem(data + offset, value, T.sizeof)

proc write_walk*[T](data: ptr UncheckedArray[byte], value: T, offset: var uint64 = 0): void =
    write_as[T](data, value, offset)
    offset += uint64(T.sizeof)

proc `->`*[T](i: var int, x: T) =
    i += int(x.sizeof)
proc `<-`*[T](i: var int, x: T) =
    i -= int(x.sizeof)

proc offbeat_state_save*(clap_plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    sync_dsp_to_ui(plugin)
    if plugin.cb_pre_save != nil:
        plugin.cb_pre_save(plugin)
    var visible_editable_param_count = 0
    for p in plugin.params:
        if (not p.is_hidden) and (not p.is_readonly):
            visible_editable_param_count += 1
    var data_bytes: seq[byte]
    if plugin.cb_data_to_bytes != nil:
        data_bytes = plugin.cb_data_to_bytes(plugin)
    var buf_size = uint32(visible_editable_param_count * (
                                Parameter.id.sizeof +
                                ParameterValue.has_changed.sizeof +
                                ParameterValue.f_raw_value.sizeof
                            ) + 4 + len(data_bytes)) #uint32 4, bool 1, float64 8
    var buffer: ptr[byte] = cast[ptr[byte]](alloc0(buf_size))
    var index = 0
    buffer[index] = buf_size
    index -> buf_size
    for p_i in 0 ..< len(plugin.params):
        var p = plugin.params[p_i]
        var v = plugin.ui_param_data[p_i]
        if (not p.is_hidden) and (not p.is_readonly):
            buffer[index] = p.id
            index -> p.id
            buffer[index] = cast[uint8](v.has_changed)
            index -> v.has_changed
            case v.kind:
                of pkFloat:
                    buffer[index] = cast[uint64](v.f_raw_value)
                    index -> v.f_raw_value
                of pkInt:
                    buffer[index] = v.i_raw_value
                    index -> v.i_raw_value
                of pkBool:
                    buffer[index] = cast[uint8](v.b_value)
                    index += int(ParameterValue.f_raw_value.sizeof)
    for data in data_bytes:
        buffer[index] = data
        index += 1
    var written_size = 0
    while written_size < int(buf_size):
        let status = stream.write(stream, buffer + written_size, uint64(int(buf_size) - written_size))
        if status > 0:
            written_size += status
        else:
            dealloc(buffer)
            return false
    dealloc(buffer)
    return true

proc offbeat_state_load*(clap_plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    withLock(plugin.controls_mutex):
        var buf_size: uint32 = 0
        if stream.read(stream, addr buf_size, uint64(uint32.sizeof)) > 0:
            var buffer: ptr[byte] = cast[ptr[byte]](alloc0(int(buf_size) - uint32.sizeof))
            var read_size = 0
            while read_size < int(buf_size):
                let status = stream.read(stream, buffer + read_size, uint64(int(buf_size) - read_size))
                if status >= 0:
                    read_size += status
                elif status == 0:
                    break
                else:
                    dealloc(buffer)
                    return false
            var data_byte_count = plugin.cb_data_byte_count(plugin)
            for b_i in countup(0, int(buf_size) - data_byte_count, (
                                Parameter.id.sizeof +
                                ParameterValue.has_changed.sizeof +
                                ParameterValue.f_raw_value.sizeof
                            )):
                var i_offset = 0
                var p_i = plugin.id_map[read_as[uint32](buffer + b_i)]
                var v = plugin.ui_param_data[p_i]
                var p = plugin.params[p_i]
                i_offset += uint32.sizeof
                v.has_changed = read_as[bool](buffer + b_i + i_offset)
                i_offset += bool.sizeof
                case v.kind:
                    of pkFloat:
                        v.f_raw_value = read_as[float64](buffer + b_i + i_offset)
                        v.value = if p.f_remap != nil:
                                                p.f_remap(v.f_raw_value)
                                            else:
                                                v.f_raw_value
                    of pkInt:
                        v.i_raw_value = read_as[int64](buffer + b_i + i_offset)
                    of pkBool:
                        v.b_value = read_as[bool](buffer + b_i + i_offset)
            var data_bytes: seq[byte]
            for i in int(buf_size) - data_byte_count ..< int(buf_size):
                data_bytes.add(read_as[byte](buffer + i))
            if plugin.cb_data_from_bytes != nil:
                plugin.cb_data_from_bytes(plugin, data_bytes)
            if plugin.cb_post_load != nil:
                plugin.cb_post_load(plugin)
            dealloc(buffer)
            return true
        else:
            return false

## tree of memory blobs
##
## key uint32
## length uint64
## data
##
## key 0 is a container of other memory blobs, which can form a tree
## key 1 is a parameter, handled by the library
##
## other keys can be assigned per plugin, to allow for specialized handling, such as grouping data for a processor graph

proc offbeat_load_handle_tree*(plugin: ptr Plugin, data: ptr UncheckedArray[byte], data_length: uint64, offset: uint64): void =
    var counter: uint64 = offset
    while counter < data_length + offset:
        var key: uint32 = read_as_walk[uint32](data, counter)
        # echo("key: " & $key)
        var length: uint64 = read_as_walk[uint64](data, counter)
        # echo("len: " & $length)
        # echo($(counter + length) & " out of " & $(data_length + offset))
        if counter + length <= data_length + offset:
            # echo("counter: " & $counter)
            plugin.save_handlers[key](plugin, data, length, counter)
            counter += length

proc offbeat_load_main*(plugin: ptr Plugin, data: ptr UncheckedArray[byte], data_length: uint64): bool =
    var counter: uint64 = 0
    var load_plugin_ptr: ptr Plugin
    # var needs_upgrade: bool = false
    # if (plugin.cb_data_version_check != nil) and
    #     (plugin.cb_data_create_plugin_of_version != nil) and
    #     (len(plugin.cb_data_upgrade_patch) != 0):
    #         var version: array[4, uint32]
    #         version[0] = read_as_walk[uint32](data, counter)
    #         version[1] = read_as_walk[uint32](data, counter)
    #         version[2] = read_as_walk[uint32](data, counter)
    #         version[3] = read_as_walk[uint32](data, counter)
    #         if plugin.cb_data_version_check(version, plugin.version) < 0:
    #             needs_upgrade = true
    #             load_plugin_ptr = plugin.cb_data_create_plugin_of_version(version)
    #         else:
    #             load_plugin_ptr = plugin
    # else:
    counter += sizeof(uint32) * 4
    load_plugin_ptr = plugin
    # error correction
    var param_tree_key: uint32 = read_as_walk[uint32](data, counter)
    # echo("top level tree key 0: " & $param_tree_key)
    if param_tree_key != 0:
        # echo("top level tree does not exist")
        return false
    var param_tree_length: uint64 = read_as_walk[uint64](data, counter)
    # echo("top level tree len: " & $param_tree_length)
    # echo($(counter + param_tree_length) & " out of " & $data_length)
    if counter + param_tree_length <= data_length:
        # echo("param tree fits")
        offbeat_load_handle_tree(load_plugin_ptr, data, param_tree_length, counter)
        counter += param_tree_length
        # var user_data_key: uint32 = read_as_walk[uint32](data, counter)
        # var user_data_length: uint64 = read_as_walk[uint64](data, counter)
        # if counter + user_data_length < data_length:
        #     load_plugin_ptr.save_handlers[user_data_key](load_plugin_ptr, user_data_length, data + counter)
        #     counter += user_data_length
    else:
        # echo("param tree does not fit")
        return false
    # if needs_upgrade:
    #     var upgraded_plugin_A = cast[ptr Plugin](alloc0(Plugin.sizeof))
    #     var upgraded_plugin_B = cast[ptr Plugin](alloc0(Plugin.sizeof))
    #     copyMem(upgraded_plugin_A, load_plugin_ptr, Plugin.sizeof)
    #     for upgrade in load_plugin_ptr.cb_data_upgrade_patch:
    #         if load_plugin_ptr.cb_data_version_check(upgrade.version, load_plugin_ptr.version) > 0:
    #             upgraded_plugin_B = upgrade.upgrade(upgraded_plugin_A)
    #             swap(upgraded_plugin_A, upgraded_plugin_B)
    #             # ensure that each upgrade call can be done with an untouched copy as it writes the new copy
    #     # set to A, use A to write B, swap to return to A
    #     copyMem(plugin, upgraded_plugin_A, Plugin.sizeof)
    return true

proc offbeat_load_handle_parameter*(plugin: ptr Plugin, data: ptr UncheckedArray[byte], data_length: uint64, offset: uint64): void =
    var counter: uint64 = offset
    if data_length > uint64(uint8.sizeof + uint32.sizeof):
        var id: uint32 = read_as_walk[uint32](data, counter)
        # echo("id: " & $id)
        var kind: uint8 = read_as_walk[uint8](data, counter)
        # echo("kind: " & $kind)
        var p_index = plugin.id_map[id]
        var v = plugin.ui_param_data[p_index]
        var p = plugin.params[p_index]
        var contained_value: bool = false
        case kind:
            of 0'u8: # float, 8 bytes
                if data_length >= uint64(uint8.sizeof + uint32.sizeof + float64.sizeof):
                    contained_value = true
                    case p.kind:
                        of pkFloat: # save and plugin data match
                            v.f_raw_value = read_as[float64](data, counter)
                            # echo("f_raw: " & $v.f_raw_value)
                            v.value = if p.f_remap != nil:
                                            p.f_remap(v.f_raw_value)
                                        else:
                                            v.f_raw_value
                        of pkInt: # saved a float, loaded as int
                            v.i_raw_value = int64(read_as[float64](data, counter))
                            # echo("i_raw: " & $v.i_raw_value)
                            v.i_value = if p.i_remap != nil:
                                            p.i_remap(v.i_raw_value)
                                        else:
                                            v.i_raw_value
                        of pkBool: # saved a float, loaded as bool
                            v.b_value = read_as[float64](data, counter) >= 0.5
                            # echo("b_val: " & $v.b_value)
            of 1'u8: # int, 8 bytes
                if data_length >= uint64(uint8.sizeof + uint32.sizeof + int64.sizeof):
                    contained_value = true
                    case p.kind:
                        of pkFloat: # saved an int, loaded as float
                            v.f_raw_value = float64(read_as[int64](data, counter))
                            # echo("f_raw: " & $v.f_raw_value)
                            v.value = if p.f_remap != nil:
                                            p.f_remap(v.f_raw_value)
                                        else:
                                            v.f_raw_value
                        of pkInt: # save and plugin data match
                            v.i_raw_value = read_as[int64](data, counter)
                            # echo("i_raw: " & $v.i_raw_value)
                            v.i_value = if p.i_remap != nil:
                                            p.i_remap(v.i_raw_value)
                                        else:
                                            v.i_raw_value
                        of pkBool: # saved an int, loaded as bool
                            v.b_value = read_as[int64](data, counter) >= 1
                            # echo("b_val: " & $v.b_value)
            of 2'u8: # bool, 1 byte
                if data_length >= uint64(uint8.sizeof + uint32.sizeof + uint8.sizeof):
                    contained_value = true
                    case p.kind:
                        of pkBool: # save and plugin data match
                            v.b_value = countSetBits(read_as[uint8](data, counter)) > 4
                            # echo("b_val: " & $v.b_value)
                        else: # saved a bool, loaded as something else
                            # i'm not sure you can get anything meaningful here
                            contained_value = false
            else:
                discard
        if not contained_value:
            # echo("setting default")
            # the data block wasn't long enough to contain meaningful data, so just set defaults
            case p.kind:
                of pkFloat:
                    var remapped = if p.f_remap != nil:
                                    p.f_remap(p.f_default)
                                else:
                                    p.f_default
                    v.f_raw_value = p.f_default
                    v.value       = remapped
                of pkInt:
                    var remapped = if p.i_remap != nil:
                                    p.i_remap(p.i_default)
                                else:
                                    p.i_default
                    v.i_raw_value = p.i_default
                    v.i_value     = remapped
                of pkBool:
                    v.b_value = p.b_default
        v.has_changed = true

proc offbeat_save_total_lengths*(plugin: ptr Plugin, state: var StateTree): uint64 =
    if len(state.tree) != 0:
        var total: uint64 = 0
        for t in state.tree.mitems:
            total += offbeat_save_total_lengths(plugin, t)
        state.data_length += total
    return state.data_length

proc offbeat_save_flatten_state_tree*(plugin: ptr Plugin, state: StateTree): ptr UncheckedArray[byte] =
    # var counter: uint64 = 0
    # write_walk[uint32](result, state.key, counter)
    discard

proc offbeat_save_param_tree_size*(plugin: ptr Plugin): uint64 =
    result += uint64(uint32.sizeof)
    result += uint64(uint64.sizeof)
    for pv in plugin.ui_param_data:
        result += uint64(uint32.sizeof)
        result += uint64(uint64.sizeof)
        result += uint64(uint32.sizeof)
        case pv.kind:
            of pkFloat:
                result += uint64(uint8.sizeof)
                result += uint64(float64.sizeof)
            of pkInt:
                result += uint64(uint8.sizeof)
                result += uint64(int64.sizeof)
            of pkBool:
                result += uint64(uint8.sizeof)
                result += uint64(uint8.sizeof)

proc offbeat_save_param_tree*(plugin: ptr Plugin, data: ptr UncheckedArray[byte], offset: uint64): void =
    var counter: uint64 = offset
    write_walk[uint32](data, 0'u32, counter) # identify as tree blob
    var length_position = counter # copy of location of total size
    write_walk[uint64](data, 0'u64, counter) # length
    for pv in plugin.ui_param_data:
        write_walk[uint32](data, 1'u32, counter)
        var param_length_position = counter # copy of location of total size
        write_walk[uint64](data, 0'u64, counter) # param length
        var p = pv.param
        write_walk[uint32](data, p.id, counter)
        case pv.kind:
            of pkFloat:
                write_walk[uint8](data, 0'u8, counter)
                write_walk[float64](data, pv.f_raw_value, counter)
            of pkInt:
                write_walk[uint8](data, 1'u8, counter)
                write_walk[int64](data, pv.i_raw_value, counter)
            of pkBool:
                write_walk[uint8](data, 2'u8, counter)
                write_walk[uint8](data, if pv.b_value: 0b1111_1111 else: 0b0000_0000, counter)
        write_as[uint64](data, counter - param_length_position - uint64(uint64.sizeof), param_length_position)
    write_as[uint64](data, counter - length_position - uint64(uint64.sizeof), length_position)

proc offbeat_save_main*(plugin: ptr Plugin, data: ptr UncheckedArray[byte]): void =
    var counter: uint64 = 0
    write_walk[uint32](data, plugin.version[0], counter)
    write_walk[uint32](data, plugin.version[1], counter)
    write_walk[uint32](data, plugin.version[2], counter)
    write_walk[uint32](data, plugin.version[3], counter)
    offbeat_save_param_tree(plugin, data, counter)

proc offbeat_new_state_save*(clap_plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.} =
    # echo("\n\nstart save")
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    sync_dsp_to_ui(plugin)
    if plugin.cb_pre_save != nil:
        plugin.cb_pre_save(plugin)
    # for i in 0 ..< len(plugin.params):
    #     var p_d = plugin.dsp_param_data[i]
    #     var p_u = plugin.ui_param_data[i]
    #     stdout.write("id" & $plugin.params[i].id & ":")
    #     case plugin.params[i].kind:
    #         of pkFloat:
    #             stdout.write(" " & $p_d.f_value)
    #             stdout.write(" " & $p_d.f_raw_value)
    #             stdout.write(" " & $p_u.f_value)
    #             stdout.write(" " & $p_u.f_raw_value)
    #         of pkInt:
    #             stdout.write(" " & $p_d.i_value)
    #             stdout.write(" " & $p_d.i_raw_value)
    #             stdout.write(" " & $p_u.i_value)
    #             stdout.write(" " & $p_u.i_raw_value)
    #         of pkBool:
    #             stdout.write(" " & $p_d.b_value)
    #             stdout.write(" " & $p_u.b_value)
    #     stdout.write("\n")
    var buf_size = offbeat_save_param_tree_size(plugin) + 16 # version struct
    var buffer: ptr UncheckedArray[byte] = cast[ptr UncheckedArray[byte]](alloc0(buf_size))
    offbeat_save_main(plugin, buffer)
    # stdout.write("saving: ")
    # for i in 0 ..< buf_size:
    #     stdout.write(buffer[i])
    #     stdout.write(" ")
    # stdout.write("end\n")
    var written_size = 0'u64
    while written_size < buf_size:
        let status = stream.write(stream, cast[pointer](buffer) + written_size, buf_size - written_size)
        if status > 0:
            # echo("wrote " & $status & " bytes")
            written_size += uint64(status)
        else: # error
            # echo("write status: " & $status)
            dealloc(buffer)
            return false
    dealloc(buffer)
    return true

proc offbeat_new_state_load*(clap_plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.} =
    # echo("\n\nstart load")
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    var buf_size = offbeat_save_param_tree_size(plugin) + 16 # + version struct
    var buffer: ptr UncheckedArray[byte] = cast[ptr UncheckedArray[byte]](alloc0(buf_size))
    var read_size = 0'u64
    var status = 1
    var last_loop_reallocated = false
    while status >= 0:
        # echo("asking for " & $(buf_size - read_size) & " bytes, writing with offset " & $read_size)
        status = stream.read(stream, cast[pointer](buffer) + read_size, uint64(buf_size - read_size))
        if status == 0:
            break # finished reading
        elif status < 0:
            # echo("read status: " & $status)
            dealloc(buffer)
            return false # error
        else:
            # echo("read " & $status & " bytes")
            read_size += uint64(status)
            if read_size > buf_size:
                var new_size: uint64 = read_size
                if last_loop_reallocated: # try to avoid reallocating every time
                    new_size += 2048
                else:
                    new_size += 256
                buffer = cast[ptr UncheckedArray[byte]](realloc0(buffer, buf_size, new_size))
                buf_size = new_size
                last_loop_reallocated = true
    if read_size < offbeat_save_param_tree_size(plugin) + 16:
        # echo("read_size too small: " & $read_size)
        dealloc(buffer)
        return false
    # stdout.write("loading: ")
    # for i in 0 ..< read_size:
    #     stdout.write(buffer[i])
    #     stdout.write(" ")
    # stdout.write("end\n")
    var load_main_result = offbeat_load_main(plugin, buffer, read_size)
    # for i in 0 ..< len(plugin.params):
    #     var p_d = plugin.dsp_param_data[i]
    #     var p_u = plugin.ui_param_data[i]
    #     stdout.write("id" & $plugin.params[i].id & ":")
    #     case plugin.params[i].kind:
    #         of pkFloat:
    #             stdout.write(" " & $p_d.f_value)
    #             stdout.write(" " & $p_d.f_raw_value)
    #             stdout.write(" " & $p_u.f_value)
    #             stdout.write(" " & $p_u.f_raw_value)
    #         of pkInt:
    #             stdout.write(" " & $p_d.i_value)
    #             stdout.write(" " & $p_d.i_raw_value)
    #             stdout.write(" " & $p_u.i_value)
    #             stdout.write(" " & $p_u.i_raw_value)
    #         of pkBool:
    #             stdout.write(" " & $p_d.b_value)
    #             stdout.write(" " & $p_u.b_value)
    #     stdout.write("\n")
    dealloc(buffer)
    return load_main_result
    # for i in 0 ..< len(plugin.params):
    #     # doesn't consider the changed value, just sets all
    #     var p_d = plugin.dsp_param_data[i]
    #     var p_u = plugin.ui_param_data[i]
    #     case plugin.params[i].kind:
    #         of pkFloat:
    #             p_d.f_raw_value = p_u.f_raw_value
    #             p_d.f_value = p_u.f_value
    #         of pkInt:
    #             p_d.i_raw_value = p_u.i_raw_value
    #             p_d.i_value = p_u.i_value
    #         of pkBool:
    #             p_d.b_value = p_u.b_value

let s_offbeat_state* = ClapPluginState(save: offbeat_new_state_save, load: offbeat_new_state_load)