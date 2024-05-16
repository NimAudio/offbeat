# offbeat 🎶
clap based plugin framework in nim, built on nim-clap bindings

offbeat is mainly built around it managing parameters for you. simply define them initially, and it handles describing them to clap, events, saving, loading, etc. parameters can be float, int, or bool, with floats being the most fully featured, with built in smoothing.

there are numerous optional callbacks to shim in additional code, if needed, in many places. many are more theoretical, while others have a clear imagined use, like the calculate callback on smoothed float parameters, which has been added in large part to enable smooth but optimized filter coefficient calculation.

##### features
- effect plugins
- parameters
- saving
- loading
- automation
- parameter smoothing

##### planned features (no specific order)
- synth plugins and other uses of midi input or output
  - possibly with a synth framework which handles voices and calls various callbacks when needed
- custom ui
  - i have started work on ui with sokol
  - i intend to simply provide a sokol context for the user to supply mesh, shader, etc for
  - however i would like to create shaders that use SDFs to create uniform based tweaking of looks and mesh based value, size, etc, for something a bit easier to place controls for, along with a library to handle mapping events to callbacks
- save/load error correction
- preset system
  - optional json format for presets (no error correction)
- global settings system
- improve ergonomics of using parameter values
  - maybe using generated macros?
  - i think i have a functional name to index mapping table set up, but i have not tried it out. it would at least be less error prone than raw indices
- non-destructive modulation
