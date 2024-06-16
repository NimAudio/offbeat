import math


type
    Changed*[T] = object
        has_changed *: bool
        value       *: T
        # raw_value   *: T
        # on_changed  *: proc (raw, old: T): T

converter changed_from_value*[T](value: T): Changed[T] =
    result = Changed[T](
        has_changed: true,
        value: value,
        # raw_value: value,
        # on_changed: nil
    )

# proc `=sink`*[T](dst: var Changed[T], src: Changed[T]): void =
#     if (dst.raw_value != src.raw_value) and (dst.raw_value != nil or dst.value != nil):
#         var new_value = if dst.on_changed != nil:
#                             dst.on_changed(src.raw_value, dst.raw_value)
#                         else:
#                             src.raw_value
#         `=destroy`(dst.value)
#         `=destroy`(dst.raw_value)
#         dst.value = new_value
#         dst.raw_value = src.raw_value

converter changed_value*[T](changed: Changed[T]): T =
    result = changed.value

converter changed_changed*[T](changed: Changed[T]): bool =
    result = changed.has_changed

proc `<-`*[T](c_to, c_from: var Changed[T]): void =
    if c_from.changed:
        c_from.has_changed = false
        c_to = c_from

proc db_af*(db: float64): float64 =
    result = pow(10, 0.05 * db)

proc af_db*(af: float64): float64 =
    result = 20 * log10(af)

proc p_f*(pitch: float64): float64 =
    result = pow(2, pitch / 12) * 8.175798915643707333682812

proc f_p*(freq: float64): float64 =
    result = log2(freq / 8.175798915643707333682812) * 12

proc lerp*(v0, v1, mix: float64): float64 =
    result = (v1 - v0) * mix + v0

const pi *: float64 = 3.1415926535897932384626433832795

# based on reaktor one pole lowpass coef calculation
proc onepole_lp_coef*(freq: float64, sr: float64): float64 =
    var input: float64 = min(0.5 * pi, max(0.001, freq) * (pi / sr));
    var tanapprox: float64 = (((0.0388452 - 0.0896638 * input) * input + 1.00005) * input) /
                            ((0.0404318 - 0.430871 * input) * input + 1);
    return tanapprox / (tanapprox + 1);

# based on reaktor one pole lowpass
proc onepole_lp*(last: var float64, coef: float64, src: float64): float64 =
    var delta_scaled: float64 = (src - last) * coef;
    var dst: float64 = delta_scaled + last;
    last = delta_scaled + dst;
    return dst;

proc simple_lp_coef*(freq: float64, sr: float64): float64 =
    var w: float64 = (2 * pi * freq) / sr;
    var twomcos: float64 = 2 - cos(w);
    return 1 - (twomcos - sqrt(twomcos * twomcos - 1));

proc simple_lp*(smooth: var float64, coef: float64, next: float64): var float64 =
    smooth += coef * (next - smooth)
    return smooth